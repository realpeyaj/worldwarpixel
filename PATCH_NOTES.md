# World War Pixel — Patch Notes

## v1.3.2 — MIRV Coverage, Fallout Balance, AI Army Cost & Coastal Ports
- **Full-Territory MIRV Targeting & Preview**: Replaced corner-biased farthest-point selection and the 12-circle northern-edge hover preview with a shared uniform 2D coverage lattice + structure/capital anchors (`compute_mirv_targets`, up to 72 warheads) so both the live targeting preview and launched MIRV strikes blanket the target nation's entire landmass.
- **Rebalanced Radioactive Fallout Cost**: Removed double-stacking of unclaimed explore and fallout multipliers (`1.85×` × `2.4×` = `4.44×`) on neutral nuclear waste so reclaiming irradiated land remains costly (`2.6×` base / ~`1.4×` explore cost) without wiping out entire armies.
- **AI Expansion Army Accounting & Pacing**: Fixed AI round-robin action starvation in large matches so bots spend troops smoothly on expansion alongside building, replaced the flat 3-troop / 10-floor naval beachhead calculation with true per-cell cost deduction, and updated on-map troop labels immediately when orders commit.
- **Strict Open-Sea Coastal Port Placement**: Ports now strictly require direct ocean coastline tiles (`coastal_grid == 1`) with open-sea navigable access, rejecting inland cells and inland lake shores.

## v1.3.1 — Freeze & Stutter Performance Fix
- **Hierarchical Ocean Pathfinding & Route Cache**: Replaced slow flat-grid pathfinding with native C++ `AStarGrid2D` coarse routing + local fine stitching and bidirectional route caching, eliminating multi-second mid-game freezes during Port trade spawning and sea invasions.
- **Precomputed Coastlines & Late-Game Border Caps**: Precomputed continent coastline lookup tables at startup and capped late-game border sampling so large 24-nation matches stay smooth without periodic lag spikes.
- **UI & Map Sync Throttling**: Coalesced rapid HUD/diplomacy updates, cached tinted structure icons, throttled map texture uploads to 30 Hz, and skipped redundant idle threat overlay redraws.

## v1.3.0 — Map-Only Home Hub, Dedicated Pages, 8-Tier Rankings, Allied Trade & Naval Raiding
- **Clean Map-Only Home Screen & Dedicated Pages**: Removed home boxes and in-game notes so the live Earth map shines directly behind the floating title and **Singleplayer / Multiplayer** hero buttons, with corner **Profile**, **Leaderboard**, **Settings**, and **Quit** controls plus full dedicated pages for Singleplayer (up to **23 AI opponents**), Multiplayer, Settings, Leaderboard, and Profile Management.
- **No Auto-Spread Spawn & Explore Rebalance**: Nations now spawn as a compact, clean circular territory and expand strictly on your manual commands (or AI decisions); neutral land exploration now consumes more troops (`1.85×`) for deeper strategic pacing.
- **Allied Trade Routes, Naval Raiding & FFA/Team Aid**: Allied Port trade routes now earn **+40% bonus Pesos** with highlighted sea lanes, Warships capture **65% trade value** on raids (`25%` instant loot + `40%` cargo), and players can send **Gold** (`50K / 100K / 250K`) and **Troop Aid** (`15% / 25% / 50%`) to both FFA pact allies and Team Mode teammates.
- **8-Tier Competitive Ranking System**: Upgraded ELO ladder (`Iron III → Bronze → Silver → Gold → Platinum → Diamond → Grandmaster → Sovereign`) with opponent-adjusted ratings, Win%, Peak Land, and sortable leaderboards (`Top ELO`, `Most Wins`, `Peak Land`).

## v1.2.0 — Placement Previews, Global Rankings, Modifiers, Replays & Combat Balance
- **Actual In-Game Missiles & Exact Blast Previews**: Rendered rotating SAM interceptors, tactical Atom missiles, heavy H-Bombs, MIRV carrier buses, and re-entry sub-warheads along ballistic arcs while previewing exact destroyed crater zones (and MIRV spreads) before launch.
- **Factory & Defense Placement Previews**: Hovering a Factory now previews dotted road connections (`+N links`), and hovering a Defense Post shows its exact fortification ring.
- **Global Leaderboard, Match History & Replays**: Added Top Commanders ELO rankings and personal Match History with deterministic Replay playback (`1× / 2× / 4×`) in-game and in the Launcher Hub.
- **Live Spectators, Lobby Modifiers & Team Chat**: Hosts can customize Game Speed (`1× / 1.5× / 2×`), Conventional Mode (`No Nukes`), AI Difficulty (`Normal / Hard / Brutal`), and Starting Economy; players can spectate live public matches and communicate via `[ALL]` / `[TEAM]` chat (`Enter` / `Tab`) and Quick Comms.
- **Warship Balance, Audio & Account Security**: Reduced Warship base speed by 45% (+5% per level-up), upgraded missile launch & anti-air SAM audio, and added **Change Password** across both the launcher and in-game menu.

## v1.1.0 — Quick Play, Team Mode, Tactical QoL & Account Security
- **Public Lobbies, Quick Play & Team Mode**: Browse open rooms, click **Quick Play** to auto-join or host an open match, toggle **Team Mode** for shared team alliances/victory, and join friends' rooms straight from the launcher Friends roster.
- **Tactical Map Pings & Threat Navigation**: Ping coordinates (`Alt + Click`) for teammates, jump straight to attack alerts via toast click or off-screen edge arrows, and see live Lv.1 + allied SAM interception domes before placing a SAM.
- **Camera, Build & Display QoL**: Added `Shift`-click multi-build, `Space`/`Home` capital snap, `Ctrl+1..4` / `Alt+1..4` camera bookmarks, persistent Display Mode & UI Scale (`Alt+Enter`), plus Post-Match Stats & Territory Timelapse charts.
- **Rank Badges, Repair & Account Security**: Persistent ELO/rank progression (`games_played`, `wins`, `elo`), launcher Settings **Verify & Repair**, launcher self-update support, plus **Confirm Password** and **Show/Hide Password** eye toggles across both the launcher and in-game sign-up flows.

## v1.0.0 — Launcher Hub, Accounts & Global Expansion
- **Launcher Hub & Fast Patching**: Added standalone Windows launcher (`WorldWarPixel.exe`) with built-in Sign In / Friends / Avatar sync, editorial Patch Notes, automatic update checks, and lightweight `.pck` patch updates so new patches don't require full binary rebuilds.
- **Account System & Friends**: Reserve a permanent unique username, verify and search commanders in the player database, receive friend request notifications, and view your Friends roster sorted from Online to longest Offline.
- **Custom Profile Pictures (Photo & GIF)**: Import `.png`, `.jpg`, `.webp`, or animated `.gif` avatars directly from the launcher or in-game menu, displayed in your profile, Friends list, Victory screen, and above your nation on the world map.
- **1:1 2048x1024 World Grid**: Doubled land-claim pixel fidelity with strict `2x2` ocean-only naval pathfinding across all global straits and seas.
- **Tactical Icons & Stereo Audio Mix**: Updated building and warhead icons across the HUD and map, paired with 44.1 kHz stereo SFX & theme music (including player-only territory capture pops, incoming friend request chimes, victory fanfare, and defeat drums).
