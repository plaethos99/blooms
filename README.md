# Last Light

A 5-minute survival game made in Godot 4.7. Ten pilgrims wake on a floating garden
island as the sun sets. Your lantern is your health: gather glowing blooms, fend off
light-eating Hollows, and step through the Sun Gate with 80% light before the sun is gone.

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
| Sprint | Shift | RUN |
| Flare (push hollows back) | Space / Q | FLARE |
| Hit with a tool | Left-click | HIT |
| Brace (70%+ light) | Right-click | BRACE |
| Autopilot | P | WATCH AI on the title screen |

Start in **Gentle** mode for your first game.

## Development
- Open the project in Godot 4.7.2 and press F5.
- All tuning numbers are in `scripts/cfg.gd`; the design is in `DESIGN.md`.
- Balance check: `python tools/balance_sim.py 16 --jobs 8` (edit the Godot path inside first).
- Sounds are synthesized by `scripts/audio.gd`. Re-bake them with
  `godot --headless --path . -- --bake-audio`.
- `ci/android-debug.keystore` is a **debug** signing key (password `android`) so that
  CI builds install over each other. Use a separate, secret release key for the Play Store.
