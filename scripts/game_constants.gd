extends Node
## Global game constants and utility functions.
##
## This singleton is autoloaded as "GameConstants" and provides:
## - Grid and timing configuration values
## - Visual settings (colors, sizes)
## - Coordinate conversion utilities between grid and world space
##
## Gameplay-tunable values are vars so the settings screen can modify them at runtime.

# =============================================================================
# LOGGING
# =============================================================================

const DEBUG_LOGGING := true
enum LogLevel { DEBUG, INFO, WARNING, ERROR }
const LOG_LEVEL := LogLevel.DEBUG

# =============================================================================
# PERSISTENCE
# =============================================================================

const SETTINGS_PATH := "user://settings.cfg"
const LEVELS_DIR := "user://levels"

## All user-tunable settings with their default values.
const DEFAULTS := {
	"MOVEMENT_MODE": 0,
	"PLAYER_HITBOX_SIZE": 36.0,
	"BOMB_FUSE_TIME": 2.0,
	"BOMB_MOVE_DELAY": 0.15,
	"BOMB_FLY_DELAY": 0.12,
	"BOMB_THROW_DISTANCE": 4,
	"CONVEYOR_MOVE_INTERVAL": 0.3,
	"PLAYER_MOVE_COOLDOWN": 0.12,
	"CURSE_DURATION": 10.0,
	"SOFT_BLOCK_SPAWN_CHANCE": 0.7,
	"POWERUP_DROP_CHANCE": 0.3,
	"STARTING_MAX_BOMBS": 5,
	"STARTING_BOMB_RANGE": 1,
	"STARTING_HAS_KICK": true,
	"STARTING_HAS_THROW": true,
}

## Path to the custom level JSON to load (empty = use procedural generation).
## Persisted to settings so the selected level survives restarts.
var CUSTOM_LEVEL_PATH := ""

## Level path the editor should load on open. Cleared by the editor after reading.
## Set by the level browser when editing or copying an existing level.
var EDITOR_LOAD_PATH := ""

# =============================================================================
# MATCH STATE (runtime only — not persisted)
# =============================================================================

## Whether a multi-level match is currently in progress.
var MATCH_ACTIVE := false

## Ordered list of level paths ("" = procedural) to cycle through.
var MATCH_LEVELS: Array[String] = []

## Index into MATCH_LEVELS for the level currently being played.
var MATCH_CURRENT_INDEX := 0

## Per-player win counts. Key = int(PlayerNumber), value = int wins.
var MATCH_SCORES: Dictionary = {}

## How many round wins a player needs to win the whole match.
var MATCH_WINS_NEEDED := 5

## Whether to re-shuffle levels when they cycle around.
var MATCH_SHUFFLED := false


# =============================================================================
# GRID SETTINGS (structural - not tunable at runtime via settings screen)
# =============================================================================

const TILE_SIZE := 64
var GRID_WIDTH := 13
var GRID_HEIGHT := 11

# =============================================================================
# EDITOR TILE TYPES
# =============================================================================

## Tile types used by the level editor. Mapped to Arena.CellType when loading.
enum EditorTile {
	EMPTY = 0,
	HARD_BLOCK = 1,
	SOFT_BLOCK = 2,
	HOLE = 3,
	ICE = 4,
	CONVEYOR_UP = 5,
	CONVEYOR_DOWN = 6,
	CONVEYOR_LEFT = 7,
	CONVEYOR_RIGHT = 8,
	SPAWN_1 = 9,
	SPAWN_2 = 10,
	SPAWN_3 = 11,
	SPAWN_4 = 12,
}

# =============================================================================
# GAMEPLAY BALANCE
# =============================================================================

enum MovementMode { SNAP, SMOOTH, FREE }
var MOVEMENT_MODE := MovementMode.SNAP

## Side length of the square collision hitbox for each player, in pixels.
var PLAYER_HITBOX_SIZE := 36.0

## How far (as a fraction of TILE_SIZE) a player can be off-axis before
## corner correction stops helping them nudge past a wall edge.
const CORNER_CORRECTION_RATIO := 0.4

var SOFT_BLOCK_SPAWN_CHANCE := 0.7
var POWERUP_DROP_CHANCE := 0.3

var HOLE_SPAWN_CHANCE := 0.05
var ICE_SPAWN_CHANCE := 0.08
var CONVEYOR_SPAWN_CHANCE := 0.06

