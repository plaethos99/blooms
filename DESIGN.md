# LAST LIGHT — revised design (v0.2)

## The place: the Lumen Terraces
A floating island of terraced gardens high above a sea of clouds. Marble ruins,
blossom trees, a koi pond, stone lantern-shrines, and on the summit the
**Sun Gate**, a marble arch with a ring of gold.

It is beautiful at the start: a golden sunset, pink blossoms, fireflies. **The
clock is the sun.** Over five minutes the sun sinks, the sky goes from gold to
violet to black, and stars and an aurora come out. The flowers and grass start
to glow as it gets darker. It gets more beautiful and more dangerous at the same time.

## The core idea: your health is your light
Every pilgrim carries a lantern. **Lantern brightness = health** (it starts at 50%).
Everyone can see how strong everyone else is just by how brightly they glow. The
gate only lets in lanterns at **80% or brighter**.

| Original (mall) | Now |
|---|---|
| Wall clock 05:00 | The sunset itself (plus the HUD clock) |
| First-aid kit | **Ember Bloom**: glowing flower, +10–15% (pink light beam) |
| Improvised tool | **Pilgrim's Staff / Bell Hammer / Lantern Pole / Broken Oar** (gold beam), 4 swings |
| Ghost | **Hollow**: moth-like shadow with a light-*eating* aura |
| Counter / pillar cover | **Lantern shrines**: hollows cannot enter the shrine's ring of light |
| Roof door | **Sun Gate** on the summit, reached by two narrow stairs (the choke point) |

## "How do players survive the creatures?" — six layers of defence
The original problem: a ghost drains 8–12%/s, you start at 50%, and without a tool
you have only a shove. One mistake kills you and there is nothing to learn. The fix
is to give **everyone** answers, each with a cost:

1. **Warning.** A hollow takes 2 seconds to form: a dark swirl on the ground, the
   light around it dims, and the HUD says *"A hollow is forming nearby…"*. It never
   forms closer than 12 m to a player.
2. **Outrun it.** Hollows move at 3.4 m/s, rising to 4.2 at night. You walk at
   5 m/s and sprint at 7.5 (3 s of stamina). A healthy player can always run away.
   **Below 20% light you are slowed to 3.6**, so dimming makes you catchable.
   That is the death spiral.
3. **Lantern Flare (everyone, Space/Q).** A burst that knocks back and stuns every
   hollow within 6 m for 1.5 s. Costs **3% light** and has a 12 s cooldown.
   This replaces the shove and is the universal panic button. Because it costs
   light, using it too often drains you.
4. **Shrines.** Four stone lanterns, each with a 6 m ring of light that hollows
   cannot enter. They are a safe place to catch your breath, but no blooms spawn
   inside them, and the rings **shrink from 03:00 and go out at 00:30**.
5. **Tools.** A hit stuns for 1.5 s, 2 hits destroy a hollow, and a tool breaks
   after 4 swings. A destroyed hollow drops a **Light Shard (+6%)**, so fighting
   turns a threat into income.
6. **Brace (70%+ light, hold RMB).** Plant your feet: the next bite does no damage,
   and with a tool you counter-swing automatically. Healthy players can stand and fight.

Hollows bite in pulses (4–6% every 0.5 s, the original 8–12%/s) after a 0.3 s
wind-up, so a quick flare or swing really does save you.

## Economy (why 2–4 people usually escape)
* 10 players need +30% each to reach 80%, so **300% total is needed**.
* Blooms spawn every 9–13 s (at most 6 on the map at once), about 25 per match,
  for **about 310% total**, plus shards from kills. That is just enough for everyone
  if no one ever took damage. With hollows, competition and flare costs, only a few make it.

## Phases
| Clock | What happens |
|---|---|
| 05:00–03:00 | Golden hour. Shrines at full size. Hollows every 12–16 s. |
| 03:00–01:00 | Sunset. Shrines shrink, hollows spawn faster and move faster. |
| **01:00** | **The Sun Gate opens.** Walk into it at 80%+ to escape right away. Below 80% it throws you back. |
| **00:30** | **Night.** Shrines go out, hollows stop fading away, and they spawn around the summit stairs. |
| 00:00 | The light is gone. Anyone still on the island is lost. |

## Controls (prototype)
WASD move · Shift sprint · Mouse look · LMB swing · RMB brace · Space/Q flare ·
Tab switch spectator target · Esc free the mouse · R restart

