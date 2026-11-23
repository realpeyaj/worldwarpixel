"""Generates smooth minimalist anti-aliased silhouettes + nation-color masks and UI 9-patches."""

from __future__ import annotations

import math
import os
from typing import Callable, Dict, List, Tuple

from PIL import Image, ImageDraw

SPRITES_DIR = os.path.join("assets", "sprites")
UI_DIR = os.path.join("assets", "ui")
CACHE_DIR = os.path.join("tools", "cache")

SS = 4  # 4x supersampling for silky smooth anti-aliased silhouettes

COL_OUTLINE = (18, 24, 34, 255)
COL_WHITE = (240, 244, 248, 255)
COL_LIGHT = (204, 212, 222, 255)
COL_STEEL = (138, 150, 166, 255)
COL_DARK = (56, 68, 84, 255)
COL_RED = (224, 72, 62, 255)
COL_ORANGE = (242, 148, 56, 255)
COL_GOLD = (232, 198, 92, 255)

MASK_FULL = (255, 255, 255, 255)
MASK_MID = (212, 212, 212, 255)
MASK_SHADE = (168, 168, 168, 255)


def _new_pair(w: int, h: int, has_mask: bool) -> Tuple[Image.Image, ImageDraw.ImageDraw, Image.Image | None, ImageDraw.ImageDraw | None]:
    bw, bh = w * SS, h * SS
    base = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(base)
    if has_mask:
        mask = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
        mdraw = ImageDraw.Draw(mask)
        return base, bdraw, mask, mdraw
    return base, bdraw, None, None


def _draw_banner() -> Tuple[Image.Image, Image.Image | None]:
    # Minimalist waving swallowtail war pennant on slender flagpole (non-square)
    base, bd, mask, md = _new_pair(64, 64, True)
    # Tapered mast + finial dot
    bd.rounded_rectangle([68, 44, 84, 232], radius=8, fill=COL_LIGHT, outline=COL_OUTLINE, width=6)
    bd.ellipse([60, 24, 92, 56], fill=COL_GOLD, outline=COL_OUTLINE, width=6)
    # Swallowtail pennant curving outward to the right
    pennant = [(82, 48), (222, 72), (176, 102), (218, 134), (82, 156)]
    bd.polygon(pennant, fill=COL_DARK, outline=COL_OUTLINE, width=8)
    inner = [(88, 58), (206, 76), (168, 102), (204, 130), (88, 146)]
    md.polygon(inner, fill=MASK_FULL)
    return base, mask


def _draw_town() -> Tuple[Image.Image, Image.Image | None]:
    # Minimalist clean 3-spire skyline silhouette (open airy profile, no square frame)
    base, bd, mask, md = _new_pair(64, 64, True)
    # Left lower roof wing
    left_poly = [(36, 206), (36, 134), (66, 102), (96, 134), (96, 206)]
    # Right wing
    right_poly = [(158, 206), (158, 122), (190, 90), (220, 122), (220, 206)]
    # Tall center spire tower
    center_poly = [(86, 206), (86, 86), (128, 34), (170, 86), (170, 206)]
    for poly in (left_poly, right_poly):
        bd.polygon(poly, fill=COL_STEEL, outline=COL_OUTLINE, width=8)
    bd.polygon(center_poly, fill=COL_LIGHT, outline=COL_OUTLINE, width=8)
    # Nation color pitched roofs + subtle center banner stripe
    md.polygon([(38, 134), (66, 104), (94, 134)], fill=MASK_MID)
    md.polygon([(160, 122), (190, 92), (218, 122)], fill=MASK_MID)
    md.polygon([(88, 86), (128, 38), (168, 86)], fill=MASK_FULL)
    # Clean slender ground bar
    bd.rounded_rectangle([28, 198, 228, 214], radius=7, fill=COL_DARK, outline=COL_OUTLINE, width=5)
    return base, mask


def _draw_port() -> Tuple[Image.Image, Image.Image | None]:
    # Minimalist sleek curved anchor silhouette
    base, bd, mask, md = _new_pair(64, 64, True)
    # Top mooring ring
    bd.ellipse([104, 24, 152, 72], outline=COL_OUTLINE, width=18)
    bd.ellipse([108, 28, 148, 68], outline=COL_WHITE, width=10)
    # Vertical shank & crossbar
    bd.rounded_rectangle([118, 66, 138, 216], radius=9, fill=COL_LIGHT, outline=COL_OUTLINE, width=6)
    bd.rounded_rectangle([76, 88, 180, 106], radius=8, fill=COL_STEEL, outline=COL_OUTLINE, width=6)
    # Smooth semicircular bottom crescent (arc)
    bd.arc([44, 96, 212, 224], start=12, end=168, fill=COL_OUTLINE, width=26)
    bd.arc([48, 100, 208, 220], start=14, end=166, fill=COL_WHITE, width=14)
    # Flukes at crescent tips (tinted with nation color)
    left_fluke = [(36, 144), (62, 124), (70, 160)]
    right_fluke = [(220, 144), (194, 124), (186, 160)]
    bd.polygon(left_fluke, fill=COL_DARK, outline=COL_OUTLINE, width=6)
    bd.polygon(right_fluke, fill=COL_DARK, outline=COL_OUTLINE, width=6)
    md.polygon(left_fluke, fill=MASK_FULL)
    md.polygon(right_fluke, fill=MASK_FULL)
    md.ellipse([110, 30, 146, 66], outline=MASK_MID, width=6)
    return base, mask


