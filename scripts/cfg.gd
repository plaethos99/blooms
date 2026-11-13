extends RefCounted
## All tuning numbers for LAST LIGHT live here.

const MATCH_TIME := 180.0 # 3 minutes
const START_LIGHT := 50.0
const MAX_LIGHT := 100.0
const ESCAPE_LIGHT := 80.0
const BRACE_LIGHT := 70.0
const DIM_LIGHT := 20.0
const GATE_OPEN_AT := 30.0 # the gate opens for the last 30 seconds
const FINAL_PHASE_AT := 15.0
const SHRINE_SHRINK_SPAN := 120.0 # shrines start shrinking this many seconds before FINAL_PHASE_AT

const BLOOM_INTERVAL := Vector2(9.0, 12.0)
const BLOOM_HEAL := Vector2(8.0, 12.0)
const MAX_BLOOMS := 6
const SHARD_HEAL := 4.0
const TOOL_INTERVAL := Vector2(18.0, 24.0)
const MAX_TOOLS := 3
const TOOL_SWINGS := 4

const HOLLOW_INTERVAL_EARLY := Vector2(10.0, 13.0)
const HOLLOW_INTERVAL_LATE := Vector2(5.0, 7.0)
const MAX_HOLLOWS := 10
const HOLLOW_TELEGRAPH := 2.0
const HOLLOW_HUNT_TIME := 12.0
const HOLLOW_SPEED := 4.0
const HOLLOW_SPEED_NIGHT := 5.0
const HOLLOW_BITE_INTERVAL := 0.5
const HOLLOW_BITE := Vector2(4.0, 6.0)
const HOLLOW_REACH := 1.3
const HOLLOW_HITS := 2
const HOLLOW_SPAWN_MIN_DIST := 10.0
const STAGGER_TIME := 1.5
const LUNGE_RANGE := 4.5
const LUNGE_SPEED := 11.0
const LUNGE_WINDUP := 0.4
const LUNGE_TIME := 0.35
const LUNGE_COOLDOWN := 3.2
const BITE_KNOCK := 1.8
const LUNGE_KNOCK := 4.5

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.5
const DIM_SPEED := 3.6
const BRACE_SPEED_MULT := 0.35
const STAMINA_MAX := 3.0
const SWING_COOLDOWN := 0.55
const SWING_REACH := 2.4
const FLARE_COOLDOWN := 1.0 # between two flares
const FLARE_RADIUS := 6.0
const FLARE_PUSH := 7.0
const FLARE_SHOVE := 7.5 # flares also blast other pilgrims away
const FLARE_START := 1
const FLARE_MAX := 3
const FLARE_RECHARGE := 45.0 # an empty hand slowly regains one flare

# Movement between the islands.
const GRAVITY := 26.0
const JUMP_VEL := 10.0
const AIR_JUMPS := 1 # double jump: one extra jump in mid-air, to save yourself from a fall
const AIR_JUMP_VEL := 10.5
const AIR_CONTROL := 5.0
const SHOVE_RANGE := 2.1
const SHOVE_FORCE := 9.5
const SHOVE_LIFT := 3.5
const SHOVE_COOLDOWN := 3.0

# Sunflare drops: announced, then they crash down somewhere. First to grab it wins.
const DROP_WARN := 6.0
const DROP_FIRST := 3.0 # seconds after GO
const DROP_INTERVAL := Vector2(15.0, 20.0)
const DROP_INTERVAL_NIGHT := Vector2(10.0, 13.0)
const DROP_FLARES := 2
const DROP_HEAL := 12.0
const DROP_BLAST := 3.5

# The Devourer: rises from the Underglow and sweeps pilgrims off the stones.
const WYRM_FIRST := 20.0 # seconds into the match
const WYRM_INTERVAL := Vector2(14.0, 20.0)
const WYRM_INTERVAL_NIGHT := Vector2(9.0, 12.0)
const WYRM_WARN := 2.6
const BRACE_RECOVER := 2.0

# Knife pendulums: blades swinging across the gaps between stepping stones.
const BLADE_PERIOD := Vector2(2.4, 3.2) # seconds for one full back-and-forth
const BLADE_ARC := 58.0 # degrees either side of straight down
const BLADE_ARM := 4.2 # pivot to blade centre
const BLADE_SIZE := 1.3 # scale of the crescent blade
const BLADE_HEIGHT := 1.6 # blade passes this high above the higher stone (mid-jump body height)
const BLADE_GAP_EXTRA := 1.1 # gaps with a blade are this much wider than the others
const BLADE_HIT_RADIUS := 0.6 # flat distance from the blade to a pilgrim's centre that counts as a hit
const BLADE_KNOCK := 7.0
const BLADE_LIFT := 3.0
const BLADE_DAMAGE := 6.0
const BLADE_HIT_COOLDOWN := 1.0

const SHRINE_MAX_RADIUS := 6.0
const SURVIVOR_COUNT := 10

const NAMES := ["You", "Wren", "Ilya", "Sora", "Mako", "Juno", "Tamsin", "Odile", "Kai", "Pell"]
const COLORS := [
	Color(0.95, 0.78, 0.42), Color(0.42, 0.62, 0.95), Color(0.9, 0.45, 0.5),
	Color(0.5, 0.85, 0.7), Color(0.75, 0.55, 0.95), Color(0.95, 0.6, 0.35),
	Color(0.55, 0.75, 0.4), Color(0.85, 0.85, 0.92), Color(0.35, 0.8, 0.9),
	Color(0.9, 0.5, 0.8),
]
const TOOL_NAMES := ["Pilgrim's Staff", "Bell Hammer", "Lantern Pole", "Broken Oar"]