## Prototype scope
* Single player against 9 AI pilgrims, which use the same rules and pathfinding.
* All visuals are procedural (no downloaded assets): sky shader, wind-blown grass,
  glowing flowers, fireflies, volumetric fog, a cloud sea, distant floating islands.
* Debug flags (after `--`): `--autostart`, `--skip=200` (jump ahead in the match),
  `--overview` (high camera), `--shot=path.png --delay=6` (save a screenshot and quit).

## Sound & polish (v0.3)
All audio is **synthesized in code** (`scripts/audio.gd`, no downloaded files), then
saved once to `res://audio/*.res` so the game loads it instantly.

| Layer | What you hear |
|---|---|
| Ambience | Wind always. A warm major-chord pad by day that crossfades to a darker minor drone at night. Wind chimes drift across the island by day (positional). In the last 30 s, a low heartbeat-pulse. |
| Hollows | A swelling hiss while one forms (your first warning, and it's directional), then a whisper and growl loop that follows it. Bites, stagger hits, and a glassy shatter when one dies. |
| Pilgrims | Footsteps, tool swings, a bell-chord flare, a metallic clang on brace, a three-note chime for blooms, a high chime for shards, a muffled thump when you're hurt, a heartbeat below 20%. |
| Moments | A bell toll at the start, a choir when the gate opens, a low toll at nightfall, ticks for the last 10 seconds, a rising shimmer on escape, a descending tone when a lantern goes out. |

Polish: the title screen orbits the island, the HUD fades in at the start, the camera
shakes when you're bitten, the view widens when you sprint and narrows when you brace.
A gate marker with distance appears once the gate opens. **Violet arrows at the screen
edge point to hollows within 14 m that you can't see.** A pillar of light rises when
anyone escapes. There are sparkle bursts on pickups, flares and kills, and a smoke puff
when a lantern goes out. The clock pulses during the last 10 seconds. **M** toggles music.

To regenerate the sounds after changing a recipe in `audio.gd`:
`Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --bake-audio`.
To use a real recording, replace the matching `audio/<name>.res`, or load your file into
`bank["<name>"]`.

## Balance (v0.5, measured)
Tuned with `python tools/balance_sim.py 16 [--gentle] --jobs 8`, which plays 16 headless
rounds in parallel with every pilgrim on AI and prints escapes per round plus the light
economy.

| Setting | Before | Now |
|---|---|---|
| Bloom heal | 10–15% | **8–12%** |
| Bloom spawn | every 9–16 s | **every 14–18 s** (max 5 on the map) |
| Starting blooms | 3 + starter | **2 + starter** |
| Shard (hollow kill) | 6% | **4%** |
| Tools | every 12–16 s, max 4 | **every 18–24 s, max 3** |

| Result (16 rounds each) | Escapes per round | Your autopilot escaped |
|---|---|---|
| Before tuning | 5.1 avg (4–7) | 4/8 |
| **Normal** | **2.6 avg** (mostly 2–4, rarely 0–1) | 7/16 |
| **Gentle** | 3.4 avg | **15/16** |

**Gentle mode only helps you**: bites on you do 50%, blooms give you 1.4×, your flare
recharges 40% faster, and hollows treat you as 6 m farther away than you are. The other
pilgrims play by Normal rules.

## Onboarding (v0.4)
- **Objective box** under the clock always shows the single next step (bloom, tool,
  hollow response, safe ring, wait at the gate, GO). A **marker with distance** points at
  the target.
- **One-time tips** appear the first time something happens: a hollow appears, you pick
  up a tool, you reach 70%, you drop below 20%, you enter a shrine ring, or someone takes a bloom.
- **Starter bloom** 7 m in front of you, reserved for you for 15 s.
- 3-step title card. **1 = Gentle** (hollows 20% slower, bites 40% weaker, more blooms),
  **2 / click = Normal**, **P = autopilot** (the AI plays as you; press P to take over).
- Compact HUD: lantern meter, one status line, and one row showing which abilities are ready.
- Recording flags: `--autopilot --timescale=2.5 --introsecs=6 --quitend`, plus Godot's
  `--write-movie file.avi --fixed-fps 15` (or `.ogv` for a 3× smaller file).

## Next steps
1. Playtest and tune `scripts/cfg.gd` (every number lives there).
2. Online multiplayer (Godot high-level multiplayer, server-authoritative).
3. Real art pass: CC0 packs (Quaternius / Kenney), character models, audio
   (wind, chimes, hollow whispers, a gate choir).
