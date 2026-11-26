<img src="assets/sprites/logo_world_war_pixel.png" alt="World War Pixel" width="280">

# World War Pixel

A real-time grand-strategy game played on a pixel-art world map. Built with Godot 4 and an authoritative Go multiplayer server, shipped with a standalone Windows launcher.

## Overview

- **Real-Time Grand Strategy**: Continuous territory expansion, conquest, and naval invasions across a 2048×1024 pixel-art Earth
- **Economy & Infrastructure**: Towns, factories with winding roads & trains, ports with multi-lane ocean trade, defense posts, and bridges
- **Strategic Weapons & Naval Warfare**: Controllable warships, missile silos, nuclear strikes (Atom, H-Bomb, MIRV), and SAM air defense
- **Accounts, Friends & Custom Avatars**: Permanent unique usernames, player search, online-sorted friends roster, room invites, and Photo/GIF profile pictures synced between the launcher and game
- **Standalone Launcher (`WorldWarPixel.exe`)**: Built-in account sign-in/friends, Patch Notes browser, automatic version checks, and lightweight `.pck` patch updates

---

## Download & Install (Windows — For Players)

Head to the **[Releases Page](https://github.com/realpeyaj/worldwarpixel/releases)** and download the latest Windows bundle:

1. Download **`WorldWarPixel-Windows-vX.Y.Z.zip`** (for example, `WorldWarPixel-Windows-v1.0.0.zip`) from the latest release.
2. Right-click the `.zip` → **Extract All…** into a folder you own (for example, `C:\Games\WorldWarPixel\`).
   - *Do not move `WorldWarPixel.exe` outside the extracted folder — keep `WorldWarPixel.exe` alongside the `game\` subfolder.*
3. Double-click **`WorldWarPixel.exe`** to open the launcher.
   - *Note:* If Windows SmartScreen warns about an unrecognized app on unsigned indie builds, click **More info** → **Run anyway**.
4. **In the Launcher:**
   - Open the **Account** tab (or click **SIGN IN** in the top-right) to create an account or sign in, upload a PNG/JPG/GIF avatar, and add friends.
   - Browse the **Patch Notes** tab for updates.
   - Click **PLAY** to launch directly into the game.

### Updating Later

You never need to re-download the full `.zip` manually:

- Open **`WorldWarPixel.exe`**. It automatically checks GitHub Releases against your installed version (`game/version.txt`).
- When a patch is available, the main button changes to **UPDATE vX.Y.Z** — click it to download and verify the compact `.pck` patch (verified with `SHA256SUMS.txt`), then click **PLAY**.

---

## Publishing Releases & Fast Patches (For Maintainers)

### Full Windows Release (Launcher + Game Engine + Content Pack)

Run the release script on Windows (requires Godot 4.7.2 console binary, Go 1.24, LLVM-MinGW `windres`, and Python 3):

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_release.ps1
```

This exports the decoupled client (`WorldWarPixel-Client.exe` + `WorldWarPixel-Client.pck`), compiles `WorldWarPixel.exe`, and packages everything into `builds/release/`:

- `WorldWarPixel-Windows-vX.Y.Z.zip` — Full first-time download bundle for friends/players (`WorldWarPixel.exe` + `game/` + `PATCH_NOTES.md`)
- `WorldWarPixel-Client.zip` — Full client payload for launcher auto-installs
- `WorldWarPixel-Patch.zip` — Content-only `.pck` + `PATCH_NOTES.md` update for existing players
- `SHA256SUMS.txt` — Integrity checksums verified automatically by `WorldWarPixel.exe`

Create a GitHub Release tagged `vX.Y.Z` (matching `config/version` in `project.godot`) and upload all 4 files above.

### Fast Content Patch (Scripts, UI, Map, or Audio Only)

When you only update GDScript, scenes, UI, map data, or audio without changing the Godot engine binary, bump `config/version` in `project.godot`, update `PATCH_NOTES.md`, and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_patch.ps1 -Version X.Y.Z
```

Upload `builds/release/WorldWarPixel-Patch.zip` and `builds/release/SHA256SUMS.txt` (or add `-Delta` to emit a tiny `WorldWarPixel-Delta-vX.Y.Z.pck` patch) to a new GitHub Release `vX.Y.Z`. Existing launchers will automatically fetch only the small patch!

---

## Running From Source & Self-Hosting

### Requirements

- [Godot Engine 4.7.2](https://godotengine.org/) (client)
- [Go 1.24](https://go.dev/) or Docker Compose (launcher build & optional multiplayer server self-hosting)

### Client (Godot Editor / CLI)

Open `project.godot` in Godot 4.7.2 and press `F5`, or launch headless/desktop from the command line:

```bash
godot --path .
```

### Multiplayer & Account Server

```bash
cd server
docker compose up -d
```

Set `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` in `server/.env` before starting Docker Compose.

### Tests

```bash
# Godot simulation & map tests
godot --headless --path . res://tests/test_runner.tscn

# Go server tests
cd server && go test ./...

# Go launcher tests
cd launcher && go test ./...
```

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE). Third-party public domain and CC0 map/audio credits are documented in [ASSETS_LICENSES.md](ASSETS_LICENSES.md).
