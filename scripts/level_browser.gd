extends Node2D
## Level browser with two tabs: preset levels (play/copy) and user levels (play/edit/copy/delete).
## Entry point for all level management outside the editor itself.

# =============================================================================
# PRESET LEVEL REGISTRY
# =============================================================================

const PRESET_LEVELS: Array[Dictionary] = [
	{ "name": "Classic",    "path": "res://levels/classic.json"    },
	{ "name": "Open Arena", "path": "res://levels/open_arena.json" },
	{ "name": "Ice Rink",   "path": "res://levels/ice_rink.json"   },
]

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	_build_ui()


# =============================================================================
# UI BUILDING
# =============================================================================

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	canvas.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Levels"
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	# --- Preset Levels tab ---
	var preset_scroll := ScrollContainer.new()
	preset_scroll.name = "Preset Levels"
	preset_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(preset_scroll)

	var preset_list := VBoxContainer.new()
	preset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_list.add_theme_constant_override("separation", 6)
	preset_list.add_theme_constant_override("margin_top", 8)
	preset_scroll.add_child(preset_list)

	for entry: Dictionary in PRESET_LEVELS:
		_add_level_row(preset_list, entry["name"], entry["path"], true)

	# --- My Levels tab ---
	var custom_outer := VBoxContainer.new()
	custom_outer.name = "My Levels"
	custom_outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_outer.add_theme_constant_override("separation", 6)
	tabs.add_child(custom_outer)

	var custom_scroll := ScrollContainer.new()
	custom_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_outer.add_child(custom_scroll)

	var custom_list := VBoxContainer.new()
	custom_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_list.add_theme_constant_override("separation", 6)
	custom_scroll.add_child(custom_list)

	var user_levels := _get_user_levels()
	if user_levels.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No custom levels yet. Create one below!"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		custom_list.add_child(empty_lbl)
	else:
		for entry: Dictionary in user_levels:
			_add_level_row(custom_list, entry["name"], entry["path"], false)

	var new_btn := Button.new()
	new_btn.text = "+ New Level"
	new_btn.add_theme_font_size_override("font_size", 16)
	new_btn.pressed.connect(_show_new_level_dialog)
	custom_outer.add_child(new_btn)

	# --- Back button ---
	var back_btn := Button.new()
	back_btn.text = "Back to Menu"
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.pressed.connect(_on_back_pressed)
	outer.add_child(back_btn)


func _add_level_row(parent: VBoxContainer, level_name: String, path: String, is_preset: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	# Active indicator
	if path == GameConstants.CUSTOM_LEVEL_PATH:
		var dot := Label.new()
		dot.text = "▶"
		dot.add_theme_font_size_override("font_size", 14)
		row.add_child(dot)

	var name_lbl := Label.new()
	name_lbl.text = level_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 16)
	row.add_child(name_lbl)

	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.pressed.connect(_on_play.bind(path))
	row.add_child(play_btn)

	if not is_preset:
		var edit_btn := Button.new()
		edit_btn.text = "Edit"
		edit_btn.pressed.connect(_on_edit.bind(path))
		row.add_child(edit_btn)

	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.pressed.connect(_on_copy.bind(path))
	row.add_child(copy_btn)

	if not is_preset:
		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.modulate = Color(1.0, 0.5, 0.5)
		del_btn.pressed.connect(_on_delete.bind(path, level_name))
		row.add_child(del_btn)

	# Separator line
	var sep := HSeparator.new()
	parent.add_child(sep)


# =============================================================================
# USER LEVEL LISTING
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
			var path := GameConstants.LEVELS_DIR + "/" + fname
			result.append({ "name": fname.get_basename(), "path": path })
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["name"] < b["name"]
	)
	return result


# =============================================================================
# ACTIONS
# =============================================================================

func _on_play(path: String) -> void:
	GameConstants.CUSTOM_LEVEL_PATH = path
	GameConstants.save_settings()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_edit(path: String) -> void:
	GameConstants.EDITOR_LOAD_PATH = path
	get_tree().change_scene_to_file("res://scenes/level_editor.tscn")


func _on_copy(path: String) -> void:
	# Open editor with source loaded but name field blank (user must save under new name)
	GameConstants.EDITOR_LOAD_PATH = "__copy__" + path
	get_tree().change_scene_to_file("res://scenes/level_editor.tscn")


func _on_delete(path: String, level_name: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Level"
	dialog.dialog_text = "Delete \"%s\"? This cannot be undone." % level_name
	dialog.get_ok_button().text = "Delete"
	dialog.confirmed.connect(_do_delete.bind(path))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _do_delete(path: String) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir:
		dir.remove(path.get_file())
	if GameConstants.CUSTOM_LEVEL_PATH == path:
		GameConstants.CUSTOM_LEVEL_PATH = ""
		GameConstants.save_settings()
	get_tree().reload_current_scene()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


# =============================================================================
# NEW LEVEL DIALOG
# =============================================================================

func _show_new_level_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Create New Level"
	dialog.get_ok_button().visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	dialog.add_child(vbox)

	# Start blank
	var blank_btn := Button.new()
	blank_btn.text = "Start Blank (13×11)"
	blank_btn.add_theme_font_size_override("font_size", 15)
	blank_btn.pressed.connect(func() -> void:
		dialog.queue_free()
		_open_editor_blank()
	)
	vbox.add_child(blank_btn)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# Copy from preset
	var preset_lbl := Label.new()
	preset_lbl.text = "Copy from Preset:"
	vbox.add_child(preset_lbl)

	for entry: Dictionary in PRESET_LEVELS:
		var path: String = entry["path"]
		var name: String = entry["name"]
		var btn := Button.new()
		btn.text = name
		btn.pressed.connect(func() -> void:
			dialog.queue_free()
			_on_copy(path)
		)
		vbox.add_child(btn)

	# Copy from user level (if any exist)
	var user_levels := _get_user_levels()
	if not user_levels.is_empty():
		var sep2 := HSeparator.new()
		vbox.add_child(sep2)

		var custom_lbl := Label.new()
		custom_lbl.text = "Copy from My Level:"
		vbox.add_child(custom_lbl)

		for entry: Dictionary in user_levels:
			var path: String = entry["path"]
			var name: String = entry["name"]
			var btn := Button.new()
			btn.text = name
			btn.pressed.connect(func() -> void:
				dialog.queue_free()
				_on_copy(path)
			)
			vbox.add_child(btn)

	var sep3 := HSeparator.new()
	vbox.add_child(sep3)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(dialog.queue_free)
	vbox.add_child(cancel_btn)

	add_child(dialog)
	dialog.popup_centered(Vector2(320, 0))


func _open_editor_blank() -> void:
	GameConstants.EDITOR_LOAD_PATH = ""
	get_tree().change_scene_to_file("res://scenes/level_editor.tscn")
