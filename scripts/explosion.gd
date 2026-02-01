extends Area2D
class_name Explosion
## Visual explosion effect that damages players and destroys soft blocks/powerups.
##
## Explosions are spawned by the Arena when a bomb explodes. Each explosion
## tile is a separate instance that:
## - Kills players on contact
## - Destroys soft blocks on contact
## - Destroys power-ups on contact (if not immune)
## - Triggers chain reactions with other bombs
##
## Explosions have a short lifetime and then disappear.

# =============================================================================
# CONSTANTS
# =============================================================================

const LOG_TAG := "Explosion"

# =============================================================================
# STATE
# =============================================================================

## Grid position of this explosion tile
var grid_pos := Vector2i.ZERO

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Connect collision signals for damage detection
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Auto-destroy after duration expires
	get_tree().create_timer(GameConstants.EXPLOSION_DURATION).timeout.connect(queue_free)


# =============================================================================
# PUBLIC API
# =============================================================================

## Initializes the explosion at a grid position.
## @param pos Grid position for this explosion tile
func setup(pos: Vector2i) -> void:
	grid_pos = pos
	position = GameConstants.grid_to_world(pos)


# =============================================================================
# PRIVATE - COLLISION HANDLERS
# =============================================================================

## Handles collision with physics bodies (soft blocks, players).
## @param body The body that entered the explosion
func _on_body_entered(body: Node2D) -> void:
	if body is SoftBlock:
		_log("Destroying soft block at %s" % grid_pos, GameConstants.LogLevel.DEBUG)
		body.destroy()
	elif body is Player:
		_log("Killing player at %s" % grid_pos)
		body.kill()


## Handles collision with areas (bombs, powerups).
## @param area The area that entered the explosion
func _on_area_entered(area: Area2D) -> void:
	if area is Bomb:
		# Trigger chain reaction
		_log("Triggering chain reaction with bomb at %s" % area.grid_pos, GameConstants.LogLevel.DEBUG)
		area.trigger_explosion()
	elif area is Powerup:
		_log("Destroying powerup at %s" % area.grid_pos, GameConstants.LogLevel.DEBUG)
		area.destroy()


# =============================================================================
# PRIVATE - LOGGING
# =============================================================================

## Logs a message with the Explosion tag.
func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(LOG_TAG, message, level)
