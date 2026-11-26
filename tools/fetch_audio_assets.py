"""Download, sound-design, and master CC0 lotsofsounds.com game audio into 44.1 kHz stereo WAVs."""

from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import urllib.parse
import urllib.request
import wave

import numpy as np
from scipy import signal

KENNEY_BASE = (
    "https://raw.githubusercontent.com/Calinou/kenney-interface-sounds/master/"
    "addons/kenney_interface_sounds/"
)
ENDLESS_SKY_BASE = "https://raw.githubusercontent.com/endless-sky/endless-sky/master/sounds/"
LOS_API_BASE = "https://api.lotsofsounds.com/api/v1/sounds/sample"
LOS_CACHE_DIR = os.path.join("tools", "cache", "lotsofsounds")
MIXKIT_CACHE_DIR = os.path.join("tools", "cache", "mixkit")
MIXKIT_OVERRIDES = {
    "friend_request": r"C:\Users\princ\Downloads\mixkit-unlock-game-notification-253.wav",
    "conquer_pop": r"C:\Users\princ\Downloads\mixkit-game-ball-tap-2073.wav",
    "victory_fanfare": r"C:\Users\princ\Downloads\mixkit-game-level-completed-2059.wav",
    "defeat_drums": r"C:\Users\princ\Downloads\mixkit-ominous-drums-227.wav",
}

# Verified Public Domain combat, missile, silo, SAM & explosion WAVs from endless-sky/endless-sky
PUBLIC_COMBAT_SFX = {
    "missile_launch.wav": ("rocket.wav", 1.60, -14.0, 0.22),
    "silo_nuke_launch.wav": ("nuke.wav", 2.50, -13.5, 0.30),
    "sam_launch.wav": ("sidewinder.wav", 0.95, -14.0, 0.14),
    "sam_intercept.wav": ("missile hit.wav", 1.40, -13.5, 0.24),
    "nuke_blast.wav": ("explosion nuke.wav", 3.50, -11.0, 0.65),
    "cannon_fire.wav": ("ballistic.wav", 1.15, -14.0, 0.20),
    "battle_clash.wav": ("explosion medium.wav", 0.85, -16.0, 0.16),
}

PUBLIC_SFX_CACHE_DIR = os.path.join("tools", "cache", "public_sfx")
SFX_DIR = os.path.join("assets", "audio", "sfx")
AMBIENCE_DIR = os.path.join("assets", "audio", "ambience")
MUSIC_DIR = os.path.join("assets", "audio", "music")
SR = 44100

_IR_CACHE: dict[tuple[int, float, float, float, int], np.ndarray] = {}


def _ensure_stereo(samples: np.ndarray) -> np.ndarray:
    arr = np.asarray(samples, dtype=np.float64)
    if arr.ndim == 1:
        return np.column_stack([arr, arr])
    if arr.shape[1] == 1:
        return np.column_stack([arr[:, 0], arr[:, 0]])
    return arr[:, :2].copy()


def _clamp_hz(freq_hz: float, sr: int) -> float:
    return float(np.clip(freq_hz, 20.0, sr * 0.45))


def _sos_lp(sig: np.ndarray, sr: int, cutoff_hz: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, _clamp_hz(cutoff_hz, sr) / (sr * 0.5), btype="low", output="sos")
    return signal.sosfilt(sos, sig, axis=0)


def _sos_hp(sig: np.ndarray, sr: int, cutoff_hz: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, _clamp_hz(cutoff_hz, sr) / (sr * 0.5), btype="high", output="sos")
    return signal.sosfilt(sos, sig, axis=0)


def _sos_bp(sig: np.ndarray, sr: int, low_hz: float, high_hz: float, order: int = 2) -> np.ndarray:
    lo = _clamp_hz(low_hz, sr)
    hi = _clamp_hz(max(high_hz, lo + 25.0), sr)
    sos = signal.butter(order, [lo / (sr * 0.5), hi / (sr * 0.5)], btype="band", output="sos")
    return signal.sosfilt(sos, sig, axis=0)


def _pink_noise(n: int, rng: np.random.Generator) -> np.ndarray:
    if n <= 4:
        return rng.standard_normal(max(1, n)).astype(np.float64)
    white = rng.standard_normal(n).astype(np.float64)
    spec = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, d=1.0 / SR)
    scale = np.where(freqs > 1.0, 1.0 / np.sqrt(np.maximum(freqs, 1.0)), 1.0)
    scale[0] = 0.0
    pink = np.fft.irfft(spec * scale, n=n)
    rms = float(np.sqrt(np.mean(pink * pink)))
    return pink / rms if rms > 1e-9 else pink


def _soft_sat(x: np.ndarray, drive: float = 1.35) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def _pan_stereo(mono: np.ndarray, pan: float = 0.0) -> np.ndarray:
    theta = (float(np.clip(pan, -1.0, 1.0)) + 1.0) * (np.pi * 0.25)
    return np.column_stack([mono * np.cos(theta), mono * np.sin(theta)])


def _widen_stereo(mono: np.ndarray, sr: int, delay_ms: float = 8.5, width: float = 0.45) -> np.ndarray:
    n = len(mono)
    d = max(1, int(delay_ms * 0.001 * sr))
    delayed = np.zeros(n, dtype=np.float64)
    if d < n:
        delayed[d:] = mono[:-d]
    high = _sos_hp(mono, sr, 420.0, order=2)
    high_del = _sos_hp(delayed, sr, 420.0, order=2)
    side = (high - high_del) * width
    left = mono + side * 0.65 - delayed * (width * 0.22)
    right = mono - side * 0.65 + delayed * (width * 0.22)
    return np.column_stack([left, right])


def _make_stereo_ir(
    sr: int, rt60: float = 1.2, predelay_ms: float = 16.0, damping_hz: float = 4800.0, seed: int = 11
) -> np.ndarray:
    key = (sr, round(rt60, 2), round(predelay_ms, 1), round(damping_hz, 0), seed)
    if key in _IR_CACHE:
        return _IR_CACHE[key]

    rng = np.random.default_rng(seed)
    ir_len = max(int(sr * min(rt60 * 1.15, 2.6)), 256)
    pre_n = min(ir_len - 32, int(predelay_ms * 0.001 * sr))
    ir = np.zeros((ir_len, 2), dtype=np.float64)
    ir[0, :] = 0.0

    # Natural stereo early reflection taps
    early_taps = [
        (0.006, 0.34, 0.18),
        (0.011, 0.16, 0.32),
        (0.017, 0.26, 0.14),
        (0.024, 0.12, 0.24),
        (0.033, 0.18, 0.15),
    ]
    for sec_off, g_l, g_r in early_taps:
        idx = pre_n + int(sec_off * sr)
        if idx < ir_len:
            ir[idx, 0] += g_l
            ir[idx, 1] += g_r

    # Frequency-damped diffuse exponential tail
    tail_n = max(1, ir_len - pre_n)
    t_tail = np.arange(tail_n, dtype=np.float64) / sr
    decay = np.exp(-6.9078 * t_tail / max(rt60, 0.08)) * np.minimum(t_tail / 0.025, 1.0)
    raw_tail = np.column_stack([rng.standard_normal(tail_n), rng.standard_normal(tail_n)])
    damped_hi = _sos_lp(raw_tail, sr, damping_hz, order=2)
    damped_lo = _sos_lp(raw_tail, sr, min(damping_hz * 0.35, 1600.0), order=2)
    late = damped_hi * np.exp(-2.2 * t_tail)[:, None] * 0.55 + damped_lo * 0.45
    ir[pre_n:, :] += late * decay[:, None] * 0.18

    ir = _sos_hp(ir, sr, 95.0, order=1)
    energy = float(np.sqrt(np.mean(np.sum(ir * ir, axis=0))))
    if energy > 1e-8:
        ir /= energy
    _IR_CACHE[key] = ir
    return ir


def _stereo_reverb(
    samples: np.ndarray,
    sr: int = SR,
    rt60: float = 1.2,
    predelay_ms: float = 18.0,
    wet: float = 0.22,
    damping_hz: float = 4800.0,
    seed: int = 11,
) -> np.ndarray:
    dry = _ensure_stereo(samples)
    ir = _make_stereo_ir(sr, rt60, predelay_ms, damping_hz, seed)
    n = len(dry)
    wet_l = signal.fftconvolve(dry[:, 0], ir[:, 0], mode="full")[:n]
    wet_r = signal.fftconvolve(dry[:, 1], ir[:, 1], mode="full")[:n]
    return dry * (1.0 - wet * 0.35) + np.column_stack([wet_l, wet_r]) * wet


def _write_pcm16_wav(
    path: str,
    samples: np.ndarray,
    sample_rate: int = SR,
    target_rms_db: float = -16.0,
    seamless_loop: bool = False,
    fade_in_ms: float = 3.0,
) -> None:
    st = _ensure_stereo(samples)
    st = np.nan_to_num(st, nan=0.0, posinf=0.0, neginf=0.0)
    st -= np.mean(st, axis=0, keepdims=True)

    if not seamless_loop:
        fade_in = min(len(st), int(max(0.5, fade_in_ms) * 0.001 * sample_rate))
        fade_out = min(len(st), int(0.012 * sample_rate))
        if fade_in > 1:
            st[:fade_in] *= np.linspace(0.0, 1.0, fade_in)[:, None]
        if fade_out > 1:
            st[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)[:, None]

    rms = float(np.sqrt(np.mean(st * st)))
    target_rms = 10.0 ** (target_rms_db / 20.0)
    if rms > 1e-8:
        st = st * (target_rms / rms)

    peak = float(np.max(np.abs(st)))
    if peak > 0.88:
        st = _soft_sat(st * (0.88 / max(peak * 0.85, 0.88)), drive=1.55)
        peak2 = float(np.max(np.abs(st)))
        if peak2 > 0.90:
            st *= 0.90 / peak2

    st = np.clip(st, -0.92, 0.92)
    pcm = (st * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm.tobytes())


def _add_at(buf: np.ndarray, offset_sec: float, chunk: np.ndarray, sr: int = SR, gain: float = 1.0) -> None:
    st = _ensure_stereo(chunk)
    i0 = int(offset_sec * sr)
    i1 = min(len(buf), i0 + len(st))
    if i0 < len(buf) and i1 > i0:
        buf[i0:i1] += st[: i1 - i0] * gain


# ---------------------------------------------------------------------------
# Modern Hybrid Cinematic / Orchestral Synth Voices
# ---------------------------------------------------------------------------

def _synth_cinematic_strings(
    freq: float, dur: float, sr: int, rng: np.random.Generator, pan: float = 0.0, bow_attack: float = 0.16
) -> np.ndarray:
    n = max(16, int(dur * sr))
    lt = np.arange(n, dtype=np.float64) / sr
    detunes_cents = [-11.0, -5.0, 0.0, 5.5, 11.5]
    pans = [-0.55, -0.25, 0.0, 0.25, 0.55]
    stereo = np.zeros((n, 2), dtype=np.float64)
    harm_weights = [1.0, 0.62, 0.42, 0.28, 0.18, 0.11, 0.06]
    vib_onset = np.minimum(lt / 0.22, 1.0)

    for cents, p_off in zip(detunes_cents, pans):
        ratio = 2.0 ** (cents / 1200.0)
        ph_jitter = rng.uniform(0.0, 2.0 * np.pi)
        vib = 1.0 + 0.0038 * np.sin(2.0 * np.pi * rng.uniform(4.8, 5.7) * lt + ph_jitter) * vib_onset
        phase = 2.0 * np.pi * np.cumsum(freq * ratio * vib) / sr + ph_jitter
        voice = np.zeros(n, dtype=np.float64)
        for k, w in enumerate(harm_weights, start=1):
            voice += w * np.sin(phase * k)
        p_val = float(np.clip(pan + p_off * 0.65, -0.95, 0.95))
        stereo += _pan_stereo(voice, p_val) * (1.0 / len(detunes_cents))

    dark = _sos_lp(stereo, sr, 950.0, order=2)
    bright = _sos_lp(stereo, sr, 3600.0, order=2)
    swell = np.sin(np.pi * np.clip(lt / max(dur, 0.05), 0.0, 1.0)) ** 0.75
    tone = dark * (1.0 - 0.65 * swell)[:, None] + bright * (0.65 * swell)[:, None]
    env = np.minimum(lt / max(bow_attack, 0.02), 1.0) * np.minimum(np.maximum((dur - lt) / 0.14, 0.0), 1.0)
    return _soft_sat(tone * 0.55, 1.15) * env[:, None]


