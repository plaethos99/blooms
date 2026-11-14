# Last Light

A 3½-minute survival game made in Godot 4.7. Ten pilgrims race across floating garden
islands as the sun sets, leaping between stepping stones over the Underglow, a glowing
abyss. Your lantern is your health. Win three relics: a **Sunflare** that falls from
the sky, the **Sky Fruit** from the walled Hidden Garden (kill the Thornback that
guards it), and the **Moon Potion** from the Crystal Cave (past the Shardback). Then
cross the gauntlet of fire vents and flying knives, douse the ring of fire with an
extinguisher, and step through the portal with 80% light before the sun is gone.

## Download
- **Latest builds:** open the [Actions](../../actions) tab, pick the newest
  successful "Build game" run, and download **LastLight-windows-portable** or
  **LastLight-android** under *Artifacts*.
- **Releases:** tagged versions (e.g. `v0.5`) are attached to [Releases](../../releases).

Windows: unzip and run `LastLight.exe`. Nothing needs installing.
Android: install `LastLight-android.apk` (allow installs from unknown sources).

## Controls
| | Desktop | Phone |
|---|---|---|
| Move | WASD | Drag on the left side |
| Look | Mouse | Drag on the right side |
| Jump | Space | JUMP |
| Sprint | Shift | Push the stick all the way |
| Push a rival | E | PUSH |
| Flare (blast hollows and rivals back) | Q / middle-click | FLARE |
| Hit with a weapon | Left-click | HIT |
| Brace (70%+ light) | Right-click | BRACE |
| Skip the flyover | Any key | Tap |
| Autopilot | P | WATCH AI on the title screen |

Start in **Gentle** mode for your first game.

## Development
- Open the project in Godot 4.7.2 and press F5.
- All tuning numbers are in `scripts/cfg.gd`; the design is in `DESIGN.md`.
- Balance check: `python tools/balance_sim.py 16 --jobs 8` (edit the Godot path inside first).
- Debug views: `-- --overview`, `-- --bridgeview=6`, `-- --wyrmtest`, `-- --demohollow`,
  `-- --navtest` (prints every bridge's stone heights and checks paths to the gate).
- Sounds are synthesized by `scripts/audio.gd`. Re-bake them with
  `godot --headless --path . -- --bake-audio`.
- `ci/android-debug.keystore` is a **debug** signing key (password `android`) so that
  CI builds install over each other. Use a separate, secret release key for the Play Store.
