extends CharacterBody2D
class_name Player
## Player character with movement, bomb placement, and power-up collection.
##
## Players move on a grid and can:
## - Move in 4 directions (arrow keys for P1, WASD for P2)
## - Place bombs (Space for P1, Tab for P2)
## - Kick bombs if they have the kick power-up
## - Collect power-ups to gain abilities
##
## Movement uses a cooldown timer for consistent speed with continuous input.

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when the player places a bomb at their current position
signal bomb_placed(grid_pos: Vector2i)

## Emitted when the player is killed by an explosion
signal died(player: Player)

# =============================================================================
# ENUMS
# =============================================================================

## Player identifier for input mapping and color assignment
enum PlayerNumber { PLAYER_1, PLAYER_2 }

## Types of curses (negative powerups)
enum CurseType { NONE, SPEED, INVERT, BOMBS }

# =============================================================================
# EXPORTS
# =============================================================================

## Which player this is (determines controls and color)
@export var player_number: PlayerNumber = PlayerNumber.PLAYER_1

## Maximum number of bombs this player can have active at once
@export var max_bombs := 5

## How many tiles this player's bombs explode in each direction
@export var bomb_range := 1

# =============================================================================
# STATE
# =============================================================================

## Log tag for this class (includes player number, set in _ready)
var _log_tag := "Player"

## Number of bombs currently placed by this player
var current_bombs := 0

## Current grid position (updated when moving)
var grid_pos := Vector2i.ZERO

## Whether this player can kick bombs
var has_kick := true

## Whether this player can throw bombs
var has_throw := true

## Movement speed multiplier (lower = faster, stacks multiplicatively)
var speed_multiplier := 1.0

## Last movement direction for throw targeting
var facing_direction := Vector2i.DOWN

## Currently active curse type (NONE if no curse)
var active_curse: CurseType = CurseType.NONE

## Time remaining on current curse
var _curse_timer := 0.0

## Timer for auto-bomb placement during BOMBS curse
var _curse_bomb_timer := 0.0

## Whether this player is still in the game
var is_alive := true

## Visual color of this player
var player_color: Color = Color.WHITE

## Reference to the arena for collision queries
var arena: Arena = null

## Cooldown timer for movement (prevents moving too fast)
var _move_timer := 0.0

## Tracks previous frame's bomb key state (for P2's Tab key)
var _bomb_key_was_pressed := false

## Whether the player is currently sliding on ice
var is_sliding := false

## Visual movement speed in px/s for smooth motion mode (matches move cooldown)
var _smooth_speed := 0.0

## Direction the player is sliding (when on ice)
var _slide_direction := Vector2i.ZERO

@onready var _shape: Polygon2D = $Shape
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

# =============================================================================
# SHAPE DEFINITIONS
# =============================================================================

## Star shape (5-pointed) for Player 1
static func _make_star(r: float) -> PackedVector2Array:
	var points: Array[Vector2] = []
	var inner := r * 0.4
	for i in range(10):
		var angle := (i * TAU / 10) - TAU / 4
		var rad := r if i % 2 == 0 else inner
		points.append(Vector2(cos(angle) * rad, sin(angle) * rad))
	return PackedVector2Array(points)

## Triangle shape for Player 2
static func _make_triangle(r: float) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for i in range(3):
		var angle := (i * TAU / 3) - TAU / 4
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return PackedVector2Array(points)

## Hexagon shape for Player 3
static func _make_hexagon(r: float) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for i in range(6):
		var angle := i * TAU / 6
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return PackedVector2Array(points)

## Circle shape (12-sided) for Player 4
static func _make_circle(r: float) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for i in range(12):
		var angle := i * TAU / 12
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	return PackedVector2Array(points)

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_log_tag = "Player%d" % GameConstants.get_player_id(player_number)
	grid_pos = GameConstants.world_to_grid(position)
	_smooth_speed = float(GameConstants.TILE_SIZE) / GameConstants.PLAYER_MOVE_COOLDOWN
	_apply_hitbox_size()
	_log("Initialized at grid position %s" % grid_pos)


