extends Node
## Global game constants and utility functions.
##
## This singleton is autoloaded as "GameConstants" and provides:
## - Grid and timing configuration values
## - Visual settings (colors, sizes)
## - Coordinate conversion utilities between grid and world space
##
## All game systems reference these constants to ensure consistent behavior.

# =============================================================================
# LOGGING
# =============================================================================

## Enable/disable debug logging globally
const DEBUG_LOGGING := true

## Log levels for filtering output
enum LogLevel { DEBUG, INFO, WARNING, ERROR }
const LOG_LEVEL := LogLevel.DEBUG

# =============================================================================
# GRID SETTINGS
# =============================================================================

## Size of each tile in pixels (width and height)
const TILE_SIZE := 64

## Number of tiles horizontally in the arena
const GRID_WIDTH := 13

## Number of tiles vertically in the arena
const GRID_HEIGHT := 11

# =============================================================================
# GAMEPLAY BALANCE
# =============================================================================

## Probability (0.0-1.0) that an empty cell will contain a soft block
const SOFT_BLOCK_SPAWN_CHANCE := 0.7

## Probability (0.0-1.0) that a destroyed soft block drops a power-up
const POWERUP_DROP_CHANCE := 0.3

## Power-up spawn weights (cumulative probability)
const POWERUP_EXTRA_BOMB_WEIGHT := 0.20
const POWERUP_FIRE_RANGE_WEIGHT := 0.20
const POWERUP_SPEED_WEIGHT := 0.15
const POWERUP_THROW_WEIGHT := 0.10
const POWERUP_KICK_WEIGHT := 0.10
## Curses (negative powerups)
const CURSE_SPEED_WEIGHT := 0.10
const CURSE_INVERT_WEIGHT := 0.08
const CURSE_BOMBS_WEIGHT := 0.07

## Duration of curse effects in seconds
const CURSE_DURATION := 10.0

## Speed multiplier for curse speed (lower = faster, this makes it extremely fast)
const CURSE_SPEED_MULTIPLIER := 0.0625

## Interval between auto-bomb placements during bomb curse
const CURSE_BOMBS_INTERVAL := 0.05

# =============================================================================
# TIMING (in seconds)
# =============================================================================

## Time from bomb placement until explosion
const BOMB_FUSE_TIME := 2.0

## Delay between each tile when a bomb is kicked (controls kick speed)
const BOMB_MOVE_DELAY := 0.15

## How long explosion visuals remain on screen
const EXPLOSION_DURATION := 0.5

## Grace period after power-up spawns where it cannot be destroyed
## Prevents immediate destruction by the explosion that revealed it
const POWERUP_IMMUNITY_TIME := 0.6

## Minimum time between player movement inputs (controls movement speed)
const PLAYER_MOVE_COOLDOWN := 0.12

## Number of tiles a thrown bomb travels
const BOMB_THROW_DISTANCE := 4

## Delay between each tile when a bomb is flying (thrown)
const BOMB_FLY_DELAY := 0.12

# =============================================================================
# VISUAL - PLAYER COLORS
# =============================================================================

## Color assignments for each player (keyed by 1-based player ID)
const PLAYER_COLORS := {
	1: Color(0.2, 0.7, 0.3, 1.0),  # Player 1: Green
	2: Color(0.3, 0.5, 1.0, 1.0),  # Player 2: Blue
}

## Display names for player colors (used in win messages)
const PLAYER_COLOR_NAMES := {
	1: "Green",
	2: "Blue",
}

# =============================================================================
# VISUAL - POWERUP COLORS
# =============================================================================

## Color for the "Extra Bomb" power-up
const POWERUP_EXTRA_BOMB_COLOR := Color(0.2, 0.5, 1.0, 1.0)  # Blue

## Color for the "Kick" power-up
const POWERUP_KICK_COLOR := Color(1.0, 0.6, 0.1, 1.0)  # Orange

## Color for the "Fire Range" power-up
const POWERUP_FIRE_RANGE_COLOR := Color(1.0, 0.3, 0.2, 1.0)  # Red/Orange

## Color for the "Speed" power-up
const POWERUP_SPEED_COLOR := Color(0.2, 0.9, 0.9, 1.0)  # Cyan

## Color for the "Throw" power-up
const POWERUP_THROW_COLOR := Color(0.9, 0.2, 0.9, 1.0)  # Purple

# =============================================================================
# VISUAL - CURSE (NEGATIVE POWERUP) COLORS
# =============================================================================

## Color for the "Curse Speed" power-up (makes you too fast)
const CURSE_SPEED_COLOR := Color(0.8, 0.0, 0.0, 1.0)  # Dark Red

## Color for the "Curse Invert" power-up (inverts controls)
const CURSE_INVERT_COLOR := Color(0.5, 0.0, 0.5, 1.0)  # Dark Purple

## Color for the "Curse Bombs" power-up (auto-places bombs)
const CURSE_BOMBS_COLOR := Color(0.4, 0.4, 0.4, 1.0)  # Dark Gray

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

## Converts grid coordinates to world position (center of tile).
## Use this for positioning entities that should be centered in their tile.
## @param grid_pos The grid coordinates (column, row)
## @return World position at the center of the specified tile
static func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE * 0.5,
		grid_pos.y * TILE_SIZE + TILE_SIZE * 0.5
	)


## Converts world position to grid coordinates.
## @param world_pos The world position in pixels
## @return Grid coordinates (column, row) containing the position
static func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x) / TILE_SIZE,
		int(world_pos.y) / TILE_SIZE
	)


## Converts grid coordinates to world position (top-left corner of tile).
## Use this for positioning nodes that have their origin at top-left (like ColorRect).
## @param grid_pos The grid coordinates (column, row)
## @return World position at the top-left corner of the specified tile
static func grid_to_world_corner(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)


## Converts PlayerNumber enum to 1-based player ID.
## @param player_number The PlayerNumber enum value (0 or 1)
## @return 1-based player ID (1 or 2)
static func get_player_id(player_number: int) -> int:
	return player_number + 1


## Logs a debug message with consistent formatting.
## @param source The system/class logging the message (e.g., "Arena", "Player")
## @param message The message to log
## @param level The severity level of the message
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
