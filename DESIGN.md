# LAST LIGHT — revised design (v0.2)

## The place: the Lumen Terraces
A floating island of terraced gardens high above a sea of clouds. Marble ruins,
blossom trees, a koi pond, stone lantern-shrines, and on the summit the
**Sun Gate**, a marble arch with a ring of gold.

It is beautiful at the start: a golden sunset, pink blossoms, fireflies. **The
clock is the sun.** Over three minutes the sun sinks, the sky goes from gold to
violet to black, and stars and an aurora come out. The flowers and grass start
to glow as it gets darker. It gets more beautiful and more dangerous at the same time.

## The core idea: your health is your light
Every pilgrim carries a lantern. **Lantern brightness = health** (it starts at 50%).
Everyone can see how strong everyone else is just by how brightly they glow. The
gate only lets in lanterns at **80% or brighter**.

| Original (mall) | Now |
|---|---|
| Wall clock 03:00 | The sunset itself (plus the HUD clock) |
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
| 03:00–02:15 | Golden hour. Shrines at full size. Hollows every 10–13 s. |
| 02:15–00:30 | Sunset. Shrines shrink, hollows spawn faster and move faster. |
| **00:30** | **The Sun Gate opens** for the last 30 seconds. Walk into it at 80%+ to escape right away. Below 80% it throws you back. |
| **00:15** | **Night.** Shrines go out, hollows stop fading away, and they spawn around the summit stairs. |
| 00:00 | The light is gone. Anyone still on the island is lost. |

## Knife pendulums
Each bridge picks a few random gaps between two stones (never two in a row) and
makes them 1.1 m wider. A crescent blade hangs exactly over the middle of each,
from a small floating rock, swinging across the path (2.4–3.2 s per swing,
desynced) at mid-jump body height. Jump while the blade is out to one side.
A hit costs 6% light and throws you sideways. Bracing cuts the throw to 40%.
Bots wait at the edge for a gap, but careless ones misjudge it. Tuning:
`BLADE_*` in `cfg.gd`.

## Double jump
One extra jump in mid-air (`AIR_JUMPS`). It cancels knockback and lets you
steer, so a missed leap, a shove or a blade hit can be saved by jumping again
before you drop too far. Bots use it too when they fall past a stone.

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

## The Sky Gardens (v0.6)
The single island became an **archipelago of seven floating islands** over the
**Underglow**, a glowing abyss of mist with luminous rivers, crystal spires, drifting
light-jellies and rising spores. Fall in and you are gone.

| Island | Height | What's there |
|---|---|---|
| Dawn Meadow (start) | 0 | Everyone spawns in a ring. The first Sunflare lands in the middle at 00:03 |
| Lantern Grove | 2.5 | Blossom trees, a shrine |
| Ember Rocks | 0 | Glowing amber crystals, a shrine |
| Mirror Pond | 7 | The pond spills over the edge as a waterfall, a shrine |
| Bell Ruins | 5.5 | Columns, a shrine |
| Heart Rock | 4 | Small island in the middle; the fastest route to the gate |
| Sun Gate Isle | 10 | The gate, a colonnade, two waterfalls, a pillar of light visible from everywhere |

- **Stepping stones**: 8 bridges of 3–7 floating stones. Each hop goes up or down by up
  to 1.2 m and the gaps are 1.2–1.8 m, so you must jump (Space, jump apex ~1.9 m).
- **Beauty**: hanging gardens (glowing vine curtains on every rim and under most stones),
  garden ledges on the cliffs, 8 waterfalls pouring into the abyss (with sound),
  blossom petals on the wind, crystals under each island, the Underglow lighting the
  islands from below.
- **Push (E)**: shove anyone within 2 m. Near an edge it sends them into the abyss.
  Bracing cuts a shove to 30%. 3 s cooldown. Bots shove too (more when a prize is close).
- **Sunflare drops**: announced 6 s ahead (beam, countdown ring, map marker, siren).
  A burning star crashes down, blasts anyone inside the ring, and leaves a Sunflare:
  **+2 flares and +12% light** for whoever grabs it first. Every 20–28 s (14–18 s at night).
- **Flares are now ammo** (start with 1, hold up to 3, an empty hand rekindles one in
  45 s). A flare blasts hollows back **and throws nearby pilgrims**.
