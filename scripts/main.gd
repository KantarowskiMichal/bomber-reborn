extends Node2D
## Main game controller. Manages players, game state, win conditions, and
## the multi-level match system.

# =============================================================================
# CONSTANTS
# =============================================================================

const LOG_TAG := "Main"
## Seconds before auto-advancing to the next round.
const AUTO_ADVANCE_DELAY := 4.0

# =============================================================================
# STATE
# =============================================================================

var players: Array[Player] = []
var game_over := false
var _winner: Player = null

## True while the pause overlay is visible and the scene tree is paused.
var _paused := false
## True while a round-result or match-winner overlay is on screen.
var _showing_result := false

## Reference to the running auto-advance Timer (so Continue can cancel it).
var _advance_timer: Timer = null

# UI layers (built in code)
var _score_hud_layer: CanvasLayer = null
var _pause_layer: CanvasLayer = null

## Label references inside the score HUD; key = int(PlayerNumber).
var _score_labels: Dictionary = {}
var _level_label: Label = null

@onready var _arena: Arena = $Arena
@onready var _player1: Player = $Player1
@onready var _player2: Player = $Player2
@onready var _win_label: Label = $CanvasLayer/WinLabel
@onready var _camera: Camera2D = $Camera2D

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Receive input / process callbacks even while the tree is paused
	# (needed for the pause and result overlays).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_setup_player(_player1, Player.PlayerNumber.PLAYER_1, 0)
	_setup_player(_player2, Player.PlayerNumber.PLAYER_2, 1)

	_win_label.visible = false

	_camera.position = Vector2(
		GameConstants.GRID_WIDTH * GameConstants.TILE_SIZE * 0.5,
		GameConstants.GRID_HEIGHT * GameConstants.TILE_SIZE * 0.5
	)

	if GameConstants.MATCH_ACTIVE:
		_build_score_hud()

	_build_pause_menu()

	_log("Game initialized with %d players" % players.size())


func _process(_delta: float) -> void:
	# In non-match quick-play, space restarts after game over.
	if game_over and not GameConstants.MATCH_ACTIVE and not _showing_result and not _paused:
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _showing_result:
		_toggle_pause()


# =============================================================================
# PLAYER SETUP
# =============================================================================

func _setup_player(player: Player, number: Player.PlayerNumber, spawn_index: int) -> void:
	var player_id := GameConstants.get_player_id(number)
	var color: Color = GameConstants.PLAYER_COLORS.get(player_id, Color.WHITE)

	player.player_number = number
	player.set_color(color)
	player.position = _arena.get_player_spawn_position(spawn_index)
	player.arena = _arena
	player.max_bombs = GameConstants.STARTING_MAX_BOMBS
	player.bomb_range = GameConstants.STARTING_BOMB_RANGE
	player.has_kick = GameConstants.STARTING_HAS_KICK
	player.has_throw = GameConstants.STARTING_HAS_THROW

	player.bomb_placed.connect(_on_player_bomb_placed.bind(player))
	player.died.connect(_on_player_died)

	_arena.register_player(player)
	players.append(player)

	_log("Player %d (%s) initialized at spawn %d" % [player_id, player.get_color_name(), spawn_index])


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_player_bomb_placed(grid_pos: Vector2i, player: Player) -> void:
	var bomb_color := player.player_color.darkened(0.3)
	_arena.place_bomb(grid_pos, player.bomb_range, bomb_color)
	player.increment_bomb_count()

	var bomb: Bomb = _arena.bombs.get(grid_pos)
	if bomb:
		bomb.exploded.connect(_on_bomb_exploded_for_player.bind(player))


func _on_bomb_exploded_for_player(_pos: Vector2i, _range: int, player: Player) -> void:
	if is_instance_valid(player):
		player.on_bomb_exploded()


func _on_player_died(dead_player: Player) -> void:
	if game_over:
		return

	_log("Player %d (%s) died!" % [
		GameConstants.get_player_id(dead_player.player_number),
		dead_player.get_color_name()])

	game_over = true
	_winner = _find_surviving_player(dead_player)

	if GameConstants.MATCH_ACTIVE:
		_handle_match_round_end()
	else:
		_show_quick_game_over()


