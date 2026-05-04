extends Arena
class_name TestArena
## Test arena with larger size and all powerups pre-spawned.
##
## Used for testing and debugging powerups and game mechanics.

# =============================================================================
# CONSTANTS
# =============================================================================

## Test arena dimensions (larger than normal)
const TEST_GRID_WIDTH := 21
const TEST_GRID_HEIGHT := 15

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_log("Initializing TEST arena (%dx%d grid)" % [TEST_GRID_WIDTH, TEST_GRID_HEIGHT])
	_generate_test_arena()
	_place_special_tiles()
	_spawn_all_powerups()
	_log("Test arena generation complete")


# =============================================================================
# OVERRIDES
# =============================================================================

## Override bounds check to use test dimensions.
func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < TEST_GRID_WIDTH \
		and pos.y >= 0 and pos.y < TEST_GRID_HEIGHT


## Override to return test arena spawn positions.
func get_player_spawn_position(player_index: int) -> Vector2:
	var w := TEST_GRID_WIDTH
	var h := TEST_GRID_HEIGHT

	var positions: Array[Vector2i] = [
		Vector2i(1, 1),          # Top-left (Player 1)
		Vector2i(w - 2, h - 2),  # Bottom-right (Player 2)
		Vector2i(w - 2, 1),      # Top-right (Player 3)
		Vector2i(1, h - 2),      # Bottom-left (Player 4)
	]

	var idx := clampi(player_index, 0, positions.size() - 1)
	var spawn_pos := positions[idx]
	_log("Player %d spawn position: %s" % [player_index + 1, spawn_pos], GameConstants.LogLevel.DEBUG)
	return GameConstants.grid_to_world(spawn_pos)


# =============================================================================
# PRIVATE - TEST ARENA GENERATION
# =============================================================================

## Generates a test arena layout with more open space.
func _generate_test_arena() -> void:
	grid.clear()
	var w := TEST_GRID_WIDTH
	var h := TEST_GRID_HEIGHT

	# Initialize empty grid
	for x in range(w):
		var column: Array[int] = []
		column.resize(h)
		column.fill(CellType.EMPTY)
		grid.append(column)

	# Place border walls and pillars
	for x in range(w):
		for y in range(h):
			var pos := Vector2i(x, y)

			if _is_border_test(x, y, w, h):
				_place_hard_block(pos)
			elif _is_pillar_test(x, y):
				_place_hard_block(pos)

	# Add some soft blocks in specific areas (not too many)
	_place_soft_block_cluster(5, 5, 3, 2)
	_place_soft_block_cluster(13, 5, 3, 2)
	_place_soft_block_cluster(5, 10, 3, 2)
	_place_soft_block_cluster(13, 10, 3, 2)
	# Note: central cluster removed to make room for the conveyor loop

	_log("Generated test arena with dimensions %dx%d" % [w, h])


## Checks if a position is on the test arena border.
func _is_border_test(x: int, y: int, w: int, h: int) -> bool:
	return x == 0 or x == w - 1 or y == 0 or y == h - 1


## Checks if a position should have a pillar (less dense than normal).
func _is_pillar_test(x: int, y: int) -> bool:
	# Pillars every 4 tiles instead of 2, and not near edges
	return x % 4 == 0 and y % 4 == 0 and x > 2 and y > 2


## Places a cluster of soft blocks.
func _place_soft_block_cluster(start_x: int, start_y: int, width: int, height: int) -> void:
	for x in range(start_x, start_x + width):
		for y in range(start_y, start_y + height):
			var pos := Vector2i(x, y)
			if _is_in_bounds(pos) and grid[x][y] == CellType.EMPTY:
				_place_soft_block(pos)


