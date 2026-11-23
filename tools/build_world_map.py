"""Reproducible free-world pixel-art Earth map compiler for World War Pixel.

Generates:
- assets/map/world_terrain.png (2048x1024 crisp semi-detailed pixel-art Earth)
- data/world/world_grid.bin (1024x512 uint8 terrain grid; ALL land including Antarctica conquerable)
- data/world/ocean_nav.bin (1024x512 uint8 strict water-only navigable ocean grid: 0=blocked, 1=coastal/strait, 2=deep ocean)
- data/world/world_meta.json (dimensions, true spherical land area, region hints, AI spawn candidates)

All geography derives from Natural Earth 50m Public Domain datasets.
"""

from __future__ import annotations

import json
import math
import os
import urllib.request
from typing import Dict, List, Tuple

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

MAP_W = 2048
MAP_H = 1024
SIM_W = 1024
SIM_H = 512
NAV_W = 1024
NAV_H = 512
SEED = 42
EARTH_RADIUS_KM = 6371.0

CACHE_DIR = os.path.join("tools", "cache")
ASSET_MAP_DIR = os.path.join("assets", "map")
DATA_WORLD_DIR = os.path.join("data", "world")

NE_URLS = {
    "ne_50m_admin_0_countries.geojson": (
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
        "master/geojson/ne_50m_admin_0_countries.geojson"
    ),
    "ne_50m_lakes.geojson": (
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
        "master/geojson/ne_50m_lakes.geojson"
    ),
    "ne_50m_rivers_lake_centerlines.geojson": (
        "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
        "master/geojson/ne_50m_rivers_lake_centerlines.geojson"
    ),
}

T_OCEAN = 0
T_LAKE = 1
T_PLAINS = 2
T_FOREST = 3
T_JUNGLE = 4
T_HILLS = 5
T_MOUNTAINS = 6
T_DESERT = 7
T_TUNDRA = 8
T_POLAR_ICE = 9

BAYER_4X4 = (
    np.array(
        [
            [0, 8, 2, 10],
            [12, 4, 14, 6],
            [3, 11, 1, 9],
            [15, 7, 13, 5],
        ],
        dtype=np.float32,
    )
    / 16.0
    - 0.5
)


def ensure_natural_earth_cache() -> Dict[str, dict]:
    os.makedirs(CACHE_DIR, exist_ok=True)
    loaded = {}
    for fname, url in NE_URLS.items():
        path = os.path.join(CACHE_DIR, fname)
        if not os.path.exists(path):
            print(f"[map-builder] Downloading {fname}...")
            urllib.request.urlretrieve(url, path)
        with open(path, "r", encoding="utf-8") as f:
            loaded[fname] = json.load(f)
    return loaded


def lon_to_x(lon: float, width: int) -> float:
    return max(0.0, min(float(width), (lon + 180.0) / 360.0 * width))


def lat_to_y(lat: float, height: int) -> float:
    return max(0.0, min(float(height), (90.0 - lat) / 180.0 * height))


def sim_row_areas_km2() -> np.ndarray:
    d_lon = (2.0 * math.pi) / SIM_W
    d_lat = math.pi / SIM_H
    rows = np.arange(SIM_H, dtype=np.float64) + 0.5
    lats = np.deg2rad(90.0 - (rows / SIM_H) * 180.0)
    return (EARTH_RADIUS_KM ** 2) * d_lon * d_lat * np.maximum(np.cos(lats), 0.01)


def fbm_noise(h: int, w: int, rng: np.random.Generator, octaves: List[Tuple[int, float]]) -> np.ndarray:
    acc = np.zeros((h, w), dtype=np.float32)
    total_w = 0.0
    for grid_h, weight in octaves:
        grid_w = max(2, grid_h * 2)
        base = rng.random((grid_h, grid_w), dtype=np.float32)
        up = ndimage.zoom(base, (h / float(grid_h), w / float(grid_w)), order=1)
        acc += up[:h, :w] * weight
        total_w += weight
    return acc / max(total_w, 1e-6)


def smooth_elliptical_field(
    lon_grid: np.ndarray,
    lat_grid: np.ndarray,
    regions: List[Tuple[float, float, float, float, float]],
) -> np.ndarray:
    field = np.zeros_like(lon_grid, dtype=np.float32)
    for clon, clat, rlon, rlat, weight in regions:
        d2 = ((lon_grid - clon) / rlon) ** 2 + ((lat_grid - clat) / rlat) ** 2
        field += weight * np.exp(-1.15 * d2)
    return field


