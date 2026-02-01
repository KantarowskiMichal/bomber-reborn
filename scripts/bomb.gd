extends Area2D
class_name Bomb
## A bomb that explodes after a fuse timer and can be kicked by players.
##
## Bombs are placed by players and explode after a set time.
## When kicked (by a player with the kick power-up), bombs move
## tile-by-tile until they hit an obstacle or player.
##
## Chain reactions occur when an explosion hits another bomb,
## triggering it to explode immediately.

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when the bomb explodes (fuse expired or chain reaction)
## @param grid_pos Position where the bomb exploded
## @param explosion_range How far the explosion should spread
signal exploded(grid_pos: Vector2i, explosion_range: int)

## Emitted when a kicked bomb moves to a new tile
## @param old_pos Previous grid position
## @param new_pos New grid position
signal moved(old_pos: Vector2i, new_pos: Vector2i)

# =============================================================================
# CONSTANTS
# =============================================================================

const LOG_TAG := "Bomb"

# =============================================================================
# EXPORTS
# =============================================================================

## Time in seconds until the bomb explodes
@export var fuse_time := GameConstants.BOMB_FUSE_TIME

## How many tiles the explosion spreads in each direction
@export var explosion_range := 2

# =============================================================================
# STATE
# =============================================================================

## Current grid position of the bomb
var grid_pos := Vector2i.ZERO

## Whether the bomb is currently moving (was kicked)
var is_moving := false

## Direction the bomb is moving (if kicked)
var _move_direction := Vector2i.ZERO

## Reference to arena for movement collision checks
var _arena: Arena = null

## Whether the bomb has already exploded (prevents double-explosion)
var _has_exploded := false

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Start the fuse timer - bomb explodes when it expires
	get_tree().create_timer(fuse_time).timeout.connect(_explode)
	_log("Fuse started (%.1fs)" % fuse_time, GameConstants.LogLevel.DEBUG)


# =============================================================================
# PUBLIC API
# =============================================================================

## Initializes the bomb at a grid position with specified range.
## @param pos Grid position to place the bomb
## @param range_value Explosion range in tiles
func setup(pos: Vector2i, range_value: int = 2) -> void:
	grid_pos = pos
	explosion_range = range_value
	position = GameConstants.grid_to_world(pos)


## Forces the bomb to explode immediately (called during chain reactions).
func trigger_explosion() -> void:
	_log("Chain reaction triggered at %s" % grid_pos)
	_explode()


## Starts the bomb moving in a direction (called when kicked).
## @param direction Direction to move (unit vector)
## @param arena Reference to arena for collision checks
func start_moving(direction: Vector2i, arena: Arena) -> void:
	_arena = arena
	_move_direction = direction
	_log("Kicked in direction %s" % direction, GameConstants.LogLevel.DEBUG)
	_try_continue_moving()


# =============================================================================
# PRIVATE
# =============================================================================

## Handles the explosion - emits signal and removes bomb from scene.
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	_log("Exploding at %s (range: %d)" % [grid_pos, explosion_range])
	exploded.emit(grid_pos, explosion_range)
	queue_free()


## Attempts to move one tile in the current direction.
## If successful, schedules the next move step.
## If blocked, stops moving.
func _try_continue_moving() -> void:
	if not _arena:
		_stop_moving()
		return

	var next_pos := grid_pos + _move_direction

	if _arena.can_bomb_move_to(next_pos):
		# Move to the next tile
		var old_pos := grid_pos
		grid_pos = next_pos
		position = GameConstants.grid_to_world(next_pos)
		is_moving = true
		moved.emit(old_pos, next_pos)

		# Schedule next move step after delay
		get_tree().create_timer(GameConstants.BOMB_MOVE_DELAY).timeout.connect(_try_continue_moving)
	else:
		# Hit an obstacle, stop moving
		_log("Stopped at %s (blocked)" % grid_pos, GameConstants.LogLevel.DEBUG)
		_stop_moving()


## Stops the bomb's movement.
func _stop_moving() -> void:
	is_moving = false
	_move_direction = Vector2i.ZERO


# =============================================================================
# PRIVATE - LOGGING
# =============================================================================

## Logs a message with the Bomb tag.
func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(LOG_TAG, message, level)