## Places all special tiles: holes, ice, and conveyors (including a loop).
func _place_special_tiles() -> void:
	# --- Ice strip (center-left) ---
	_place_ice(Vector2i(5, 7))
	_place_ice(Vector2i(6, 7))
	_place_ice(Vector2i(7, 7))

	# --- Hole strip (center-right) ---
	_place_hole(Vector2i(14, 7))
	_place_hole(Vector2i(15, 7))
	_place_hole(Vector2i(16, 7))

	# --- Individual conveyors: one of each direction ---
	_place_conveyor(Vector2i(3, 5),  Vector2i.UP)
	_place_conveyor(Vector2i(17, 5), Vector2i.DOWN)
	_place_conveyor(Vector2i(10, 2), Vector2i.RIGHT)
	_place_conveyor(Vector2i(10, 12), Vector2i.LEFT)

	# --- Clockwise conveyor loop in the center ---
	# Layout (9,5)→(11,5)→(11,9)→(9,9)→back
	#
	#   → → ↓
	#   ↑   ↓
	#   ↑   ↓
	#   ↑   ↓
	#   ↑ ← ←
	#
	# Top row (going right)
	_place_conveyor(Vector2i(9,  5), Vector2i.RIGHT)
	_place_conveyor(Vector2i(10, 5), Vector2i.RIGHT)
	_place_conveyor(Vector2i(11, 5), Vector2i.DOWN)
	# Right column (going down)
	_place_conveyor(Vector2i(11, 6), Vector2i.DOWN)
	_place_conveyor(Vector2i(11, 7), Vector2i.DOWN)
	_place_conveyor(Vector2i(11, 8), Vector2i.DOWN)
	_place_conveyor(Vector2i(11, 9), Vector2i.LEFT)
	# Bottom row (going left)
	_place_conveyor(Vector2i(10, 9), Vector2i.LEFT)
	_place_conveyor(Vector2i(9,  9), Vector2i.UP)
	# Left column (going up)
	_place_conveyor(Vector2i(9, 8), Vector2i.UP)
	_place_conveyor(Vector2i(9, 7), Vector2i.UP)
	_place_conveyor(Vector2i(9, 6), Vector2i.UP)


# =============================================================================
# PRIVATE - POWERUP SPAWNING
# =============================================================================

## Spawns one of each powerup type in a row for testing.
func _spawn_all_powerups() -> void:
	var powerup_types := [
		Powerup.Type.EXTRA_BOMB,
		Powerup.Type.KICK,
		Powerup.Type.FIRE_RANGE,
		Powerup.Type.SPEED,
		Powerup.Type.THROW,
		Powerup.Type.CURSE_SPEED,
		Powerup.Type.CURSE_INVERT,
		Powerup.Type.CURSE_BOMBS,
	]

	# Spawn powerups in a row near the top
	var start_x := 3
	var y := 2

	for i in range(powerup_types.size()):
		var pos := Vector2i(start_x + i * 2, y)
		if _is_in_bounds(pos) and grid[pos.x][pos.y] == CellType.EMPTY:
			_spawn_specific_powerup(pos, powerup_types[i])

	# Spawn another row near the bottom for player 2
	y = TEST_GRID_HEIGHT - 3
	for i in range(powerup_types.size()):
		var pos := Vector2i(start_x + i * 2, y)
		if _is_in_bounds(pos) and grid[pos.x][pos.y] == CellType.EMPTY:
			_spawn_specific_powerup(pos, powerup_types[i])


## Spawns a specific powerup type at a position.
func _spawn_specific_powerup(pos: Vector2i, powerup_type: Powerup.Type) -> void:
	var powerup: Powerup = PowerupScene.instantiate()
	powerup.setup(pos, powerup_type)
	powerup.collected.connect(_on_powerup_removed.bind(pos))
	powerup.destroyed.connect(_on_powerup_removed.bind(pos))
	add_child(powerup)
	powerups[pos] = powerup
	grid[pos.x][pos.y] = CellType.POWERUP
	_log("Spawned %s at %s" % [powerup.get_type_name(), pos])