def _draw_factory() -> Tuple[Image.Image, Image.Image | None]:
    # Minimalist asymmetric sawtooth roof + slender smokestack + wisp
    base, bd, mask, md = _new_pair(64, 64, True)
    # Slender chimney on right
    bd.polygon([(178, 178), (186, 60), (210, 60), (218, 178)], fill=COL_STEEL, outline=COL_OUTLINE, width=7)
    md.rectangle([188, 72, 208, 92], fill=MASK_FULL)
    # Soft curved minimalist smoke wisps
    bd.ellipse([188, 30, 218, 50], fill=(195, 204, 214, 190))
    bd.ellipse([204, 16, 232, 34], fill=(215, 222, 230, 140))
    # Asymmetric twin sawtooth silhouette (not boxy)
    hall = [(30, 212), (30, 126), (92, 86), (92, 126), (154, 86), (154, 134), (222, 134), (222, 212)]
    bd.polygon(hall, fill=COL_LIGHT, outline=COL_OUTLINE, width=8)
    # Team accent roof fascia triangles
    md.polygon([(34, 126), (90, 90), (90, 126)], fill=MASK_FULL)
    md.polygon([(94, 126), (152, 90), (152, 126)], fill=MASK_FULL)
    bd.rounded_rectangle([24, 204, 232, 220], radius=7, fill=COL_DARK, outline=COL_OUTLINE, width=5)
    return base, mask


def _draw_defense_post() -> Tuple[Image.Image, Image.Image | None]:
    # Clean tapered heraldic/tactical shield silhouette (sharp point, curved crown)
    base, bd, mask, md = _new_pair(64, 64, True)
    shield = [
        (46, 52), (128, 32), (210, 52),
        (206, 136), (174, 192), (128, 228), (82, 192), (50, 136),
    ]
    bd.polygon(shield, fill=COL_LIGHT, outline=COL_OUTLINE, width=9)
    inner = [
        (64, 68), (128, 52), (192, 68),
        (188, 132), (162, 178), (128, 206), (94, 178), (68, 132),
    ]
    md.polygon(inner, fill=MASK_FULL)
    # Subtle chevron across shield center
    chev = [(80, 118), (128, 88), (176, 118), (176, 138), (128, 108), (80, 138)]
    bd.polygon(chev, fill=COL_WHITE, outline=COL_OUTLINE, width=5)
    return base, mask


def _draw_silo() -> Tuple[Image.Image, Image.Image | None]:
    # Unmistakable Nuclear Missile Silo: open blast doors + subterranean launch pit + tall ICBM warhead + radiation emblem
    base, bd, mask, md = _new_pair(64, 64, True)
    # Outer armored concrete bunker ring & open left/right blast hatch doors
    bd.rounded_rectangle([16, 128, 72, 224], radius=10, fill=COL_STEEL, outline=COL_OUTLINE, width=7)
    bd.rounded_rectangle([184, 128, 240, 224], radius=10, fill=COL_STEEL, outline=COL_OUTLINE, width=7)
    md.rounded_rectangle([24, 138, 64, 214], radius=6, fill=MASK_MID)
    md.rounded_rectangle([192, 138, 232, 214], radius=6, fill=MASK_MID)
    # Subterranean launch pit with hazard rim & ignition glow
    bd.ellipse([44, 136, 212, 236], fill=COL_DARK, outline=COL_OUTLINE, width=9)
    md.ellipse([54, 146, 202, 226], outline=MASK_FULL, width=14)
    bd.ellipse([68, 158, 188, 216], fill=(22, 26, 34, 255), outline=COL_GOLD, width=6)
    bd.ellipse([88, 172, 168, 208], fill=(242, 128, 42, 220))
    # Prominent ICBM nuclear missile rising vertically from the silo pit
    fins_l = [(96, 132), (62, 172), (62, 192), (102, 178)]
    fins_r = [(160, 132), (194, 172), (194, 192), (154, 178)]
    bd.polygon(fins_l, fill=COL_RED, outline=COL_OUTLINE, width=7)
    bd.polygon(fins_r, fill=COL_RED, outline=COL_OUTLINE, width=7)
    body = [(96, 68), (160, 68), (164, 182), (92, 182)]
    bd.polygon(body, fill=COL_WHITE, outline=COL_OUTLINE, width=8)
    # Nation color band + red nuclear warhead nosecone
    md.rectangle([102, 114, 154, 142], fill=MASK_FULL)
    nose = [(128, 12), (162, 68), (94, 68)]
    bd.polygon(nose, fill=COL_RED, outline=COL_OUTLINE, width=8)
    # High-contrast radiation warning band & nuclear core dot on fuselage
    bd.rectangle([100, 74, 156, 98], fill=COL_GOLD, outline=COL_OUTLINE, width=5)
    bd.ellipse([118, 148, 138, 168], fill=COL_GOLD, outline=COL_OUTLINE, width=5)
    return base, mask