func _process(delta: float) -> void:
	if not is_alive:
		return

	# Tick down movement cooldown
	_move_timer = maxf(0.0, _move_timer - delta)

	# Handle curse timer
	_handle_curse_timer(delta)

	if GameConstants.MOVEMENT_MODE == GameConstants.MovementMode.FREE:
		_handle_free_movement(delta)
	else:
		_handle_movement()

	_handle_bomb_placement()

	# Handle curse effects
	_handle_curse_effects(delta)

	# Smooth motion: lerp visual position toward logical grid position
	if GameConstants.MOVEMENT_MODE == GameConstants.MovementMode.SMOOTH and _smooth_speed > 0.0:
		var target := GameConstants.grid_to_world(grid_pos)
		position = position.move_toward(target, _smooth_speed * delta)


# =============================================================================
# PUBLIC API
# =============================================================================

## Sets the player's visual color.
## @param color The color to apply to the player's sprite
func set_color(color: Color) -> void:
	player_color = color
	_setup_shape()
	if _shape:
		_shape.color = color
	_log("Color set to %s" % get_color_name(), GameConstants.LogLevel.DEBUG)


## Sets up the player's visual polygon based on their player number and current hitbox size.
func _setup_shape() -> void:
	if not _shape:
		return

	var r := GameConstants.PLAYER_HITBOX_SIZE * 0.5
	match player_number:
		PlayerNumber.PLAYER_1:
			_shape.polygon = _make_star(r)
		PlayerNumber.PLAYER_2:
			_shape.polygon = _make_triangle(r)
		_:
			if GameConstants.get_player_id(player_number) % 2 == 1:
				_shape.polygon = _make_hexagon(r)
			else:
				_shape.polygon = _make_circle(r)


## Applies the current PLAYER_HITBOX_SIZE from GameConstants to this player's collision
## shape and visual polygon so both stay in sync.
func _apply_hitbox_size() -> void:
	if _collision_shape:
		if _collision_shape.shape is CircleShape2D:
			(_collision_shape.shape as CircleShape2D).radius = GameConstants.PLAYER_HITBOX_SIZE * 0.5
		else:
			var circle := CircleShape2D.new()
			circle.radius = GameConstants.PLAYER_HITBOX_SIZE * 0.5
			_collision_shape.shape = circle
	_setup_shape()


## Returns the display name of this player's color.
## @return Color name string (e.g., "Green", "Blue")
func get_color_name() -> String:
	return GameConstants.PLAYER_COLOR_NAMES.get(GameConstants.get_player_id(player_number), "Unknown")


## Called when a bomb is placed to track active bomb count.
func increment_bomb_count() -> void:
	current_bombs += 1
	_log("Bomb placed (active: %d/%d)" % [current_bombs, max_bombs], GameConstants.LogLevel.DEBUG)


## Called when one of this player's bombs explodes.
## Decrements the active bomb count to allow placing more bombs.
func on_bomb_exploded() -> void:
	current_bombs = maxi(0, current_bombs - 1)
	_log("Bomb exploded (active: %d/%d)" % [current_bombs, max_bombs], GameConstants.LogLevel.DEBUG)


## Kills this player (called when hit by explosion).
## Hides the player and emits the died signal.
func kill() -> void:
	if not is_alive:
		return

	is_alive = false
	visible = false
	_log("Killed!")
	died.emit(self)


## Applies a curse to this player.
## @param curse_type The type of curse to apply
func apply_curse(curse_type: CurseType) -> void:
	active_curse = curse_type
	_curse_timer = GameConstants.CURSE_DURATION
	_curse_bomb_timer = 0.0
	_log("Curse applied: %s (%.1fs)" % [CurseType.keys()[curse_type], GameConstants.CURSE_DURATION])


## Returns true if a curse is currently active.
func has_active_curse() -> bool:
	return active_curse != CurseType.NONE


## Clears the active curse.
func _clear_curse() -> void:
	var old_curse := active_curse
	active_curse = CurseType.NONE
	_curse_timer = 0.0
	_curse_bomb_timer = 0.0
	_log("Curse expired: %s" % CurseType.keys()[old_curse])


