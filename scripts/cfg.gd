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

# ---------------------------------------------------------------- Level 1: The Gauntlet
# A straight race in parallel lanes (3 now, 5 later for online play), four phases:
# fire blades -> moving steps -> monster arena -> rope chasm -> the Sun Gate.
const COURSE_TIME := 240.0 # 4 minutes
const LANES := 3
const LANE_W := 14.0 # metres between lane centres
const COURSE_START_LIGHT := 60.0
const LAMP_LIGHT := 100.0
const COURSE_BLADE_DAMAGE := 10.0 # fire blades burn more than plain steel
const RESPAWN_DELAY := 1.2 # seconds between falling and reappearing at the checkpoint
const RESPAWN_LIGHT := 45.0 # at least this much light after a respawn
const KILLS_NEEDED := 4 # monsters each pilgrim must bring down to leave the arena
const KILL_HEAL := 6.0
const MEDAL_GOLD := 130.0 # finish times (seconds from GO)
const MEDAL_SILVER := 175.0

# Moving steps.
const STEP_BOB := 0.9 # metres up and down
const STEP_SWAY := 1.3 # metres side to side
const STEP_PERIOD := Vector2(3.0, 3.8)
const FERRY_DWELL := 1.6 # seconds a lane-crossing step waits in each lane
const FERRY_MOVE := 1.8 # seconds it takes to slide to the next lane

# Weapons.
const AXE_REACH := 2.9
const AXE_DAMAGE := 3
const AXE_COOLDOWN := 0.5
const ARROW_SPEED := 42.0
const ARROW_DAMAGE := 1
const ARROW_COOLDOWN := 0.42
const SAW_SPEED := 22.0
const SAW_RANGE := 13.0
const SAW_DAMAGE := 2
const AIM_ASSIST := 0.16 # radians: arrows and saws bend towards a monster this close to the aim

# Flying monsters (Duskwings).
const FLYER_HP := 3
const FLYER_SPEED := 7.0
const FLYER_DIVE_SPEED := 15.0
const FLYER_AIM_TIME := 0.9 # the red glow before a dive
const FLYER_BITE := 12.0
const FLYER_KNOCK := 6.0
const FLYERS_MIN := 3
const FLYERS_MAX := 8

# Rope chasm.
const ROPE_RANGE := 15.0
const ROPE_SPEED := 17.0
const ROPE_HANG := 2.35 # feet hang this far below the ring
const RING_SWAY := 2.0
const GUST_EVERY := Vector2(5.0, 7.5)
const GUST_WARN := 0.9
const GUST_TIME := 1.4
const GUST_PUSH := 9.0