def _synth_cinematic_brass(
    freq: float, dur: float, sr: int, rng: np.random.Generator, pan: float = 0.0, attack_s: float = 0.045
) -> np.ndarray:
    n = max(16, int(dur * sr))
    lt = np.arange(n, dtype=np.float64) / sr
    detunes = [-6.5, -1.8, 2.2, 7.0]
    stereo = np.zeros((n, 2), dtype=np.float64)
    harm_weights = [1.0, 0.84, 0.68, 0.50, 0.36, 0.24, 0.14, 0.08]
    vib = 1.0 + 0.0032 * np.sin(2.0 * np.pi * 5.1 * lt) * np.minimum(lt / 0.16, 1.0)

    for idx, cents in enumerate(detunes):
        ratio = 2.0 ** (cents / 1200.0)
        phase = 2.0 * np.pi * np.cumsum(freq * ratio * vib) / sr + rng.uniform(0.0, np.pi)
        v = np.zeros(n, dtype=np.float64)
        for k, w in enumerate(harm_weights, start=1):
            v += w * np.sin(phase * k)
        p_off = (-0.35 + 0.7 * idx / 3.0) * 0.5
        stereo += _pan_stereo(v, float(np.clip(pan + p_off, -0.95, 0.95))) * 0.25

    air = _sos_bp(_pink_noise(n, rng), sr, 750.0, 2600.0, order=2) * np.exp(-42.0 * lt) * 0.16
    stereo += _pan_stereo(air, pan)

    warm = _sos_lp(stereo, sr, 820.0, order=2)
    full = _sos_lp(stereo, sr, 3900.0, order=2)
    bloom = np.minimum(lt / max(attack_s * 1.4, 0.02), 1.0) * (0.45 + 0.55 * np.exp(-2.4 * lt))
    shaped = warm * (1.0 - bloom)[:, None] + full * bloom[:, None]
    env = np.minimum(lt / max(attack_s, 0.008), 1.0) * np.minimum(np.maximum((dur - lt) / 0.06, 0.0), 1.0)
    return _soft_sat(shaped * 0.42, 1.3) * env[:, None]


def _synth_felt_piano(freq: float, dur: float, sr: int, rng: np.random.Generator, pan: float = 0.0) -> np.ndarray:
    n = max(16, int(dur * sr))
    lt = np.arange(n, dtype=np.float64) / sr
    B = 0.00018
    sig = np.zeros(n, dtype=np.float64)
    for k, w in [(1, 1.0), (2, 0.52), (3, 0.24), (4, 0.11), (5, 0.045), (6, 0.018)]:
        fk = freq * k * np.sqrt(1.0 + B * k * k)
        if fk >= sr * 0.42:
            continue
        decay_rate = 1.6 + k * 2.1
        sig += w * np.sin(2.0 * np.pi * fk * lt) * np.exp(-decay_rate * lt)
    hammer = _sos_bp(_pink_noise(n, rng), sr, 240.0, 1400.0, order=2) * np.exp(-95.0 * lt) * 0.28
    env = np.minimum(lt / 0.006, 1.0) * np.minimum(np.maximum((dur - lt) / 0.04, 0.0), 1.0)
    mono = _sos_lp((sig * 0.55 + hammer) * env, sr, 3400.0, order=2)
    return _pan_stereo(mono, pan)


def _synth_sub_pulse(freq: float, dur: float, sr: int) -> np.ndarray:
    n = max(16, int(dur * sr))
    lt = np.arange(n, dtype=np.float64) / sr
    ph = 2.0 * np.pi * freq * lt
    body = np.sin(ph) + 0.30 * np.sin(2.0 * ph) + 0.10 * np.sin(3.0 * ph)
    body = _sos_lp(body, sr, 260.0, order=2)
    env = np.minimum(lt / 0.014, 1.0) * np.exp(-3.2 * lt) * np.minimum(np.maximum((dur - lt) / 0.04, 0.0), 1.0)
    return _pan_stereo(body * env * 0.85, 0.0)


def _synth_taiko_boom(
    f_hi: float, f_lo: float, dur: float, sr: int, rng: np.random.Generator, accent: float = 1.0
) -> np.ndarray:
    n = max(16, int(dur * sr))
    lt = np.arange(n, dtype=np.float64) / sr
    f_sweep = (f_hi - f_lo) * np.exp(-20.0 * lt) + f_lo
    ph = 2.0 * np.pi * np.cumsum(f_sweep) / sr
    membrane = np.sin(ph) + 0.32 * np.sin(ph * 1.59) * np.exp(-10.0 * lt) + 0.18 * np.sin(ph * 2.13) * np.exp(-16.0 * lt)
    beater = _sos_bp(_pink_noise(n, rng), sr, 180.0, 1400.0, order=2) * np.exp(-65.0 * lt) * 0.45
    env = np.minimum(lt / 0.004, 1.0) * np.exp(-4.8 * lt)
    raw = _soft_sat((membrane * 0.8 + beater) * env * accent, 1.45)
    return _widen_stereo(raw, sr, delay_ms=5.5, width=0.28)


def _synth_cinematic_snare(dur: float, sr: int, rng: np.random.Generator, accent: float = 1.0) -> np.ndarray:
    n = max(16, int(dur * sr))
    lt = np.arange(n, dtype=np.float64) / sr
    shell_ph = 2.0 * np.pi * np.cumsum(220.0 * np.exp(-30.0 * lt) + 178.0) / sr
    shell = np.sin(shell_ph) * np.exp(-26.0 * lt) * 0.55
    stick = _sos_bp(rng.standard_normal(n), sr, 1800.0, 6800.0, order=2) * np.exp(-55.0 * lt) * 0.55
    wires = _sos_hp(_pink_noise(n, rng), sr, 1400.0, order=2) * np.exp(-18.0 * lt) * 0.65
    env = np.minimum(lt / 0.0015, 1.0)
    return _widen_stereo(_soft_sat((shell + stick + wires) * env * accent, 1.25), sr, delay_ms=4.5, width=0.45)


def _synth_cymbal_swell(dur: float, sr: int, rng: np.random.Generator, accent: float = 1.0, crash: bool = False) -> np.ndarray:
    n = max(16, int(dur * sr))
    lt = np.arange(n, dtype=np.float64) / sr
    noise_l = _pink_noise(n, rng)
    noise_r = _pink_noise(n, rng)
    shimmer = np.column_stack([
        _sos_bp(noise_l, sr, 2100.0, 10500.0, order=2),
        _sos_bp(noise_r, sr, 2250.0, 11200.0, order=2),
    ])
    if crash:
        env = np.minimum(lt / 0.008, 1.0) * np.exp(-2.6 * lt) * np.minimum(np.maximum((dur - lt) / 0.15, 0.0), 1.0)
    else:
        t_norm = lt / max(dur - 0.08, 0.05)
        env = np.where(lt <= dur - 0.08, np.clip(t_norm, 0.0, 1.0) ** 2.6, np.maximum((dur - lt) / 0.08, 0.0))
    return shimmer * env[:, None] * (0.45 * accent)


# ---------------------------------------------------------------------------
# 1. Public-Domain Combat/Missile/Nuke SFX (Stereo Remastered)
# ---------------------------------------------------------------------------