# =============================================================================
# PRIVATE - INPUT HANDLING
# =============================================================================

## Returns the movement direction based on currently pressed keys.
## Player 1 uses arrow keys, Player 2 uses WASD.
## If INVERT curse is active, directions are reversed.
## @return Direction vector or Vector2i.ZERO if no movement key pressed
func _get_movement_direction() -> Vector2i:
	var direction := Vector2i.ZERO

	match player_number:
		PlayerNumber.PLAYER_1:
			# Arrow keys for Player 1
			if Input.is_action_pressed("ui_up"):
				direction = Vector2i.UP
			elif Input.is_action_pressed("ui_down"):
				direction = Vector2i.DOWN
			elif Input.is_action_pressed("ui_left"):
				direction = Vector2i.LEFT
			elif Input.is_action_pressed("ui_right"):
				direction = Vector2i.RIGHT
		PlayerNumber.PLAYER_2:
			# WASD for Player 2
			if Input.is_physical_key_pressed(KEY_W):
				direction = Vector2i.UP
			elif Input.is_physical_key_pressed(KEY_S):
				direction = Vector2i.DOWN
			elif Input.is_physical_key_pressed(KEY_A):
				direction = Vector2i.LEFT
			elif Input.is_physical_key_pressed(KEY_D):
				direction = Vector2i.RIGHT

	# Invert controls if cursed
	if active_curse == CurseType.INVERT and direction != Vector2i.ZERO:
		direction = -direction

	return direction


## Checks if the bomb placement key was just pressed.
## Player 1 uses Space (ui_accept), Player 2 uses Tab.
## Tab requires manual tracking since it's not an action.
## @return True if bomb key was just pressed this frame
func _is_bomb_key_just_pressed() -> bool:
	match player_number:
		PlayerNumber.PLAYER_1:
			return Input.is_action_just_pressed("ui_accept")
		PlayerNumber.PLAYER_2:
			# Manual just_pressed detection for Tab key
			var is_pressed := Input.is_physical_key_pressed(KEY_TAB)
			var just_pressed := is_pressed and not _bomb_key_was_pressed
			_bomb_key_was_pressed = is_pressed
			return just_pressed
	return false


# =============================================================================
# PRIVATE - MOVEMENT
# =============================================================================

## Processes movement input and attempts to move if cooldown allows.
## Movement is grid-based (snap to tile centers).
## When sliding on ice, continues in the slide direction automatically.
func _handle_movement() -> void:
	# Respect movement cooldown for consistent speed
	if _move_timer > 0:
		return

	# When sliding on ice, use slide direction instead of input
	var direction: Vector2i
	if is_sliding and _slide_direction != Vector2i.ZERO:
		direction = _slide_direction
	else:
		direction = _get_movement_direction()

	if direction != Vector2i.ZERO and _try_move(direction):
		# Reset cooldown on successful move
		var effective_speed := speed_multiplier
		# Apply curse speed if active (makes you way too fast)
		if active_curse == CurseType.SPEED:
			effective_speed *= GameConstants.CURSE_SPEED_MULTIPLIER
		# Slide faster on ice
		if is_sliding:
			effective_speed *= 0.5
		var actual_cooldown := GameConstants.PLAYER_MOVE_COOLDOWN * effective_speed
		_move_timer = actual_cooldown
		_smooth_speed = float(GameConstants.TILE_SIZE) / actual_cooldown


## Attempts to move in the specified direction.
## Handles kicking bombs if the player has the kick ability.
## @param direction Direction to move (unit vector)
## @return True if movement or kick was successful
func _try_move(direction: Vector2i) -> bool:
	if not arena:
		return false

	# Track facing direction for throw ability
	facing_direction = direction

	var target_pos := grid_pos + direction

	# Try to kick bomb if we have the ability and there's a bomb ahead
	if has_kick and arena.has_bomb_at(target_pos):
		_log("Kicking bomb at %s" % target_pos, GameConstants.LogLevel.DEBUG)
		arena.kick_bomb(target_pos, direction)
		return true

	# Try to walk to target tile
	if arena.is_tile_walkable(target_pos):
		grid_pos = target_pos
		if GameConstants.MOVEMENT_MODE == GameConstants.MovementMode.SNAP:
			position = GameConstants.grid_to_world(grid_pos)

		# Check for special tile effects after moving
		_check_tile_effects(direction)
		return true

	# If sliding and hit a wall, stop sliding
	if is_sliding:
		is_sliding = false
		_slide_direction = Vector2i.ZERO

	return false


