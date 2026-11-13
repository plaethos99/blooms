# Last Light

A 3-minute survival game made in Godot 4.7. Ten pilgrims race across floating garden
islands as the sun sets, leaping between stepping stones over the Underglow, a glowing
abyss. Your lantern is your health: grab glowing blooms, race rivals to falling
Sunflares, shove them off the stones, time your jumps past swinging knife pendulums, survive the
Hollows and the Devourer, and step
through the Sun Gate with 80% light before the sun is gone.

## Two ways to play
- **Level 1: The Gauntlet** (press **L** on the title screen). A 4-minute race in three
  parallel lanes. Pass the **fire blades**, grab your **lamp**, cross the **moving steps**
  (pick up a crossbow, an axe and a saw on the way), bring down **4 flying monsters** in
  the shared arena, take the **rope launcher** and swing ring to ring across the chasm,
  then walk into the **Sun Gate**. Fall after you have the lamp and you restart that
  phase; fall before it and your run is over. Finish times earn gold, silver or bronze.
- **Classic islands** (the original open game; press **C** on the Level 1 title to go back).

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
| Hit with a tool | Left-click | HIT |
| Brace (70%+ light) | Right-click | BRACE |
| Skip the gate flyover | Any key | Tap |
| Autopilot | P | WATCH AI on the title screen |

Level 1 adds: **left-click** attack with your weapon, **right-click** fire the rope at
the ring in the gold circle, **Space** let go of the rope, **1 / 2 / 3**, **X** or the
mouse wheel to switch weapons (phone: HIT, ROPE, SWAP).

Start in **Gentle** mode for your first game.

## Development
- Open the project in Godot 4.7.2 and press F5.
- All tuning numbers are in `scripts/cfg.gd`; the design is in `DESIGN.md`.
- Balance check: `python tools/balance_sim.py 16 --jobs 8` (edit the Godot path inside first).
- Level 1 debug: `res://scenes/course.tscn -- --autostart --autopilot --log` races the AI
  headless; `--phase=N` starts everyone at phase N, `--trace` prints positions.
- Debug views: `-- --overview`, `-- --bridgeview=6`, `-- --wyrmtest`, `-- --demohollow`,
  `-- --navtest` (prints every bridge's stone heights and checks paths to the gate).
- Sounds are synthesized by `scripts/audio.gd`. Re-bake them with
  `godot --headless --path . -- --bake-audio`.
- `ci/android-debug.keystore` is a **debug** signing key (password `android`) so that
  CI builds install over each other. Use a separate, secret release key for the Play Store.
