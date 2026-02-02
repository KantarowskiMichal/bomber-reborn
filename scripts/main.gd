extends Node2D
## Main game controller. Manages players, game state, and win conditions.
##
## This is the root node for the game scene. It handles:
## - Player initialization and setup
## - Connecting player signals for bomb placement and death
## - Tracking active bombs per player
## - Detecting game over conditions
## - Displaying win/draw messages
## - Scene restart on player input

# =============================================================================
# CONSTANTS
# =============================================================================

const LOG_TAG := "Main"

# =============================================================================
# STATE
# =============================================================================

## All registered players in the game
var players: Array[Player] = []

## Whether the game has ended (a player died)
var game_over := false

## The winning player (null if draw)
var _winner: Player = null

@onready var _arena: Arena = $Arena
@onready var _player1: Player = $Player1
@onready var _player2: Player = $Player2
@onready var _win_label: Label = $CanvasLayer/WinLabel

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_log("Game starting...")

	# Initialize both players
	_setup_player(_player1, Player.PlayerNumber.PLAYER_1, 0)
	_setup_player(_player2, Player.PlayerNumber.PLAYER_2, 1)

	# Hide win message until game ends
	_win_label.visible = false

	_log("Game initialized with %d players" % players.size())


func _process(_delta: float) -> void:
	# Allow restarting the game after game over
	if game_over and Input.is_action_just_pressed("ui_accept"):
		_log("Restarting game...")
		get_tree().reload_current_scene()


# =============================================================================
# PRIVATE - SETUP
# =============================================================================

## Configures a player with their number, color, and spawn position.
## Connects all necessary signals for gameplay.
## @param player The player node to set up
## @param number The player's identifier (PLAYER_1 or PLAYER_2)
## @param spawn_index Index for spawn position selection (0-3)
func _setup_player(player: Player, number: Player.PlayerNumber, spawn_index: int) -> void:
	var player_id := GameConstants.get_player_id(number)
	var color: Color = GameConstants.PLAYER_COLORS.get(player_id, Color.WHITE)

	# Configure player properties
	player.player_number = number
	player.set_color(color)
	player.position = _arena.get_player_spawn_position(spawn_index)
	player.arena = _arena

	# Connect gameplay signals
	player.bomb_placed.connect(_on_player_bomb_placed.bind(player))
	player.died.connect(_on_player_died)

	# Register with arena for collision queries
	_arena.register_player(player)
	players.append(player)

	_log("Player %d (%s) initialized at spawn %d" % [player_id, player.get_color_name(), spawn_index])


# =============================================================================
# PRIVATE - SIGNAL HANDLERS
# =============================================================================

## Called when a player places a bomb.
## Creates the bomb in the arena and tracks it for the player.
## @param grid_pos Position where the bomb was placed
## @param player The player who placed the bomb
func _on_player_bomb_placed(grid_pos: Vector2i, player: Player) -> void:
	_log("Player %d placed bomb at %s" % [GameConstants.get_player_id(player.player_number), grid_pos], GameConstants.LogLevel.DEBUG)

	# Darken the player's color for the bomb
	var bomb_color := player.player_color.darkened(0.3)
	_arena.place_bomb(grid_pos, player.bomb_range, bomb_color)
	player.increment_bomb_count()

	# Connect bomb explosion to decrement player's bomb count when it explodes
	var bomb: Bomb = _arena.bombs.get(grid_pos)
	if bomb:
		bomb.exploded.connect(_on_bomb_exploded_for_player.bind(player))


## Called when a bomb placed by a specific player explodes.
## Decrements that player's active bomb count.
## @param _pos Position of the explosion (unused)
## @param _range Explosion range (unused)
## @param player The player who placed the bomb
func _on_bomb_exploded_for_player(_pos: Vector2i, _range: int, player: Player) -> void:
	if is_instance_valid(player):
		player.on_bomb_exploded()


## Called when any player dies.
## Triggers game over and determines the winner.
## @param dead_player The player who died
func _on_player_died(dead_player: Player) -> void:
	if game_over:
		return

	_log("Player %d (%s) died!" % [GameConstants.get_player_id(dead_player.player_number), dead_player.get_color_name()])

	game_over = true
	_winner = _find_surviving_player(dead_player)
	_show_game_over_message()


# =============================================================================
# PRIVATE - GAME OVER
# =============================================================================

## Finds a surviving player (if any) after a player dies.
## @param dead_player The player who just died
## @return The surviving player, or null if none (draw)
func _find_surviving_player(dead_player: Player) -> Player:
	for player in players:
		if player != dead_player and player.is_alive:
			return player
	return null


## Displays the game over message with winner info.
func _show_game_over_message() -> void:
	var message: String

	if _winner:
		message = "%s Player wins!" % _winner.get_color_name()
		_log("Game over - %s Player wins!" % _winner.get_color_name())
	else:
		message = "Draw!"
		_log("Game over - Draw!")

	_win_label.text = message + "\n\nPress Space to restart"
	_win_label.visible = true


# =============================================================================
# PRIVATE - LOGGING
# =============================================================================

## Logs a message with the Main tag.
func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(LOG_TAG, message, level)