func _find_surviving_player(dead_player: Player) -> Player:
	for player in players:
		if player != dead_player and player.is_alive:
			return player
	return null


# =============================================================================
# QUICK-GAME (non-match) OVER
# =============================================================================

func _show_quick_game_over() -> void:
	var msg: String
	if _winner:
		msg = "%s Player wins!\n\nPress Space to restart" % _winner.get_color_name()
		_log("Game over — %s Player wins!" % _winner.get_color_name())
	else:
		msg = "Draw!\n\nPress Space to restart"
		_log("Game over — Draw!")

	_win_label.text = msg
	_win_label.visible = true


# =============================================================================
# MATCH FLOW
# =============================================================================

func _handle_match_round_end() -> void:
	# Award point to the winner (if not a draw)
	if _winner:
		var pnum := int(_winner.player_number)
		GameConstants.MATCH_SCORES[pnum] = GameConstants.MATCH_SCORES.get(pnum, 0) + 1
		_update_score_hud()

		if GameConstants.MATCH_SCORES[pnum] >= GameConstants.MATCH_WINS_NEEDED:
			_show_result_overlay(true)
			return

	# Advance to next level (wrap + optional re-shuffle)
	GameConstants.MATCH_CURRENT_INDEX = (GameConstants.MATCH_CURRENT_INDEX + 1) \
			% GameConstants.MATCH_LEVELS.size()
	if GameConstants.MATCH_CURRENT_INDEX == 0 and GameConstants.MATCH_SHUFFLED:
		GameConstants.MATCH_LEVELS.shuffle()

	_show_result_overlay(false)


func _advance_to_next_level() -> void:
	_showing_result = false
	get_tree().paused = false
	GameConstants.CUSTOM_LEVEL_PATH = \
			GameConstants.MATCH_LEVELS[GameConstants.MATCH_CURRENT_INDEX]
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _get_current_level_name() -> String:
	var path := GameConstants.CUSTOM_LEVEL_PATH
	if path == "":
		return "Procedural"
	return path.get_file().get_basename()


# =============================================================================
# SCORE HUD (match mode only)
# =============================================================================

func _build_score_hud() -> void:
	_score_hud_layer = CanvasLayer.new()
	_score_hud_layer.layer = 5
	add_child(_score_hud_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.offset_bottom = 38
	_score_hud_layer.add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hbox.offset_bottom = 38
	hbox.add_theme_constant_override("separation", 8)
	_score_hud_layer.add_child(hbox)

	# Left: Player 1 score
	var p1_lbl := Label.new()
	p1_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_lbl.add_theme_font_size_override("font_size", 18)
	p1_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hbox.add_child(p1_lbl)
	_score_labels[int(Player.PlayerNumber.PLAYER_1)] = p1_lbl

	# Centre: level name + index
	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 12)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(_level_label)

	# Right: Player 2 score
	var p2_lbl := Label.new()
	p2_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2_lbl.add_theme_font_size_override("font_size", 18)
	p2_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(p2_lbl)
	_score_labels[int(Player.PlayerNumber.PLAYER_2)] = p2_lbl

	_update_score_hud()


func _update_score_hud() -> void:
	for player in players:
		var pnum := int(player.player_number)
		if _score_labels.has(pnum):
			var wins: int = GameConstants.MATCH_SCORES.get(pnum, 0)
			var needed: int = GameConstants.MATCH_WINS_NEEDED
			var lbl: Label = _score_labels[pnum]
			lbl.text = "%s  %d / %d" % [player.get_color_name(), wins, needed]
			lbl.modulate = player.player_color

	if _level_label:
		var total := GameConstants.MATCH_LEVELS.size()
		var idx := GameConstants.MATCH_CURRENT_INDEX + 1
		_level_label.text = "%s\n%d of %d" % [_get_current_level_name(), idx, total]


# =============================================================================
# RESULT OVERLAY (round over / match over)
# =============================================================================