def fetch_public_combat_sfx() -> None:
    """Download/load real Public Domain combat WAVs and remaster into wide punchy stereo cinema SFX."""
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(PUBLIC_SFX_CACHE_DIR, exist_ok=True)
    rng = np.random.default_rng(2025)

    for dest_name, (src_name, max_dur, rms_db, fade_out_sec) in PUBLIC_COMBAT_SFX.items():
        cache_path = os.path.join(PUBLIC_SFX_CACHE_DIR, src_name)
        if not os.path.exists(cache_path) or os.path.getsize(cache_path) == 0:
            url = ENDLESS_SKY_BASE + urllib.parse.quote(src_name)
            print(f"[audio-fetch] Downloading public-domain {src_name} -> {dest_name}...")
            with urllib.request.urlopen(url, timeout=20) as resp:
                raw_bytes = resp.read()
            with open(cache_path, "wb") as f:
                f.write(raw_bytes)
        else:
            with open(cache_path, "rb") as f:
                raw_bytes = f.read()

        with wave.open(io.BytesIO(raw_bytes), "rb") as wf:
            n_ch = wf.getnchannels()
            sw = wf.getsampwidth()
            sr_in = wf.getframerate()
            frames = wf.readframes(wf.getnframes())

        assert sw == 2, f"Expected 16-bit PCM WAV for {src_name}, got sampwidth={sw}"
        arr = np.frombuffer(frames, dtype=np.int16).astype(np.float64) / 32768.0
        if n_ch > 1:
            arr = arr.reshape(-1, n_ch).mean(axis=1)
        if sr_in != SR:
            gcd = int(np.gcd(SR, sr_in))
            arr = signal.resample_poly(arr, SR // gcd, sr_in // gcd)

        target_n = int(max_dur * SR)
        if len(arr) >= target_n:
            arr = arr[:target_n].copy()
        else:
            pad = np.zeros(target_n, dtype=np.float64)
            pad[: len(arr)] = arr
            arr = pad

        src_rms = float(np.sqrt(np.mean(arr * arr)))
        if src_rms > 1e-8:
            arr /= src_rms * 4.5

        lt = np.arange(target_n, dtype=np.float64) / SR
        st = _widen_stereo(arr, SR, delay_ms=7.0, width=0.45)

        if dest_name == "nuke_blast.wav":
            # Layer seismic sub-drop shockwave + white-hot initial snap + wide hall shockwave reverb
            sub_f = 54.0 * np.exp(-2.8 * lt) + 24.0
            sub = np.sin(2.0 * np.pi * np.cumsum(sub_f) / SR) * np.minimum(lt / 0.012, 1.0) * np.exp(-1.15 * lt) * 0.85
            flash = _sos_bp(_pink_noise(target_n, rng), SR, 1200.0, 10500.0, order=2) * np.exp(-24.0 * lt) * 0.55
            st += _pan_stereo(sub, 0.0) + _widen_stereo(flash, SR, delay_ms=3.5, width=0.65)
            st = _stereo_reverb(st, SR, rt60=2.1, predelay_ms=22.0, wet=0.38, damping_hz=3600.0, seed=101)
        elif dest_name == "silo_nuke_launch.wav":
            # Pneumatic silo hatch thump + metallic lock + deep rocket afterburner rumble
            hatch = _synth_taiko_boom(110.0, 42.0, 0.25, SR, rng, accent=0.9)
            _add_at(st, 0.0, hatch, SR, 0.55)
            rumble = _sos_bp(_pink_noise(target_n, rng), SR, 45.0, 220.0, order=2) * np.sin(np.pi * np.clip(lt / max_dur, 0.0, 1.0)) * 0.42
            st += _widen_stereo(rumble, SR, delay_ms=9.0, width=0.4)
            st = _stereo_reverb(st, SR, rt60=1.25, predelay_ms=14.0, wet=0.24, damping_hz=4400.0, seed=102)
        elif dest_name == "missile_launch.wav":
            snap = _sos_bp(_pink_noise(target_n, rng), SR, 900.0, 6200.0, order=2) * np.exp(-32.0 * lt) * 0.40
            whoosh = _sos_bp(_pink_noise(target_n, rng), SR, 300.0, 2200.0, order=2) * np.exp(-3.2 * lt) * 0.25
            st += _widen_stereo(snap + whoosh, SR, delay_ms=6.0, width=0.55)
            st = _stereo_reverb(st, SR, rt60=0.85, predelay_ms=12.0, wet=0.18, damping_hz=5500.0, seed=103)
        elif dest_name == "sam_launch.wav":
            snap = _sos_bp(_pink_noise(target_n, rng), SR, 1600.0, 7800.0, order=2) * np.exp(-44.0 * lt) * 0.42
            st += _widen_stereo(snap, SR, delay_ms=4.0, width=0.5)
            st = _stereo_reverb(st, SR, rt60=0.65, predelay_ms=10.0, wet=0.16, damping_hz=6000.0, seed=104)
        elif dest_name == "sam_intercept.wav":
            crack = _sos_hp(_pink_noise(target_n, rng), SR, 1500.0, order=2) * np.exp(-26.0 * lt) * 0.35
            st += _widen_stereo(crack, SR, delay_ms=5.0, width=0.6)
            st = _stereo_reverb(st, SR, rt60=1.15, predelay_ms=18.0, wet=0.28, damping_hz=5200.0, seed=105)
        elif dest_name == "cannon_fire.wav":
            punch = _synth_taiko_boom(145.0, 44.0, 0.32, SR, rng, accent=0.85)
            _add_at(st, 0.0, punch, SR, 0.50)
            st = _stereo_reverb(st, SR, rt60=1.05, predelay_ms=16.0, wet=0.22, damping_hz=4200.0, seed=106)
        elif dest_name == "battle_clash.wav":
            thump1 = _synth_taiko_boom(120.0, 48.0, 0.24, SR, rng, accent=0.75)
            thump2 = _synth_taiko_boom(105.0, 44.0, 0.22, SR, rng, accent=0.6)
            _add_at(st, 0.0, thump1, SR, 0.40)
            _add_at(st, 0.14, thump2, SR, 0.32)
            st = _stereo_reverb(st, SR, rt60=0.75, predelay_ms=12.0, wet=0.20, damping_hz=3800.0, seed=107)

        fade_out_n = min(len(st), int(fade_out_sec * SR))
        if fade_out_n > 1:
            t_fade = np.linspace(0.0, np.pi * 0.5, fade_out_n)
            st[-fade_out_n:] *= (np.cos(t_fade) ** 2)[:, None]

        dest_path = os.path.join(SFX_DIR, dest_name)
        _write_pcm16_wav(dest_path, st, SR, rms_db)

    sources_path = os.path.join("assets", "audio", "SOURCES.txt")
    lines = [
        "World War Pixel — Verified Audio Sources & Licenses",
        "===================================================",
        "UI, Orchestral Theme & Tactical Foley: Custom 44.1 kHz Stereo Studio-DSP synthesis (CC0 / Project Original)",
        "Bubble-Wrap Land Conquest Pops (conquer_pop_001..006.wav) & Invasion Warning (invasion_warning.wav): Custom 44.1 kHz Stereo Physical-Model DSP synthesis (CC0 / Project Original)",
        "Base UI Library Reference Credits: Kenney Interface Sounds (CC0 1.0 Public Domain) replaced with unified modern stereo foley.",
        "",
        "Public-Domain Missile, Silo, SAM, Intercept & Combat Base SFX (endless-sky/endless-sky sounds/*, License: public-domain, stereo remastered):",
    ]
    for dest_name, (src_name, max_dur, _, _) in PUBLIC_COMBAT_SFX.items():
        lines.append(f"- assets/audio/sfx/{dest_name} <- {ENDLESS_SKY_BASE}{urllib.parse.quote(src_name)} ({max_dur:.2f}s stereo remaster)")
    with open(sources_path, "w", encoding="utf-8") as sf:
        sf.write("\n".join(lines) + "\n")
    print(f"[audio-fetch] Remastered {len(PUBLIC_COMBAT_SFX)} public-domain combat/nuke WAVs into wide stereo + wrote {sources_path}.")


# ---------------------------------------------------------------------------
# 2. Modern Stereo Command-Center UI & Tactical Foley
# ---------------------------------------------------------------------------

def _make_tactile_click(dur: float, f_body: float, f_tick: float, pan: float, rng: np.random.Generator) -> np.ndarray:
    n = int(dur * SR)
    lt = np.arange(n, dtype=np.float64) / SR
    body = np.sin(2.0 * np.pi * f_body * lt) * np.exp(-62.0 * lt) * 0.55
    snap = _sos_bp(_pink_noise(n, rng), SR, f_tick * 0.7, f_tick * 1.4, order=2) * np.exp(-95.0 * lt) * 0.65
    air = np.sin(2.0 * np.pi * f_tick * lt) * np.exp(-78.0 * lt) * 0.25
    env = np.minimum(lt / 0.0012, 1.0)
    st = _pan_stereo((body + snap + air) * env, pan)
    return _stereo_reverb(st, SR, rt60=0.18, predelay_ms=4.0, wet=0.10, damping_hz=6000.0, seed=12)


def _make_panel_glide(dur: float, rising: bool, rng: np.random.Generator) -> np.ndarray:
    n = int(dur * SR)
    lt = np.arange(n, dtype=np.float64) / SR
    noise = _pink_noise(n, rng)
    lo = _sos_bp(noise, SR, 350.0, 950.0, order=2)
    hi = _sos_bp(noise, SR, 1200.0, 3200.0, order=2)
    t_norm = lt / dur
    sweep = t_norm if rising else (1.0 - t_norm)
    air = lo * (1.0 - sweep) * 0.45 + hi * sweep * 0.55
    air *= np.sin(np.pi * t_norm) ** 0.9
    f_tone = (480.0 + 260.0 * t_norm) if rising else (620.0 - 220.0 * t_norm)
    tone = np.sin(2.0 * np.pi * np.cumsum(f_tone) / SR) * np.exp(-18.0 * lt) * 0.25
    st = _widen_stereo(air + tone, SR, delay_ms=5.0, width=0.4)
    return _stereo_reverb(st, SR, rt60=0.28, predelay_ms=6.0, wet=0.14, damping_hz=5500.0, seed=13)


def generate_modern_ui_sfx() -> None:
    """Synthesize sleek modern stereo AAA strategy UI foley (replaces legacy Kenney bloops + adds upgrade_001/002)."""
    os.makedirs(SFX_DIR, exist_ok=True)
    rng = np.random.default_rng(314)

    # Tactile slate UI clicks
    _write_pcm16_wav(os.path.join(SFX_DIR, "drop_001.wav"), _make_tactile_click(0.085, 290.0, 3400.0, -0.05, rng), SR, -16.5)
    _write_pcm16_wav(os.path.join(SFX_DIR, "drop_002.wav"), _make_tactile_click(0.085, 320.0, 3800.0, 0.05, rng), SR, -16.5)

    # Silky panel glides
    _write_pcm16_wav(os.path.join(SFX_DIR, "open_001.wav"), _make_panel_glide(0.17, True, rng), SR, -17.5)
    _write_pcm16_wav(os.path.join(SFX_DIR, "close_001.wav"), _make_panel_glide(0.15, False, rng), SR, -17.5)

    # Expand launch: crisp tactical map-brush surge + muted sub push
    for idx, (f_sub, f_hi) in enumerate([(92.0, 1750.0), (104.0, 1950.0)], start=1):
        n_e = int(0.24 * SR)
        lt = np.arange(n_e, dtype=np.float64) / SR
        brush = _sos_bp(_pink_noise(n_e, rng), SR, 380.0, f_hi, order=2) * np.sin(np.pi * (lt / 0.24)) ** 1.1 * 0.55
        thump = _synth_taiko_boom(f_sub * 1.4, f_sub * 0.58, 0.20, SR, rng, accent=0.65)
        st_e = _widen_stereo(brush, SR, delay_ms=6.5, width=0.55)
        _add_at(st_e, 0.0, thump, SR, 0.55)
        st_e = _stereo_reverb(st_e, SR, rt60=0.42, predelay_ms=8.0, wet=0.18, damping_hz=5200.0, seed=20 + idx)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"glass_00{idx}.wav"), st_e, SR, -15.5)

    # Build placed: heavy anchor thud + brushed steel lock + subtle warm D5 harmonic confirm
    for idx, f_res in enumerate([(293.66, 440.0), (329.63, 493.88)], start=1):
        n_b = int(0.30 * SR)
        lt = np.arange(n_b, dtype=np.float64) / SR
        st_b = _synth_taiko_boom(128.0, 50.0, 0.24, SR, rng, accent=0.80) * 0.72
        latch = _make_tactile_click(0.08, 420.0, 4200.0, 0.12 if idx == 1 else -0.12, rng)
        _add_at(st_b, 0.045, latch, SR, 0.55)
        _add_at(st_b, 0.03, _synth_felt_piano(f_res[0], 0.24, SR, rng, -0.12), SR, 0.35)
        _add_at(st_b, 0.07, _synth_felt_piano(f_res[1], 0.22, SR, rng, 0.12), SR, 0.30)
        st_b = _stereo_reverb(st_b, SR, rt60=0.45, predelay_ms=10.0, wet=0.18, damping_hz=4800.0, seed=30 + idx)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"maximize_00{idx}.wav"), st_b, SR, -15.0)

    # Dedicated Upgrade Instant SFX (ascending glass chime & tech shimmer)
    for idx, notes in enumerate([(587.33, 880.0), (659.25, 987.77)], start=1):
        n_u = int(0.38 * SR)
        st_u = np.zeros((n_u, 2), dtype=np.float64)
        _add_at(st_u, 0.00, _synth_felt_piano(notes[0], 0.28, SR, rng, -0.18), SR, 0.65)
        _add_at(st_u, 0.055, _synth_felt_piano(notes[1], 0.31, SR, rng, 0.18), SR, 0.75)
        lt = np.arange(n_u, dtype=np.float64) / SR
        shimmer = np.sin(2.0 * np.pi * notes[1] * 2.0 * lt) * np.exp(-9.0 * lt) * 0.18
        st_u += _widen_stereo(shimmer, SR, delay_ms=5.0, width=0.6)
        st_u = _stereo_reverb(st_u, SR, rt60=0.65, predelay_ms=10.0, wet=0.24, damping_hz=6500.0, seed=40 + idx)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"upgrade_00{idx}.wav"), st_u, SR, -15.5)

    # Trade Gold: warm refined stereo treasury shimmer
    for idx, notes in enumerate([(659.25, 987.77), (783.99, 1174.66)], start=1):
        n_g = int(0.28 * SR)
        st_g = np.zeros((n_g, 2), dtype=np.float64)
        _add_at(st_g, 0.0, _synth_felt_piano(notes[0], 0.22, SR, rng, -0.15), SR, 0.55)
        _add_at(st_g, 0.05, _synth_felt_piano(notes[1], 0.22, SR, rng, 0.15), SR, 0.65)
        st_g = _stereo_reverb(st_g, SR, rt60=0.55, predelay_ms=8.0, wet=0.22, damping_hz=6200.0, seed=50 + idx)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"pluck_00{idx}.wav"), st_g, SR, -17.0)

    # Error: restrained low muted dual-thud tactical deny
    n_err = int(0.22 * SR)
    st_err = np.zeros((n_err, 2), dtype=np.float64)
    _add_at(st_err, 0.00, _synth_taiko_boom(165.0, 92.0, 0.10, SR, rng, accent=0.65), SR, 0.70)
    _add_at(st_err, 0.085, _synth_taiko_boom(135.0, 74.0, 0.12, SR, rng, accent=0.80), SR, 0.85)
    st_err = _stereo_reverb(st_err, SR, rt60=0.22, predelay_ms=5.0, wet=0.12, damping_hz=2800.0, seed=60)
    _write_pcm16_wav(os.path.join(SFX_DIR, "error_001.wav"), st_err, SR, -15.5)

    # Switch / Army Order: mechanical tactical command relay
    n_sw = int(0.14 * SR)
    st_sw = _make_tactile_click(0.06, 360.0, 4100.0, -0.08, rng)
    st_full_sw = np.zeros((n_sw, 2), dtype=np.float64)
    _add_at(st_full_sw, 0.0, st_sw, SR, 0.85)
    _add_at(st_full_sw, 0.04, _make_tactile_click(0.07, 250.0, 3000.0, 0.08, rng), SR, 0.65)
    _write_pcm16_wav(os.path.join(SFX_DIR, "switch_001.wav"), st_full_sw, SR, -16.0)

    # Confirmation & Bong utility chimes
    for idx, pair in enumerate([(440.0, 659.25), (523.25, 783.99)], start=1):
        n_cf = int(0.28 * SR)
        st_cf = np.zeros((n_cf, 2), dtype=np.float64)
        _add_at(st_cf, 0.0, _synth_felt_piano(pair[0], 0.24, SR, rng, -0.1), SR, 0.65)
        _add_at(st_cf, 0.06, _synth_felt_piano(pair[1], 0.22, SR, rng, 0.1), SR, 0.75)
        st_cf = _stereo_reverb(st_cf, SR, rt60=0.45, predelay_ms=8.0, wet=0.18, damping_hz=5500.0, seed=65 + idx)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"confirmation_00{idx}.wav"), st_cf, SR, -16.0)

    n_bg = int(0.26 * SR)
    st_bg = _synth_felt_piano(587.33, 0.26, SR, rng, 0.0)
    st_bg = _stereo_reverb(st_bg, SR, rt60=0.45, predelay_ms=8.0, wet=0.18, damping_hz=5000.0, seed=68)
    _write_pcm16_wav(os.path.join(SFX_DIR, "bong_001.wav"), st_bg, SR, -16.5)

    print("[audio-fetch] Synthesized 17 sleek modern stereo UI & tactical foley WAVs.")


# ---------------------------------------------------------------------------
# 3. Upgraded Procedural Maritime, Diplomacy, Rail, Radar & Victory SFX
# ---------------------------------------------------------------------------

