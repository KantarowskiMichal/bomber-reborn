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

## Whether the bomb is currently flying (was thrown)
var is_flying := false

## Direction the bomb is moving (if kicked)
var _move_direction := Vector2i.ZERO

## Reference to arena for movement collision checks
var _arena: Arena = null

## Whether the bomb has already exploded (prevents double-explosion)
var _has_exploded := false

## Number of tiles remaining to fly
var _fly_tiles_remaining := 0

## Direction the bomb is flying (if thrown)
var _fly_direction := Vector2i.ZERO

## Whether the fuse expired while airborne (should explode on landing)
var _explode_on_landing := false

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Start the fuse timer - bomb explodes when it expires
	get_tree().create_timer(fuse_time).timeout.connect(_on_fuse_expired)
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
# PRIVATE - FLYING (THROW MECHANIC)
# =============================================================================

## Called when the fuse timer expires.
## If flying, defer explosion until landing; otherwise explode immediately.
func _on_fuse_expired() -> void:
	if is_flying:
		_explode_on_landing = true
		_log("Fuse expired while flying - will explode on landing", GameConstants.LogLevel.DEBUG)
	else:
		_explode()


## Starts the bomb flying in a direction (called when thrown).
## @param direction Direction to fly (unit vector)
## @param arena Reference to arena for collision checks
func start_flying(direction: Vector2i, arena: Arena) -> void:
	_arena = arena
	_fly_direction = direction
	_fly_tiles_remaining = GameConstants.BOMB_THROW_DISTANCE
	is_flying = true
	rotation_degrees = 45.0  # Rotate to show bomb is airborne
	_log("Thrown in direction %s" % direction, GameConstants.LogLevel.DEBUG)
	_try_continue_flying()


## Attempts to fly one tile in the current direction.
## Handles collisions with hard blocks, other bombs, etc.
func _try_continue_flying() -> void:
	if not _arena or _fly_tiles_remaining <= 0:
		_land()
		return

	var next_pos := grid_pos + _fly_direction

	# Check what's at the next position
	if not _arena.is_in_bounds(next_pos):
		# Out of bounds - land at current position
		_land()
		return

	var cell_type: int = _arena.get_cell_type(next_pos)

	match cell_type:
		Arena.CellType.HARD_BLOCK:
			# Hard block - stop before it
			_land()
			return
		Arena.CellType.BOMB:
			# Another bomb - check what's after it to decide behavior
			_log("Bouncing off bomb at %s" % next_pos, GameConstants.LogLevel.DEBUG)

			var after_bomb := next_pos + _fly_direction
			var can_continue := _arena.is_in_bounds(after_bomb) and _arena.get_cell_type(after_bomb) != Arena.CellType.HARD_BLOCK

			if can_continue:
				# Can continue past this bomb - fly over it (one tile at a time)
				_fly_over_position(next_pos)
			else:
				# Can't continue past - stack on this bomb
				_fly_to_position_and_land(next_pos)
			return
		_:
			# Empty, soft block, or powerup - fly through
			_fly_to_position(next_pos)


## Moves the bomb to a new position during flight.
func _fly_to_position(new_pos: Vector2i) -> void:
	var old_pos := grid_pos
	grid_pos = new_pos
	position = GameConstants.grid_to_world(new_pos)
	_fly_tiles_remaining -= 1
	moved.emit(old_pos, new_pos)

	# Schedule next fly step after delay
	get_tree().create_timer(GameConstants.BOMB_FLY_DELAY).timeout.connect(_try_continue_flying)


## Moves the bomb over a position (flying over another bomb) without counting as distance.
func _fly_over_position(new_pos: Vector2i) -> void:
	var old_pos := grid_pos
	grid_pos = new_pos
	position = GameConstants.grid_to_world(new_pos)
	# Don't decrement _fly_tiles_remaining - bouncing doesn't count as distance
	moved.emit(old_pos, new_pos)

	# Schedule next fly step after delay
	get_tree().create_timer(GameConstants.BOMB_FLY_DELAY).timeout.connect(_try_continue_flying)


## Moves the bomb to a position and lands there (for stacking on bombs).
func _fly_to_position_and_land(new_pos: Vector2i) -> void:
	var old_pos := grid_pos
	grid_pos = new_pos
	position = GameConstants.grid_to_world(new_pos)
	moved.emit(old_pos, new_pos)

	# Land after a delay to show the final movement
	get_tree().create_timer(GameConstants.BOMB_FLY_DELAY).timeout.connect(_land)


## Called when the bomb finishes flying and lands.
func _land() -> void:
	is_flying = false
	_fly_direction = Vector2i.ZERO
	rotation_degrees = 0.0  # Reset rotation on landing
	_log("Landed at %s" % grid_pos, GameConstants.LogLevel.DEBUG)

	# Notify arena of landing so it can register the bomb at the new position
	if _arena:
		_arena.on_bomb_landed(grid_pos, self)

	# If fuse expired while airborne, explode now
	if _explode_on_landing:
		_log("Exploding after landing (fuse expired while airborne)")
		_explode()


# =============================================================================
# PRIVATE - LOGGING
# =============================================================================

## Logs a message with the Bomb tag.
func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(LOG_TAG, message, level)