func _show_result_overlay(is_match_over: bool) -> void:
	_showing_result = true
	get_tree().paused = true

	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	# Dim background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	layer.add_child(bg)

	# Centred content box
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 14)
	layer.add_child(vbox)

	# Heading
	var heading := Label.new()
	heading.add_theme_font_size_override("font_size", 30)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(heading)

	# Winner line
	var winner_lbl := Label.new()
	winner_lbl.add_theme_font_size_override("font_size", 20)
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(winner_lbl)

	if is_match_over:
		heading.text = "Match Over!"
		if _winner:
			winner_lbl.text = "%s Player wins the match!" % _winner.get_color_name()
			winner_lbl.modulate = _winner.player_color
		else:
			winner_lbl.text = "It's a Draw!"
	else:
		heading.text = "Round Over!"
		if _winner:
			winner_lbl.text = "%s Player wins this round!" % _winner.get_color_name()
			winner_lbl.modulate = _winner.player_color
		else:
			winner_lbl.text = "Draw — no points awarded"

	# Score table
	vbox.add_child(HSeparator.new())
	var score_title := Label.new()
	score_title.text = "Final Score:" if is_match_over else "Score:"
	score_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(score_title)

	for player in players:
		var pnum := int(player.player_number)
		var wins: int = GameConstants.MATCH_SCORES.get(pnum, 0)
		var score_lbl := Label.new()
		score_lbl.text = "%s: %d" % [player.get_color_name(), wins]
		score_lbl.add_theme_font_size_override("font_size", 18)
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_lbl.modulate = player.player_color
		vbox.add_child(score_lbl)

	vbox.add_child(HSeparator.new())

	if is_match_over:
		var menu_btn := _overlay_button("Back to Menu")
		menu_btn.pressed.connect(func() -> void:
			get_tree().paused = false
			GameConstants.MATCH_ACTIVE = false
			GameConstants.MATCH_SCORES.clear()
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		)
		vbox.add_child(menu_btn)
	else:
		var continue_btn := _overlay_button(
				"Continue  (auto in %ds)" % int(AUTO_ADVANCE_DELAY))
		continue_btn.pressed.connect(func() -> void:
			if _advance_timer:
				_advance_timer.stop()
				_advance_timer = null
			_advance_to_next_level()
		)
		vbox.add_child(continue_btn)

		# Countdown label under the button
		var cd_lbl := Label.new()
		cd_lbl.add_theme_font_size_override("font_size", 12)
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.process_mode = Node.PROCESS_MODE_ALWAYS
		vbox.add_child(cd_lbl)

		# Auto-advance timer
		_advance_timer = Timer.new()
		_advance_timer.wait_time = AUTO_ADVANCE_DELAY
		_advance_timer.one_shot = true
		_advance_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_advance_timer.timeout.connect(_advance_to_next_level)
		layer.add_child(_advance_timer)
		_advance_timer.start()

		# Update button text each second via a repeating timer
		var tick := Timer.new()
		tick.wait_time = 0.25
		tick.autostart = true
		tick.process_mode = Node.PROCESS_MODE_ALWAYS
		tick.timeout.connect(func() -> void:
			if not is_instance_valid(_advance_timer):
				return
			var secs := ceili(_advance_timer.time_left)
			continue_btn.text = "Continue  (auto in %ds)" % secs
		)
		layer.add_child(tick)


## Creates a Button suitable for use inside a paused-tree overlay.
func _overlay_button(label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 18)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	return btn


# =============================================================================
# PAUSE MENU
# =============================================================================

func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 20
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.visible = false
	add_child(_pause_layer)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.70)
	_pause_layer.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 20)
	vbox.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.process_mode = Node.PROCESS_MODE_ALWAYS
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.add_theme_font_size_override("font_size", 22)
	resume_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	resume_btn.pressed.connect(_toggle_pause)
	vbox.add_child(resume_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Back to Main Menu"
	menu_btn.add_theme_font_size_override("font_size", 22)
	menu_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_btn.pressed.connect(_on_quit_to_menu)
	vbox.add_child(menu_btn)


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_layer.visible = _paused
	get_tree().paused = _paused


func _on_quit_to_menu() -> void:
	get_tree().paused = false
	GameConstants.MATCH_ACTIVE = false
	GameConstants.MATCH_SCORES.clear()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


# =============================================================================
# LOGGING
# =============================================================================

func _log(message: String, level: GameConstants.LogLevel = GameConstants.LogLevel.INFO) -> void:
	GameConstants.log_message(LOG_TAG, message, level)