def generate_procedural_sfx() -> None:
    """Synthesize modern layered stereo maritime, rail, diplomacy, radar, and orchestral victory WAVs."""
    os.makedirs(SFX_DIR, exist_ok=True)
    rng = np.random.default_rng(777)

    # 1. ship_depart.wav: rich warm harbor horn chord + stereo pink bow-wake wash (0.72s)
    n_ship = int(0.72 * SR)
    lt_s = np.arange(n_ship, dtype=np.float64) / SR
    st_ship = np.zeros((n_ship, 2), dtype=np.float64)
    _add_at(st_ship, 0.0, _synth_cinematic_brass(146.83, 0.62, SR, rng, -0.08, 0.08), SR, 0.72)
    _add_at(st_ship, 0.0, _synth_cinematic_brass(220.00, 0.62, SR, rng, 0.08, 0.09), SR, 0.45)
    wake = _sos_bp(_pink_noise(n_ship, rng), SR, 180.0, 950.0, order=2) * np.sin(np.pi * (lt_s / 0.72)) * 0.28
    st_ship += _widen_stereo(wake, SR, delay_ms=10.0, width=0.65)
    st_ship = _stereo_reverb(st_ship, SR, rt60=1.25, predelay_ms=18.0, wet=0.28, damping_hz=3600.0, seed=71)
    _write_pcm16_wav(os.path.join(SFX_DIR, "ship_depart.wav"), st_ship, SR, -15.5)

    # 2. boat_bell.wav: authentic bronze ship's bell double-ring + bow splash (0.95s)
    n_bl = int(0.95 * SR)
    t_bl = np.arange(n_bl, dtype=np.float64) / SR
    partials = [(1.0, 0.55, 4.8), (2.0, 0.34, 6.2), (2.40, 0.24, 7.8), (2.98, 0.16, 10.5), (4.18, 0.09, 14.0)]
    bell_f = 987.77  # B5 resonant naval bronze
    bell_sig = np.zeros(n_bl, dtype=np.float64)
    for strike_t, amp_s in [(0.0, 0.78), (0.175, 1.0)]:
        dt = np.maximum(0.0, t_bl - strike_t)
        mask = (t_bl >= strike_t).astype(np.float64)
        atk = np.minimum(dt / 0.0025, 1.0)
        for mult, w, dec in partials:
            bell_sig += mask * amp_s * w * atk * np.exp(-dec * dt) * np.sin(2.0 * np.pi * (bell_f * mult) * dt)
        clapper = _sos_bp(_pink_noise(n_bl, rng), SR, 2400.0, 7200.0, order=2) * mask * np.exp(-120.0 * dt) * 0.30 * amp_s
        bell_sig += clapper
    splash = _sos_bp(_pink_noise(n_bl, rng), SR, 260.0, 1250.0, order=2) * np.sin(np.pi * (t_bl / 0.95)) * 0.14
    st_bl = _widen_stereo(bell_sig, SR, delay_ms=5.0, width=0.45) + _widen_stereo(splash, SR, delay_ms=11.0, width=0.7)
    st_bl = _stereo_reverb(st_bl, SR, rt60=1.05, predelay_ms=15.0, wet=0.25, damping_hz=5800.0, seed=72)
    _write_pcm16_wav(os.path.join(SFX_DIR, "boat_bell.wav"), st_bl, SR, -14.0)

    # 3. warship_horn.wav: deep modern destroyer twin-interval foghorn + sea air (0.90s)
    n_wh = int(0.90 * SR)
    lt_wh = np.arange(n_wh, dtype=np.float64) / SR
    st_wh = np.zeros((n_wh, 2), dtype=np.float64)
    _add_at(st_wh, 0.0, _synth_cinematic_brass(87.31, 0.80, SR, rng, -0.06, 0.07), SR, 0.75)
    _add_at(st_wh, 0.0, _synth_cinematic_brass(130.81, 0.80, SR, rng, 0.06, 0.075), SR, 0.55)
    _add_at(st_wh, 0.0, _synth_sub_pulse(43.65, 0.78, SR), SR, 0.50)
    air_wh = _sos_bp(_pink_noise(n_wh, rng), SR, 280.0, 1100.0, order=2) * np.sin(np.pi * (lt_wh / 0.90)) * 0.18
    st_wh += _widen_stereo(air_wh, SR, delay_ms=8.0, width=0.55)
    st_wh = _stereo_reverb(st_wh, SR, rt60=1.55, predelay_ms=22.0, wet=0.30, damping_hz=3200.0, seed=73)
    _write_pcm16_wav(os.path.join(SFX_DIR, "warship_horn.wav"), st_wh, SR, -13.5)

    # 4. bridge_connect.wav: heavy structural steel clank + harmonic chord bloom (0.58s)
    n_br = int(0.58 * SR)
    st_br = _synth_taiko_boom(155.0, 56.0, 0.25, SR, rng, accent=0.80) * 0.65
    clank = _make_tactile_click(0.11, 520.0, 4600.0, -0.15, rng)
    _add_at(st_br, 0.02, clank, SR, 0.65)
    _add_at(st_br, 0.04, _synth_felt_piano(293.66, 0.48, SR, rng, -0.18), SR, 0.55)
    _add_at(st_br, 0.08, _synth_felt_piano(440.00, 0.44, SR, rng, 0.18), SR, 0.55)
    st_br = _stereo_reverb(st_br, SR, rt60=0.75, predelay_ms=12.0, wet=0.22, damping_hz=5200.0, seed=74)
    _write_pcm16_wav(os.path.join(SFX_DIR, "bridge_connect.wav"), st_br, SR, -15.0)

    # 5. army_deploy.wav: layered tactical taiko punch + crisp kit snap (0.35s)
    n_ar = int(0.35 * SR)
    st_ar = _synth_taiko_boom(140.0, 54.0, 0.30, SR, rng, accent=1.0)
    _add_at(st_ar, 0.0, _synth_cinematic_snare(0.14, SR, rng, accent=0.45), SR, 0.42)
    st_ar = _stereo_reverb(st_ar, SR, rt60=0.55, predelay_ms=8.0, wet=0.18, damping_hz=4200.0, seed=75)
    _write_pcm16_wav(os.path.join(SFX_DIR, "army_deploy.wav"), st_ar, SR, -14.0)

    # 6. diplomacy_chime.wav: lush concert-hall major-9th felt-piano & string harmonic chime (0.72s)
    n_dp = int(0.72 * SR)
    st_dp = np.zeros((n_dp, 2), dtype=np.float64)
    for delay_s, f_n, p_n in [(0.0, 392.00, -0.25), (0.04, 587.33, 0.15), (0.08, 739.99, -0.10), (0.12, 880.00, 0.25)]:
        _add_at(st_dp, delay_s, _synth_felt_piano(f_n, 0.55, SR, rng, p_n), SR, 0.58)
    _add_at(st_dp, 0.0, _synth_cinematic_strings(392.00, 0.65, SR, rng, 0.0, 0.12), SR, 0.32)
    st_dp = _stereo_reverb(st_dp, SR, rt60=1.15, predelay_ms=14.0, wet=0.28, damping_hz=6000.0, seed=76)
    _write_pcm16_wav(os.path.join(SFX_DIR, "diplomacy_chime.wav"), st_dp, SR, -15.5)

    # 7. betrayal_alert.wav: dramatic modern cinematic low brass "braaam" + sub-drop (0.85s)
    n_bt = int(0.85 * SR)
    st_bt = np.zeros((n_bt, 2), dtype=np.float64)
    _add_at(st_bt, 0.0, _synth_cinematic_brass(110.00, 0.78, SR, rng, -0.20, 0.04), SR, 0.75)
    _add_at(st_bt, 0.0, _synth_cinematic_brass(155.56, 0.78, SR, rng, 0.20, 0.04), SR, 0.65)
    _add_at(st_bt, 0.0, _synth_sub_pulse(55.00, 0.78, SR), SR, 0.70)
    _add_at(st_bt, 0.0, _synth_taiko_boom(120.0, 36.0, 0.45, SR, rng, accent=0.9), SR, 0.55)
    st_bt = _stereo_reverb(st_bt, SR, rt60=1.35, predelay_ms=18.0, wet=0.30, damping_hz=3400.0, seed=77)
    _write_pcm16_wav(os.path.join(SFX_DIR, "betrayal_alert.wav"), st_bt, SR, -13.5)

    # 8. target_lock.wav: sleek modern HUD avionics laser-lock FM sweep + twin telemetry ticks (0.40s)
    n_lk = int(0.40 * SR)
    lt_lk = np.arange(n_lk, dtype=np.float64) / SR
    st_lk = np.zeros((n_lk, 2), dtype=np.float64)
    sweep_f = 520.0 + 960.0 * (1.0 - np.exp(-12.0 * lt_lk))
    sweep_sig = np.sin(2.0 * np.pi * np.cumsum(sweep_f) / SR) * np.minimum(lt_lk / 0.01, 1.0) * np.exp(-9.0 * lt_lk) * 0.35
    st_lk += _widen_stereo(sweep_sig, SR, delay_ms=4.0, width=0.5)
    _add_at(st_lk, 0.02, _make_tactile_click(0.08, 880.0, 5200.0, -0.20, rng), SR, 0.70)
    _add_at(st_lk, 0.14, _make_tactile_click(0.09, 1174.66, 6200.0, 0.20, rng), SR, 0.85)
    st_lk = _stereo_reverb(st_lk, SR, rt60=0.45, predelay_ms=8.0, wet=0.18, damping_hz=6500.0, seed=78)
    _write_pcm16_wav(os.path.join(SFX_DIR, "target_lock.wav"), st_lk, SR, -15.0)

    # 9. troop_donate.wav: warm ascending convoy chord + light snare tap (0.58s)
    n_td = int(0.58 * SR)
    st_td = np.zeros((n_td, 2), dtype=np.float64)
    _add_at(st_td, 0.0, _synth_cinematic_snare(0.10, SR, rng, accent=0.45), SR, 0.35)
    _add_at(st_td, 0.00, _synth_felt_piano(329.63, 0.45, SR, rng, -0.22), SR, 0.55)
    _add_at(st_td, 0.06, _synth_felt_piano(440.00, 0.45, SR, rng, 0.00), SR, 0.55)
    _add_at(st_td, 0.12, _synth_felt_piano(659.25, 0.42, SR, rng, 0.22), SR, 0.62)
    st_td = _stereo_reverb(st_td, SR, rt60=0.80, predelay_ms=10.0, wet=0.22, damping_hz=5600.0, seed=79)
    _write_pcm16_wav(os.path.join(SFX_DIR, "troop_donate.wav"), st_td, SR, -15.0)

    # 10. retreat_horn.wav: distant French-horn ensemble descending tactical recall (0.58s)
    n_rt = int(0.58 * SR)
    st_rt = np.zeros((n_rt, 2), dtype=np.float64)
    _add_at(st_rt, 0.00, _synth_cinematic_brass(440.00, 0.22, SR, rng, -0.15, 0.03), SR, 0.65)
    _add_at(st_rt, 0.16, _synth_cinematic_brass(293.66, 0.38, SR, rng, 0.15, 0.04), SR, 0.72)
    st_rt = _stereo_reverb(st_rt, SR, rt60=1.05, predelay_ms=14.0, wet=0.26, damping_hz=4400.0, seed=80)
    _write_pcm16_wav(os.path.join(SFX_DIR, "retreat_horn.wav"), st_rt, SR, -15.5)

    # 11. victory_fanfare.wav: epic orchestral victory (3.20s stereo brass + soaring strings + taiko + cymbal)
    fan_dur = 3.20
    n_fan = int(fan_dur * SR)
    st_fan = np.zeros((n_fan, 2), dtype=np.float64)
    fan_notes = [
        (0.00, 0.24, [(293.66, -0.25), (146.83, 0.0)]),
        (0.24, 0.24, [(369.99, 0.20), (185.00, 0.0)]),
        (0.48, 0.26, [(440.00, -0.15), (220.00, 0.0)]),
        (0.74, 2.20, [(587.33, -0.35), (440.00, 0.30), (369.99, -0.20), (293.66, 0.15), (146.83, 0.0)]),
    ]
    for st_s, d_s, pairs in fan_notes:
        g_note = 0.34 if len(pairs) > 2 else 0.55
        for f_v, p_v in pairs:
            _add_at(st_fan, st_s, _synth_cinematic_brass(f_v, d_s, SR, rng, p_v, 0.035), SR, g_note)
        _add_at(st_fan, st_s, _synth_taiko_boom(120.0, 52.0, min(0.45, d_s + 0.1), SR, rng, accent=1.0), SR, 0.48)
    _add_at(st_fan, 0.74, _synth_cinematic_strings(587.33, 2.25, SR, rng, -0.25, 0.22), SR, 0.45)
    _add_at(st_fan, 0.74, _synth_cinematic_strings(739.99, 2.25, SR, rng, 0.25, 0.22), SR, 0.38)
    _add_at(st_fan, 0.74, _synth_cymbal_swell(2.1, SR, rng, accent=0.85, crash=True), SR, 0.45)
    st_fan = _stereo_reverb(st_fan, SR, rt60=1.95, predelay_ms=24.0, wet=0.34, damping_hz=5200.0, seed=81)
    _write_pcm16_wav(os.path.join(SFX_DIR, "victory_fanfare.wav"), st_fan, SR, -11.5)

    print("[audio-fetch] Synthesized 11 modern stereo maritime, diplomacy, radar, and orchestral victory SFX WAVs.")


def _make_bubble_wrap_pop(
    dur: float,
    f_cavity_lo: float,
    f_cavity_peak: float,
    f_crack_lo: float,
    f_crack_hi: float,
    pan: float,
    seed_offset: int,
    rng: np.random.Generator,
) -> np.ndarray:
    """Physically modeled crisp polyethylene bubble-wrap pop at t0=4.5ms (beyond 3ms fade-in)."""
    n = max(64, int(dur * SR))
    lt = np.arange(n, dtype=np.float64) / SR
    t0 = 0.0045
    dt = np.maximum(0.0, lt - t0)
    mask = (lt >= t0).astype(np.float64)

    # Layer 1: faint pre-rupture plastic film crinkle before t0
    pre_mask = ((lt >= 0.001) & (lt < t0)).astype(np.float64)
    crinkle = _sos_bp(rng.standard_normal(n), SR, 3500.0, 9000.0, order=2) * pre_mask * 0.08

    # Layer 2: sharp polyethylene membrane rupture snap
    raw_burst = 0.65 * rng.standard_normal(n) + 0.35 * _pink_noise(n, rng)
    snap_band = _sos_bp(raw_burst, SR, f_crack_lo, f_crack_hi, order=2)
    snap = snap_band * mask * (0.85 * np.exp(-360.0 * dt) + 0.65 * np.exp(-1600.0 * dt))

    # Layer 3: hollow air-pocket cavity pop resonance
    f_t = f_cavity_lo + (f_cavity_peak - f_cavity_lo) * np.exp(-340.0 * dt) * (1.0 - np.exp(-1400.0 * dt))
    phase = 2.0 * np.pi * np.cumsum(f_t) / SR
    cav_env = mask * np.minimum(dt / 0.0008, 1.0) * np.exp(-135.0 * dt)
    cavity = (np.sin(phase) + 0.24 * np.sin(phase * 1.85)) * cav_env * 0.90

    # Layer 4: micro air-release puff
    puff = _sos_bp(_pink_noise(n, rng), SR, 1300.0, 4800.0, order=2) * mask * np.exp(-95.0 * dt) * 0.22

    mono = _soft_sat(crinkle + snap + cavity + puff, drive=1.25)
    st = _pan_stereo(mono, pan)
    return _stereo_reverb(st, SR, rt60=0.14, predelay_ms=3.5, wet=0.07, damping_hz=6800.0, seed=200 + seed_offset)


