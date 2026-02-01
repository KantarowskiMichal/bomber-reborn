extends Area2D
class_name Powerup
## Collectible power-up that grants abilities to players.
##
## Power-ups spawn when soft blocks are destroyed (based on drop chance).
## Players collect them by walking over them.
##
## Types:
## - EXTRA_BOMB: Increases the player's max bomb capacity by 1
## - KICK: Grants the ability to kick bombs
##
## Power-ups have a brief immunity period after spawning to prevent
## immediate destruction by the same explosion that revealed them.

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when a player collects this power-up
signal collected

## Emitted when the power-up is destroyed by an explosion
signal destroyed

# =============================================================================
# CONSTANTS
# =============================================================================

const LOG_TAG := "Powerup"

# =============================================================================
# ENUMS
# =============================================================================

## Available power-up types
enum Type {
	EXTRA_BOMB,  ## Increases max bomb capacity
	KICK,        ## Allows kicking bombs
}

# =============================================================================
# CONFIGURATION
# =============================================================================

## Visual configuration for each power-up type
## Contains color and display label
const VISUALS := {
	Type.EXTRA_BOMB: {
		"color": GameConstants.POWERUP_EXTRA_BOMB_COLOR,
		"label": "+B",  # "+B" for extra Bomb
	},
	Type.KICK: {
		"color": GameConstants.POWERUP_KICK_COLOR,
		"label": "K",   # "K" for Kick
	},
}

## Display names for logging
const TYPE_NAMES := {
	Type.EXTRA_BOMB: "Extra Bomb",
	Type.KICK: "Kick",
}

# =============================================================================
# STATE
# =============================================================================

## Grid position of this power-up
var grid_pos := Vector2i.ZERO

## Type of power-up (determines effect when collected)
var type: Type = Type.EXTRA_BOMB

## Whether the power-up is immune to explosions (grace period after spawn)
var _is_immune := true

## Whether the power-up has been collected (prevents double-collection)
var _is_collected := false

## Whether the power-up has been destroyed (prevents double-destruction)
var _is_destroyed := false

@onready var _color_rect: ColorRect = $ColorRect
@onready var _label: Label = $Label

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Connect collision for player pickup
	body_entered.connect(_on_body_entered)

	# Start immunity timer - prevents instant destruction by revealing explosion
	get_tree().create_timer(GameConstants.POWERUP_IMMUNITY_TIME).timeout.connect(_on_immunity_expired)
	_log("Spawned with %.1fs immunity" % GameConstants.POWERUP_IMMUNITY_TIME, GameConstants.LogLevel.DEBUG)


# =============================================================================
# PUBLIC API
# =============================================================================

## Initializes the power-up at a grid position with a specific type.
## @param pos Grid position to place the power-up
## @param powerup_type Type of power-up to create
func setup(pos: Vector2i, powerup_type: Type = Type.EXTRA_BOMB) -> void:
	grid_pos = pos
	type = powerup_type
	position = GameConstants.grid_to_world(pos)

	# Update visuals (defer if not in tree yet)
	if is_inside_tree():
		_update_visuals()
	else:
		call_deferred("_update_visuals")


## Destroys the power-up (called when hit by explosion).
## Only works if immunity period has expired.
func destroy() -> void:
	if _is_destroyed or _is_collected:
		return
	if _is_immune:
		_log("Destruction blocked - still immune", GameConstants.LogLevel.DEBUG)
		return

	_destroy()


## Forces destruction regardless of immunity (used during explosion propagation).
func force_destroy() -> void:
	if _is_destroyed or _is_collected:
		return
	_destroy()


## Internal destruction logic.
func _destroy() -> void:
	_is_destroyed = true
	_log("Destroyed by explosion at %s" % grid_pos)
	destroyed.emit()
	queue_free()


## Returns the display name for this power-up's type.
## @return Type name string (e.g., "Extra Bomb", "Kick")
func get_type_name() -> String:
	return TYPE_NAMES.get(type, "Unknown")


# =============================================================================
# PRIVATE
# =============================================================================

## Updates the visual appearance based on power-up type.
func _update_visuals() -> void:
	if not _color_rect or not _label:
		return

	var visual_data: Dictionary = VISUALS.get(type, VISUALS[Type.EXTRA_BOMB])
	_color_rect.color = visual_data.color
	_label.text = visual_data.label


## Called when the immunity period expires.
func _on_immunity_expired() -> void:
	_is_immune = false
	_log("Immunity expired at %s" % grid_pos, GameConstants.LogLevel.DEBUG)


## Handles collision with physics bodies (players).
## @param body The body that entered the power-up area
func _on_body_entered(body: Node2D) -> void:
	if _is_collected:
		return
	if not body is Player:
		return

	_is_collected = true
	var player := body as Player
	_apply_effect(player)
	_log("%s collected by Player %d at %s" % [get_type_name(), GameConstants.get_player_id(player.player_number), grid_pos])
	collected.emit()
	queue_free()


## Applies the power-up effect to the collecting player.
## @param player The player who collected the power-up
func _apply_effect(player: Player) -> void:
	var player_id := GameConstants.get_player_id(player.player_number)
	match type:
		Type.EXTRA_BOMB:
			player.max_bombs += 1
			_log("Player %d max bombs increased to %d" % [player_id, player.max_bombs], GameConstants.LogLevel.DEBUG)
		Type.KICK:
			player.has_kick = true
			_log("Player %d gained kick ability" % player_id, GameConstants.LogLevel.DEBUG)


# =============================================================================
# PRIVATE - LOGGING
# =============================================================================

## Logs a message with the Powerup tag.
func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(LOG_TAG, message, level)
