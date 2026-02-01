extends StaticBody2D
class_name SoftBlock
## Destructible block that can be destroyed by explosions.
##
## Soft blocks fill the arena randomly (controlled by SOFT_BLOCK_SPAWN_CHANCE).
## When destroyed by an explosion:
## 1. The block emits a 'destroyed' signal with its grid position
## 2. The Arena receives this signal and may spawn a power-up
## 3. The block is removed from the scene
##
## Soft blocks use a brown/tan color to distinguish from hard blocks.

# =============================================================================
# SIGNALS
# =============================================================================

## Emitted when this block is destroyed by an explosion
## @param grid_pos The grid position where the block was located
signal destroyed(grid_pos: Vector2i)

# =============================================================================
# STATE
# =============================================================================

## Cached grid position (set from world position on ready)
var grid_pos := Vector2i.ZERO

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Calculate and cache grid position from world position
	# Add half tile size because block position is at top-left corner
	grid_pos = GameConstants.world_to_grid(
		position + Vector2(GameConstants.TILE_SIZE * 0.5, GameConstants.TILE_SIZE * 0.5)
	)

# =============================================================================
# PUBLIC API
# =============================================================================

## Destroys this block. Called when hit by an explosion.
## Emits the destroyed signal before removing from scene.
func destroy() -> void:
	destroyed.emit(grid_pos)
	queue_free()