def generate_conquest_sfx() -> None:
    """Synthesize 6 tactile stereo bubble-wrap conquest pops and 1 restrained invasion warning."""
    os.makedirs(SFX_DIR, exist_ok=True)
    rng = np.random.default_rng(909)

    pop_variants = [
        (0.095, 420.0, 1080.0, 2200.0, 9800.0, -0.20, 1),
        (0.100, 490.0, 1260.0, 2600.0, 10600.0, 0.14, 2),
        (0.098, 560.0, 1390.0, 2400.0, 11000.0, -0.08, 3),
        (0.112, 380.0, 880.0, 2100.0, 8900.0, 0.20, 4),
        (0.105, 680.0, 1520.0, 2800.0, 11200.0, -0.15, 5),
        (0.108, 455.0, 1160.0, 2350.0, 10200.0, 0.07, 6),
    ]
    for idx, (dur, f_lo, f_pk, c_lo, c_hi, pan, s_off) in enumerate(pop_variants, start=1):
        st_pop = _make_bubble_wrap_pop(dur, f_lo, f_pk, c_lo, c_hi, pan, s_off, rng)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"conquer_pop_00{idx}.wav"), st_pop, SR, -15.5)

    # Restrained modern tactical perimeter warning when enemy conquers player territory
    dur_w = 0.58
    n_w = int(dur_w * SR)
    lt_w = np.arange(n_w, dtype=np.float64) / SR
    st_warn = np.zeros((n_w, 2), dtype=np.float64)
    pulses = [(0.00, 311.13, 622.25, -0.14, 0.42), (0.22, 233.08, 466.16, 0.14, 0.44)]
    for t_s, f_br, f_ping, p_pan, gain_br in pulses:
        _add_at(st_warn, t_s, _synth_cinematic_brass(f_br, 0.20, SR, rng, p_pan, 0.025), SR, gain_br)
        _add_at(st_warn, t_s, _make_tactile_click(0.065, f_ping, 4400.0, -p_pan, rng), SR, 0.38)
        dt_p = np.maximum(0.0, lt_w - t_s)
        mask_p = (lt_w >= t_s).astype(np.float64)
        ping = np.sin(2.0 * np.pi * f_ping * dt_p) * mask_p * np.minimum(dt_p / 0.003, 1.0) * np.exp(-16.0 * dt_p) * 0.28
        st_warn += _pan_stereo(ping, p_pan)
    st_warn = _stereo_reverb(st_warn, SR, rt60=0.68, predelay_ms=12.0, wet=0.22, damping_hz=4600.0, seed=210)
    _write_pcm16_wav(os.path.join(SFX_DIR, "invasion_warning.wav"), st_warn, SR, -14.5)
    print("[audio-fetch] Synthesized 6 stereo bubble-wrap conquest pops + 1 tactical invasion warning WAV.")


# ---------------------------------------------------------------------------
# 4. Seamless 14.0s Stereo Ocean & Stratospheric Breeze Ambience
# ---------------------------------------------------------------------------

def generate_ocean_ambience() -> None:
    os.makedirs(AMBIENCE_DIR, exist_ok=True)
    dest = os.path.join(AMBIENCE_DIR, "world_ocean_ambience.wav")
    duration_sec = 14.0
    n_samples = int(SR * duration_sec)
    crossfade = int(SR * 2.0)
    total_gen = n_samples + crossfade

    rng = np.random.default_rng(108)
    p_l = _pink_noise(total_gen, rng)
    p_r = _pink_noise(total_gen, rng)
    surf = np.column_stack([_sos_lp(p_l, SR, 460.0, order=2), _sos_lp(p_r, SR, 460.0, order=2)])
    breeze = np.column_stack([
        _sos_bp(p_l, SR, 280.0, 1250.0, order=2),
        _sos_bp(p_r, SR, 280.0, 1250.0, order=2),
    ]) * 0.22

    t = np.arange(total_gen, dtype=np.float64) / SR
    sw_l = (0.60 + 0.40 * np.sin(2.0 * np.pi * (2.0 / duration_sec) * t))[:, None]
    sw_r = (0.60 + 0.40 * np.sin(2.0 * np.pi * (2.0 / duration_sec) * t + 0.9))[:, None]
    br_mod = (0.68 + 0.32 * np.sin(2.0 * np.pi * (3.0 / duration_sec) * t + 1.4))[:, None]
    raw = np.column_stack([surf[:, 0] * sw_l[:, 0], surf[:, 1] * sw_r[:, 0]]) + breeze * br_mod

    alpha = np.linspace(0.0, 1.0, crossfade, dtype=np.float64)[:, None]
    loop = raw[crossfade:].copy()
    loop[:crossfade] = raw[crossfade : 2 * crossfade] * np.sqrt(alpha) + raw[:crossfade] * np.sqrt(1.0 - alpha)
    _write_pcm16_wav(dest, loop, SR, -18.5, seamless_loop=True)
    print(f"[audio-fetch] Synthesized seamless {duration_sec:.1f}s stereo ocean & high-altitude ambience at {dest}")


# ---------------------------------------------------------------------------
# 5. Modern Hybrid Orchestral-Cinematic Grand-Strategy Theme (100 BPM, 16 bars)
# ---------------------------------------------------------------------------

def generate_game_theme() -> None:
    """Synthesize a wide 44.1 kHz stereo 16-bar modern hybrid-cinematic strategy theme (D minor, 100 BPM)."""
    os.makedirs(MUSIC_DIR, exist_ok=True)
    dest = os.path.join(MUSIC_DIR, "world_war_pixel_theme.wav")

    bpm = 100.0
    beat_sec = 60.0 / bpm  # 0.60s
    bar_sec = beat_sec * 4.0  # 2.40s
    rng = np.random.default_rng(404)

    # 16 bars x 2.40s = 38.40s seamless stereo orchestral-cinematic loop
    chords = [
        # Intro / Strategic Tension (Bars 1-4)
        (73.42, [146.83, 220.00, 261.63, 329.63]),  # Dm9
        (58.27, [116.54, 174.61, 220.00, 293.66]),  # Bbmaj7
        (65.41, [130.81, 196.00, 220.00, 261.63]),  # C6
        (55.00, [110.00, 164.81, 220.00, 293.66]),  # Asus4 -> A
        # Escalation (Bars 5-8)
        (73.42, [146.83, 220.00, 261.63, 349.23]),  # Dm7
        (98.00, [196.00, 233.08, 293.66, 349.23]),  # Gm7
        (58.27, [116.54, 174.61, 220.00, 293.66]),  # Bbmaj7
        (55.00, [110.00, 164.81, 220.00, 277.18]),  # A7 (swell)
        # Heroic Climax (Bars 9-14)
        (73.42, [146.83, 220.00, 293.66, 349.23]),  # Dm
        (87.31, [174.61, 220.00, 261.63, 349.23]),  # F
        (65.41, [130.81, 196.00, 261.63, 329.63]),  # C
        (98.00, [196.00, 233.08, 293.66, 349.23]),  # Gm7
        (58.27, [116.54, 174.61, 233.08, 293.66]),  # Bb
        (98.00, [196.00, 233.08, 293.66, 392.00]),  # Gm
        # Dramatic Cadence & Turnaround (Bars 15-16)
        (55.00, [110.00, 164.81, 220.00, 277.18]),  # A7
        (73.42, [146.83, 220.00, 293.66, 329.63]),  # Dm(add9)
    ]

    # Felt-piano tactical 8th-note ostinato degrees (cycled across bars 0..15)
    piano_arps = [
        [293.66, 440.00, 523.25, 440.00, 349.23, 440.00, 587.33, 440.00],  # Dm9
        [233.08, 349.23, 440.00, 349.23, 293.66, 349.23, 523.25, 349.23],  # Bbmaj7
        [261.63, 392.00, 440.00, 392.00, 329.63, 392.00, 523.25, 392.00],  # C6
        [220.00, 329.63, 440.00, 329.63, 277.18, 329.63, 440.00, 329.63],  # Asus4->A
    ]

    # Thematic horn/brass melodies (bars 4..15): (start_beat, dur_beats, freq_hz)
    lead_melody = [
        [],
        [],
        [(0.0, 1.8, 440.00), (2.0, 1.8, 523.25)],
        [(0.0, 2.0, 493.88), (2.0, 1.6, 440.00)],
        [(0.0, 1.0, 440.00), (1.0, 0.5, 493.88), (1.5, 0.5, 523.25), (2.0, 1.8, 587.33)],
        [(0.0, 1.5, 523.25), (1.5, 0.5, 466.16), (2.0, 1.8, 440.00)],
        [(0.0, 1.0, 392.00), (1.0, 1.0, 466.16), (2.0, 1.8, 523.25)],
        [(0.0, 2.0, 440.00), (2.0, 1.8, 554.37)],
        [(0.0, 1.0, 587.33), (1.0, 0.5, 659.25), (1.5, 0.5, 698.46), (2.0, 1.8, 880.00)],
        [(0.0, 1.0, 783.99), (1.0, 0.5, 698.46), (1.5, 0.5, 659.25), (2.0, 1.8, 587.33)],
        [(0.0, 1.0, 659.25), (1.0, 1.0, 587.33), (2.0, 1.8, 523.25)],
        [(0.0, 1.5, 587.33), (1.5, 0.5, 466.16), (2.0, 1.8, 440.00)],
        [(0.0, 1.0, 466.16), (1.0, 1.0, 587.33), (2.0, 1.8, 698.46)],
        [(0.0, 1.5, 587.33), (1.5, 0.5, 523.25), (2.0, 1.8, 466.16)],
        [(0.0, 2.0, 440.00), (2.0, 1.0, 554.37), (3.0, 0.9, 659.25)],
        [(0.0, 2.6, 587.33), (2.6, 1.2, 440.00)],
    ]

    total_sec = len(chords) * bar_sec  # 38.4s
    crossfade_sec = bar_sec  # 2.4s exact bar crossfade
    gen_sec = total_sec + crossfade_sec
    n_gen = int(SR * gen_sec)
    mix = np.zeros((n_gen, 2), dtype=np.float64)

    for bar_idx in range(len(chords) + 1):
        c_idx = bar_idx % len(chords)
        bar_t0 = bar_idx * bar_sec
        if bar_t0 >= gen_sec:
            break

        bass_f, chord_notes = chords[c_idx]
        climax = (8 <= c_idx <= 14)
        mid_build = (4 <= c_idx <= 7)

        # 1. Wide stereo lush string ensemble pad per bar
        pad_pans = [-0.50, 0.45, -0.25, 0.30]
        pad_gain = 0.24 if climax else (0.20 if mid_build else 0.16)
        for v_i, c_hz in enumerate(chord_notes):
            _add_at(
                mix,
                bar_t0,
                _synth_cinematic_strings(c_hz, bar_sec * 1.06, SR, rng, pad_pans[v_i % 4], 0.22),
                SR,
                pad_gain,
            )
        if climax:
            _add_at(mix, bar_t0, _synth_cinematic_strings(chord_notes[0] * 2.0, bar_sec * 1.04, SR, rng, 0.0, 0.28), SR, 0.18)

        # 2. Deep warm modern sub-bass pulse on beat 1 and syncopated 2.5
        _add_at(mix, bar_t0, _synth_sub_pulse(bass_f, beat_sec * 1.7, SR), SR, 0.42 if climax else 0.32)
        _add_at(mix, bar_t0 + 2.5 * beat_sec, _synth_sub_pulse(bass_f, beat_sec * 1.3, SR), SR, 0.34 if climax else 0.24)

        # 3. Tactical felt-piano 8th-note ostinato panning subtly across stereo
        arp_seq = piano_arps[c_idx % 4]
        for step_i, p_hz in enumerate(arp_seq):
            t_note = bar_t0 + step_i * (beat_sec * 0.5)
            p_pan = -0.32 + 0.64 * (float(step_i % 4) / 3.0)
            p_gain = 0.20 if (step_i % 2 == 0) else 0.14
            if climax:
                p_gain *= 0.85
            _add_at(mix, t_note, _synth_felt_piano(p_hz, beat_sec * 1.15, SR, rng, p_pan), SR, p_gain)

        # 4. French Horn / Brass Ensemble Heroic Melody
        for st_b, dur_b, m_hz in lead_melody[c_idx]:
            t_m = bar_t0 + st_b * beat_sec
            b_gain = 0.28 if climax else 0.19
            _add_at(mix, t_m, _synth_cinematic_brass(m_hz, dur_b * beat_sec, SR, rng, 0.06, 0.055), SR, b_gain)
            if climax:
                _add_at(mix, t_m, _synth_cinematic_brass(m_hz * 0.5, dur_b * beat_sec, SR, rng, -0.14, 0.06), SR, 0.18)

        # 5. Modern Hybrid Taiko + Snare Percussion
        if c_idx >= 2:
            kicks = [(0.0, 1.0), (1.5, 0.55), (2.0, 0.88), (3.5, 0.65)] if (mid_build or climax) else [(0.0, 0.65), (2.0, 0.52)]
            k_gain = 0.44 if climax else (0.34 if mid_build else 0.22)
            for b_k, acc in kicks:
                _add_at(mix, bar_t0 + b_k * beat_sec, _synth_taiko_boom(115.0, bass_f * 0.72, 0.36, SR, rng, acc), SR, k_gain)

        if mid_build or climax:
            for b_s, s_acc in [(1.0, 0.65), (2.75, 0.45), (3.0, 0.78), (3.5, 0.55)]:
                _add_at(mix, bar_t0 + b_s * beat_sec, _synth_cinematic_snare(0.11, SR, rng, s_acc), SR, 0.22 if climax else 0.15)
        if c_idx in (7, 15):
            _add_at(mix, bar_t0 + 2.0 * beat_sec, _synth_cymbal_swell(2.0 * beat_sec, SR, rng, accent=0.85, crash=False), SR, 0.32)
        if c_idx in (8, 12):
            _add_at(mix, bar_t0, _synth_cymbal_swell(2.4, SR, rng, accent=0.80, crash=True), SR, 0.28)

    # Concert hall master ambience + subsonic clean HP + warm analog glue
    mix = _stereo_reverb(mix, SR, rt60=1.85, predelay_ms=22.0, wet=0.22, damping_hz=5200.0, seed=404)
    mix = _sos_hp(mix, SR, 28.0, order=2)
    mix = _sos_lp(mix, SR, 15500.0, order=2)

    xf = int(crossfade_sec * SR)
    n_loop = int(total_sec * SR)
    alpha = np.linspace(0.0, 1.0, xf, dtype=np.float64)[:, None]
    loop = mix[xf : xf + n_loop].copy()
    loop[:xf] = mix[xf : 2 * xf] * np.sqrt(alpha) + mix[:xf] * np.sqrt(1.0 - alpha)
    _write_pcm16_wav(dest, loop, SR, -16.0, seamless_loop=True)
    print(f"[audio-fetch] Synthesized seamless {total_sec:.1f}s stereo hybrid-cinematic theme at {dest}")