- **Hollows** are bat-winged shadow wraiths: crown of horns, six burning eyes, a jaw
  that opens, tendrils. They screech when they pick you, rear back with blazing eyes,
  then **lunge**. Bites knock you back, and on a stone that can mean a fall.
- **The Devourer**: a vast serpent swimming in the Underglow. From 00:45 in, every
  26–36 s (15–20 s at night) it picks a bridge with pilgrims on it. The stones glow red
  and the abyss roars for 2.6 s, then it bursts up through the bridge and sweeps
  everyone it touches into the abyss.
- **Rush**: title camera circles the Sun Gate; on start the camera holds on the gate
  ("your only way out"), flies back over the islands to you, then 3-2-1-RUN!. A driving
  drum loop runs under the match and swells for drops, hollows and the Devourer.
- **Map** (top right, heading-up): islands, stones, gate, incoming Sunflares with
  countdown, blooms, tools, pilgrims, hollows nearby, and the bridge about to be struck.

Balance (all AI, player on autopilot): **Normal 2.9 escapes per round** (12 rounds,
stdev 1.4), **Gentle 2.2** with the player escaping 5/8. About 6 of 10 pilgrims fall
into the Underglow each round, 3 of them pushed.

## Realistic world (v0.7)
The world now uses photo textures and models made in Blender, matched to six
reference images. Characters, creatures and gameplay are unchanged.

- **References and textures** were generated in Grok Imagine. Google Flow blocked
  the requests with "unusual activity". The job files are in `3d/tests/lastlight_world`.
- **Textures** (`textures/`): cliff, dark rock, meadow grass, mossy stone, marble and
  bark, each tileable at 1024 px with a normal map. Plus cut-outs for ivy, blossoms,
  leaves, grass clumps and wildflowers.
- **Models** (`models/`), built by `build_world.py` in Blender:
  - seven islands with stratified cliffs and eroded undersides
  - rock-chunk stepping stones
  - blossom and leaf trees with photo foliage
  - a marble arch gate, fluted columns and boulders
- **Rendering**: rock is textured from three sides, with moss from the models'
  vertex colours and meadow patches from noise. Grass, flowers and ivy are photo
  cards that sway in the wind. The look uses AgX tone mapping, height fog that pools
  in the abyss, and cloud wisps drifting below the islands.
- **Speed**: 57-60 fps at 1600x900 on a GTX 1050 Ti. Balance is unchanged (2.4
  escapes per round over 8 simulated rounds).

## Pilgrims (v0.8)
Every pilgrim is now a different person, designed from Grok concept art
(`3d/tests/lastlight_world/chars/`) and built in Blender by `build_characters.py`
from the Human Base Meshes bundle:

| Name | Who | Look |
|---|---|---|
| You | Wayfarer | Tousled brown hair, amber travelling cloak, linen tunic, satchel |
| Wren | Scout | Black pixie cut, sky-blue tunic, grey scarf, bracers |
| Ilya | Monk | Shaved head, crimson robes, sash, prayer beads |
| Sora | Sky-dancer | Long white ponytail, mint gown with ribbons, gold circlet |
| Mako | Smith | Big beard, lavender shirt, leather apron, broad build |
| Juno | Archer | Copper braid, orange jerkin and capelet, quiver |
| Tamsin | Herbalist | Straw hat, green dress, cream apron |
| Odile | Noble | Dark bun, silver circlet, long white high-collared coat |
| Kai | Runner | Spiky hair, cyan headband, sleeveless top, shorts (shortest) |
| Pell | Storyteller | Long white beard, floppy hat, magenta robe, staff |

- Each pilgrim is one skinned mesh with one material (colours baked into the mesh),
  7,000–9,000 vertices, with a 19-bone skeleton.
- Eight animations: idle, walk, run (speed-matched), jump, fall, push, swing, brace.
- The lantern hangs from the left hand and tools sit in the right. Being hurt
  flashes the whole figure red.
- Gameplay is unchanged (same collision capsule). Balance: 2.5 escapes per round
  over 8 simulated rounds. The characters cost about 2–4 fps.

## Next steps
1. Playtest jumping and pushing with real people; tune `scripts/cfg.gd`.
2. Online multiplayer (Godot high-level multiplayer, server-authoritative).
3. Real art pass: CC0 packs (Quaternius / Kenney), character models, audio
   (wind, chimes, hollow whispers, a gate choir).
