<img src="assets/sprites/logo_world_war_pixel.png" alt="World War Pixel" width="280">

# World War Pixel

A real-time grand-strategy game played on a pixel-art world map. Built with Godot 4 and an authoritative Go multiplayer server.

## Overview

- Continuous real-time territory expansion, conquest, and naval invasions
- Economy and infrastructure: towns, factories, trade routes, ports, and bridges
- Strategic weapons and defense: missile silos, nuclear strikes, SAM interception, and warships
- Singleplayer against AI and online multiplayer with rooms, friends, invites, and spectator mode

## Requirements

- [Godot Engine 4.7](https://godotengine.org/) (client)
- [Go 1.24](https://go.dev/) or Docker Compose (optional, for self-hosting the multiplayer server)

## Running Locally

### Client

Open `project.godot` in Godot 4.7 and run the project (`F5`), or launch from the command line:

```bash
godot --path .
```

### Multiplayer Server

```bash
cd server
docker compose up -d
```

Set `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` in `server/.env` before starting Docker Compose.

### Tests

```bash
godot --headless --path . res://tests/test_runner.tscn
```

```bash
cd server && go test ./...
```

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE). Third-party public domain and CC0 map/audio credits are documented in [ASSETS_LICENSES.md](ASSETS_LICENSES.md).