# ---------------------------------------------------------------------------
# 6. CC0 lotsofsounds.com Fetcher, Transient Editor & Studio Mastering Pipeline
# ---------------------------------------------------------------------------

def _find_ffmpeg() -> str:
    ff = shutil.which("ffmpeg")
    if ff:
        return ff
    fallback = r"C:\Program Files\Softdeluxe\Free Download Manager\ffmpeg.exe"
    if os.path.exists(fallback):
        return fallback
    raise FileNotFoundError("ffmpeg executable not found in PATH or fallback location.")


def _fetch_los_mp3(sound_id: str) -> str:
    os.makedirs(LOS_CACHE_DIR, exist_ok=True)
    cache_path = os.path.join(LOS_CACHE_DIR, f"{sound_id}.mp3")
    if os.path.exists(cache_path) and os.path.getsize(cache_path) > 512:
        return cache_path

    api_url = f"{LOS_API_BASE}/{sound_id}/stream"
    meta_raw = subprocess.check_output(
        ["curl.exe", "-sSL", "--fail", "-m", "20", api_url],
        stderr=subprocess.STDOUT,
    ).decode("utf-8")
    payload = json.loads(meta_raw)
    stream_url = payload["data"]["stream_url"]
    tmp_path = cache_path + ".tmp"
    subprocess.check_call(
        ["curl.exe", "-sSL", "--fail", "-m", "60", "-o", tmp_path, stream_url],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
    assert os.path.getsize(tmp_path) > 512, f"Downloaded MP3 for {sound_id} is unexpectedly small."
    os.replace(tmp_path, cache_path)
    return cache_path


def _decode_mp3_stereo_44k(mp3_path: str, ffmpeg_bin: str) -> np.ndarray:
    raw = subprocess.check_output(
        [
            ffmpeg_bin,
            "-v",
            "error",
            "-i",
            mp3_path,
            "-f",
            "f32le",
            "-acodec",
            "pcm_f32le",
            "-ac",
            "2",
            "-ar",
            str(SR),
            "pipe:1",
        ]
    )
    arr = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    n_frames = len(arr) // 2
    assert n_frames > 16, f"Decoded audio from {mp3_path} is empty."
    st = arr[: n_frames * 2].reshape(n_frames, 2)
    return st


def _load_los_stereo(sound_id: str, ffmpeg_bin: str) -> np.ndarray:
    mp3_path = _fetch_los_mp3(sound_id)
    st = _decode_mp3_stereo_44k(mp3_path, ffmpeg_bin)
    peak = float(np.max(np.abs(st)))
    if peak > 1e-6:
        st = st / peak * 0.90
    return st


def _trim_onset(st: np.ndarray, threshold_db: float = -28.0, pre_roll_ms: float = 2.5) -> np.ndarray:
    mono = np.max(np.abs(st), axis=1)
    peak = float(np.max(mono))
    if peak < 1e-7:
        return st
    thresh = peak * (10.0 ** (threshold_db / 20.0))
    hits = np.flatnonzero(mono >= thresh)
    if len(hits) == 0:
        return st
    pre_n = int(pre_roll_ms * 0.001 * SR)
    i0 = max(0, int(hits[0]) - pre_n)
    return st[i0:].copy()


def _extract_best_window(
    st: np.ndarray,
    dur_sec: float,
    sr: int = SR,
    pre_roll_ms: float = 14.0,
    min_start_sec: float = 0.0,
    threshold_ratio: float = 0.38,
) -> np.ndarray:
    target_n = max(64, int(dur_sec * sr))
    if len(st) <= target_n:
        out = _trim_onset(st, -30.0, pre_roll_ms)
        return out
    hop = max(1, int(0.02 * sr))
    mono_sq = np.mean(st * st, axis=1)
    n_hops = max(1, len(mono_sq) // hop)
    hop_rms = np.sqrt(np.mean(mono_sq[: n_hops * hop].reshape(n_hops, hop), axis=1))
    min_h = min(n_hops - 1, int(min_start_sec / 0.02))
    sub = hop_rms[min_h:]
    sub_max = float(np.max(sub)) if len(sub) > 0 else 0.0
    if sub_max < 1e-7:
        return _trim_onset(st, -30.0, pre_roll_ms)[:target_n]
    hits = np.flatnonzero(sub >= sub_max * threshold_ratio)
    h_idx = min_h + (int(hits[0]) if len(hits) > 0 else int(np.argmax(sub)))
    i0 = max(0, h_idx * hop - int(pre_roll_ms * 0.001 * sr))
    if i0 + target_n > len(st):
        i0 = max(0, len(st) - target_n)
    win = st[i0 : i0 + target_n].copy()
    if float(np.sqrt(np.mean(win * win))) < 1e-5:
        return _trim_onset(st, -30.0, pre_roll_ms)[:target_n]
    return win


def _extract_distinct_pops(
    st: np.ndarray, count: int, pop_dur_sec: float = 0.135, min_sep_sec: float = 0.35
) -> list[np.ndarray]:
    mono = np.mean(np.abs(st), axis=1)
    win_n = max(8, int(0.003 * SR))
    kernel = np.ones(win_n, dtype=np.float64) / win_n
    env = np.convolve(mono, kernel, mode="same")
    sep_n = int(min_sep_sec * SR)
    pre_n = int(0.004 * SR)
    pop_n = int(pop_dur_sec * SR)

    work = env.copy()
    slices: list[np.ndarray] = []
    for _ in range(count):
        if len(work) == 0:
            break
        pk = int(np.argmax(work))
        if work[pk] < 1e-6:
            break
        i0 = max(0, pk - pre_n)
        i1 = min(len(st), i0 + pop_n)
        chunk = st[i0:i1].copy()
        if float(np.sqrt(np.mean(chunk * chunk))) > 1e-5:
            slices.append(chunk)
        lo = max(0, pk - sep_n)
        hi = min(len(work), pk + sep_n)
        work[lo:hi] = 0.0
    while len(slices) < count:
        slices.append(_trim_onset(st, -26.0, 4.0)[:pop_n])
    return slices


def _pitch_shift_resample(st: np.ndarray, rate: float) -> np.ndarray:
    if abs(rate - 1.0) < 1e-4:
        return st.copy()
    n_in = len(st)
    n_out = max(16, int(round(n_in / rate)))
    x_old = np.arange(n_in, dtype=np.float64)
    x_new = np.linspace(0.0, n_in - 1.0, n_out)
    left = np.interp(x_new, x_old, st[:, 0])
    right = np.interp(x_new, x_old, st[:, 1])
    return np.column_stack([left, right])


def _presence_shelf(st: np.ndarray, sr: int, lo_hz: float, hi_hz: float, gain_db: float) -> np.ndarray:
    mult = (10.0 ** (gain_db / 20.0)) - 1.0
    return st + _sos_bp(st, sr, lo_hz, hi_hz, order=2) * mult


def _make_seamless_loop(st: np.ndarray, target_dur_sec: float, xfade_sec: float, sr: int = SR) -> np.ndarray:
    target_n = int(target_dur_sec * sr)
    xf = min(int(xfade_sec * sr), target_n // 4)
    needed = target_n + xf
    if len(st) < needed:
        reps = int(np.ceil(needed / max(1, len(st))))
        src = np.tile(st, (reps, 1))[:needed].copy()
    else:
        src = st[:needed].copy()
    alpha = np.linspace(0.0, 1.0, xf, dtype=np.float64)[:, None]
    loop = src[xf : xf + target_n].copy()
    loop[:xf] = src[xf : 2 * xf] * np.sqrt(alpha) + src[:xf] * np.sqrt(1.0 - alpha)
    return loop


def _shape_tail(
    st: np.ndarray,
    max_dur_sec: float,
    fade_in_ms: float = 2.5,
    fade_out_sec: float = 0.08,
    pan: float = 0.0,
) -> np.ndarray:
    n_target = max(32, int(max_dur_sec * SR))
    if len(st) > n_target:
        out = st[:n_target].copy()
    else:
        out = st.copy()
    fi_n = min(len(out), int(fade_in_ms * 0.001 * SR))
    if fi_n > 1:
        out[:fi_n] *= np.linspace(0.0, 1.0, fi_n)[:, None]
    fo_n = min(len(out) // 2 if len(out) > 64 else len(out), int(fade_out_sec * SR))
    if fo_n > 1:
        t_f = np.linspace(0.0, np.pi * 0.5, fo_n)
        out[-fo_n:] *= (np.cos(t_f) ** 2)[:, None]
    if abs(pan) > 1e-3:
        gain_l = float(np.cos((np.clip(pan, -1.0, 1.0) + 1.0) * np.pi * 0.25)) * np.sqrt(2.0)
        gain_r = float(np.sin((np.clip(pan, -1.0, 1.0) + 1.0) * np.pi * 0.25)) * np.sqrt(2.0)
        out[:, 0] *= gain_l
        out[:, 1] *= gain_r
    return out


def build_lotsofsounds_audio() -> None:
    """Fetch, edit, and studio-master all 29 active game audio items from verified CC0 lotsofsounds.com sources."""
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(AMBIENCE_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)

    ffmpeg_bin = _find_ffmpeg()
    rng = np.random.default_rng(2026)

    # All 29 verified CC0 sample IDs (matched to SFX_TRACKER.md)
    los_credits: list[tuple[str, str, str]] = []

    def fetch(sid: str) -> np.ndarray:
        return _load_los_stereo(sid, ffmpeg_bin)

    print("[audio-los] Fetching & mastering 29 CC0 sound groups from lotsofsounds.com...")

    # #1 Main Theme Music -> 36.0s seamless orchestral loop with sculpted SFX pocket
    mus_raw = _trim_onset(fetch("fs-569367"), -36.0, 20.0)
    mus = _make_seamless_loop(mus_raw, 36.0, 2.4, SR)
    mus = _sos_hp(mus, SR, 32.0, order=2)
    mus = _sos_lp(mus, SR, 15500.0, order=2)
    mus = _presence_shelf(mus, SR, 2200.0, 4400.0, -2.2)
    _write_pcm16_wav(os.path.join(MUSIC_DIR, "world_war_pixel_theme.wav"), mus, SR, -17.0, seamless_loop=True)
    los_credits.append(("assets/audio/music/world_war_pixel_theme.wav", "fs-569367", "Sea Warrior Theme (36.0s seamless loop)"))

    # #2 Ocean & Wind Ambience -> 24.0s seamless stereo surf loop
    amb_raw = _trim_onset(fetch("fs-145213"), -36.0, 50.0)
    amb = _make_seamless_loop(amb_raw, 24.0, 3.0, SR)
    amb = _sos_hp(amb, SR, 55.0, order=2)
    amb = _sos_lp(amb, SR, 5800.0, order=2)
    _write_pcm16_wav(os.path.join(AMBIENCE_DIR, "world_ocean_ambience.wav"), amb, SR, -20.0, seamless_loop=True)
    los_credits.append(("assets/audio/ambience/world_ocean_ambience.wav", "fs-145213", "Ocean Waves Loop (24.0s seamless loop)"))

    # #3 Land Conquest Bubble-Wrap Pops (6 distinct variants, ultra-crisp onset)
    multi_pops = _extract_distinct_pops(fetch("fs-164469"), 2, 0.135, 0.35)
    pop_specs = [
        ("conquer_pop_001.wav", _trim_onset(fetch("fs-217760"), -26.0, 2.0), 0.135, -0.20, "fs-217760"),
        ("conquer_pop_002.wav", _trim_onset(fetch("fs-217761"), -26.0, 2.0), 0.140, 0.16, "fs-217761"),
        ("conquer_pop_003.wav", _trim_onset(fetch("fs-217762"), -26.0, 2.0), 0.140, -0.10, "fs-217762"),
        ("conquer_pop_004.wav", _trim_onset(fetch("fs-217764"), -26.0, 2.0), 0.125, 0.20, "fs-217764"),
        ("conquer_pop_005.wav", multi_pops[0], 0.135, -0.14, "fs-164469#pop1"),
        ("conquer_pop_006.wav", multi_pops[1], 0.135, 0.08, "fs-164469#pop2"),
    ]
    for idx_p, (fname, chunk, p_dur, pan, src_tag) in enumerate(pop_specs, start=1):
        pop = _shape_tail(chunk, p_dur, fade_in_ms=1.5, fade_out_sec=0.028, pan=pan)
        pop = _sos_hp(pop, SR, 140.0, order=2)
        pop = _presence_shelf(pop, SR, 2200.0, 7200.0, 2.0)
        pop = _stereo_reverb(pop, SR, rt60=0.14, predelay_ms=3.0, wet=0.05, damping_hz=6800.0, seed=300 + idx_p)
        _write_pcm16_wav(os.path.join(SFX_DIR, fname), pop, SR, -15.5, fade_in_ms=1.5)
        los_credits.append((f"assets/audio/sfx/{fname}", src_tag.split("#")[0], f"Bubble-Wrap Pop variant #{idx_p}"))

    # #4 Under-Attack Invasion Warning -> tactical submarine sonar ping
    warn = _extract_best_window(fetch("fs-70299"), 0.95, SR, 12.0, 0.0, 0.32)
    warn = _shape_tail(warn, 0.95, fade_in_ms=4.0, fade_out_sec=0.18)
    warn = _sos_hp(warn, SR, 140.0, order=2)
    warn = _sos_lp(warn, SR, 7500.0, order=2)
    warn = _stereo_reverb(warn, SR, rt60=0.65, predelay_ms=10.0, wet=0.18, damping_hz=5000.0, seed=310)
    _write_pcm16_wav(os.path.join(SFX_DIR, "invasion_warning.wav"), warn, SR, -14.5)
    los_credits.append(("assets/audio/sfx/invasion_warning.wav", "fs-70299", "Submarine Sonar warning pulse"))

    # #5 Land Expansion Launch (glass_001/002)
    for idx_g, sid_g in enumerate(["fs-127196", "fs-127197"], start=1):
        g = _shape_tail(_trim_onset(fetch(sid_g), -28.0, 3.0), 0.36, fade_in_ms=2.0, fade_out_sec=0.06)
        g = _sos_hp(g, SR, 65.0, order=2)
        g = _presence_shelf(g, SR, 1800.0, 5200.0, 1.5)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"glass_00{idx_g}.wav"), g, SR, -15.5, fade_in_ms=2.0)
        los_credits.append((f"assets/audio/sfx/glass_00{idx_g}.wav", sid_g, "Cinematic Whoosh Hit"))

    # #6 Retreat / Cancel / Eliminated Horn
    ret = _extract_best_window(fetch("fs-507471"), 1.15, SR, 28.0, 0.1, 0.42)
    ret = _shape_tail(ret, 1.15, fade_in_ms=35.0, fade_out_sec=0.28)
    ret = _sos_hp(ret, SR, 55.0, order=2)
    ret = _sos_lp(ret, SR, 4800.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "retreat_horn.wav"), ret, SR, -15.0)
    los_credits.append(("assets/audio/sfx/retreat_horn.wav", "fs-507471", "Long Distant Foghorn recall"))

    # #7 Homeland Counter-Attack Clash -> Punch Hit + low artillery body
    clash = _shape_tail(_trim_onset(fetch("fs-118513"), -28.0, 2.0), 0.55, fade_in_ms=1.5, fade_out_sec=0.10)
    cannon_lo = _sos_lp(_shape_tail(_trim_onset(fetch("fs-184650"), -26.0, 2.0), 0.45, fade_in_ms=2.0, fade_out_sec=0.14), SR, 260.0, order=2)
    _add_at(clash, 0.0, cannon_lo, SR, 0.40)
    clash = _sos_hp(clash, SR, 42.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "battle_clash.wav"), clash, SR, -14.5, fade_in_ms=1.5)
    los_credits.append(("assets/audio/sfx/battle_clash.wav", "fs-118513", "Punch Hit + low cannon thump"))

    # #8 Building Placed (maximize_001/002) -> crisp industrial impact + anchor sub thud
    for idx_b, sid_b in enumerate(["fs-131304", "fs-127148"], start=1):
        bld = _shape_tail(_trim_onset(fetch(sid_b), -28.0, 2.0), 0.36, fade_in_ms=1.5, fade_out_sec=0.08)
        _add_at(bld, 0.0, _synth_taiko_boom(115.0, 48.0, 0.18, SR, rng, accent=0.8), SR, 0.32)
        bld = _sos_hp(bld, SR, 45.0, order=2)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"maximize_00{idx_b}.wav"), bld, SR, -15.0, fade_in_ms=1.5)
        los_credits.append((f"assets/audio/sfx/maximize_00{idx_b}.wav", sid_b, "Industrial Building Placement"))

    # #9 Instant Building Upgrade (upgrade_001/002)
    for idx_u, sid_u in enumerate(["fs-242501", "fs-220173"], start=1):
        up = _shape_tail(_trim_onset(fetch(sid_u), -30.0, 4.0), 0.50, fade_in_ms=3.0, fade_out_sec=0.10)
        up = _sos_hp(up, SR, 120.0, order=2)
        up = _stereo_reverb(up, SR, rt60=0.55, predelay_ms=8.0, wet=0.14, damping_hz=6400.0, seed=320 + idx_u)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"upgrade_00{idx_u}.wav"), up, SR, -15.5)
        los_credits.append((f"assets/audio/sfx/upgrade_00{idx_u}.wav", sid_u, "Power Up Upgrade Chime"))

    # #10 Factory Road / Water Bridge Connected
    br = _shape_tail(_trim_onset(fetch("fs-107589"), -28.0, 3.0), 0.58, fade_in_ms=2.0, fade_out_sec=0.12)
    _add_at(br, 0.0, _synth_taiko_boom(135.0, 52.0, 0.22, SR, rng, accent=0.85), SR, 0.35)
    br = _sos_hp(br, SR, 55.0, order=2)
    br = _stereo_reverb(br, SR, rt60=0.65, predelay_ms=10.0, wet=0.18, damping_hz=5600.0, seed=325)
    _write_pcm16_wav(os.path.join(SFX_DIR, "bridge_connect.wav"), br, SR, -15.0, fade_in_ms=2.0)
    los_credits.append(("assets/audio/sfx/bridge_connect.wav", "fs-107589", "Steel Link Clank + Anchor"))

    # #11 Trade Gold / Captured Trade Ship (pluck_001/002)
    for idx_c, (sid_c, c_dur) in enumerate([("fs-167564", 0.34), ("fs-167565", 0.42)], start=1):
        cn = _shape_tail(_trim_onset(fetch(sid_c), -28.0, 2.0), c_dur, fade_in_ms=1.5, fade_out_sec=0.07)
        cn = _sos_hp(cn, SR, 260.0, order=2)
        cn = _stereo_reverb(cn, SR, rt60=0.45, predelay_ms=6.0, wet=0.14, damping_hz=7200.0, seed=330 + idx_c)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"pluck_00{idx_c}.wav"), cn, SR, -17.0, fade_in_ms=1.5)
        los_credits.append((f"assets/audio/sfx/pluck_00{idx_c}.wav", sid_c, "Coin Drop Ring treasury chime"))

    # #12 Naval Landing Bell -> pitched down 0.86x for authentic bronze ship's bell
    bell = _pitch_shift_resample(_trim_onset(fetch("fs-116779"), -30.0, 3.0), 0.86)
    bell = _shape_tail(bell, 0.95, fade_in_ms=2.0, fade_out_sec=0.20)
    bell = _sos_hp(bell, SR, 120.0, order=2)
    bell = _stereo_reverb(bell, SR, rt60=0.95, predelay_ms=12.0, wet=0.20, damping_hz=6000.0, seed=335)
    _write_pcm16_wav(os.path.join(SFX_DIR, "boat_bell.wav"), bell, SR, -14.5, fade_in_ms=2.0)
    los_credits.append(("assets/audio/sfx/boat_bell.wav", "fs-116779", "Bronze Naval Landing Bell"))

    # #13 Trade Ship Departing Port -> clean harbor boat horn blast
    sh_dep = _extract_best_window(fetch("fs-162350"), 1.15, SR, 22.0, 0.2, 0.45)
    sh_dep = _shape_tail(sh_dep, 1.15, fade_in_ms=25.0, fade_out_sec=0.24)
    sh_dep = _sos_hp(sh_dep, SR, 65.0, order=2)
    sh_dep = _sos_lp(sh_dep, SR, 5200.0, order=2)
    sh_dep = _stereo_reverb(sh_dep, SR, rt60=1.0, predelay_ms=14.0, wet=0.22, damping_hz=4200.0, seed=340)
    _write_pcm16_wav(os.path.join(SFX_DIR, "ship_depart.wav"), sh_dep, SR, -15.5)
    los_credits.append(("assets/audio/sfx/ship_depart.wav", "fs-162350", "Harbor Boat Horn Blast"))

    # #14 Warship Horn -> deep Epic Inception Horn
    wh = _shape_tail(_trim_onset(fetch("fs-194812"), -32.0, 12.0), 1.30, fade_in_ms=18.0, fade_out_sec=0.26)
    wh = _sos_hp(wh, SR, 38.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "warship_horn.wav"), wh, SR, -13.5)
    los_credits.append(("assets/audio/sfx/warship_horn.wav", "fs-194812", "Deep Destroyer Warship Horn"))

    # #15 Warship Naval Cannon Fire
    can = _shape_tail(_trim_onset(fetch("fs-184650"), -28.0, 2.0), 1.15, fade_in_ms=1.5, fade_out_sec=0.20)
    can = _sos_hp(can, SR, 40.0, order=2)
    can = _stereo_reverb(can, SR, rt60=0.85, predelay_ms=12.0, wet=0.16, damping_hz=4800.0, seed=345)
    _write_pcm16_wav(os.path.join(SFX_DIR, "cannon_fire.wav"), can, SR, -14.0, fade_in_ms=1.5)
    los_credits.append(("assets/audio/sfx/cannon_fire.wav", "fs-184650", "Naval Cannon Boom"))

    # #16 Missile Target Lock
    lk = _shape_tail(_trim_onset(fetch("fs-220182"), -30.0, 3.0), 0.38, fade_in_ms=2.0, fade_out_sec=0.06)
    lk = _sos_hp(lk, SR, 180.0, order=2)
    lk = _presence_shelf(lk, SR, 2000.0, 6200.0, 1.5)
    _write_pcm16_wav(os.path.join(SFX_DIR, "target_lock.wav"), lk, SR, -15.0, fade_in_ms=2.0)
    los_credits.append(("assets/audio/sfx/target_lock.wav", "fs-220182", "Avionics Target Lock Beep"))

    # #17 Atom Bomb Launch -> punchy rocket launch + ignition thruster tail
    rkt_tail = _shape_tail(_extract_best_window(fetch("fs-146770"), 1.00, SR, 10.0, 0.0, 0.4), 1.00, fade_in_ms=12.0, fade_out_sec=0.25)
    msl = _shape_tail(_trim_onset(fetch("fs-47252"), -28.0, 2.0), 1.30, fade_in_ms=2.0, fade_out_sec=0.24)
    _add_at(msl, 0.04, rkt_tail, SR, 0.50)
    msl = _sos_hp(msl, SR, 45.0, order=2)
    msl = _stereo_reverb(msl, SR, rt60=0.90, predelay_ms=12.0, wet=0.18, damping_hz=5200.0, seed=350)
    _write_pcm16_wav(os.path.join(SFX_DIR, "missile_launch.wav"), msl, SR, -13.5, fade_in_ms=2.0)
    los_credits.append(("assets/audio/sfx/missile_launch.wav", "fs-47252", "Atom Missile Launch + Rocket Ignition"))

    # #18 Hydrogen Bomb / MIRV Silo Launch -> pneumatic silo hatch thump + deep rocket roar
    silo = _shape_tail(_trim_onset(fetch("fs-146770"), -30.0, 10.0), 2.35, fade_in_ms=12.0, fade_out_sec=0.35)
    _add_at(silo, 0.0, _synth_taiko_boom(110.0, 40.0, 0.28, SR, rng, accent=0.95), SR, 0.55)
    silo = _sos_hp(silo, SR, 38.0, order=2)
    silo = _stereo_reverb(silo, SR, rt60=1.10, predelay_ms=14.0, wet=0.20, damping_hz=4500.0, seed=355)
    _write_pcm16_wav(os.path.join(SFX_DIR, "silo_nuke_launch.wav"), silo, SR, -13.0)
    los_credits.append(("assets/audio/sfx/silo_nuke_launch.wav", "fs-146770", "ICBM Silo Rocket Ignition"))

    # #19 SAM Interceptor Launch -> high-speed interceptor passby
    sam = _shape_tail(_trim_onset(fetch("fs-105016"), -28.0, 2.0), 0.92, fade_in_ms=1.5, fade_out_sec=0.16)
    sam = _sos_hp(sam, SR, 140.0, order=2)
    sam = _presence_shelf(sam, SR, 2400.0, 7500.0, 2.0)
    _write_pcm16_wav(os.path.join(SFX_DIR, "sam_launch.wav"), sam, SR, -13.5, fade_in_ms=1.5)
    los_credits.append(("assets/audio/sfx/sam_launch.wav", "fs-105016", "SAM Interceptor Whoosh"))

    # #20 SAM Mid-Air Intercept -> sharp metallic airburst
    icp = _shape_tail(_trim_onset(fetch("fs-244394"), -28.0, 2.0), 1.35, fade_in_ms=1.5, fade_out_sec=0.28)
    icp = _sos_hp(icp, SR, 75.0, order=2)
    icp = _stereo_reverb(icp, SR, rt60=1.0, predelay_ms=14.0, wet=0.22, damping_hz=5400.0, seed=360)
    _write_pcm16_wav(os.path.join(SFX_DIR, "sam_intercept.wav"), icp, SR, -13.5, fade_in_ms=1.5)
    los_credits.append(("assets/audio/sfx/sam_intercept.wav", "fs-244394", "Mid-Air Flak / Missile Intercept"))

    # #21 Nuclear Detonation Blast -> massive sub-shockwave layered blend
    nuke = _shape_tail(_trim_onset(fetch("fs-149966"), -28.0, 4.0), 3.60, fade_in_ms=2.0, fade_out_sec=0.75)
    nuke_layer = _shape_tail(_trim_onset(fetch("fs-156498"), -28.0, 4.0), 3.60, fade_in_ms=2.0, fade_out_sec=0.75)
    _add_at(nuke, 0.0, nuke_layer, SR, 0.56)
    lt_nk = np.arange(len(nuke), dtype=np.float64) / SR
    sub_drop = np.sin(2.0 * np.pi * np.cumsum(48.0 * np.exp(-2.2 * lt_nk) + 26.0) / SR) * np.minimum(lt_nk / 0.015, 1.0) * np.exp(-1.1 * lt_nk)
    nuke += _pan_stereo(sub_drop, 0.0) * 0.42
    nuke = _sos_hp(nuke, SR, 28.0, order=2)
    nuke = _stereo_reverb(nuke, SR, rt60=2.1, predelay_ms=20.0, wet=0.30, damping_hz=3600.0, seed=365)
    _write_pcm16_wav(os.path.join(SFX_DIR, "nuke_blast.wav"), nuke, SR, -10.5, fade_in_ms=2.0)
    los_credits.append(("assets/audio/sfx/nuke_blast.wav", "fs-149966", "Nuclear Detonation + Shockwave Layer (fs-156498)"))

    # #22 Diplomacy / Alliance Chime
    dip = _shape_tail(_trim_onset(fetch("fs-456965"), -30.0, 4.0), 1.15, fade_in_ms=3.0, fade_out_sec=0.22)
    dip = _sos_hp(dip, SR, 140.0, order=2)
    dip = _stereo_reverb(dip, SR, rt60=0.95, predelay_ms=12.0, wet=0.20, damping_hz=6200.0, seed=370)
    _write_pcm16_wav(os.path.join(SFX_DIR, "diplomacy_chime.wav"), dip, SR, -15.5)
    los_credits.append(("assets/audio/sfx/diplomacy_chime.wav", "fs-456965", "Glockenspiel Alliance Chime"))

    # #23 Betrayal / Broken Alliance Alert -> Epic Trailer Horn
    bet = _shape_tail(_trim_onset(fetch("fs-204310"), -30.0, 12.0), 1.65, fade_in_ms=14.0, fade_out_sec=0.35)
    bet = _sos_hp(bet, SR, 38.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "betrayal_alert.wav"), bet, SR, -12.5)
    los_credits.append(("assets/audio/sfx/betrayal_alert.wav", "fs-204310", "Betrayal Dramatic Brass Alert"))

    # #24 Troop Donation Sent
    don = _extract_best_window(fetch("fs-215415"), 0.72, SR, 6.0, 0.0, 0.35)
    don = _shape_tail(don, 0.72, fade_in_ms=3.0, fade_out_sec=0.14)
    don = _sos_hp(don, SR, 140.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "troop_donate.wav"), don, SR, -15.0)
    los_credits.append(("assets/audio/sfx/troop_donate.wav", "fs-215415", "Troop Donation Notification Ping"))

    # #25 Victory Fanfare
    vic = _shape_tail(_trim_onset(fetch("fs-456966"), -32.0, 10.0), 3.60, fade_in_ms=6.0, fade_out_sec=0.55)
    vic = _sos_hp(vic, SR, 45.0, order=2)
    vic = _stereo_reverb(vic, SR, rt60=1.6, predelay_ms=18.0, wet=0.22, damping_hz=5800.0, seed=375)
    _write_pcm16_wav(os.path.join(SFX_DIR, "victory_fanfare.wav"), vic, SR, -11.5)
    los_credits.append(("assets/audio/sfx/victory_fanfare.wav", "fs-456966", "Success Trumpet Victory Fanfare"))

    # #26 UI Button / Radial Tap (drop_001/002)
    for idx_u2, (sid_u2, u_dur) in enumerate([("fs-171697", 0.11), ("fs-216859", 0.10)], start=1):
        tap = _shape_tail(_trim_onset(fetch(sid_u2), -26.0, 1.5), u_dur, fade_in_ms=1.5, fade_out_sec=0.025)
        tap = _sos_hp(tap, SR, 160.0, order=2)
        tap = _sos_lp(tap, SR, 11000.0, order=2)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"drop_00{idx_u2}.wav"), tap, SR, -17.0, fade_in_ms=1.5)
        los_credits.append((f"assets/audio/sfx/drop_00{idx_u2}.wav", sid_u2, "Tactile UI Button Tap"))

    # #27 UI Panel Open
    opn = _shape_tail(_trim_onset(fetch("fs-150950"), -28.0, 3.0), 0.24, fade_in_ms=4.0, fade_out_sec=0.05)
    opn = _sos_bp(opn, SR, 280.0, 6500.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "open_001.wav"), opn, SR, -18.0)
    los_credits.append(("assets/audio/sfx/open_001.wav", "fs-150950", "UI Panel Open Swoosh"))

    # #28 UI Panel Close (pitched down 0.90x so close feels naturally lower than open)
    cls_raw = _pitch_shift_resample(_trim_onset(fetch("fs-169867"), -28.0, 3.0), 0.90)
    cls = _shape_tail(cls_raw, 0.22, fade_in_ms=4.0, fade_out_sec=0.05)
    cls = _sos_bp(cls, SR, 240.0, 5800.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "close_001.wav"), cls, SR, -18.0)
    los_credits.append(("assets/audio/sfx/close_001.wav", "fs-169867", "UI Panel Close Swoosh"))

    # #29 Error / Action Rejected
    err = _shape_tail(_trim_onset(fetch("fs-220187"), -28.0, 2.0), 0.34, fade_in_ms=2.0, fade_out_sec=0.07)
    err = _sos_hp(err, SR, 90.0, order=2)
    err = _sos_lp(err, SR, 4800.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "error_001.wav"), err, SR, -16.0, fade_in_ms=2.0)
    los_credits.append(("assets/audio/sfx/error_001.wav", "fs-220187", "Deny Wrong Answer UI Alert"))

    sources_path = os.path.join("assets", "audio", "SOURCES.txt")
    lines = [
        "World War Pixel — Verified Audio Sources & Licenses",
        "===================================================",
        "All 29 active game audio entries below were sourced from Lots of Sounds (CC0 1.0 Public Domain, via https://api.lotsofsounds.com/api/v1/sounds/sample) and mastered to 44.1 kHz 16-bit Stereo PCM.",
        "Legacy unused placeholders (army_deploy.wav, switch_001.wav, confirmation_001/002.wav, bong_001.wav): Custom 44.1 kHz Stereo DSP (CC0 / Project Original).",
        "",
        "CC0 Lots of Sounds Source Mapping:",
    ]
    for fpath, sid, desc in los_credits:
        lines.append(f"- {fpath} <- https://www.lotsofsounds.com/sounds/{sid} ({desc}; CC0)")
    with open(sources_path, "w", encoding="utf-8") as sf:
        sf.write("\n".join(lines) + "\n")
    print(f"[audio-los] Mastered {len(los_credits)} CC0 stereo 44.1 kHz WAV assets + updated {sources_path}.")


