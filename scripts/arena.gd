extends Node2D
class_name Arena
## Manages the game arena grid, blocks, bombs, and explosions.
##
## The Arena is responsible for:
## - Generating the initial level layout with hard/soft blocks
## - Tracking the grid state (what's in each cell)
## - Spawning and managing bombs, explosions, and power-ups
## - Providing pathfinding queries for players and bombs
##
## Grid coordinates use (x, y) where x is column and y is row.
## (0, 0) is the top-left corner of the arena.

# =============================================================================
# CONSTANTS
# =============================================================================

## Log tag for this class
const LOG_TAG := "Arena"

## Cardinal directions for explosion spread and movement checks
const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT,
]

## Types of content that can occupy a grid cell
enum CellType {
	EMPTY,       ## Walkable empty space
	HARD_BLOCK,  ## Indestructible wall
	SOFT_BLOCK,  ## Destructible block (may drop power-up)
	BOMB,        ## Active bomb
	POWERUP,     ## Collectible power-up
}

# =============================================================================
# PRELOADED SCENES
# =============================================================================

const HardBlockScene := preload("res://scenes/hard_block.tscn")
const SoftBlockScene := preload("res://scenes/soft_block.tscn")
const BombScene := preload("res://scenes/bomb.tscn")
const ExplosionScene := preload("res://scenes/explosion.tscn")
const PowerupScene := preload("res://scenes/powerup.tscn")

# =============================================================================
# STATE
# =============================================================================

## 2D grid storing CellType for each position. Access as grid[x][y].
var grid: Array[Array] = []

## Active bombs indexed by their grid position
var bombs: Dictionary = {}  # Vector2i -> Bomb

## Active power-ups indexed by their grid position
var powerups: Dictionary = {}  # Vector2i -> Powerup

## Registered players for collision queries
var players: Array[Player] = []

## Protected spawn positions where soft blocks won't generate
var spawn_zones: Array[Vector2i] = []

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_log("Initializing arena (%dx%d grid)" % [GameConstants.GRID_WIDTH, GameConstants.GRID_HEIGHT])
	_compute_spawn_zones()
	_generate_arena()
	_log("Arena generation complete")


# =============================================================================
# PUBLIC API
# =============================================================================

## Registers a player with the arena for collision queries.
## @param player The player to register
func register_player(player: Player) -> void:
	if player not in players:
		players.append(player)
		_log("Registered player %d" % GameConstants.get_player_id(player.player_number))


## Returns the world position for a player's spawn point.
## Players spawn in corners: P1=top-left, P2=bottom-right, etc.
## @param player_index Zero-based index of the player (0, 1, 2, 3)
## @return World position (center of spawn tile)
func get_player_spawn_position(player_index: int) -> Vector2:
	var w := GameConstants.GRID_WIDTH
	var h := GameConstants.GRID_HEIGHT

	# Spawn positions in each corner of the arena
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


## Checks if a tile can be walked on by a player.
## @param pos Grid position to check
## @return True if the tile is empty or contains only a power-up
func is_tile_walkable(pos: Vector2i) -> bool:
	if not _is_in_bounds(pos):
		return false
	var cell: int = grid[pos.x][pos.y]
	return cell == CellType.EMPTY or cell == CellType.POWERUP


## Checks if a bomb can be placed at the given position.
## @param pos Grid position to check
## @return True if the position is empty and has no existing bomb
func can_place_bomb(pos: Vector2i) -> bool:
	return _is_in_bounds(pos) and grid[pos.x][pos.y] == CellType.EMPTY and not bombs.has(pos)


## Checks if there is an active bomb at the given position.
## @param pos Grid position to check
## @return True if a bomb exists at the position
func has_bomb_at(pos: Vector2i) -> bool:
	return bombs.has(pos)


## Places a new bomb at the specified grid position.
## @param pos Grid position where the bomb will be placed
## @param explosion_range How many tiles the explosion will spread in each direction
func place_bomb(pos: Vector2i, explosion_range: int) -> void:
	if not can_place_bomb(pos):
		_log("Cannot place bomb at %s - position blocked" % pos, GameConstants.LogLevel.WARNING)
		return

	var bomb: Bomb = BombScene.instantiate()
	bomb.setup(pos, explosion_range)
	bomb.exploded.connect(_on_bomb_exploded)
	add_child(bomb)
	bombs[pos] = bomb
	grid[pos.x][pos.y] = CellType.BOMB
	_log("Bomb placed at %s (range: %d)" % [pos, explosion_range])