var CONVEYOR_MOVE_INTERVAL := 0.3

const POWERUP_EXTRA_BOMB_WEIGHT := 0.20
const POWERUP_FIRE_RANGE_WEIGHT := 0.20
const POWERUP_SPEED_WEIGHT := 0.15
const POWERUP_THROW_WEIGHT := 0.10
const POWERUP_KICK_WEIGHT := 0.10
const CURSE_SPEED_WEIGHT := 0.10
const CURSE_INVERT_WEIGHT := 0.08
const CURSE_BOMBS_WEIGHT := 0.07

var CURSE_DURATION := 10.0
const CURSE_SPEED_MULTIPLIER := 0.0625
const CURSE_BOMBS_INTERVAL := 0.05

# =============================================================================
# TIMING
# =============================================================================

var BOMB_FUSE_TIME := 2.0
var BOMB_MOVE_DELAY := 0.15
var BOMB_FLY_DELAY := 0.12
var BOMB_THROW_DISTANCE := 4
var EXPLOSION_DURATION := 0.5
const POWERUP_IMMUNITY_TIME := 0.6
var PLAYER_MOVE_COOLDOWN := 0.12

# =============================================================================
# PLAYER STARTING STATS
# =============================================================================

var STARTING_MAX_BOMBS := 5
var STARTING_BOMB_RANGE := 1
var STARTING_HAS_KICK := true
var STARTING_HAS_THROW := true

# =============================================================================
# VISUAL - PLAYER COLORS (structural - not tunable)
# =============================================================================

const PLAYER_COLORS := {
	1: Color(0.2, 0.7, 0.3, 1.0),
	2: Color(0.3, 0.5, 1.0, 1.0),
}

const PLAYER_COLOR_NAMES := {
	1: "Green",
	2: "Blue",
}

# =============================================================================
# VISUAL - POWERUP COLORS (structural - not tunable)
# =============================================================================

const POWERUP_EXTRA_BOMB_COLOR := Color(0.2, 0.5, 1.0, 1.0)
const POWERUP_KICK_COLOR := Color(1.0, 0.6, 0.1, 1.0)
const POWERUP_FIRE_RANGE_COLOR := Color(1.0, 0.3, 0.2, 1.0)
const POWERUP_SPEED_COLOR := Color(0.2, 0.9, 0.9, 1.0)
const POWERUP_THROW_COLOR := Color(0.9, 0.2, 0.9, 1.0)
const CURSE_SPEED_COLOR := Color(0.8, 0.0, 0.0, 1.0)
const CURSE_INVERT_COLOR := Color(0.5, 0.0, 0.5, 1.0)
const CURSE_BOMBS_COLOR := Color(0.4, 0.4, 0.4, 1.0)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

static func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE * 0.5,
		grid_pos.y * TILE_SIZE + TILE_SIZE * 0.5
	)


static func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x) / TILE_SIZE,
		int(world_pos.y) / TILE_SIZE
	)


static func grid_to_world_corner(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)


static func get_player_id(player_number: int) -> int:
	return player_number + 1


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LEVELS_DIR))
	load_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in DEFAULTS:
		cfg.set_value("settings", key, get(key))
	cfg.set_value("state", "CUSTOM_LEVEL_PATH", CUSTOM_LEVEL_PATH)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key: String in DEFAULTS:
		if cfg.has_section_key("settings", key):
			set(key, cfg.get_value("settings", key))
	if cfg.has_section_key("state", "CUSTOM_LEVEL_PATH"):
		CUSTOM_LEVEL_PATH = cfg.get_value("state", "CUSTOM_LEVEL_PATH", "")


func reset_to_defaults() -> void:
	for key: String in DEFAULTS:
		set(key, DEFAULTS[key])
	save_settings()


static func log_message(source: String, message: String, level: LogLevel = LogLevel.INFO) -> void:
	if not DEBUG_LOGGING:
		return
	if level < LOG_LEVEL:
		return

	var level_str := ""
	match level:
		LogLevel.DEBUG:
			level_str = "DEBUG"
		LogLevel.INFO:
			level_str = "INFO"
		LogLevel.WARNING:
			level_str = "WARN"
		LogLevel.ERROR:
			level_str = "ERROR"

	print("[%s] [%s] %s" % [level_str, source, message])