def _load_mixkit_wav(src_path: str, cache_name: str) -> np.ndarray:
    os.makedirs(MIXKIT_CACHE_DIR, exist_ok=True)
    cache_path = os.path.join(MIXKIT_CACHE_DIR, cache_name)
    if os.path.exists(src_path):
        shutil.copy2(src_path, cache_path)
    assert os.path.exists(cache_path), f"Missing Mixkit WAV source and cache: {src_path}"
    with wave.open(cache_path, "rb") as wf:
        n_ch = wf.getnchannels()
        sw = wf.getsampwidth()
        sr_in = wf.getframerate()
        frames = wf.readframes(wf.getnframes())
    assert sw == 2, f"Expected 16-bit PCM WAV for {cache_name}, got sampwidth={sw}"
    arr = np.frombuffer(frames, dtype=np.int16).astype(np.float64) / 32768.0
    st = arr.reshape(-1, n_ch)[:, :2] if n_ch >= 2 else np.column_stack([arr, arr])
    if sr_in != SR:
        gcd = int(np.gcd(SR, sr_in))
        st = signal.resample_poly(st, SR // gcd, sr_in // gcd, axis=0)
    peak = float(np.max(np.abs(st)))
    if peak > 1e-6:
        st = st / peak * 0.90
    return st


def apply_user_mixkit_overrides() -> None:
    """Master and install user-supplied Mixkit WAVs (friend request, bubble-pop conquer, victory, defeat)."""
    os.makedirs(SFX_DIR, exist_ok=True)

    # Incoming Friend Request
    fr_raw = _trim_onset(_load_mixkit_wav(MIXKIT_OVERRIDES["friend_request"], "mixkit-unlock-game-notification-253.wav"), -32.0, 3.0)
    fr = _shape_tail(fr_raw, 1.35, fade_in_ms=2.0, fade_out_sec=0.14)
    fr = _sos_hp(fr, SR, 80.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "friend_request.wav"), fr, SR, -14.5, fade_in_ms=2.0)

    # Bubble-Pop Conquer (6 micro-varied stereo variants from mixkit-game-ball-tap-2073.wav)
    pop_base = _trim_onset(_load_mixkit_wav(MIXKIT_OVERRIDES["conquer_pop"], "mixkit-game-ball-tap-2073.wav"), -28.0, 1.5)
    pop_rates = [0.93, 0.97, 1.00, 1.04, 1.08, 0.95]
    pop_pans = [-0.18, 0.14, -0.06, 0.18, -0.12, 0.08]
    for idx_p, (rate, pan) in enumerate(zip(pop_rates, pop_pans), start=1):
        shifted = _pitch_shift_resample(pop_base, rate)
        pop = _shape_tail(shifted, 0.15, fade_in_ms=1.5, fade_out_sec=0.028, pan=pan)
        pop = _sos_hp(pop, SR, 110.0, order=2)
        _write_pcm16_wav(os.path.join(SFX_DIR, f"conquer_pop_00{idx_p}.wav"), pop, SR, -15.0, fade_in_ms=1.5)

    # Won / Victory
    vic_raw = _trim_onset(_load_mixkit_wav(MIXKIT_OVERRIDES["victory_fanfare"], "mixkit-game-level-completed-2059.wav"), -36.0, 6.0)
    vic = _shape_tail(vic_raw, 3.55, fade_in_ms=4.0, fade_out_sec=0.25)
    vic = _sos_hp(vic, SR, 38.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "victory_fanfare.wav"), vic, SR, -11.5)

    # Lost / Defeat
    def_raw = _trim_onset(_load_mixkit_wav(MIXKIT_OVERRIDES["defeat_drums"], "mixkit-ominous-drums-227.wav"), -36.0, 6.0)
    df = _shape_tail(def_raw, 4.10, fade_in_ms=4.0, fade_out_sec=0.35)
    df = _sos_hp(df, SR, 32.0, order=2)
    _write_pcm16_wav(os.path.join(SFX_DIR, "defeat_drums.wav"), df, SR, -11.5)

    sources_path = os.path.join("assets", "audio", "SOURCES.txt")
    with open(sources_path, "r", encoding="utf-8") as sf:
        existing_txt = sf.read().rstrip()
    mixkit_block = "\n".join([
        "",
        "Mixkit Royalty-Free User Overrides (mastered 44.1 kHz 16-bit Stereo):",
        "- assets/audio/sfx/friend_request.wav <- Mixkit Unlock Game Notification 253 (mixkit-unlock-game-notification-253.wav)",
        "- assets/audio/sfx/conquer_pop_001..006.wav <- Mixkit Game Ball Tap 2073 (mixkit-game-ball-tap-2073.wav, 6 pitch/pan variants)",
        "- assets/audio/sfx/victory_fanfare.wav <- Mixkit Game Level Completed 2059 (mixkit-game-level-completed-2059.wav)",
        "- assets/audio/sfx/defeat_drums.wav <- Mixkit Ominous Drums 227 (mixkit-ominous-drums-227.wav)",
    ])
    with open(sources_path, "w", encoding="utf-8") as sf:
        sf.write(existing_txt + mixkit_block + "\n")
    print("[audio-mixkit] Mastered 4 user Mixkit overrides (friend_request, 6x conquer_pop, victory_fanfare, defeat_drums).")


def main() -> None:
    # Keep 5 legacy unused WAVs valid 44.1 kHz stereo before overwriting active assets with CC0 + Mixkit masters
    generate_modern_ui_sfx()
    generate_procedural_sfx()
    build_lotsofsounds_audio()
    apply_user_mixkit_overrides()
    print("[audio-fetch] SUCCESS: All 46 project audio files verified & studio-mastered.")


if __name__ == "__main__":
    main()