def _draw_sam() -> Tuple[Image.Image, Image.Image | None]:
    # Unmistakable Twin-Tube SAM Air-Defense Battery + Parabolic Radar Dish + Cyan Sweep Waves
    base, bd, mask, md = _new_pair(64, 64, True)
    # Heavy armored SAM turret pedestal at bottom
    bd.rounded_rectangle([32, 184, 224, 232], radius=12, fill=COL_DARK, outline=COL_OUTLINE, width=8)
    md.rounded_rectangle([46, 194, 210, 222], radius=8, fill=MASK_FULL)
    bd.ellipse([86, 152, 170, 204], fill=COL_STEEL, outline=COL_OUTLINE, width=7)
    # Parabolic radar dish on lower-left + glowing cyan radar detection arcs
    bd.arc([16, 84, 108, 184], start=125, end=305, fill=COL_WHITE, width=18)
    bd.line([(56, 136), (86, 112)], fill=COL_GOLD, width=8)
    bd.arc([18, 22, 172, 168], start=210, end=330, fill=(100, 236, 255, 255), width=10)
    bd.arc([38, 46, 148, 150], start=210, end=330, fill=COL_WHITE, width=8)
    # Twin angled SAM launch tubes + 2 protruding red-tipped interceptor rockets aiming up-right
    tube1 = [(74, 142), (168, 48), (192, 72), (98, 166)]
    tube2 = [(104, 172), (198, 78), (222, 102), (128, 196)]
    for tb, m_fill in ((tube1, MASK_FULL), (tube2, MASK_MID)):
        bd.polygon(tb, fill=COL_STEEL, outline=COL_OUTLINE, width=8)
    md.polygon([(84, 140), (154, 70), (168, 84), (98, 154)], fill=MASK_FULL)
    md.polygon([(114, 170), (184, 100), (198, 114), (128, 184)], fill=MASK_MID)
    # Protruding red/white SAM interceptor warhead tips
    tip1 = [(172, 44), (214, 22), (196, 68)]
    tip2 = [(202, 74), (242, 52), (226, 98)]
    bd.polygon(tip1, fill=COL_RED, outline=COL_OUTLINE, width=6)
    bd.polygon(tip2, fill=COL_RED, outline=COL_OUTLINE, width=6)
    return base, mask


def _draw_attack() -> Tuple[Image.Image, Image.Image | None]:
    # Minimalist crossed sleek tactical blades (no square background)
    base, bd, _m, _md = _new_pair(64, 64, False)
    # First blade bottom-left -> top-right
    blade1 = [(48, 192), (176, 44), (212, 42), (202, 76), (74, 212)]
    # Second blade bottom-right -> top-left
    blade2 = [(208, 192), (80, 44), (44, 42), (54, 76), (182, 212)]
    bd.polygon(blade1, fill=COL_LIGHT, outline=COL_OUTLINE, width=8)
    bd.polygon(blade2, fill=COL_WHITE, outline=COL_OUTLINE, width=8)
    # Minimalist cross-guards
    bd.line([(46, 166), (88, 208)], fill=COL_GOLD, width=14)
    bd.line([(210, 166), (168, 208)], fill=COL_GOLD, width=14)
    return base, None


def _draw_diplomacy() -> Tuple[Image.Image, Image.Image | None]:
    # Minimalist handshake silhouette (clasped hands + left/right cuffs)
    base, bd, _m, _md = _new_pair(64, 64, False)
    # Left & right angled cuffs
    cuff_l = [(12, 92), (56, 62), (82, 118), (34, 150)]
    cuff_r = [(244, 92), (200, 62), (174, 118), (222, 150)]
    bd.polygon(cuff_l, fill=COL_STEEL, outline=COL_OUTLINE, width=7)
    bd.polygon(cuff_r, fill=COL_LIGHT, outline=COL_OUTLINE, width=7)
    # Clasped palm & fingers in center
    palm = [(62, 86), (128, 70), (194, 86), (186, 162), (128, 192), (70, 162)]
    bd.polygon(palm, fill=COL_GOLD, outline=COL_OUTLINE, width=8)
    # Upper thumb fold + finger ridges
    bd.polygon([(82, 82), (138, 66), (168, 98), (118, 120)], fill=COL_WHITE, outline=COL_OUTLINE, width=6)
    for fy in (134, 154, 172):
        bd.line([(96, fy), (162, fy + 10)], fill=COL_OUTLINE, width=6)
    return base, None


