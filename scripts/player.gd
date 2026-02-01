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

# =============================================================================
# EXPORTS
# =============================================================================

## Which player this is (determines controls and color)
@export var player_number: PlayerNumber = PlayerNumber.PLAYER_1

## Maximum number of bombs this player can have active at once
@export var max_bombs := 1

## How many tiles this player's bombs explode in each direction
@export var bomb_range := 2

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
var has_kick := false

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

@onready var _color_rect: ColorRect = $ColorRect

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_log_tag = "Player%d" % GameConstants.get_player_id(player_number)
	grid_pos = GameConstants.world_to_grid(position)
	_log("Initialized at grid position %s" % grid_pos)


func _process(delta: float) -> void:
	if not is_alive:
		return

	# Tick down movement cooldown
	_move_timer = maxf(0.0, _move_timer - delta)

	_handle_movement()
	_handle_bomb_placement()


# =============================================================================
# PUBLIC API
# =============================================================================

## Sets the player's visual color.
## @param color The color to apply to the player's sprite
func set_color(color: Color) -> void:
	player_color = color
	if _color_rect:
		_color_rect.color = color
	_log("Color set to %s" % get_color_name(), GameConstants.LogLevel.DEBUG)


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


# =============================================================================
# PRIVATE - INPUT HANDLING
# =============================================================================

## Returns the movement direction based on currently pressed keys.
## Player 1 uses arrow keys, Player 2 uses WASD.
## @return Direction vector or Vector2i.ZERO if no movement key pressed
func _get_movement_direction() -> Vector2i:
	match player_number:
		PlayerNumber.PLAYER_1:
			# Arrow keys for Player 1
			if Input.is_action_pressed("ui_up"):
				return Vector2i.UP
			if Input.is_action_pressed("ui_down"):
				return Vector2i.DOWN
			if Input.is_action_pressed("ui_left"):
				return Vector2i.LEFT
			if Input.is_action_pressed("ui_right"):
				return Vector2i.RIGHT
		PlayerNumber.PLAYER_2:
			# WASD for Player 2
			if Input.is_physical_key_pressed(KEY_W):
				return Vector2i.UP
			if Input.is_physical_key_pressed(KEY_S):
				return Vector2i.DOWN
			if Input.is_physical_key_pressed(KEY_A):
				return Vector2i.LEFT
			if Input.is_physical_key_pressed(KEY_D):
				return Vector2i.RIGHT
	return Vector2i.ZERO


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
func _handle_movement() -> void:
	# Respect movement cooldown for consistent speed
	if _move_timer > 0:
		return

	var direction := _get_movement_direction()
	if direction != Vector2i.ZERO and _try_move(direction):
		# Reset cooldown on successful move
		_move_timer = GameConstants.PLAYER_MOVE_COOLDOWN


## Attempts to move in the specified direction.
## Handles kicking bombs if the player has the kick ability.
## @param direction Direction to move (unit vector)
## @return True if movement or kick was successful
func _try_move(direction: Vector2i) -> bool:
	if not arena:
		return false

	var target_pos := grid_pos + direction

	# Try to kick bomb if we have the ability and there's a bomb ahead
	if has_kick and arena.has_bomb_at(target_pos):
		_log("Kicking bomb at %s" % target_pos, GameConstants.LogLevel.DEBUG)
		arena.kick_bomb(target_pos, direction)
		return true

	# Try to walk to target tile
	if arena.is_tile_walkable(target_pos):
		grid_pos = target_pos
		position = GameConstants.grid_to_world(grid_pos)
		return true

	return false


# =============================================================================
# PRIVATE - BOMB PLACEMENT
# =============================================================================

## Handles bomb placement input.
## Places a bomb at the player's current position if possible.
func _handle_bomb_placement() -> void:
	if not _is_bomb_key_just_pressed():
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
# PRIVATE - LOGGING
# =============================================================================

## Logs a message with this player's tag.
func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(_log_tag, message, level)