## Initiates a kick on a bomb, sending it moving in the specified direction.
## @param pos Current grid position of the bomb to kick
## @param direction Direction vector to kick the bomb (e.g., Vector2i.RIGHT)
func kick_bomb(pos: Vector2i, direction: Vector2i) -> void:
	if not bombs.has(pos):
		_log("No bomb to kick at %s" % pos, GameConstants.LogLevel.WARNING)
		return

	var bomb: Bomb = bombs[pos]

	# Connect movement tracking if not already connected
	if not bomb.moved.is_connected(_on_bomb_moved):
		bomb.moved.connect(_on_bomb_moved.bind(bomb))

	bomb.start_moving(direction, self)
	_log("Bomb at %s kicked in direction %s" % [pos, direction])


## Checks if a kicked bomb can move to the specified position.
## Bombs can move through empty tiles and power-ups, but not through
## blocks, other bombs, or players.
## @param pos Grid position to check
## @return True if the bomb can move to this position
func can_bomb_move_to(pos: Vector2i) -> bool:
	if not _is_in_bounds(pos):
		return false

	var cell: int = grid[pos.x][pos.y]

	# Bombs can only move through empty cells and power-ups
	if cell != CellType.EMPTY and cell != CellType.POWERUP:
		return false

	# Cannot move into a player
	return not _has_player_at(pos)


## Returns the cell type at the given position.
## @param pos Grid position to check
## @return CellType at the position, or HARD_BLOCK if out of bounds
func get_cell_type(pos: Vector2i) -> CellType:
	if not _is_in_bounds(pos):
		return CellType.HARD_BLOCK
	return grid[pos.x][pos.y] as CellType


## Checks if a position is within the arena bounds.
## @param pos Grid position to check
## @return True if the position is valid
func is_in_bounds(pos: Vector2i) -> bool:
	return _is_in_bounds(pos)


## Initiates a throw on a bomb, sending it flying in the specified direction.
## @param pos Current grid position of the bomb to throw
## @param direction Direction vector to throw the bomb (e.g., Vector2i.RIGHT)
func throw_bomb(pos: Vector2i, direction: Vector2i) -> void:
	if not bombs.has(pos):
		_log("No bomb to throw at %s" % pos, GameConstants.LogLevel.WARNING)
		return

	var bomb: Bomb = bombs[pos]

	# Clear the bomb from its current position in the grid
	if _is_in_bounds(pos):
		grid[pos.x][pos.y] = CellType.EMPTY
	bombs.erase(pos)

	# Connect movement tracking if not already connected
	if not bomb.moved.is_connected(_on_bomb_moved):
		bomb.moved.connect(_on_bomb_moved.bind(bomb))

	bomb.start_flying(direction, self)
	_log("Bomb at %s thrown in direction %s" % [pos, direction])


## Called when a thrown bomb lands at a position.
## Registers the bomb in the grid and tracking dictionary.
## @param pos Grid position where the bomb landed
## @param bomb The bomb that landed
func on_bomb_landed(pos: Vector2i, bomb: Bomb) -> void:
	if _is_in_bounds(pos):
		grid[pos.x][pos.y] = CellType.BOMB
	bombs[pos] = bomb
	_log("Bomb landed at %s" % pos, GameConstants.LogLevel.DEBUG)


# =============================================================================
# PRIVATE - ARENA GENERATION
# =============================================================================

## Calculates protected spawn zones where soft blocks won't generate.
## Each corner gets an L-shaped area of 3 tiles to give players room to move.
func _compute_spawn_zones() -> void:
	spawn_zones.clear()
	var w := GameConstants.GRID_WIDTH
	var h := GameConstants.GRID_HEIGHT

	# Each corner has 3 protected tiles in an L-shape pattern
	# This ensures players have room to move and place their first bomb
	var corners := [
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],              # Top-left
		[Vector2i(w-2, 1), Vector2i(w-3, 1), Vector2i(w-2, 2)],        # Top-right
		[Vector2i(1, h-2), Vector2i(2, h-2), Vector2i(1, h-3)],        # Bottom-left
		[Vector2i(w-2, h-2), Vector2i(w-3, h-2), Vector2i(w-2, h-3)],  # Bottom-right
	]

	for corner in corners:
		for pos in corner:
			spawn_zones.append(pos)

	_log("Computed %d spawn zone tiles" % spawn_zones.size(), GameConstants.LogLevel.DEBUG)