def _draw_upgrade() -> Tuple[Image.Image, Image.Image | None]:
    # Clean bold Arrow Up icon for structure upgrade (left radial button)
    base, bd, _m, _md = _new_pair(64, 64, False)
    arrow = [
        (128, 22), (218, 114), (166, 114), (166, 224),
        (90, 224), (90, 114), (38, 114),
    ]
    bd.polygon(arrow, fill=(116, 236, 156, 255), outline=COL_OUTLINE, width=8)
    bd.polygon([(128, 42), (188, 102), (148, 102), (148, 206), (108, 206), (108, 102), (68, 102)], fill=COL_WHITE)
    return base, None


def _draw_boat() -> Tuple[Image.Image, Image.Image | None]:
    # Clean minimalist side-profile boat icon for naval/boat radial button (right radial button)
    base, bd, _m, _md = _new_pair(64, 64, False)
    # Cabin & mast
    bd.rounded_rectangle([84, 78, 166, 138], radius=10, fill=COL_WHITE, outline=COL_OUTLINE, width=7)
    bd.polygon([(124, 34), (138, 34), (138, 82), (124, 82)], fill=COL_GOLD, outline=COL_OUTLINE, width=5)
    # Sleek boat hull
    hull = [(20, 134), (236, 134), (202, 198), (48, 198)]
    bd.polygon(hull, fill=(98, 198, 246, 255), outline=COL_OUTLINE, width=8)
    bd.line([(36, 214), (220, 214)], fill=COL_WHITE, width=8)
    return base, None


def _draw_coin() -> Tuple[Image.Image, Image.Image | None]:
    # Clean minimalist Peso gold coin icon for bottom HUD
    base, bd, _m, _md = _new_pair(64, 64, False)
    bd.ellipse([28, 28, 228, 228], fill=COL_GOLD, outline=COL_OUTLINE, width=8)
    bd.ellipse([48, 48, 208, 208], outline=COL_WHITE, width=6)
    bd.line([(104, 78), (104, 182)], fill=COL_OUTLINE, width=12)
    bd.arc([84, 78, 164, 134], start=270, end=90, fill=COL_OUTLINE, width=12)
    bd.line([(78, 104), (174, 104)], fill=COL_OUTLINE, width=7)
    return base, None


def _draw_troops() -> Tuple[Image.Image, Image.Image | None]:
    # Clean minimalist shield/troop badge icon for bottom HUD
    base, bd, _m, _md = _new_pair(64, 64, False)
    shield = [(128, 24), (214, 56), (198, 152), (128, 228), (58, 152), (42, 56)]
    bd.polygon(shield, fill=(116, 196, 252, 255), outline=COL_OUTLINE, width=8)
    inner = [(128, 46), (190, 70), (178, 142), (128, 198), (78, 142), (66, 70)]
    bd.polygon(inner, fill=COL_WHITE)
    return base, None


def _draw_missile() -> Tuple[Image.Image, Image.Image | None]:
    # Sleek pointed missile oriented +X (points right) for exact curved trajectory tangent rotation
    base, bd, _m, _md = _new_pair(64, 64, False)
    # Thruster flare at tail
    bd.polygon([(14, 128), (56, 106), (56, 150)], fill=COL_ORANGE)
    # Tail delta fins
    bd.polygon([(46, 108), (28, 72), (82, 106)], fill=COL_RED, outline=COL_OUTLINE, width=6)
    bd.polygon([(46, 148), (28, 184), (82, 150)], fill=COL_RED, outline=COL_OUTLINE, width=6)
    # Sleek cylindrical fuselage
    bd.rounded_rectangle([48, 104, 188, 152], radius=12, fill=COL_WHITE, outline=COL_OUTLINE, width=7)
    # Pointed aerodynamic warhead cone
    bd.polygon([(182, 104), (240, 128), (182, 152)], fill=COL_RED, outline=COL_OUTLINE, width=7)
    return base, None


def _draw_wifi() -> Tuple[Image.Image, Image.Image | None]:
    # Clean smooth 3-arc signal emblem
    base, bd, _m, _md = _new_pair(64, 64, False)
    cx, cy = 128, 198
    for rad in (148, 102, 58):
        bd.arc([cx - rad, cy - rad, cx + rad, cy + rad], start=224, end=316, fill=COL_WHITE, width=18)
    bd.ellipse([cx - 18, cy - 18, cx + 18, cy + 18], fill=COL_WHITE)
    return base, None