## Checks for special tile effects at the current position.
## @param move_direction The direction the player moved to get here
func _check_tile_effects(move_direction: Vector2i) -> void:
	if not arena:
		return

	# Check for hole - instant death
	if arena.is_hole(grid_pos):
		_log("Fell into hole at %s" % grid_pos)
		kill()
		return

	# Check for ice - start sliding
	if arena.is_ice(grid_pos):
		if not is_sliding:
			_log("Started sliding on ice at %s" % grid_pos, GameConstants.LogLevel.DEBUG)
		is_sliding = true
		_slide_direction = move_direction
	else:
		# Stopped sliding (reached non-ice tile)
		if is_sliding:
			_log("Stopped sliding at %s" % grid_pos, GameConstants.LogLevel.DEBUG)
		is_sliding = false
		_slide_direction = Vector2i.ZERO


## Processes continuous pixel-based movement (FREE movement mode).
## The player's hitbox radius is kept clear of all walls via _clamp_to_walls,
## so the visual shape never overlaps a wall. Corner correction nudges the
## player perpendicular to their direction when they clip a wall corner.
func _handle_free_movement(delta: float) -> void:
	if not arena:
		return

	var direction: Vector2i
	if is_sliding and _slide_direction != Vector2i.ZERO:
		direction = _slide_direction
	else:
		direction = _get_movement_direction()

	if direction == Vector2i.ZERO:
		if is_sliding:
			is_sliding = false
			_slide_direction = Vector2i.ZERO
		return

	facing_direction = direction

	var effective_speed := speed_multiplier
	if active_curse == CurseType.SPEED:
		effective_speed *= GameConstants.CURSE_SPEED_MULTIPLIER
	if is_sliding:
		effective_speed *= 0.5
	var pixel_speed := float(GameConstants.TILE_SIZE) / (GameConstants.PLAYER_MOVE_COOLDOWN * effective_speed)

	var new_position := position + Vector2(direction) * pixel_speed * delta

	# Kick bomb before clamping — check the intended tile first
	var intended_grid := GameConstants.world_to_grid(new_position)
	if intended_grid != grid_pos and has_kick and arena.has_bomb_at(intended_grid):
		arena.kick_bomb(intended_grid, direction)
		return

	# If moving toward a wall, apply corner nudge in the perpendicular axis
	var wall_ahead := grid_pos + direction
	if not arena.is_in_bounds(wall_ahead) or not arena.is_tile_walkable(wall_ahead):
		if is_sliding:
			is_sliding = false
			_slide_direction = Vector2i.ZERO
		new_position += _corner_nudge(direction, pixel_speed, delta)

	# Clamp so hitbox edge never enters a wall tile
	new_position = _clamp_to_walls(new_position)

	# Update logical grid position if center crossed into a new walkable tile
	var new_grid_pos := GameConstants.world_to_grid(new_position)
	if new_grid_pos != grid_pos:
		if arena.is_tile_walkable(new_grid_pos):
			grid_pos = new_grid_pos
			_check_tile_effects(direction)

	position = new_position


## Returns a perpendicular nudge vector that steers the player toward their
## tile's center axis when they are slightly clipping a wall corner.
func _corner_nudge(move_dir: Vector2i, speed: float, delta: float) -> Vector2:
	var tile_center := GameConstants.grid_to_world(grid_pos)
	var threshold := GameConstants.TILE_SIZE * GameConstants.CORNER_CORRECTION_RATIO

	var offset: float
	var nudge := Vector2.ZERO

	if move_dir.x != 0:
		offset = position.y - tile_center.y
		if abs(offset) < threshold and abs(offset) > 0.5:
			nudge.y = -sign(offset) * speed * delta
	else:
		offset = position.x - tile_center.x
		if abs(offset) < threshold and abs(offset) > 0.5:
			nudge.x = -sign(offset) * speed * delta

	return nudge


