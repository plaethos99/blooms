# Handoff: branch `devnov13-26` (13 Nov 2026)

Build tag: `dev1326`. The "Build game" workflow was run by hand on that tag; download
**LastLight-windows-portable** and **LastLight-android** from that run's Artifacts.

## What this branch adds
**Level 1: The Gauntlet**, a second game mode next to the original open-island game
("Classic", unchanged). On the Classic title screen press **L** (phone: LEVEL 1); on the
Level 1 title press **C** to go back.

A 4-minute race in 3 parallel lanes. Ten pilgrims (you plus 9 bots) split 4/3/3:

1. **Fire blades**: 10 stones, 5 burning pendulums. The pattern is the same in every
   lane, and the last two swing against each other. Ends at the **lamp**: light goes
   to 100% and checkpoints unlock.
2. **Moving steps**: 12 steps that bob, sway or zigzag. Two steps ferry you between
   lanes. You pick up a crossbow, an axe and a saw on the way (each pilgrim gets their own).
3. **Arena**: the lanes merge. Flying monsters (Duskwings) circle, glow red, then dive.
   **4 kills** open your lane's gateway and hand you the rope launcher.
4. **Rope chasm**: 8 sliding rings per lane, plus 3 rings that drift between lanes.
   Right-click zips you to the ring in the gold circle and Space lets go. Fire blades
   and wind gusts get in the way.
5. Walk into the **Sun Gate**. Finish times earn medals: gold up to 2:10, silver up to
   2:55, bronze after that.

**Falling:** before the lamp, the run ends. After the lamp, you come back at the start
of your current phase after 1.2 s; the same happens if your lantern burns out.

**Screen:** almost no text. It shows the clock, 4 phase icons (your kill count sits
under the arena icon), your race place, the lantern bar and weapon slots. A crosshair
appears only while aiming. A guide wisp floats to your next step, and a control icon
shows once the first time each control is needed.

**Camera:** follows behind you and swings back down the course when you leave the
mouse alone (except in the arena). It is framed differently for each phase.

## Files
| File | What |
|---|---|
| `scenes/course.tscn` | Level 1 scene (root script `course_main.gd`) |
| `scripts/course.gd` | Course layout: extends `world.gd`; lanes, steps, rings, lamps, gateways, gusts, routes, guide wisp |
| `scripts/course_main.gd` | Rules: extends `main.gd`; phases, checkpoints, weapons, monsters, rope, ranking |
| `scripts/course_ai.gd` | Bot (and autopilot) logic for Level 1 |
| `scripts/course_hud.gd` | Level 1 HUD: extends `hud.gd` |
| `scripts/flyer.gd` | Duskwing monsters |
| `scripts/arms.gd` | Weapon models (axe, saw, crossbow, rope launcher) |
| `scripts/cfg.gd` | New Level 1 section at the bottom (all tuning numbers) |

Shared files changed:
- `world.gd`: the island table and centre can now be overridden.
- `blades.gd`: fire blades, fixed swing timing per gap, free-hanging blades.
- `survivor.gd`: Level 1 state, rope, weapons, respawn.
- `bot.gd`, `player.gd`, `touch.gd`, `hud.gd`, `main.gd`: hooks.
- `light_meter.gd`: the threshold marks are now optional.
- `project.godot`: phones use the OpenGL **Compatibility** renderer
  (`renderer/rendering_method.mobile="gl_compatibility"`); Windows keeps Forward+.

To rebuild, run "Build game" by hand on the branch or a tag:
`gh workflow run build.yml --ref devnov13-26`. Pushing this branch or a `dev*` tag
alone does not start a build, because the workflow only triggers on `main` and `v*` tags.

## Android startup failure (dev1326)
The `dev1326` APK failed at startup on the tester's phone. Nobody could read the phone's
crash log (no phone connected over USB). What was checked:
- The APK's own game files, run on desktop with the mobile renderer and the touch
  layer: they start fine with no script errors.
- The new APK matches the last `main` APK (same SDK levels, signing and arm64 library)
  apart from the new Level 1 files.

So the likely cause is the phone's Vulkan graphics driver. The fix switches phones to
the Compatibility renderer, which runs on almost every Android GPU; both modes were
checked with it on desktop. If it still fails, connect the phone with USB debugging
and run `adb logcat -s godot` while starting the app.

## Status
- **Verified (AI, headless):** 5 full races with all 10 pilgrims finishing (bots
  1:24–3:51) and no script errors. Screenshots checked for every phase and both title
  screens. Classic mode still runs.
- **Played by a person:** 2 sessions (3 runs), no errors. Findings:
  - Phase 1 (blades): 2–4 falls per session before reaching the lamp.
  - **Phase 2 (moving steps) is too hard for a person: 9 respawns in one run, and the
    player never finished.** This is the top thing to tune.
- **Not tested:** rope aiming and axe timing with a real mouse; the rebuilt APK
  (Compatibility renderer) on a real phone.

## Suggested next steps
1. Make the moving steps easier to read and land:
   - smaller movement in `cfg.gd` (`STEP_BOB`, `STEP_SWAY`) and slower cycles (`STEP_PERIOD`);
   - bigger steps (`STEP_R` in `course.gd`);
   - a short "landing assist" while touching a step.
2. Phase 1: slightly slower blades (`BLADE_PERIOD`) or wider safe gaps until the lamp.
3. After the first human runs, retune medal times (`MEDAL_GOLD`, `MEDAL_SILVER`) and
   bot hesitation (`course_ai.gd`: `hes_t`, `hang_t`).
4. Not built yet: crows in the rope chasm (only blades and gusts disturb you there).
5. Online play: lanes are deterministic from the match clock (`course.sim_t`), so
   clients only need a shared seed and start time. `Cfg.LANES = 5` gives 5 lanes.

## How to run
- Play: open the project in Godot 4.7.2, press F5, then press **L**. Or run the scene
  `res://scenes/course.tscn`.
- Headless AI race:
  `godot --headless --path . res://scenes/course.tscn --fixed-fps 60 --quit-after 15000 -- --autostart --autopilot --log`
- `--phase=N` starts everyone at phase N, and `--trace` (with `--who=Name`) prints positions.
