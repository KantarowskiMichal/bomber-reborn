extends Node2D
class_name Conveyor
## A conveyor belt tile that moves bombs in a specific direction.
##
## Bombs placed on or kicked onto a conveyor will be pushed
## in the direction the conveyor points.

## The direction this conveyor moves things
var direction := Vector2i.DOWN

@onready var _arrow: Polygon2D = $Arrow


## Sets the conveyor direction and rotates the visual accordingly.
## @param dir Direction vector (UP, DOWN, LEFT, RIGHT)
func set_direction(dir: Vector2i) -> void:
	direction = dir
	# Rotate arrow to point in the correct direction
	if _arrow:
		match dir:
			Vector2i.UP:
				_arrow.rotation = 0
			Vector2i.DOWN:
				_arrow.rotation = PI
			Vector2i.LEFT:
				_arrow.rotation = -PI / 2
			Vector2i.RIGHT:
				_arrow.rotation = PI / 2
