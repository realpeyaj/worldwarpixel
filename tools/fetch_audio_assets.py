"""Fetch smooth modern CC0 Kenney interface audio and synthesize subtle procedural SFX & ocean ambience."""

from __future__ import annotations

import io
import os
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

# Verified Public Domain combat, missile, silo, SAM & explosion WAVs from endless-sky/endless-sky
PUBLIC_COMBAT_SFX = {
    "missile_launch.wav": ("rocket.wav", 1.55, -14.5, 0.18),
    "silo_nuke_launch.wav": ("nuke.wav", 2.40, -14.0, 0.25),
    "sam_launch.wav": ("sidewinder.wav", 0.90, -14.5, 0.12),
    "sam_intercept.wav": ("missile hit.wav", 1.35, -14.0, 0.22),
    "nuke_blast.wav": ("explosion nuke.wav", 3.20, -11.5, 0.55),
    "cannon_fire.wav": ("ballistic.wav", 1.10, -14.5, 0.18),
    "battle_clash.wav": ("explosion medium.wav", 0.72, -16.5, 0.12),
}

PUBLIC_SFX_CACHE_DIR = os.path.join("tools", "cache", "public_sfx")

SFX_FILES = [
    "drop_001.wav",
    "drop_002.wav",
    "glass_001.wav",
    "glass_002.wav",
    "maximize_001.wav",
    "maximize_002.wav",
    "pluck_001.wav",
    "pluck_002.wav",
    "confirmation_001.wav",
    "confirmation_002.wav",
    "error_001.wav",
    "open_001.wav",
    "close_001.wav",
    "switch_001.wav",
    "bong_001.wav",
]

SFX_DIR = os.path.join("assets", "audio", "sfx")
AMBIENCE_DIR = os.path.join("assets", "audio", "ambience")
MUSIC_DIR = os.path.join("assets", "audio", "music")


def fetch_kenney_sfx() -> None:
    os.makedirs(SFX_DIR, exist_ok=True)
    for fname in SFX_FILES:
        dest = os.path.join(SFX_DIR, fname)
        if not os.path.exists(dest) or os.path.getsize(dest) == 0:
            print(f"[audio-fetch] Downloading CC0 {fname}...")
            urllib.request.urlretrieve(KENNEY_BASE + fname, dest)
        with wave.open(dest, "rb") as wf:
            assert wf.getnframes() > 0, f"Invalid empty WAV: {dest}"


def _write_pcm16_wav(path: str, samples: np.ndarray, sample_rate: int = 44100, target_rms_db: float = -16.0) -> None:
    rms = float(np.sqrt(np.mean(samples * samples)))
    target_rms = 10.0 ** (target_rms_db / 20.0)
    if rms > 1e-8:
        samples = samples * (target_rms / rms)
    samples = np.clip(samples, -0.78, 0.78)
    pcm = (samples * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm.tobytes())