def _draw_trade_ship() -> Tuple[Image.Image, Image.Image | None]:
    # Sleek compact top-down cargo hull pointing +X (384x192 -> 96x48)
    base, bd, mask, md = _new_pair(96, 48, True)
    hull = [
        (30, 56), (274, 54), (362, 96), (274, 138), (30, 136), (18, 114), (18, 78)
    ]
    bd.polygon(hull, fill=COL_DARK, outline=COL_OUTLINE, width=10)
    # Stern bridge house (clean oval/pill)
    bd.rounded_rectangle([42, 68, 86, 124], radius=12, fill=COL_WHITE, outline=COL_OUTLINE, width=6)
    # Twin sleek cargo holds tinted in nation color
    md.rounded_rectangle([104, 68, 188, 124], radius=10, fill=MASK_FULL)
    md.rounded_rectangle([198, 72, 276, 120], radius=10, fill=MASK_MID)
    return base, mask


def _draw_warship() -> Tuple[Image.Image, Image.Image | None]:
    # Sleek pointed top-down naval cruiser pointing +X (384x192 -> 96x48)
    base, bd, mask, md = _new_pair(96, 48, True)
    hull = [
        (24, 60), (140, 44), (264, 52), (370, 96),
        (264, 140), (140, 148), (24, 132), (14, 96),
    ]
    bd.polygon(hull, fill=COL_STEEL, outline=COL_OUTLINE, width=10)
    # Nation-colored deck stripe / pennant deck
    md.polygon([(68, 76), (242, 72), (324, 96), (242, 120), (68, 116)], fill=MASK_MID)
    # Sleek bridge superstructure
    bd.rounded_rectangle([144, 70, 212, 122], radius=14, fill=COL_LIGHT, outline=COL_OUTLINE, width=6)
    # Fore and aft naval turrets + barrels
    bd.line([(256, 96), (318, 96)], fill=COL_OUTLINE, width=10)
    bd.ellipse([236, 78, 274, 114], fill=COL_WHITE, outline=COL_OUTLINE, width=6)
    bd.line([(60, 96), (104, 96)], fill=COL_OUTLINE, width=10)
    bd.ellipse([88, 80, 122, 112], fill=COL_WHITE, outline=COL_OUTLINE, width=6)
    return base, mask


def _draw_train() -> Tuple[Image.Image, Image.Image | None]:
    # Smooth rounded top-down locomotive pointing +X (256x128 -> 64x32)
    base, bd, mask, md = _new_pair(64, 32, True)
    bd.rounded_rectangle([18, 30, 118, 98], radius=14, fill=COL_STEEL, outline=COL_OUTLINE, width=8)
    bd.rounded_rectangle([128, 28, 240, 100], radius=22, fill=COL_LIGHT, outline=COL_OUTLINE, width=8)
    md.rounded_rectangle([28, 42, 108, 86], radius=10, fill=MASK_FULL)
    md.rounded_rectangle([142, 42, 214, 86], radius=12, fill=MASK_MID)
    return base, mask


GENERATORS: Dict[str, Tuple[bool, Callable[[], Tuple[Image.Image, Image.Image | None]]]] = {
    "icon_banner": (True, _draw_banner),
    "icon_town": (True, _draw_town),
    "icon_port": (True, _draw_port),
    "icon_factory": (True, _draw_factory),
    "icon_attack": (False, _draw_attack),
    "icon_defense_post": (True, _draw_defense_post),
    "icon_silo": (True, _draw_silo),
    "icon_sam": (True, _draw_sam),
    "icon_trade_ship": (True, _draw_trade_ship),
    "icon_warship": (True, _draw_warship),
    "icon_train": (True, _draw_train),
    "icon_missile": (False, _draw_missile),
    "icon_diplomacy": (False, _draw_diplomacy),
    "icon_wifi": (False, _draw_wifi),
    "icon_upgrade": (False, _draw_upgrade),
    "icon_boat": (False, _draw_boat),
    "icon_coin": (False, _draw_coin),
    "icon_troops": (False, _draw_troops),
}


def _composite_with_color(base: Image.Image, mask: Image.Image | None, rgb: Tuple[int, int, int]) -> Image.Image:
    out = base.copy()
    if mask is None:
        return out
    tinted = mask.copy()
    px = tinted.load()
    for y in range(tinted.height):
        for x in range(tinted.width):
            r, _g, _b, a = px[x, y]
            if a > 0:
                f = r / 255.0
                px[x, y] = (int(rgb[0] * f), int(rgb[1] * f), int(rgb[2] * f), a)
    out.alpha_composite(tinted)
    return out