## Generates the arena layout with hard blocks, soft blocks, and empty spaces.
## Layout follows classic Bomberman pattern:
## - Border of hard blocks around the edge
## - Hard block pillars at every even (x, y) coordinate
## - Random soft blocks filling remaining space (except spawn zones)
func _generate_arena() -> void:
	grid.clear()
	var w := GameConstants.GRID_WIDTH
	var h := GameConstants.GRID_HEIGHT
	var soft_block_count := 0

	# Initialize empty grid - each column is an array of cell types
	for x in range(w):
		var column: Array[int] = []
		column.resize(h)
		column.fill(CellType.EMPTY)
		grid.append(column)

	# Place blocks according to the level pattern
	for x in range(w):
		for y in range(h):
			var pos := Vector2i(x, y)

			if _is_border(x, y, w, h):
				# Outer walls are always hard blocks
				_place_hard_block(pos)
			elif _is_pillar(x, y):
				# Interior pillars at even coordinates
				_place_hard_block(pos)
			elif pos in spawn_zones:
				# Keep spawn areas clear for players
				continue
			elif randf() < GameConstants.SOFT_BLOCK_SPAWN_CHANCE:
				_place_soft_block(pos)
				soft_block_count += 1

	_log("Generated arena with %d soft blocks" % soft_block_count)


## Checks if a position is on the arena border.
func _is_border(x: int, y: int, w: int, h: int) -> bool:
	return x == 0 or x == w - 1 or y == 0 or y == h - 1


## Checks if a position should have a pillar (hard block at even coordinates).
func _is_pillar(x: int, y: int) -> bool:
	return x % 2 == 0 and y % 2 == 0


## Validates that a grid position is within arena bounds.
func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GameConstants.GRID_WIDTH \
		and pos.y >= 0 and pos.y < GameConstants.GRID_HEIGHT


# =============================================================================
# PRIVATE - BLOCK MANAGEMENT
# =============================================================================

## Instantiates and places a hard (indestructible) block.
func _place_hard_block(pos: Vector2i) -> void:
	var block := HardBlockScene.instantiate()
	block.position = GameConstants.grid_to_world_corner(pos)
	add_child(block)
	grid[pos.x][pos.y] = CellType.HARD_BLOCK


## Instantiates and places a soft (destructible) block.
func _place_soft_block(pos: Vector2i) -> void:
	var block: SoftBlock = SoftBlockScene.instantiate()
	block.position = GameConstants.grid_to_world_corner(pos)
	block.destroyed.connect(_on_soft_block_destroyed)
	add_child(block)
	grid[pos.x][pos.y] = CellType.SOFT_BLOCK


## Called when a soft block is destroyed by an explosion.
## Clears the grid cell and potentially spawns a power-up.
func _on_soft_block_destroyed(pos: Vector2i) -> void:
	grid[pos.x][pos.y] = CellType.EMPTY
	_log("Soft block destroyed at %s" % pos, GameConstants.LogLevel.DEBUG)

	# Roll for power-up drop
	if randf() < GameConstants.POWERUP_DROP_CHANCE:
		_spawn_powerup(pos)


# =============================================================================
# PRIVATE - POWERUP MANAGEMENT
# =============================================================================

## Spawns a random power-up at the specified position.
## Type is determined by cumulative weighted random selection.
func _spawn_powerup(pos: Vector2i) -> void:
	var powerup: Powerup = PowerupScene.instantiate()

	# Select random power-up type based on cumulative weights
	var roll := randf()
	var powerup_type: Powerup.Type

	var cumulative := 0.0

	# Positive powerups
	cumulative += GameConstants.POWERUP_EXTRA_BOMB_WEIGHT
	if roll < cumulative:
		powerup_type = Powerup.Type.EXTRA_BOMB
	else:
		cumulative += GameConstants.POWERUP_FIRE_RANGE_WEIGHT
		if roll < cumulative:
			powerup_type = Powerup.Type.FIRE_RANGE
		else:
			cumulative += GameConstants.POWERUP_SPEED_WEIGHT
			if roll < cumulative:
				powerup_type = Powerup.Type.SPEED
			else:
				cumulative += GameConstants.POWERUP_THROW_WEIGHT
				if roll < cumulative:
					powerup_type = Powerup.Type.THROW
				else:
					cumulative += GameConstants.POWERUP_KICK_WEIGHT
					if roll < cumulative:
						powerup_type = Powerup.Type.KICK
					# Curses (negative powerups)
					else:
						cumulative += GameConstants.CURSE_SPEED_WEIGHT
						if roll < cumulative:
							powerup_type = Powerup.Type.CURSE_SPEED
						else:
							cumulative += GameConstants.CURSE_INVERT_WEIGHT
							if roll < cumulative:
								powerup_type = Powerup.Type.CURSE_INVERT
							else:
								powerup_type = Powerup.Type.CURSE_BOMBS

	powerup.setup(pos, powerup_type)
	powerup.collected.connect(_on_powerup_removed.bind(pos))
	powerup.destroyed.connect(_on_powerup_removed.bind(pos))
	add_child(powerup)
	powerups[pos] = powerup
	grid[pos.x][pos.y] = CellType.POWERUP
	_log("Spawned %s power-up at %s" % [powerup.get_type_name(), pos])


