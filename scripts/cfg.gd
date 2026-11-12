extends RefCounted
## All tuning numbers for LAST LIGHT live here.

const MATCH_TIME := 300.0
const START_LIGHT := 50.0
const MAX_LIGHT := 100.0
const ESCAPE_LIGHT := 80.0
const BRACE_LIGHT := 70.0
const DIM_LIGHT := 20.0
const GATE_OPEN_AT := 60.0
const FINAL_PHASE_AT := 30.0
const SHRINE_SHRINK_SPAN := 150.0 # shrines start shrinking this many seconds before FINAL_PHASE_AT

const BLOOM_INTERVAL := Vector2(14.0, 18.0)
const BLOOM_HEAL := Vector2(8.0, 12.0)
const MAX_BLOOMS := 5
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

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.5
const DIM_SPEED := 3.6
const BRACE_SPEED_MULT := 0.35
const STAMINA_MAX := 3.0
const SWING_COOLDOWN := 0.55
const SWING_REACH := 2.4
const FLARE_COOLDOWN := 12.0
const FLARE_COST := 3.0
const FLARE_RADIUS := 6.0
const FLARE_PUSH := 7.0
const BRACE_RECOVER := 2.0

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
