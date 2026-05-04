extends Node2D
## Match setup screen. Player ticks the levels they want to play, sets win target
## and order, then launches the match.

const PRESET_LEVELS: Array[Dictionary] = [
	{ "name": "Classic",    "path": "res://levels/classic.json"    },
	{ "name": "Open Arena", "path": "res://levels/open_arena.json" },
	{ "name": "Ice Rink",   "path": "res://levels/ice_rink.json"   },
]

## Maps level path (or "" for procedural) to its CheckBox widget.
var _checks: Dictionary = {}
var _shuffle_check: CheckBox
var _wins_spin: SpinBox
var _start_btn: Button

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_build_ui()


# =============================================================================
# UI
# =============================================================================

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	canvas.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Match Setup"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	# Level list ----------------------------------------------------------------
	var list_lbl := Label.new()
	list_lbl.text = "— Select Levels —"
	list_lbl.add_theme_font_size_override("font_size", 15)
	list_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(list_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	_add_level_check(list, "Procedural (random each round)", "")

	list.add_child(HSeparator.new())

	for entry: Dictionary in PRESET_LEVELS:
		_add_level_check(list, entry["name"], entry["path"])

	var user_levels := _get_user_levels()
	if not user_levels.is_empty():
		list.add_child(HSeparator.new())
		for entry: Dictionary in user_levels:
			_add_level_check(list, entry["name"], entry["path"])

	# Select All / None ---------------------------------------------------------
	var sel_row := HBoxContainer.new()
	sel_row.add_theme_constant_override("separation", 8)
	outer.add_child(sel_row)

	var all_btn := Button.new()
	all_btn.text = "Select All"
	all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_btn.pressed.connect(_on_select_all)
	sel_row.add_child(all_btn)

	var none_btn := Button.new()
	none_btn.text = "Select None"
	none_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	none_btn.pressed.connect(_on_select_none)
	sel_row.add_child(none_btn)

	# Match options -------------------------------------------------------------
	var opts_lbl := Label.new()
	opts_lbl.text = "— Match Options —"
	opts_lbl.add_theme_font_size_override("font_size", 15)
	opts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(opts_lbl)

	var shuffle_row := HBoxContainer.new()
	outer.add_child(shuffle_row)
	var shuffle_lbl := Label.new()
	shuffle_lbl.text = "Shuffle level order"
	shuffle_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shuffle_row.add_child(shuffle_lbl)
	_shuffle_check = CheckBox.new()
	_shuffle_check.button_pressed = GameConstants.MATCH_SHUFFLED
	shuffle_row.add_child(_shuffle_check)

	var wins_row := HBoxContainer.new()
	outer.add_child(wins_row)
	var wins_lbl := Label.new()
	wins_lbl.text = "Wins needed to win match"
	wins_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wins_row.add_child(wins_lbl)
	_wins_spin = SpinBox.new()
	_wins_spin.min_value = 1
	_wins_spin.max_value = 20
	_wins_spin.value = GameConstants.MATCH_WINS_NEEDED
	_wins_spin.custom_minimum_size = Vector2(80, 0)
	wins_row.add_child(_wins_spin)

	# Bottom buttons ------------------------------------------------------------
	_start_btn = Button.new()
	_start_btn.text = "Start Match"
	_start_btn.add_theme_font_size_override("font_size", 20)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start_pressed)
	outer.add_child(_start_btn)

	var back_btn := Button.new()
	back_btn.text = "Back to Menu"
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	)
	outer.add_child(back_btn)


func _add_level_check(parent: VBoxContainer, label_text: String, path: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var chk := CheckBox.new()
	chk.toggled.connect(_on_any_toggled)
	row.add_child(chk)

	_checks[path] = chk


# =============================================================================
# HELPERS
# =============================================================================

func _get_user_levels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(GameConstants.LEVELS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			result.append({
				"name": fname.get_basename(),
				"path": GameConstants.LEVELS_DIR + "/" + fname,
			})
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["name"] < b["name"]
	)
	return result


func _selected_paths() -> Array[String]:
	var out: Array[String] = []
	for path: String in _checks:
		if _checks[path].button_pressed:
			out.append(path)
	return out


# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_any_toggled(_pressed: bool) -> void:
	_start_btn.disabled = _selected_paths().is_empty()


func _on_select_all() -> void:
	for path in _checks:
		_checks[path].button_pressed = true


func _on_select_none() -> void:
	for path in _checks:
		_checks[path].button_pressed = false


func _on_start_pressed() -> void:
	var selected := _selected_paths()
	if selected.is_empty():
		return

	var shuffled: bool = _shuffle_check.button_pressed
	if shuffled:
		selected.shuffle()

	GameConstants.MATCH_ACTIVE = true
	GameConstants.MATCH_LEVELS = selected
	GameConstants.MATCH_CURRENT_INDEX = 0
	GameConstants.MATCH_SCORES.clear()
	GameConstants.MATCH_WINS_NEEDED = int(_wins_spin.value)
	GameConstants.MATCH_SHUFFLED = shuffled

	GameConstants.CUSTOM_LEVEL_PATH = GameConstants.MATCH_LEVELS[0]
	get_tree().change_scene_to_file("res://scenes/main.tscn")