## Called when a power-up is collected by a player or destroyed.
## Cleans up the tracking dictionary and grid state.
func _on_powerup_removed(pos: Vector2i) -> void:
	powerups.erase(pos)
	if _is_in_bounds(pos) and grid[pos.x][pos.y] == CellType.POWERUP:
		grid[pos.x][pos.y] = CellType.EMPTY
	_log("Power-up removed at %s" % pos, GameConstants.LogLevel.DEBUG)


## Forcibly destroys a power-up at the given position.
## Called during explosion propagation when we know a powerup should be destroyed.
## The powerup's destroyed signal will trigger _on_powerup_removed to clean up tracking.
func _destroy_powerup_at(pos: Vector2i) -> void:
	if not powerups.has(pos):
		return

	powerups[pos].force_destroy()


# =============================================================================
# PRIVATE - BOMB MANAGEMENT
# =============================================================================

## Called when a bomb's fuse expires and it explodes.
## Removes the bomb from tracking and triggers explosion creation.
func _on_bomb_exploded(pos: Vector2i, explosion_range: int) -> void:
	_log("Bomb exploded at %s (range: %d)" % [pos, explosion_range])
	bombs.erase(pos)
	if _is_in_bounds(pos):
		grid[pos.x][pos.y] = CellType.EMPTY
	_create_explosion(pos, explosion_range)


## Called when a kicked bomb moves from one tile to another.
## Updates the grid state and bomb tracking dictionary.
## Flying bombs are ignored - they're airborne and don't affect the grid until landing.
func _on_bomb_moved(old_pos: Vector2i, new_pos: Vector2i, bomb: Bomb) -> void:
	# Flying bombs are airborne - don't register them in the grid
	# They get registered when they land via on_bomb_landed()
	if bomb.is_flying:
		return

	# Clear old position in grid
	if _is_in_bounds(old_pos) and grid[old_pos.x][old_pos.y] == CellType.BOMB:
		grid[old_pos.x][old_pos.y] = CellType.EMPTY

	# Mark new position in grid
	if _is_in_bounds(new_pos):
		grid[new_pos.x][new_pos.y] = CellType.BOMB

	# Update tracking dictionary
	bombs.erase(old_pos)
	bombs[new_pos] = bomb
	_log("Bomb moved from %s to %s" % [old_pos, new_pos], GameConstants.LogLevel.DEBUG)


# =============================================================================
# PRIVATE - EXPLOSION MANAGEMENT
# =============================================================================

## Creates the explosion pattern radiating from the bomb's position.
## Explosion spreads in 4 cardinal directions, stopping when hitting obstacles.
## @param center Grid position where the bomb exploded
## @param explosion_range Number of tiles the explosion reaches in each direction
func _create_explosion(center: Vector2i, explosion_range: int) -> void:
	# Explosion always occurs at the center (bomb's position)
	_spawn_explosion_tile(center)

	# Spread explosion in each cardinal direction
	for dir in DIRECTIONS:
		for i in range(1, explosion_range + 1):
			var pos: Vector2i = center + dir * i

			# Stop if we hit the arena boundary
			if not _is_in_bounds(pos):
				break

			var cell: int = grid[pos.x][pos.y]
			match cell:
				CellType.HARD_BLOCK:
					# Hard blocks stop explosion completely (no damage)
					break
				CellType.SOFT_BLOCK:
					# Soft blocks get destroyed but stop the explosion
					_spawn_explosion_tile(pos)
					break
				CellType.POWERUP:
					# Power-ups get destroyed and explosion continues through
					_destroy_powerup_at(pos)
					_spawn_explosion_tile(pos)
				_:
					# Empty space or bomb - explosion continues
					_spawn_explosion_tile(pos)


## Spawns a single explosion visual/hitbox at the specified position.
func _spawn_explosion_tile(pos: Vector2i) -> void:
	var explosion: Explosion = ExplosionScene.instantiate()
	explosion.setup(pos)
	add_child(explosion)


# =============================================================================
# PRIVATE - PLAYER QUERIES
# =============================================================================

## Checks if any living player occupies the specified grid position.
## Used to prevent bombs from moving into players.
func _has_player_at(pos: Vector2i) -> bool:
	for player in players:
		if player.is_alive and player.grid_pos == pos:
			return true
	return false


# =============================================================================
# PRIVATE - LOGGING
# =============================================================================

## Logs a message with the Arena tag.
func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(LOG_TAG, message, level)