def _make_9patch(
    size: int,
    fill: Tuple[int, int, int, int],
    border: Tuple[int, int, int, int],
    hi: Tuple[int, int, int, int],
    sh: Tuple[int, int, int, int],
    cut_top: bool = True,
    cut_bottom: bool = True,
    top_border: Tuple[int, int, int, int] | None = None,
    bottom_border: Tuple[int, int, int, int] | None = None,
    corner_accent: Tuple[int, int, int, int] | None = None,
) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    m = size - 1
    tb = top_border if top_border is not None else border
    bb = bottom_border if bottom_border is not None else border

    for y in range(size):
        for x in range(size):
            if cut_top and y == 0 and (x == 0 or x == m):
                continue
            if cut_bottom and y == m and (x == 0 or x == m):
                continue
            is_top_diag = cut_top and y == 1 and (x == 1 or x == m - 1)
            is_bot_diag = cut_bottom and y == m - 1 and (x == 1 or x == m - 1)
            if y == 0 or is_top_diag:
                px[x, y] = tb
            elif y == m or is_bot_diag:
                px[x, y] = bb
            elif x == 0 or x == m:
                px[x, y] = border
            elif (y == 1 if cut_top else y == 0) or x == 1:
                px[x, y] = hi
            elif (y == m - 1 if cut_bottom else y == m) or x == m - 1:
                px[x, y] = sh
            else:
                px[x, y] = fill

    if cut_top and not cut_bottom:
        for x in range(1, m):
            px[x, m] = bb
        px[1, m - 1] = hi
        px[m - 1, m - 1] = sh
    elif not cut_top and cut_bottom:
        for x in range(1, m):
            px[x, 0] = tb
        for x in range(1, m):
            px[x, 1] = hi
        px[1, 1] = hi

    if corner_accent is not None and size >= 12:
        for ax, ay in ((2, 2), (m - 2, 2), (2, m - 2), (m - 2, m - 2)):
            px[ax, ay] = corner_accent
    return img


def generate_ui_9patch_textures() -> None:
    os.makedirs(UI_DIR, exist_ok=True)
    specs = {
        "panel_9patch.png": dict(
            size=16,
            fill=(18, 28, 42, 240),
            border=(9, 14, 22, 255),
            hi=(74, 108, 144, 255),
            sh=(12, 19, 29, 255),
            corner_accent=(214, 178, 86, 255),
        ),
        "dock_top_9patch.png": dict(
            size=16,
            fill=(18, 28, 42, 242),
            border=(9, 14, 22, 255),
            hi=(74, 108, 144, 255),
            sh=(14, 22, 34, 255),
            cut_top=True,
            cut_bottom=False,
            bottom_border=(10, 16, 26, 255),
        ),
        "dock_bottom_9patch.png": dict(
            size=16,
            fill=(14, 22, 34, 244),
            border=(9, 14, 22, 255),
            hi=(48, 72, 100, 255),
            sh=(10, 16, 24, 255),
            cut_top=False,
            cut_bottom=True,
            top_border=(36, 56, 80, 255),
        ),
        # Neutral grayscale stepped bevels tinted cleanly via StyleBoxTexture.modulate_color
        "btn_normal_9patch.png": dict(
            size=16,
            fill=(212, 216, 222, 255),
            border=(46, 52, 62, 255),
            hi=(252, 254, 255, 255),
            sh=(132, 138, 148, 255),
        ),
        "btn_hover_9patch.png": dict(
            size=16,
            fill=(228, 232, 238, 255),
            border=(56, 64, 76, 255),
            hi=(255, 255, 255, 255),
            sh=(156, 162, 172, 255),
        ),
        "btn_pressed_9patch.png": dict(
            size=16,
            fill=(192, 196, 204, 255),
            border=(46, 52, 62, 255),
            hi=(118, 124, 134, 255),
            sh=(232, 236, 242, 255),
        ),
        "btn_disabled_9patch.png": dict(
            size=16,
            fill=(172, 176, 184, 195),
            border=(42, 46, 54, 210),
            hi=(206, 210, 218, 200),
            sh=(112, 116, 124, 200),
        ),
    }
    for fname, kw in specs.items():
        img = _make_9patch(**kw)
        dest = os.path.join(UI_DIR, fname)
        img.save(dest, format="PNG")
        print(f"[ui] Generated {dest} ({img.width}x{img.height})")


def _render_pixel_sprite_16(rows: List[str], out_size: int = 32) -> Image.Image:
    """Renders a 16x16 bitmap with automatic 1px dark outline into a crisp NEAREST RGBA image."""
    w, h = 16, 16
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    fg = set()
    palette = {
        "#": (244, 248, 255, 255),
        "s": (182, 200, 222, 255),
        "g": (248, 210, 88, 255),
    }
    for y in range(min(h, len(rows))):
        row = rows[y]
        for x in range(min(w, len(row))):
            if row[x] in palette:
                fg.add((x, y))
    for x, y in fg:
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                nx, ny = x + ox, y + oy
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in fg:
                    px[nx, ny] = (12, 18, 28, 255)
    for y in range(min(h, len(rows))):
        row = rows[y]
        for x in range(min(w, len(row))):
            ch = row[x]
            if ch in palette:
                px[x, y] = palette[ch]
    return img.resize((out_size, out_size), Image.Resampling.NEAREST)