## Clamps new_pos so the player's hitbox circle (radius = PLAYER_HITBOX_SIZE/2)
## does not overlap any wall tile adjacent to the player's current grid_pos.
func _clamp_to_walls(new_pos: Vector2) -> Vector2:
	var r := GameConstants.PLAYER_HITBOX_SIZE * 0.5
	var ts := float(GameConstants.TILE_SIZE)
	var result := new_pos

	# Right wall
	var right := Vector2i(grid_pos.x + 1, grid_pos.y)
	if not arena.is_in_bounds(right) or not arena.is_tile_walkable(right):
		result.x = minf(result.x, right.x * ts - r)

	# Left wall
	var left := Vector2i(grid_pos.x - 1, grid_pos.y)
	if not arena.is_in_bounds(left) or not arena.is_tile_walkable(left):
		result.x = maxf(result.x, (left.x + 1) * ts + r)

	# Down wall
	var down := Vector2i(grid_pos.x, grid_pos.y + 1)
	if not arena.is_in_bounds(down) or not arena.is_tile_walkable(down):
		result.y = minf(result.y, down.y * ts - r)

	# Up wall
	var up_tile := Vector2i(grid_pos.x, grid_pos.y - 1)
	if not arena.is_in_bounds(up_tile) or not arena.is_tile_walkable(up_tile):
		result.y = maxf(result.y, (up_tile.y + 1) * ts + r)

	return result


# =============================================================================
# PRIVATE - BOMB PLACEMENT
# =============================================================================

## Handles bomb placement input.
## Places a bomb at the player's current position if possible.
## If player has throw ability and is standing on a bomb, throws it instead.
func _handle_bomb_placement() -> void:
	if not _is_bomb_key_just_pressed():
		return

	# If we have throw ability and are standing on a bomb, throw it
	if has_throw and arena and arena.has_bomb_at(grid_pos):
		_log("Throwing bomb at %s in direction %s" % [grid_pos, facing_direction])
		arena.throw_bomb(grid_pos, facing_direction)
		return

	# Check if we've reached our bomb limit
	if current_bombs >= max_bombs:
		_log("Cannot place bomb - at max capacity (%d/%d)" % [current_bombs, max_bombs], GameConstants.LogLevel.DEBUG)
		return

	# Try to place bomb at current position
	if arena and arena.can_place_bomb(grid_pos):
		_log("Placing bomb at %s" % grid_pos)
		bomb_placed.emit(grid_pos)


# =============================================================================
# PRIVATE - CURSE HANDLING
# =============================================================================

## Ticks down the curse timer and clears the curse when it expires.
func _handle_curse_timer(delta: float) -> void:
	if active_curse == CurseType.NONE:
		return

	_curse_timer -= delta
	if _curse_timer <= 0:
		_clear_curse()


## Handles ongoing curse effects (like auto-bomb placement).
func _handle_curse_effects(delta: float) -> void:
	if active_curse != CurseType.BOMBS:
		return

	# Auto-place/throw bombs at interval
	_curse_bomb_timer -= delta
	if _curse_bomb_timer <= 0:
		_curse_bomb_timer = GameConstants.CURSE_BOMBS_INTERVAL
		_curse_auto_bomb()


## Automatically places or throws a bomb (BOMBS curse effect).
## Respects all normal bomb placement rules (bomb limit, valid position, etc.)
func _curse_auto_bomb() -> void:
	if not arena:
		return

	# If standing on a bomb and have throw, throw it in facing direction
	if has_throw and arena.has_bomb_at(grid_pos):
		arena.throw_bomb(grid_pos, facing_direction)
		return

	# Check bomb limit (same as normal placement)
	if current_bombs >= max_bombs:
		return

	# Try to place a bomb at current position (same rules as normal placement)
	if arena.can_place_bomb(grid_pos):
		bomb_placed.emit(grid_pos)


# =============================================================================
# PRIVATE - LOGGING
# =============================================================================

## Logs a message with this player's tag.
func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(_log_tag, message, level)