def fetch_public_combat_sfx() -> None:
    """Download real Public Domain missile, silo, SAM, intercept, and explosion WAVs."""
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(PUBLIC_SFX_CACHE_DIR, exist_ok=True)
    sr_target = 44100

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
            sr = wf.getframerate()
            frames = wf.readframes(wf.getnframes())

        assert sw == 2, f"Expected 16-bit PCM WAV for {src_name}, got sampwidth={sw}"
        arr = np.frombuffer(frames, dtype=np.int16).astype(np.float64) / 32768.0
        if n_ch > 1:
            arr = arr.reshape(-1, n_ch).mean(axis=1)
        if sr != sr_target:
            gcd = int(np.gcd(sr_target, sr))
            arr = signal.resample_poly(arr, sr_target // gcd, sr // gcd)

        max_samples = min(len(arr), int(max_dur * sr_target))
        arr = arr[:max_samples].copy()
        fade_in_n = min(len(arr), int(0.004 * sr_target))
        if fade_in_n > 1:
            arr[:fade_in_n] *= np.linspace(0.0, 1.0, fade_in_n)
        fade_out_n = min(len(arr), int(fade_out_sec * sr_target))
        if fade_out_n > 1:
            t_fade = np.linspace(0.0, np.pi * 0.5, fade_out_n)
            arr[-fade_out_n:] *= np.cos(t_fade) ** 2

        dest_path = os.path.join(SFX_DIR, dest_name)
        _write_pcm16_wav(dest_path, arr, sr_target, rms_db)
        with wave.open(dest_path, "rb") as wf:
            assert wf.getnframes() > 0, f"Invalid processed WAV: {dest_path}"

    sources_path = os.path.join("assets", "audio", "SOURCES.txt")
    lines = [
        "World War Pixel — Verified Audio Sources & Licenses",
        "===================================================",
        "UI Sounds: Kenney Interface Sounds (CC0 1.0 Public Domain) via Calinou/kenney-interface-sounds",
        "",
        "Public-Domain Missile, Silo, SAM, Intercept & Combat SFX (endless-sky/endless-sky sounds/*, License: public-domain):",
    ]
    for dest_name, (src_name, max_dur, _, _) in PUBLIC_COMBAT_SFX.items():
        lines.append(f"- assets/audio/sfx/{dest_name} <- {ENDLESS_SKY_BASE}{urllib.parse.quote(src_name)} ({max_dur:.2f}s)")
    with open(sources_path, "w", encoding="utf-8") as sf:
        sf.write("\n".join(lines) + "\n")
    print(f"[audio-fetch] Processed {len(PUBLIC_COMBAT_SFX)} public-domain combat/missile WAVs + wrote {sources_path}.")


def generate_procedural_sfx() -> None:
    """Synthesize subtle, warm, non-clicky maritime and diplomacy chimes."""
    os.makedirs(SFX_DIR, exist_ok=True)
    sr = 44100
    rng = np.random.default_rng(77)

    # 1. ship_depart.wav: warm distant low-brass nautical tone + gentle water whoosh (0.55s)
    t_ship = np.linspace(0.0, 0.55, int(sr * 0.55), endpoint=False)
    env_ship = np.sin(np.pi * (t_ship / 0.55)) ** 1.4
    horn = (
        0.65 * np.sin(2.0 * np.pi * 165.0 * t_ship)
        + 0.25 * np.sin(2.0 * np.pi * 247.5 * t_ship)
        + 0.12 * np.sin(2.0 * np.pi * 330.0 * t_ship)
    )
    b_sw, a_sw = signal.butter(2, 650.0 / (sr * 0.5), btype="low")
    wash = signal.lfilter(b_sw, a_sw, rng.standard_normal(len(t_ship))) * 0.35
    _write_pcm16_wav(os.path.join(SFX_DIR, "ship_depart.wav"), (horn * 0.75 + wash) * env_ship, sr, -16.0)

    # 2. bridge_connect.wav: soft rising harmonic chord chime (0.40s)
    t_br = np.linspace(0.0, 0.40, int(sr * 0.40), endpoint=False)
    env_br = np.minimum(t_br / 0.03, 1.0) * np.exp(-5.5 * t_br)
    freq_sweep = 293.66 + 146.83 * (1.0 - np.exp(-8.0 * t_br))
    chord = 0.65 * np.sin(2.0 * np.pi * freq_sweep * t_br) + 0.35 * np.sin(2.0 * np.pi * 440.0 * t_br)
    _write_pcm16_wav(os.path.join(SFX_DIR, "bridge_connect.wav"), chord * env_br, sr, -15.0)

    # 3. army_deploy.wav: warm muted tactical drum thud (0.24s)
    t_ar = np.linspace(0.0, 0.24, int(sr * 0.24), endpoint=False)
    env_ar = np.minimum(t_ar / 0.008, 1.0) * np.exp(-14.0 * t_ar)
    f_drop = 125.0 * np.exp(-16.0 * t_ar) + 58.0
    phase = 2.0 * np.pi * np.cumsum(f_drop) / sr
    thud = np.sin(phase) * env_ar
    _write_pcm16_wav(os.path.join(SFX_DIR, "army_deploy.wav"), thud, sr, -14.0)

    # 4. diplomacy_chime.wav: warm fifth chord chime (0.42s)
    t_dp = np.linspace(0.0, 0.42, int(sr * 0.42), endpoint=False)
    env_dp = np.minimum(t_dp / 0.025, 1.0) * np.exp(-5.2 * t_dp)
    chime = 0.55 * np.sin(2.0 * np.pi * 392.0 * t_dp) + 0.45 * np.sin(2.0 * np.pi * 587.33 * t_dp)
    _write_pcm16_wav(os.path.join(SFX_DIR, "diplomacy_chime.wav"), chime * env_dp, sr, -16.0)

    # 5. betrayal_alert.wav: tense low warning brass tone (0.50s)
    t_bt2 = np.linspace(0.0, 0.50, int(sr * 0.50), endpoint=False)
    env_bt2 = np.minimum(t_bt2 / 0.02, 1.0) * np.exp(-4.6 * t_bt2)
    b_w, a_w = signal.butter(2, 820.0 / (sr * 0.5), btype="low")
    warn = signal.lfilter(b_w, a_w, 0.55 * np.sin(2.0 * np.pi * 155.56 * t_bt2) + 0.45 * np.sin(2.0 * np.pi * 220.0 * t_bt2) + 0.20 * np.sin(2.0 * np.pi * 311.13 * t_bt2))
    _write_pcm16_wav(os.path.join(SFX_DIR, "betrayal_alert.wav"), warn * env_bt2, sr, -14.0)

    # 6. boat_bell.wav: resonant brass ship's bell double-ring ("ding-ding!") + water wash for island exploration
    t_bl = np.linspace(0.0, 0.72, int(sr * 0.72), endpoint=False)
    t2 = np.maximum(0.0, t_bl - 0.17)
    e1 = np.minimum(t_bl / 0.004, 1.0) * np.exp(-7.5 * t_bl)
    e2 = (t_bl >= 0.17).astype(np.float64) * np.minimum(t2 / 0.004, 1.0) * np.exp(-5.8 * t2)
    bell_f = 1046.5  # C6 ship's brass bell fundamental + metallic partials
    bell = (
        0.55 * np.sin(2.0 * np.pi * bell_f * t_bl)
        + 0.30 * np.sin(2.0 * np.pi * (bell_f * 1.504) * t_bl)
        + 0.18 * np.sin(2.0 * np.pi * (bell_f * 2.0) * t_bl)
        + 0.10 * np.sin(2.0 * np.pi * (bell_f * 2.83) * t_bl)
    ) * (0.75 * e1 + 1.0 * e2)
    wash_b = signal.lfilter(b_sw, a_sw, rng.standard_normal(len(t_bl))) * 0.16 * np.sin(np.pi * (t_bl / 0.72))
    _write_pcm16_wav(os.path.join(SFX_DIR, "boat_bell.wav"), bell + wash_b, sr, -13.5)

    # 7. target_lock.wav: crisp tactical double-beep radar lock for nuke 1st-click staging
    t_lk = np.linspace(0.0, 0.32, int(sr * 0.32), endpoint=False)
    p1 = ((t_lk >= 0.0) & (t_lk < 0.09)).astype(np.float64) * np.sin(np.pi * np.clip(t_lk / 0.09, 0.0, 1.0))
    p2 = ((t_lk >= 0.13) & (t_lk < 0.25)).astype(np.float64) * np.sin(np.pi * np.clip((t_lk - 0.13) / 0.12, 0.0, 1.0))
    lock_sig = (0.7 * np.sin(2.0 * np.pi * 880.0 * t_lk) + 0.3 * np.sin(2.0 * np.pi * 1318.5 * t_lk)) * p1 + (0.7 * np.sin(2.0 * np.pi * 1174.66 * t_lk) + 0.3 * np.sin(2.0 * np.pi * 1760.0 * t_lk)) * p2
    _write_pcm16_wav(os.path.join(SFX_DIR, "target_lock.wav"), lock_sig, sr, -14.5)

    # 8. warship_horn.wav: deep naval dreadnought horn + helm chime
    t_wh = np.linspace(0.0, 0.62, int(sr * 0.62), endpoint=False)
    env_wh = np.sin(np.pi * (t_wh / 0.62)) ** 1.2
    wh_sig = (
        0.55 * np.sin(2.0 * np.pi * 110.0 * t_wh)
        + 0.35 * np.sin(2.0 * np.pi * 164.81 * t_wh)
        + 0.22 * np.sin(2.0 * np.pi * 220.0 * t_wh)
        + 0.12 * np.sin(2.0 * np.pi * 880.0 * t_wh) * np.exp(-9.0 * t_wh)
    ) * env_wh
    _write_pcm16_wav(os.path.join(SFX_DIR, "warship_horn.wav"), wh_sig, sr, -14.5)

    # 9. troop_donate.wav: warm ascending supply convoy chord
    t_td = np.linspace(0.0, 0.45, int(sr * 0.45), endpoint=False)
    env_td = np.minimum(t_td / 0.02, 1.0) * np.exp(-5.0 * t_td)
    td_sig = (
        0.50 * np.sin(2.0 * np.pi * 329.63 * t_td)
        + 0.40 * np.sin(2.0 * np.pi * 440.0 * t_td)
        + 0.35 * np.sin(2.0 * np.pi * 659.25 * np.maximum(0.0, t_td - 0.08)) * (t_td >= 0.08).astype(np.float64)
    ) * env_td
    _write_pcm16_wav(os.path.join(SFX_DIR, "troop_donate.wav"), td_sig, sr, -15.0)

    # 10. retreat_horn.wav: descending tactical recall signal
    t_rt = np.linspace(0.0, 0.40, int(sr * 0.40), endpoint=False)
    env_rt = np.minimum(t_rt / 0.015, 1.0) * np.exp(-5.5 * t_rt)
    f_rt = np.where(t_rt < 0.16, 440.0, 329.63)
    ph_rt = 2.0 * np.pi * np.cumsum(f_rt) / sr
    rt_sig = (0.70 * np.sin(ph_rt) + 0.30 * np.sin(2.0 * ph_rt)) * env_rt
    _write_pcm16_wav(os.path.join(SFX_DIR, "retreat_horn.wav"), rt_sig, sr, -15.5)

    # 11. victory_fanfare.wav: triumphant brass fanfare + timpani roll & resolving major chord
    fan_dur = 2.4
    n_fan = int(sr * fan_dur)
    fan_sig = np.zeros(n_fan, dtype=np.float64)
    # Ascending D-major brass fanfare: D4 -> F#4 -> A4 -> D5 sustained chord
    fan_notes = [
        (0.00, 0.22, [293.66, 146.83]),
        (0.22, 0.22, [369.99, 185.00]),
        (0.44, 0.24, [440.00, 220.00]),
        (0.68, 1.65, [587.33, 440.00, 369.99, 293.66, 146.83]),
    ]
    for st_s, d_s, freqs in fan_notes:
        idx0 = int(st_s * sr)
        for f_v in freqs:
            voice = _synth_brass(f_v, d_s, sr, rng, 0.005)
            end_i = min(n_fan, idx0 + len(voice))
            fan_sig[idx0:end_i] += voice[: end_i - idx0] * (0.42 if len(freqs) > 2 else 0.65)
        drum = _synth_war_drum(105.0, 52.0, min(0.32, d_s), sr, 1.0)
        end_d = min(n_fan, idx0 + len(drum))
        fan_sig[idx0:end_d] += drum[: end_d - idx0] * 0.55
    _write_pcm16_wav(os.path.join(SFX_DIR, "victory_fanfare.wav"), fan_sig, sr, -11.5)

    print("[audio-fetch] Synthesized 11 procedural maritime, bell, lock, diplomacy, and victory fanfare SFX WAVs.")


def generate_ocean_ambience() -> None:
    os.makedirs(AMBIENCE_DIR, exist_ok=True)
    dest = os.path.join(AMBIENCE_DIR, "world_ocean_ambience.wav")
    if os.path.exists(dest) and os.path.getsize(dest) > 100000:
        with wave.open(dest, "rb") as wf:
            if wf.getnframes() > 0:
                print(f"[audio-fetch] Verified existing {dest}")
                return

    sr = 44100
    duration_sec = 12.0
    n_samples = int(sr * duration_sec)
    crossfade = int(sr * 2.0)
    total_gen = n_samples + crossfade

    rng = np.random.default_rng(108)
    white = rng.standard_normal(total_gen).astype(np.float64)
    b_low, a_low = signal.butter(3, 420.0 / (sr * 0.5), btype="low")
    surf_noise = signal.lfilter(b_low, a_low, white)
    b_air, a_air = signal.butter(2, [250.0 / (sr * 0.5), 1100.0 / (sr * 0.5)], btype="band")
    breeze_noise = signal.lfilter(b_air, a_air, white) * 0.22

    t = np.arange(total_gen, dtype=np.float64) / sr
    swell_1 = 0.55 + 0.45 * np.sin(2.0 * np.pi * (2.0 / duration_sec) * t)
    swell_2 = 0.65 + 0.35 * np.sin(2.0 * np.pi * (3.0 / duration_sec) * t + 1.1)
    raw = surf_noise * swell_1 + breeze_noise * swell_2

    alpha = np.linspace(0.0, 1.0, crossfade, dtype=np.float64)
    loop = raw[crossfade:].copy()
    loop[:crossfade] = raw[crossfade : 2 * crossfade] * np.sqrt(alpha) + raw[:crossfade] * np.sqrt(1.0 - alpha)
    _write_pcm16_wav(dest, loop, sr, -18.0)


def _synth_brass(freq: float, dur: float, sr: int, rng: np.random.Generator, vibrato: float = 0.004) -> np.ndarray:
    """Rich heroic trumpet/brass voice with bright attack harmonics."""
    n = int(dur * sr)
    if n <= 1 or freq <= 0.0:
        return np.zeros(max(1, n), dtype=np.float64)
    lt = np.arange(n, dtype=np.float64) / sr
    vib = 1.0 + vibrato * np.sin(2.0 * np.pi * 5.2 * lt) * np.minimum(lt / 0.14, 1.0)
    phase = 2.0 * np.pi * np.cumsum(freq * vib) / sr
    bright = np.minimum(lt / 0.045, 1.0) * (0.55 + 0.45 * np.exp(-3.0 * lt))
    sig = np.zeros(n, dtype=np.float64)
    weights = [1.0, 0.78, 0.56, 0.42, 0.30, 0.20, 0.12, 0.07]
    for h_i, w in enumerate(weights, start=1):
        h_env = bright if h_i >= 3 else np.ones(n, dtype=np.float64)
        sig += w * h_env * np.sin(phase * h_i)
    env = np.minimum(lt / 0.025, 1.0) * np.minimum(np.maximum((dur - lt) / 0.035, 0.0), 1.0)
    env *= 0.85 + 0.15 * np.exp(-5.0 * lt)
    return (sig / 2.6) * env


def _synth_snare(dur: float, sr: int, rng: np.random.Generator, accent: float = 1.0) -> np.ndarray:
    """Crisp military marching snare drum hit."""
    n = int(dur * sr)
    lt = np.arange(n, dtype=np.float64) / sr
    b_sn, a_sn = signal.butter(2, [1100.0 / (sr * 0.5), 5200.0 / (sr * 0.5)], btype="band")
    buzz = signal.lfilter(b_sn, a_sn, rng.standard_normal(n)) * np.exp(-26.0 * lt)
    shell = np.sin(2.0 * np.pi * np.cumsum(210.0 * np.exp(-28.0 * lt) + 175.0) / sr) * np.exp(-32.0 * lt)
    env = np.minimum(lt / 0.002, 1.0)
    return (buzz * 0.78 + shell * 0.52) * env * accent


def _synth_war_drum(freq_start: float, freq_end: float, dur: float, sr: int, accent: float = 1.0) -> np.ndarray:
    """Deep battle bass drum / timpani boom."""
    n = int(dur * sr)
    lt = np.arange(n, dtype=np.float64) / sr
    f = (freq_start - freq_end) * np.exp(-18.0 * lt) + freq_end
    phase = 2.0 * np.pi * np.cumsum(f) / sr
    body = np.sin(phase) + 0.25 * np.sin(phase * 1.98) * np.exp(-12.0 * lt)
    env = np.minimum(lt / 0.005, 1.0) * np.exp(-5.5 * lt)
    return body * env * accent


def generate_game_theme() -> None:
    """Synthesize a seamless martial, drummy, trumpety 16-bar grand-strategy march (D minor, 116 BPM)."""
    os.makedirs(MUSIC_DIR, exist_ok=True)
    dest = os.path.join(MUSIC_DIR, "world_war_pixel_theme.wav")

    sr = 44100
    bpm = 116.0
    beat_sec = 60.0 / bpm
    bar_sec = beat_sec * 4.0
    rng = np.random.default_rng(404)

    # Heroic D-minor martial progression (16 bars -> ~33.10s seamless loop)
    chords = [
        (73.42, 146.83, 220.00, 293.66),  # 1: Dm
        (73.42, 146.83, 220.00, 349.23),  # 2: Dm
        (58.27, 116.54, 174.61, 293.66),  # 3: Bb
        (65.41, 130.81, 196.00, 261.63),  # 4: C (roll)
        (73.42, 146.83, 220.00, 349.23),  # 5: Dm
        (98.00, 196.00, 233.08, 293.66),  # 6: Gm
        (58.27, 116.54, 174.61, 233.08),  # 7: Bb
        (55.00, 110.00, 164.81, 277.18),  # 8: A7 (roll)
        (73.42, 146.83, 220.00, 349.23),  # 9: Dm (climax)
        (87.31, 174.61, 220.00, 261.63),  # 10: F
        (65.41, 130.81, 196.00, 261.63),  # 11: C
        (98.00, 196.00, 233.08, 293.66),  # 12: Gm (roll)
        (58.27, 116.54, 174.61, 293.66),  # 13: Bb
        (98.00, 196.00, 233.08, 293.66),  # 14: Gm
        (55.00, 110.00, 164.81, 277.18),  # 15: A7
        (73.42, 146.83, 220.00, 293.66),  # 16: Dm turnaround
    ]
    # Note frequencies for heroic fanfare trumpet motifs: (start_beat, dur_beats, freq_hz)
    fanfares = [
        [(0.0, 0.75, 440.00), (0.75, 0.25, 440.00), (1.0, 1.0, 587.33), (2.0, 1.5, 523.25), (3.5, 0.5, 440.00)],
        [(0.0, 1.0, 587.33), (1.0, 0.75, 659.25), (1.75, 0.25, 587.33), (2.0, 1.8, 523.25)],
        [(0.0, 1.0, 466.16), (1.0, 1.0, 587.33), (2.0, 1.5, 698.46), (3.5, 0.5, 587.33)],
        [(0.0, 1.2, 523.25), (1.5, 0.5, 440.00), (2.0, 1.6, 392.00)],
        [(0.0, 0.75, 440.00), (0.75, 0.25, 440.00), (1.0, 1.0, 587.33), (2.0, 1.0, 698.46), (3.0, 1.0, 659.25)],
        [(0.0, 1.2, 587.33), (1.5, 0.5, 466.16), (2.0, 1.8, 523.25)],
        [(0.0, 0.75, 466.16), (0.75, 0.25, 466.16), (1.0, 1.0, 587.33), (2.0, 1.8, 523.25)],
        [(0.0, 1.5, 440.00), (2.0, 1.6, 554.37)],
        [(0.0, 1.0, 587.33), (1.0, 0.5, 659.25), (1.5, 0.5, 698.46), (2.0, 1.8, 880.00)],
        [(0.0, 0.75, 698.46), (0.75, 0.25, 698.46), (1.0, 1.0, 783.99), (2.0, 1.8, 698.46)],
        [(0.0, 1.0, 659.25), (1.0, 1.0, 587.33), (2.0, 1.8, 523.25)],
        [(0.0, 1.0, 587.33), (1.0, 1.0, 466.16), (2.0, 1.8, 440.00)],
        [(0.0, 0.75, 466.16), (0.75, 0.25, 523.25), (1.0, 1.0, 587.33), (2.0, 1.8, 698.46)],
        [(0.0, 1.0, 587.33), (1.0, 0.5, 523.25), (1.5, 0.5, 466.16), (2.0, 1.8, 440.00)],
        [(0.0, 1.5, 440.00), (2.0, 1.0, 554.37), (3.0, 0.9, 659.25)],
        [(0.0, 2.2, 587.33), (2.5, 1.2, 440.00)],
    ]

    total_sec = len(chords) * bar_sec
    crossfade_sec = 2.0
    gen_sec = total_sec + crossfade_sec
    n_gen = int(sr * gen_sec)
    mix = np.zeros(n_gen, dtype=np.float64)

    def _add_at(offset_sec: float, chunk: np.ndarray, gain: float) -> None:
        i0 = int(offset_sec * sr)
        i1 = min(n_gen, i0 + len(chunk))
        if i0 < n_gen and i1 > i0:
            mix[i0:i1] += chunk[: i1 - i0] * gain

    snare_pattern = [(0.0, 0.9), (1.0, 0.75), (1.5, 0.55), (1.75, 0.65), (2.0, 1.0), (3.0, 0.8), (3.5, 0.6)]
    for bar_idx in range(len(chords) + 2):
        c_idx = bar_idx % len(chords)
        bar_t0 = bar_idx * bar_sec
        if bar_t0 >= gen_sec:
            break

        bass_f, f1, f2, f3 = chords[c_idx]
        # Marching staccato low-brass war accompaniment
        for b_off, g_horn in [(0.0, 0.26), (1.0, 0.16), (2.0, 0.24), (3.0, 0.18)]:
            t_note = bar_t0 + b_off * beat_sec
            _add_at(t_note, _synth_brass(bass_f, beat_sec * 0.82, sr, rng, 0.001), g_horn)
            _add_at(t_note, _synth_brass(f1, beat_sec * 0.68, sr, rng, 0.001), g_horn * 0.62)
            _add_at(t_note, _synth_brass(f2, beat_sec * 0.68, sr, rng, 0.001), g_horn * 0.55)
            _add_at(t_note, _synth_brass(f3, beat_sec * 0.68, sr, rng, 0.001), g_horn * 0.42)

        # Lead military trumpet melody (with octave support on bars 8..15 climax)
        climax = (8 <= c_idx <= 14)
        for start_b, dur_b, hz in fanfares[c_idx]:
            t_note = bar_t0 + start_b * beat_sec
            tr_wave = _synth_brass(hz, dur_b * beat_sec, sr, rng, 0.0045)
            _add_at(t_note, tr_wave, 0.34 if climax else 0.30)
            if climax:
                _add_at(t_note, _synth_brass(hz * 0.5, dur_b * beat_sec, sr, rng, 0.003), 0.16)

        # Deep war drums + timpani boom on beats 1, 3, and 4-and
        for b_kick, acc in [(0.0, 1.0), (1.75, 0.55), (2.0, 0.90), (3.0, 0.72), (3.5, 0.65)]:
            _add_at(bar_t0 + b_kick * beat_sec, _synth_war_drum(115.0, bass_f * 0.65, 0.34, sr, acc), 0.36)

        # Military snare cadence + dramatic turnaround rolls every 4th bar
        for b_sn, acc in snare_pattern:
            _add_at(bar_t0 + b_sn * beat_sec, _synth_snare(0.11, sr, rng, acc), 0.25)
        if (c_idx % 4) == 3:
            for roll_i in range(8):
                b_r = 3.0 + float(roll_i) * 0.125
                r_acc = 0.45 + 0.55 * (float(roll_i) / 7.0)
                _add_at(bar_t0 + b_r * beat_sec, _synth_snare(0.08, sr, rng, r_acc), 0.26)

    b_warm, a_warm = signal.butter(2, 6200.0 / (sr * 0.5), btype="low")
    mix = signal.lfilter(b_warm, a_warm, mix)

    xf = int(crossfade_sec * sr)
    n_loop = int(total_sec * sr)
    alpha = np.linspace(0.0, 1.0, xf, dtype=np.float64)
    loop = mix[xf : xf + n_loop].copy()
    loop[:xf] = mix[xf : 2 * xf] * np.sqrt(alpha) + mix[:xf] * np.sqrt(1.0 - alpha)
    _write_pcm16_wav(dest, loop, sr, -16.5)
    print(f"[audio-fetch] Synthesized seamless {total_sec:.1f}s martial trumpet-and-drum theme at {dest}")


def main() -> None:
    fetch_kenney_sfx()
    fetch_public_combat_sfx()
    generate_procedural_sfx()
    generate_ocean_ambience()
    generate_game_theme()
    print("[audio-fetch] SUCCESS: All smooth modern & public-domain combat audio assets verified.")


if __name__ == "__main__":
    main()
