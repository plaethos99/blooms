extends RefCounted
## All tuning numbers for LAST LIGHT live here.

const MATCH_TIME := 210.0 # 3:30: three trials, then the gauntlet
const START_LIGHT := 50.0
const MAX_LIGHT := 100.0
const ESCAPE_LIGHT := 80.0
const BRACE_LIGHT := 70.0
const DIM_LIGHT := 20.0
const FINAL_PHASE_AT := 30.0 # night: the hollows gather at the portal
const SHRINE_SHRINK_SPAN := 130.0 # shrines start shrinking this many seconds before FINAL_PHASE_AT

const BLOOM_INTERVAL := Vector2(9.0, 12.0)
const BLOOM_HEAL := Vector2(8.0, 12.0)
const MAX_BLOOMS := 6
const SHARD_HEAL := 4.0
const TOOL_INTERVAL := Vector2(18.0, 24.0)
const MAX_TOOLS := 3
const TOOL_SWINGS := 5

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
const TOOL_NAMES := ["Thorn Spear", "Sky Blade", "Bell Hammer", "Pilgrim's Staff"]

# ---------------------------------------------------------------- the three trials (v0.9)
# To pass the portal you need the SUNFLARE (grab a drop), the SKY FRUIT (Hidden Garden,
# guarded by the Thornback) and the MOON POTION (Crystal Cave, guarded by the Shardback),
# plus 80% light. Each relic also brightens your lantern.
const FRUIT_HEAL := 8.0
const POTION_HEAL := 8.0
const BEAST_HP := 10 # weapon hit = 1, flare = 2
const BEAST_FRUITS := 2 # the tree drops this many when the Thornback falls
const BEAST_REFORM := 30.0
const BEAST_SPEED := 4.4
const BEAST_CHARGE_SPEED := 12.0
const BEAST_DAMAGE := 11.0
const BEAST_KNOCK := 10.0
const CRAWLER_HP := 6
const CRAWLER_REFORM := 16.0
const CRAWLER_SPEED := 4.8
const CRAWLER_DAMAGE := 9.0
const CRAWLER_KNOCK := 8.0
const GUARD_WINDUP := 0.65 # the tell before every attack
const GUARD_REACH := 2.7
const GUARD_COOLDOWN := 1.5
const GUARD_FLARE_DAMAGE := 2
const POTION_BREW := 24.0 # a new potion appears on the altar this long after one is taken
const FRUIT_RIPEN := 2.0 # fruit falls this long after the Thornback goes down

# The gauntlet: the causeway from Heart Rock to the portal.
const JET_CYCLE := Vector2(4.6, 5.6) # seconds between bursts of a fire vent
const JET_WARN := 0.8
const JET_BURN := 1.2
const FIRE_DAMAGE := 7.0
const FIRE_KNOCK := 4.0
const KNIFE_INTERVAL := Vector2(2.8, 3.8)
const KNIFE_WARN := 0.8
const KNIFE_SPEED := 15.0
const KNIFE_DAMAGE := 7.0
const KNIFE_KNOCK := 5.0
const KNIFE_HIT_RADIUS := 0.65
# The fire seal round the portal: put a section out with an extinguisher to get through.
const SEAL_SEGMENTS := 4
const SEAL_RADIUS := 5.0
const SEAL_OUT_TIME := 6.0
const SEAL_DAMAGE := 9.0
const EXT_INTERVAL := Vector2(15.0, 19.0)
const MAX_EXTINGUISHERS := 2
const EXT_MAX_HELD := 2
const WARD_INTERVAL := Vector2(16.0, 22.0) # Sun Ward artifact: absorbs one hit
const MAX_WARDS := 2
const WARD_MAX_HELD := 1