def generate_pixel_ui_icons() -> None:
    """Generates crisp nearest-neighbor pixel-art action icons for menus, headers, and close/back controls."""
    os.makedirs(SPRITES_DIR, exist_ok=True)
    bitmaps = {
        "icon_play": [
            "................",
            "....##..........",
            "....####........",
            "....######......",
            "....########....",
            "....##########..",
            "....###########.",
            "....############",
            "....###########s",
            "....##########ss",
            "....########ssss",
            "....######ss....",
            "....####ss......",
            "....##ss........",
            "................",
            "................",
        ],
        "icon_back": [
            "................",
            "......##........",
            ".....###........",
            "....####........",
            "...#####........",
            "..##############",
            ".###############",
            ".##############s",
            "..######ssssssss",
            "...#####........",
            "....####........",
            ".....###........",
            "......##........",
            "................",
            "................",
            "................",
        ],
        "icon_close": [
            "................",
            "................",
            "..##........##..",
            "..###......###..",
            "...###....###...",
            "....###..###....",
            ".....######.....",
            "......####......",
            "......####......",
            ".....######.....",
            "....###..###....",
            "...###....###...",
            "..###......###..",
            "..ss........ss..",
            "................",
            "................",
        ],
        "icon_friends": [
            "................",
            "...###....###...",
            "..#####..#####..",
            "..#####..#####..",
            "..sssss..sssss..",
            "...###....###...",
            ".#######.######.",
            "########.#######",
            "########.#######",
            "########.#######",
            ".sssssss.ssssss.",
            "................",
            "..........g.....",
            ".........ggg....",
            "..........g.....",
            "................",
        ],
        "icon_multiplayer": [
            "................",
            ".....######.....",
            "...##########...",
            "..###s####s###..",
            "..##ss####ss##..",
            ".###s######s###.",
            ".##############.",
            ".sssss####sssss.",
            ".##############.",
            ".###s######s###.",
            "..##ss####ss##..",
            "..###s####s###..",
            "...##########...",
            ".....ssssss.....",
            "................",
            "................",
        ],
        "icon_audio": [
            "................",
            ".......##.......",
            "......###...s...",
            ".....####....s..",
            "..#######..s..s.",
            "..#######...s.s.",
            "..#######...s.s.",
            "..#######...s.s.",
            "..#######...s.s.",
            "..#######..s..s.",
            ".....####....s..",
            "......sss...s...",
            ".......ss.......",
            "................",
            "................",
            "................",
        ],
    }
    for name, rows in bitmaps.items():
        img = _render_pixel_sprite_16(rows, 32)
        dest = os.path.join(SPRITES_DIR, f"{name}.png")
        img.save(dest, format="PNG")
        print(f"[ui-icon] Generated {dest} ({img.width}x{img.height})")