def rasterize_rings(img: Image.Image, rings: list, w: int, h: int, fill_val: int) -> None:
    draw = ImageDraw.Draw(img)
    if not rings:
        return
    outer = [(lon_to_x(pt[0], w), lat_to_y(pt[1], h)) for pt in rings[0]]
    if len(outer) >= 3:
        draw.polygon(outer, fill=fill_val)
    for hole in rings[1:]:
        h_pts = [(lon_to_x(pt[0], w), lat_to_y(pt[1], h)) for pt in hole]
        if len(h_pts) >= 3:
            draw.polygon(h_pts, fill=0)


def rasterize_earth_hi(gj: dict) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Rasterize Natural Earth 50m directly at crisp 2048x1024."""
    land_img = Image.new("L", (MAP_W, MAP_H), 0)
    ata_img = Image.new("L", (MAP_W, MAP_H), 0)
    for feat in gj["ne_50m_admin_0_countries.geojson"]["features"]:
        geom = feat.get("geometry")
        if not geom:
            continue
        props = feat["properties"]
        a3 = str(props.get("ADM0_A3", ""))
        cont = str(props.get("CONTINENT", ""))
        polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
        target_img = ata_img if (a3 == "ATA" or cont == "Antarctica") else land_img
        for poly in polys:
            rasterize_rings(target_img, poly, MAP_W, MAP_H, 1)

    land_hi = np.array(land_img, dtype=np.uint8) > 0
    ata_hi = np.array(ata_img, dtype=np.uint8) > 0
    ata_hi[-1, :] = np.logical_or(ata_hi[-1, :], ata_hi[-2, :])
    land_hi = land_hi | ata_hi

    lake_img = Image.new("L", (MAP_W, MAP_H), 0)
    for feat in gj["ne_50m_lakes.geojson"]["features"]:
        rank = feat.get("properties", {}).get("scalerank", 5)
        if rank is not None and int(rank) > 4:
            continue
        geom = feat.get("geometry")
        if not geom:
            continue
        polys = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
        for poly in polys:
            rasterize_rings(lake_img, poly, MAP_W, MAP_H, 1)
    lake_hi = np.array(lake_img, dtype=np.uint8) > 0
    land_hi[lake_hi] = False
    return land_hi, lake_hi, ata_hi


def enlarge_tiny_islands_hi(land_hi: np.ndarray, lake_hi: np.ndarray) -> np.ndarray:
    """Gently enlarge ONLY tiny islands at 2048x1024 (rounded, strait-preserving).

    Medium/large islands and continents (>160 px) remain 100% untouched.
    """
    comp_map, n_comp = ndimage.label(land_hi, structure=np.ones((3, 3), dtype=bool))
    sizes = np.bincount(comp_map.ravel())

    target_steps = np.zeros(n_comp + 1, dtype=np.int32)
    for cid in range(1, n_comp + 1):
        sz = int(sizes[cid])
        if sz <= 45:
            target_steps[cid] = 3
        elif sz <= 160:
            target_steps[cid] = 2

    owner = comp_map.copy()
    struct_cross = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], dtype=bool)
    struct_box = np.ones((3, 3), dtype=bool)

    for step, dil_struct in ((1, struct_cross), (2, struct_box), (3, struct_cross)):
        eligible_ids = set(np.nonzero(target_steps >= step)[0].tolist())
        if not eligible_ids:
            break
        elig_mask = np.isin(owner, list(eligible_ids))
        cand_mask = ndimage.binary_dilation(elig_mask, structure=dil_struct) & (owner == 0) & (~lake_hi)
        ys, xs = np.nonzero(cand_mask)
        if len(xs) == 0:
            break

        to_assign: List[Tuple[int, int, int]] = []
        for y, x in zip(ys.tolist(), xs.tolist()):
            y0, y1 = max(0, y - 1), min(MAP_H, y + 2)
            x0, x1 = max(0, x - 1), min(MAP_W, x + 2)
            patch3 = owner[y0:y1, x0:x1]
            elig_vals = patch3[patch3 > 0]
            if len(elig_vals) == 0:
                continue
            vals, counts = np.unique(elig_vals, return_counts=True)
            best_idx = int(np.argmax(counts))
            chosen_cid = int(vals[best_idx])
            if chosen_cid not in eligible_ids:
                continue
            # Keep corners rounded on box pass
            if step == 2 and int(counts[best_idx]) < 2:
                continue

            # Strait guard: require NO other landmass component within a 7x7 window
            yy0, yy1 = max(0, y - 3), min(MAP_H, y + 4)
            xx0, xx1 = max(0, x - 3), min(MAP_W, x + 4)
            patch7 = owner[yy0:yy1, xx0:xx1]
            others = patch7[(patch7 > 0) & (patch7 != chosen_cid)]
            if len(others) == 0:
                to_assign.append((y, x, chosen_cid))

        for y, x, chosen_cid in to_assign:
            owner[y, x] = chosen_cid

    return owner > 0


def _get_real_strait_sim_cells() -> List[Tuple[int, int]]:
    """Canonical 1024x512 natural sea-strait pixels kept open on terrain, sim_grid, and ocean_nav."""
    cells: List[Tuple[int, int]] = [
        # Strait of Dover / English Channel
        (515, 110), (516, 110), (517, 110),
        # Irish Sea North Channel
        (494, 98), (494, 99), (495, 98),
        # Messina, Bonifacio, Tartary, La Perouse, Palk
        (int(round(lon_to_x(15.65, SIM_W))), int(round(lat_to_y(38.15, SIM_H)))),
        (int(round(lon_to_x(9.2, SIM_W))), int(round(lat_to_y(41.35, SIM_H)))),
        (int(round(lon_to_x(141.6, SIM_W))), int(round(lat_to_y(52.2, SIM_H)))),
        (int(round(lon_to_x(142.0, SIM_W))), int(round(lat_to_y(45.7, SIM_H)))),
        (int(round(lon_to_x(79.6, SIM_W))), int(round(lat_to_y(9.2, SIM_H)))),
        # Strait of Gibraltar
        (495, 154), (496, 154), (497, 154),
        # Oresund / Kattegat -> Baltic Sea
        (544, 96), (545, 96), (545, 97), (546, 97), (547, 97), (547, 98), (548, 98),
        # Aegean Cyclades channel -> Dardanelles & Bosporus -> Kerch Strait
        (585, 148), (585, 149), (585, 150), (585, 151), (586, 151), (586, 152),
        (586, 142), (586, 141), (587, 141), (588, 141),
        (588, 140), (589, 140), (590, 140), (591, 140), (592, 140), (592, 139), (593, 139), (593, 138),
        (616, 126), (616, 127), (616, 128),
        # Bab-el-Mandeb (Red Sea <-> Gulf of Aden)
        (632, 216), (633, 216), (633, 217), (633, 218), (634, 218), (634, 219), (635, 219), (635, 220),
        # Strait of Hormuz (Persian Gulf <-> Gulf of Oman)
        (670, 181), (671, 181), (672, 181), (673, 181),
        # White Sea Throat
        (626, 68), (626, 67), (627, 67),
    ]
    return [(sx, sy) for sx, sy in cells if 0 <= sx < SIM_W and 0 <= sy < SIM_H]


def _open_sea_straits_hi(land_hi: np.ndarray) -> np.ndarray:
    """Open sub-pixel-pinched real sea straits at 2048x1024 so terrain matches navigable ocean."""
    out = land_hi.copy()
    for sx, sy in _get_real_strait_sim_cells():
        out[sy * 2 : sy * 2 + 2, sx * 2 : sx * 2 + 2] = False
    return out


def classify_pixel_art_biomes_hi(
    land_hi: np.ndarray,
    lake_hi: np.ndarray,
    ata_hi: np.ndarray,
    rng: np.random.Generator,
) -> Tuple[np.ndarray, np.ndarray]:
    """Crisp 2048x1024 discrete biome classification with smooth elliptical fields."""
    elev = fbm_noise(MAP_H, MAP_W, rng, [(12, 0.45), (32, 0.30), (96, 0.17), (256, 0.08)])
    moist = fbm_noise(MAP_H, MAP_W, rng, [(8, 0.50), (24, 0.32), (72, 0.18)])
    lat_warp = (fbm_noise(MAP_H, MAP_W, rng, [(10, 0.65), (28, 0.35)]) - 0.5) * 14.0
    lon_warp = (fbm_noise(MAP_H, MAP_W, rng, [(10, 0.65), (28, 0.35)]) - 0.5) * 16.0

    lons = (np.arange(MAP_W, dtype=np.float32) + 0.5) / MAP_W * 360.0 - 180.0
    lats = 90.0 - (np.arange(MAP_H, dtype=np.float32) + 0.5) / MAP_H * 180.0
    lon_grid, lat_grid = np.meshgrid(lons, lats)
    w_lon = lon_grid + lon_warp
    w_lat = lat_grid + lat_warp

    mountain_boost = smooth_elliptical_field(
        w_lon,
        w_lat,
        [
            (86.0, 33.0, 17.0, 7.0, 0.38),
            (-69.0, -18.0, 5.5, 22.0, 0.33),
            (-113.0, 46.0, 9.0, 14.0, 0.28),
            (11.0, 46.5, 8.0, 3.0, 0.26),
            (46.0, 38.0, 12.0, 6.0, 0.24),
            (72.0, 38.0, 9.0, 5.5, 0.26),
            (38.5, 9.0, 4.5, 5.0, 0.22),
            (13.0, 63.0, 6.0, 6.0, 0.20),
        ],
    )
    elev = np.clip(elev * 0.72 + mountain_boost, 0.0, 1.0)

    arid = smooth_elliptical_field(
        w_lon,
        w_lat,
        [
            (10.0, 23.0, 24.0, 8.5, 0.52),
            (46.0, 23.0, 12.0, 7.5, 0.48),
            (92.0, 41.0, 20.0, 5.5, 0.42),
            (60.0, 39.0, 10.0, 5.5, 0.34),
            (129.0, -25.0, 13.0, 6.5, 0.44),
            (-110.0, 30.0, 7.5, 6.5, 0.34),
            (18.0, -24.0, 6.5, 6.0, 0.36),
            (-69.0, -23.0, 3.5, 7.0, 0.32),
        ],
    )
    humid = smooth_elliptical_field(
        w_lon,
        w_lat,
        [
            (-62.0, -4.0, 14.0, 9.5, 0.48),
            (20.0, 0.0, 10.0, 6.0, 0.42),
            (114.0, 1.5, 22.0, 11.0, 0.38),
            (89.0, 23.0, 11.0, 7.0, 0.28),
            (-10.0, 49.0, 18.0, 10.0, 0.20),
            (-82.0, 36.0, 14.0, 9.0, 0.22),
        ],
    )
    eff_moist = np.clip(moist + humid - arid, 0.0, 1.0)
    abs_wlat = np.abs(w_lat)

    # Identify open ocean vs inland lakes cleanly
    water_hi = ~land_hi
    w_comp, _ = ndimage.label(water_hi)
    w_sizes = np.bincount(w_comp.ravel())
    w_sizes[0] = 0
    ocean_id = int(np.argmax(w_sizes))
    open_ocean_hi = w_comp == ocean_id

    grid_hi = np.full((MAP_H, MAP_W), T_LAKE, dtype=np.uint8)
    grid_hi[open_ocean_hi] = T_OCEAN

    grid_hi[land_hi] = T_PLAINS
    grid_hi[land_hi & (eff_moist > 0.47)] = T_FOREST
    grid_hi[land_hi & (abs_wlat < 22.0) & (eff_moist > 0.58)] = T_JUNGLE
    grid_hi[land_hi & (eff_moist < 0.29) & (abs_wlat < 49.0)] = T_DESERT
    grid_hi[land_hi & (elev > 0.56)] = T_HILLS
    grid_hi[land_hi & (elev > 0.69)] = T_MOUNTAINS
    grid_hi[land_hi & (w_lat > 62.5)] = T_TUNDRA

    greenland = land_hi & (lat_grid > 58.0) & (lon_grid > -74.0) & (lon_grid < -10.0)
    if np.any(greenland):
        gl_edt = ndimage.distance_transform_edt(greenland)
        grid_hi[greenland & ((gl_edt + (elev - 0.5) * 14.0) > 8.5)] = T_POLAR_ICE

    grid_hi[land_hi & ((lat_grid < -58.0) | ata_hi)] = T_POLAR_ICE
    grid_hi[lake_hi & (~land_hi)] = T_LAKE
    return grid_hi, elev


def render_crisp_pixel_art_terrain(
    grid_hi: np.ndarray,
    elev: np.ndarray,
    rivers_gj: dict,
    rng: np.random.Generator,
) -> Image.Image:
    """Render the original Phase 1 crisp semi-detailed pixel-art 2048x1024 Earth."""
    land = grid_hi >= T_PLAINS
    water = ~land
    lake_mask = grid_hi == T_LAKE

    ocean_edt = ndimage.distance_transform_edt(water).astype(np.float32)
    bathy_noise = fbm_noise(MAP_H, MAP_W, rng, [(16, 0.55), (48, 0.45)])
    depth_val = np.clip((ocean_edt / 65.0) + (bathy_noise - 0.5) * 0.25, 0.0, 1.0)
    dither = np.tile(BAYER_4X4, (MAP_H // 4 + 1, MAP_W // 4 + 1))[:MAP_H, :MAP_W]

    ocean_palette = np.array(
        [
            [62, 118, 158],
            [44, 93, 132],
            [33, 73, 108],
            [24, 55, 85],
            [17, 41, 66],
        ],
        dtype=np.float32,
    )
    band_f = np.clip(depth_val * 4.0 + dither * 0.65, 0.0, 3.999)
    band_idx = np.round(band_f).astype(np.int32)
    rgb = ocean_palette[band_idx].copy()

    rgb[lake_mask] = np.array([42, 96, 138], dtype=np.float32)

    shoreline = ndimage.binary_dilation(land, structure=np.ones((3, 3), dtype=bool)) & water & (~lake_mask)
    rgb[shoreline] = np.array([86, 148, 184], dtype=np.float32)

    biome_colors = {
        T_PLAINS: np.array([110, 152, 88], dtype=np.float32),
        T_FOREST: np.array([66, 116, 68], dtype=np.float32),
        T_JUNGLE: np.array([45, 96, 60], dtype=np.float32),
        T_HILLS: np.array([128, 132, 86], dtype=np.float32),
        T_MOUNTAINS: np.array([124, 116, 112], dtype=np.float32),
        T_DESERT: np.array([196, 166, 112], dtype=np.float32),
        T_TUNDRA: np.array([126, 138, 122], dtype=np.float32),
        T_POLAR_ICE: np.array([218, 232, 242], dtype=np.float32),
    }
    for b_code, col in biome_colors.items():
        rgb[grid_hi == b_code] = col

    gy, gx = np.gradient(elev)
    shade = np.clip((-gx * 0.7 - gy * 0.7) * 8.5, -0.22, 0.24)
    relief_scale = np.where((grid_hi == T_HILLS) | (grid_hi == T_MOUNTAINS) | (grid_hi == T_POLAR_ICE), 1.45, 0.65)
    rgb[land] *= 1.0 + shade[land, None] * relief_scale[land, None]

    stipple = rng.random((MAP_H, MAP_W), dtype=np.float32)
    forest_canopy = ((grid_hi == T_FOREST) | (grid_hi == T_JUNGLE)) & (stipple > 0.78)
    rgb[forest_canopy] *= 0.84
    dune_stripe = (grid_hi == T_DESERT) & (((np.arange(MAP_W)[None, :] + np.arange(MAP_H)[:, None] * 2) % 7) == 0) & (stipple > 0.45)
    rgb[dune_stripe] *= 1.09
    snow_peaks = (grid_hi == T_MOUNTAINS) & (elev > 0.81) & (stipple > 0.35)
    rgb[snow_peaks] = np.array([218, 226, 234], dtype=np.float32)
    ice_ridge = (grid_hi == T_POLAR_ICE) & (stipple > 0.86)
    rgb[ice_ridge] = np.array([186, 208, 226], dtype=np.float32)

    eroded_land = ndimage.binary_erosion(land, structure=np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], dtype=bool))
    coast_ink = land & (~eroded_land)
    rgb[coast_ink] = rgb[coast_ink] * 0.48 + np.array([14, 24, 34], dtype=np.float32) * 0.52

    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), mode="RGB")

    river_img = Image.new("L", (MAP_W, MAP_H), 0)
    r_draw = ImageDraw.Draw(river_img)
    for feat in rivers_gj["features"]:
        rank = feat.get("properties", {}).get("scalerank", 6)
        if rank is not None and int(rank) > 5:
            continue
        geom = feat.get("geometry")
        if not geom:
            continue
        lines = [geom["coordinates"]] if geom["type"] == "LineString" else geom["coordinates"]
        for line in lines:
            pts = [(lon_to_x(pt[0], MAP_W), lat_to_y(pt[1], MAP_H)) for pt in line]
            if len(pts) >= 2:
                r_draw.line(pts, fill=1, width=1)
    river_mask = (np.array(river_img, dtype=np.uint8) > 0) & land & (grid_hi != T_POLAR_ICE)
    out_arr = np.array(img, dtype=np.uint8)
    out_arr[river_mask] = np.array([50, 108, 146], dtype=np.uint8)
    return Image.fromarray(out_arr, mode="RGB")


def downsample_to_sim_grid(grid_hi: np.ndarray) -> np.ndarray:
    """Downsample 2048x1024 grid_hi to 1024x512 sim_grid preserving narrow straits AND tiny islands."""
    land_hi = grid_hi >= T_PLAINS
    comp_hi, n_comp = ndimage.label(land_hi, structure=[[0, 1, 0], [1, 1, 1], [0, 1, 0]])
    sizes = np.bincount(comp_hi.ravel())
    tiny_ids = set(np.nonzero((sizes > 0) & (sizes <= 240))[0].tolist())
    tiny_hi = np.isin(comp_hi, list(tiny_ids))

    blocks = grid_hi.reshape(SIM_H, 2, SIM_W, 2)
    land_blocks = blocks >= T_PLAINS
    tiny_blocks = tiny_hi.reshape(SIM_H, 2, SIM_W, 2)

    # Use majority (>= 2 of 4 hi-res pixels) on continents/large islands so narrow straits stay open,
    # while keeping ANY pixel of tiny oceanic islands intact.
    is_land = (land_blocks.sum(axis=(1, 3)) >= 2) | tiny_blocks.any(axis=(1, 3))

    sim_grid = np.zeros((SIM_H, SIM_W), dtype=np.uint8)
    sim_grid[~is_land] = blocks[:, 0, :, 0][~is_land]
    is_lake = (~is_land) & (blocks == T_LAKE).all(axis=(1, 3))
    sim_grid[is_lake] = T_LAKE

    ys, xs = np.nonzero(is_land)
    for y, x in zip(ys.tolist(), xs.tolist()):
        vals = blocks[y, :, x, :].ravel()
        land_vals = vals[vals >= T_PLAINS]
        u, uc = np.unique(land_vals, return_counts=True)
        sim_grid[y, x] = u[np.argmax(uc)]

    for sx, sy in _get_real_strait_sim_cells():
        sim_grid[sy, sx] = T_OCEAN
    return sim_grid


def build_ocean_nav_grid(sim_grid: np.ndarray) -> np.ndarray:
    """Build 1024x512 strict water-only nav grid (0=blocked, 1=coastal/strait T_OCEAN, 2=deep ocean)."""
    open_ocean = sim_grid == T_OCEAN
    # Keep strictly the single 4-connected global ocean component so boats never tunnel across land.
    comp, _ = ndimage.label(open_ocean)
    sizes = np.bincount(comp.ravel())
    sizes[0] = 0
    main_ocean = int(np.argmax(sizes))
    connected = comp == main_ocean

    dist = ndimage.distance_transform_edt(connected)
    nav = np.zeros((NAV_H, NAV_W), dtype=np.uint8)
    nav[connected] = 1
    nav[connected & (dist >= 2.0)] = 2
    assert int(np.sum((nav > 0) & (sim_grid != T_OCEAN))) == 0, "Ocean nav grid overlapped non-ocean terrain!"
    return nav


def find_nearest_land(sim_grid: np.ndarray, lon: float, lat: float, max_r: int = 8) -> Tuple[int, int] | None:
    cx = int(min(SIM_W - 1, max(0, round(lon_to_x(lon, SIM_W)))))
    cy = int(min(SIM_H - 1, max(0, round(lat_to_y(lat, SIM_H)))))
    if sim_grid[cy, cx] >= T_PLAINS:
        return cx, cy
    best = None
    best_d2 = 1e9
    for dy in range(-max_r, max_r + 1):
        for dx in range(-max_r, max_r + 1):
            yy, xx = cy + dy, cx + dx
            if 0 <= yy < SIM_H and 0 <= xx < SIM_W and sim_grid[yy, xx] >= T_PLAINS:
                d2 = dx * dx + dy * dy
                if d2 < best_d2:
                    best_d2 = d2
                    best = (xx, yy)
    return best


def main() -> None:
    os.makedirs(ASSET_MAP_DIR, exist_ok=True)
    os.makedirs(DATA_WORLD_DIR, exist_ok=True)
    rng = np.random.default_rng(SEED)

    gj = ensure_natural_earth_cache()
    print("[map-builder] Rasterizing Natural Earth 50m at 2048x1024...")
    land_hi, lake_hi, ata_hi = rasterize_earth_hi(gj)

    print("[map-builder] Gently enlarging ONLY tiny oceanic islands (preserving straits)...")
    land_hi = enlarge_tiny_islands_hi(land_hi, lake_hi)
    land_hi = _open_sea_straits_hi(land_hi)

    print("[map-builder] Classifying crisp pixel-art biomes & rendering 2048x1024 terrain...")
    grid_hi, elev = classify_pixel_art_biomes_hi(land_hi, lake_hi, ata_hi, rng)
    terrain_img = render_crisp_pixel_art_terrain(grid_hi, elev, gj["ne_50m_rivers_lake_centerlines.geojson"], rng)
    terrain_img.save(os.path.join(ASSET_MAP_DIR, "world_terrain.png"), format="PNG")

    print("[map-builder] Building 1024x512 simulation grid and strict 1024x512 ocean nav grid...")
    sim_grid = downsample_to_sim_grid(grid_hi)
    nav_grid = build_ocean_nav_grid(sim_grid)
    assert int(np.sum((nav_grid > 0) & (sim_grid != T_OCEAN))) == 0

    # Verify all major world seas/gulfs are navigable and part of the unified connected ocean
    sea_comp, _ = ndimage.label(nav_grid > 0)
    sea_labels_seen = set()
    for sea_name, slon, slat in [
        ("North Atlantic", -35.0, 35.0),
        ("South Atlantic", -15.0, -20.0),
        ("Indian Ocean", 75.0, -10.0),
        ("Pacific Ocean", -140.0, 0.0),
        ("Southern Ocean", 0.0, -62.0),
        ("Mediterranean W", 5.0, 38.5),
        ("Mediterranean E", 24.0, 34.5),
        ("Black Sea", 34.0, 43.2),
        ("Red Sea", 38.5, 20.0),
        ("Persian Gulf", 51.5, 26.5),
        ("Baltic Sea", 19.8, 57.5),
        ("North Sea", 3.5, 56.0),
        ("English Channel", -1.5, 50.0),
        ("Hudson Bay", -84.0, 59.5),
        ("Gulf of Mexico", -90.0, 25.0),
        ("Caribbean Sea", -75.0, 15.0),
        ("Java Sea", 111.0, -5.0),
        ("South China Sea", 114.0, 14.0),
        ("Philippine Sea", 132.0, 18.0),
        ("Sea of Japan", 134.0, 39.0),
        ("Bering Strait", -169.0, 65.8),
    ]:
        nx = int(min(NAV_W - 1, max(0, round(lon_to_x(slon, NAV_W)))))
        ny = int(min(NAV_H - 1, max(0, round(lat_to_y(slat, NAV_H)))))
        val = int(nav_grid[ny, nx])
        cid = int(sea_comp[ny, nx])
        assert val > 0 and cid > 0, f"Regional sea blocked in ocean_nav.bin: {sea_name} ({nx},{ny}) val={val}"
        sea_labels_seen.add(cid)
    assert len(sea_labels_seen) == 1, f"Oceans split into {len(sea_labels_seen)} disconnected components!"

    with open(os.path.join(DATA_WORLD_DIR, "world_grid.bin"), "wb") as f:
        f.write(sim_grid.tobytes(order="C"))
    with open(os.path.join(DATA_WORLD_DIR, "ocean_nav.bin"), "wb") as f:
        f.write(nav_grid.tobytes(order="C"))

    row_areas = sim_row_areas_km2()
    land_mask = sim_grid >= T_PLAINS
    ys, xs = np.nonzero(land_mask)
    total_conquerable_area = float(np.sum(row_areas[ys]))
    ata_ys, _ = np.nonzero(land_mask & (np.arange(SIM_H)[:, None] > int(lat_to_y(-58.5, SIM_H))))
    ata_area = float(np.sum(row_areas[ata_ys]))

    for label, lon, lat in [
        ("Hawaii", -155.5, 19.6),
        ("Iceland", -18.5, 64.9),
        ("Madagascar", 46.8, -18.9),
        ("Cuba", -79.5, 21.8),
        ("Japan", 138.2, 36.2),
        ("Falklands", -59.5, -51.7),
        ("Antarctica South Pole", 0.0, -82.0),
    ]:
        assert find_nearest_land(sim_grid, lon, lat, max_r=4) is not None, f"Missing {label}"

    region_specs = [
        ("North America", -100.0, 44.0), ("United States", -96.0, 38.0), ("Canada", -102.0, 58.0),
        ("Alaska", -152.0, 64.0), ("Central America", -86.0, 13.0), ("Caribbean Islands", -74.0, 20.5),
        ("South America", -58.0, -14.0), ("Amazon Basin", -62.0, -4.0), ("Patagonia", -69.0, -45.0),
        ("Western Europe", 4.0, 48.0), ("British Isles", -2.5, 54.0), ("Scandinavia", 15.0, 63.0),
        ("Eastern Europe", 28.0, 50.0), ("Mediterranean", 14.0, 40.0), ("North Africa", 12.0, 24.0),
        ("West Africa", -4.0, 12.0), ("East Africa", 36.0, 2.0), ("Southern Africa", 24.0, -24.0),
        ("Madagascar", 46.8, -19.0), ("Middle East", 45.0, 26.0), ("Central Asia", 66.0, 43.0),
        ("Siberia", 98.0, 61.0), ("South Asia", 78.0, 21.0), ("East Asia", 112.0, 35.0),
        ("Southeast Asia", 104.0, 13.0), ("Japanese Archipelago", 138.5, 36.5),
        ("Australia", 134.0, -25.0), ("New Zealand", 172.0, -42.0), ("Greenland", -42.0, 72.0),
        ("Antarctica / South Pole", 0.0, -82.0), ("Antarctic Peninsula", -64.0, -66.0),
        ("East Antarctica", 85.0, -76.0),
    ]
    region_labels = [
        {"name": name, "x": round(lon_to_x(lon, SIM_W), 1), "y": round(lat_to_y(lat, SIM_H), 1)}
        for name, lon, lat in region_specs
    ]

    ai_coords = [
        (-98.0, 39.0), (-75.0, 41.0), (-118.0, 35.0), (-50.0, -21.0), (-68.0, -34.0),
        (2.3, 48.8), (13.4, 52.5), (-3.7, 40.4), (37.6, 55.7), (18.0, 59.3),
        (31.2, 30.0), (3.4, 6.5), (28.0, -26.2), (38.7, 9.0), (46.7, 24.7),
        (77.2, 28.6), (116.4, 39.9), (121.5, 31.2), (100.5, 13.7), (139.7, 35.7),
        (151.2, -33.8), (115.8, -31.9), (-1.5, 52.5), (-63.5, -65.0),
    ]
    ai_spawns = []
    for lon, lat in ai_coords:
        pt = find_nearest_land(sim_grid, lon, lat, max_r=6)
        if pt is not None:
            ai_spawns.append({"x": pt[0], "y": pt[1]})

    meta_payload = {
        "version": 2,
        "mode": "free_world",
        "sim_width": SIM_W,
        "sim_height": SIM_H,
        "map_width": MAP_W,
        "map_height": MAP_H,
        "nav_width": NAV_W,
        "nav_height": NAV_H,
        "total_land_cells": int(len(xs)),
        "total_conquerable_area_km2": round(total_conquerable_area, 1),
        "antarctica_land_cells": int(len(ata_ys)),
        "antarctica_area_km2": round(ata_area, 1),
        "region_labels": region_labels,
        "ai_spawn_candidates": ai_spawns,
    }
    with open(os.path.join(DATA_WORLD_DIR, "world_meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta_payload, f, indent=2)

    print(
        f"[map-builder] SUCCESS: {len(xs):,} land cells "
        f"(Antarctica={len(ata_ys):,} cells / {ata_area:,.0f} km2), "
        f"total conquerable={total_conquerable_area:,.0f} km2, "
        f"nav_ocean_cells={int(np.sum(nav_grid > 0)):,}."
    )


if __name__ == "__main__":
    main()