def generate_pixel_logo() -> None:
    """Generates a crisp nearest-neighbor pixel-art logo for the Home Screen (352x96)."""
    pw, ph = 92, 25
    canvas = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    px = canvas.load()

    # 1. Pixelated Earth Globe + Tactical Crosshair on left (center 12, 12, radius 9)
    cx, cy, rad = 12, 12, 9
    for y in range(cy - rad - 1, cy + rad + 2):
        for x in range(cx - rad - 1, cx + rad + 2):
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            if d2 <= (rad + 1) ** 2 and d2 > rad ** 2:
                px[x, y] = (15, 23, 36, 255)
            elif d2 <= rad ** 2:
                # Ocean base
                col = (36, 98, 178, 255)
                if (x + y) % 5 == 0:
                    col = (46, 116, 202, 255)
                # Pixel continent shapes
                if (
                    (7 <= x <= 11 and 6 <= y <= 11)
                    or (8 <= x <= 10 and 12 <= y <= 17)
                    or (13 <= x <= 18 and 6 <= y <= 12)
                    or (14 <= x <= 17 and 13 <= y <= 16)
                ):
                    col = (74, 184, 108, 255) if (x + y) % 3 != 0 else (104, 212, 132, 255)
                # Highlight at top-left
                if (x - (cx - 3)) ** 2 + (y - (cy - 3)) ** 2 <= 4:
                    col = (min(255, col[0] + 35), min(255, col[1] + 35), min(255, col[2] + 35), 255)
                px[x, y] = col

    # Red tactical crosshair reticle on globe
    for dx in (-4, -3, 3, 4):
        px[cx + 2 + dx, cy - 2] = (255, 86, 64, 255)
    for dy in (-4, -3, 3, 4):
        px[cx + 2, cy - 2 + dy] = (255, 86, 64, 255)
    px[cx + 2, cy - 2] = (255, 224, 92, 255)

    # 5x7 pixel bitmap font for W O R L D A P I X E
    glyphs = {
        "W": ["10001", "10001", "10101", "10101", "10101", "11011", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        " ": ["000", "000", "000", "000", "000", "000", "000"],
    }

    def draw_pixel_word(word: str, start_x: int, start_y: int, top_col: Tuple[int, int, int, int], bot_col: Tuple[int, int, int, int]) -> None:
        cur_x = start_x
        for ch in word:
            rows = glyphs[ch]
            gw = len(rows[0])
            # Drop shadow & dark outline
            for gy, row in enumerate(rows):
                for gx, bit in enumerate(row):
                    if bit == "1":
                        for oy in (-1, 0, 1):
                            for ox in (-1, 0, 1):
                                sx, sy = cur_x + gx + ox, start_y + gy + oy
                                if 0 <= sx < pw and 0 <= sy < ph and px[sx, sy][3] == 0:
                                    px[sx, sy] = (14, 20, 30, 235)
                        if cur_x + gx + 1 < pw and start_y + gy + 1 < ph:
                            px[cur_x + gx + 1, start_y + gy + 1] = (10, 15, 24, 255)
            # Foreground pixel fill
            for gy, row in enumerate(rows):
                for gx, bit in enumerate(row):
                    if bit == "1":
                        px[cur_x + gx, start_y + gy] = top_col if gy < 3 else bot_col
            cur_x += gw + 1

    # Top row: "WORLD WAR" in crisp icy-steel pixels
    draw_pixel_word("WORLD WAR", 27, 3, (244, 250, 255, 255), (176, 204, 232, 255))
    # Bottom row: "PIXEL" in golden-amber pixels with flanking tactical bars
    draw_pixel_word("PIXEL", 39, 14, (255, 236, 124, 255), (242, 174, 54, 255))
    for bx in range(27, 37):
        px[bx, 17] = (242, 174, 54, 255)
        px[bx, 18] = (14, 20, 30, 240)
    for bx in range(70, 82):
        px[bx, 17] = (242, 174, 54, 255)
        px[bx, 18] = (14, 20, 30, 240)

    logo = canvas.resize((pw * 4, ph * 4), Image.Resampling.NEAREST)
    dest = os.path.join(SPRITES_DIR, "logo_world_war_pixel.png")
    logo.save(dest, format="PNG")
    print(f"[logo] Generated pixel-art logo {dest} ({logo.width}x{logo.height})")

    # Square multi-size app icon built from the 21x21 globe + crosshair emblem
    emblem = canvas.crop((2, 2, 23, 23))
    icon_specs = [
        (256, 231),
        (128, 126),
        (64, 63),
        (48, 42),
        (32, 30),
        (16, 16),
    ]
    frames: List[Image.Image] = []
    for box_sz, inner_sz in icon_specs:
        scaled = emblem.resize((inner_sz, inner_sz), Image.Resampling.NEAREST)
        if inner_sz == box_sz:
            frames.append(scaled)
        else:
            square = Image.new("RGBA", (box_sz, box_sz), (0, 0, 0, 0))
            offset = (box_sz - inner_sz) // 2
            square.paste(scaled, (offset, offset))
            frames.append(square)

    png_icon_dest = os.path.join(SPRITES_DIR, "app_icon.png")
    frames[0].save(png_icon_dest, format="PNG")
    ico_dest = os.path.join(SPRITES_DIR, "app_icon.ico")
    frames[0].save(
        ico_dest,
        format="ICO",
        sizes=[(f.width, f.height) for f in frames],
        append_images=frames[1:],
    )
    print(f"[logo] Generated square app icons {png_icon_dest} and {ico_dest}")


def main() -> None:
    os.makedirs(SPRITES_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    generate_ui_9patch_textures()
    generate_pixel_ui_icons()
    generate_pixel_logo()

    cell_w, cell_h = 112, 84
    sheet = Image.new("RGBA", (len(GENERATORS) * cell_w, cell_h), (48, 72, 62, 255))
    sample_blue = (72, 148, 240)
    for idx, (name, (has_mask, gen_fn)) in enumerate(GENERATORS.items()):
        hi_base, hi_mask = gen_fn()
        tw, th = hi_base.width // SS, hi_base.height // SS
        base = hi_base.resize((tw, th), Image.Resampling.LANCZOS)
        base_path = os.path.join(SPRITES_DIR, f"{name}.png")
        base.save(base_path, format="PNG")
        msg = f"[icons] Generated smooth {base_path} ({base.width}x{base.height})"

        mask = None
        if has_mask and hi_mask is not None:
            mask = hi_mask.resize((tw, th), Image.Resampling.LANCZOS)
            mask_path = os.path.join(SPRITES_DIR, f"{name}_mask.png")
            mask.save(mask_path, format="PNG")
            msg += " + mask"
        print(msg)

        preview_img = _composite_with_color(base, mask, sample_blue)
        scale = min(92 / float(base.width), 68 / float(base.height))
        up = preview_img.resize((max(8, int(base.width * scale)), max(8, int(base.height * scale))), Image.Resampling.LANCZOS)
        ox = idx * cell_w + (cell_w - up.width) // 2
        oy = (cell_h - up.height) // 2
        sheet.paste(up, (ox, oy), up)

    preview_path = os.path.join(CACHE_DIR, "icons_preview.png")
    sheet.save(preview_path, format="PNG")
    print(f"[icons] Contact sheet preview saved to {preview_path}")


if __name__ == "__main__":
    main()
