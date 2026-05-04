extends Node2D
## In-game level editor. Lets players design and save custom levels.
## Levels are stored as JSON files in user://levels/.

# =============================================================================
# TILE APPEARANCE
# =============================================================================

const TILE_COLORS: Dictionary = {
	GameConstants.EditorTile.EMPTY:          Color(0.13, 0.13, 0.13),
	GameConstants.EditorTile.HARD_BLOCK:     Color(0.30, 0.30, 0.40),
	GameConstants.EditorTile.SOFT_BLOCK:     Color(0.60, 0.40, 0.20),
	GameConstants.EditorTile.HOLE:           Color(0.04, 0.04, 0.04),
	GameConstants.EditorTile.ICE:            Color(0.60, 0.85, 1.00),
	GameConstants.EditorTile.CONVEYOR_UP:    Color(0.80, 0.60, 0.10),
	GameConstants.EditorTile.CONVEYOR_DOWN:  Color(0.80, 0.60, 0.10),
	GameConstants.EditorTile.CONVEYOR_LEFT:  Color(0.80, 0.60, 0.10),
	GameConstants.EditorTile.CONVEYOR_RIGHT: Color(0.80, 0.60, 0.10),
	GameConstants.EditorTile.SPAWN_1:        Color(0.20, 0.70, 0.30),
	GameConstants.EditorTile.SPAWN_2:        Color(0.30, 0.50, 1.00),
	GameConstants.EditorTile.SPAWN_3:        Color(0.90, 0.30, 0.30),
	GameConstants.EditorTile.SPAWN_4:        Color(0.90, 0.70, 0.10),
}

const TILE_LABELS: Dictionary = {
	GameConstants.EditorTile.EMPTY:          "Empty",
	GameConstants.EditorTile.HARD_BLOCK:     "Hard Block",
	GameConstants.EditorTile.SOFT_BLOCK:     "Soft Block",
	GameConstants.EditorTile.HOLE:           "Hole",
	GameConstants.EditorTile.ICE:            "Ice",
	GameConstants.EditorTile.CONVEYOR_UP:    "Conveyor ↑",
	GameConstants.EditorTile.CONVEYOR_DOWN:  "Conveyor ↓",
	GameConstants.EditorTile.CONVEYOR_LEFT:  "Conveyor ←",
	GameConstants.EditorTile.CONVEYOR_RIGHT: "Conveyor →",
	GameConstants.EditorTile.SPAWN_1:        "Spawn P1",
	GameConstants.EditorTile.SPAWN_2:        "Spawn P2",
	GameConstants.EditorTile.SPAWN_3:        "Spawn P3",
	GameConstants.EditorTile.SPAWN_4:        "Spawn P4",
}

# Fixed tile size in the editor canvas (pixels per cell)
const CELL_SIZE := 40

# =============================================================================
# STATE
# =============================================================================

var _grid: Array[Array] = []   ## _grid[x][y] = EditorTile int
var _grid_width := 13
var _grid_height := 11
var _selected_tile: int = GameConstants.EditorTile.HARD_BLOCK
var _painting := false
var _paint_value: int = GameConstants.EditorTile.HARD_BLOCK  # left-click tile
var _erase_mode := false  # right-click erase

# UI references
var _canvas: Control
var _status: Label
var _name_edit: LineEdit
var _palette_btns: Array[Button] = []
var _width_spin: SpinBox
var _height_spin: SpinBox

# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Consume EDITOR_LOAD_PATH before building UI so it won't linger on scene restart.
	var raw_path := GameConstants.EDITOR_LOAD_PATH
	GameConstants.EDITOR_LOAD_PATH = ""

	var is_copy := raw_path.begins_with("__copy__")
	var load_path := raw_path.trim_prefix("__copy__")

	_init_grid(_grid_width, _grid_height)
	_build_ui()

	if load_path != "":
		_load_level(load_path)
		# Pre-fill name only when editing an existing user level (not copying)
		if not is_copy and load_path.begins_with("user://"):
			_name_edit.text = load_path.get_file().get_basename()
		elif is_copy:
			# Suggest a name so the user knows to rename before saving
			var src_name := load_path.get_file().get_basename()
			_name_edit.placeholder_text = "Copy of %s" % src_name
			_set_status("Copied from \"%s\" — enter a new name and save." % src_name)


# =============================================================================
# GRID MANAGEMENT
# =============================================================================

func _init_grid(w: int, h: int) -> void:
	_grid_width = w
	_grid_height = h
	_grid.clear()
	for x in range(w):
		var col: Array[int] = []
		col.resize(h)
		col.fill(GameConstants.EditorTile.EMPTY)
		_grid.append(col)


func _resize_grid(new_w: int, new_h: int) -> void:
	var old_grid := _grid.duplicate(true)
	var old_w := _grid_width
	var old_h := _grid_height
	_init_grid(new_w, new_h)
	# Copy existing tiles into the new grid where they overlap
	for x in range(mini(old_w, new_w)):
		for y in range(mini(old_h, new_h)):
			_grid[x][y] = old_grid[x][y]
	_update_canvas_size()


func _set_tile(gx: int, gy: int, tile: int) -> void:
	if gx < 0 or gx >= _grid_width or gy < 0 or gy >= _grid_height:
		return
	# If placing a spawn tile, remove any previous instance of that same spawn
	if tile >= GameConstants.EditorTile.SPAWN_1 and tile <= GameConstants.EditorTile.SPAWN_4:
		for x in range(_grid_width):
			for y in range(_grid_height):
				if _grid[x][y] == tile:
					_grid[x][y] = GameConstants.EditorTile.EMPTY
	_grid[gx][gy] = tile
	_canvas.queue_redraw()


func _canvas_pos_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x) / CELL_SIZE, int(pos.y) / CELL_SIZE)


# =============================================================================
# SAVE / LOAD
# =============================================================================

func _save_level(name: String) -> void:
	if name.strip_edges() == "":
		_set_status("Enter a level name first.")
		return

	var safe_name := name.strip_edges().replace(" ", "_")
	var path := GameConstants.LEVELS_DIR + "/" + safe_name + ".json"

	# Build JSON data
	var tiles: Array = []
	for x in range(_grid_width):
		var col: Array = []
		for y in range(_grid_height):
			col.append(_grid[x][y])
		tiles.append(col)

	var data := {
		"width": _grid_width,
		"height": _grid_height,
		"tiles": tiles,
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Error: could not write to %s" % path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_set_status("Saved: %s" % safe_name)


func _load_level(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Error: could not open %s" % path)
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		_set_status("Error: invalid JSON in level file.")
		return
	file.close()

	var data: Dictionary = json.get_data()
	var lw: int = data.get("width", 13)
	var lh: int = data.get("height", 11)

	_init_grid(lw, lh)
	_width_spin.value = lw
	_height_spin.value = lh

	var tiles: Array = data.get("tiles", [])
	for x in range(mini(tiles.size(), lw)):
		var col: Array = tiles[x]
		for y in range(mini(col.size(), lh)):
			_grid[x][y] = int(col[y])

	_update_canvas_size()
	_canvas.queue_redraw()
	_set_status("Loaded: %s" % path.get_file().get_basename())


func _get_saved_levels() -> Array[String]:
	var levels: Array[String] = []
	var dir := DirAccess.open(GameConstants.LEVELS_DIR)
	if dir == null:
		return levels
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			levels.append(GameConstants.LEVELS_DIR + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return levels


# =============================================================================
# UI BUILDING
# =============================================================================

func _build_ui() -> void:
	var canvas_layer := CanvasLayer.new()
	add_child(canvas_layer)

	# Root margin container
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	canvas_layer.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)

	# Title
	var title := Label.new()
	title.text = "Level Editor"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	# Main area: sidebar | grid scroll
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(hbox)

	_build_sidebar(hbox)
	_build_grid_area(hbox)

	# Status bar at the bottom
	_status = Label.new()
	_status.text = "Left-click: paint  |  Right-click: erase"
	_status.add_theme_font_size_override("font_size", 13)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(_status)


func _build_sidebar(parent: HBoxContainer) -> void:
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(210, 0)
	sidebar.add_theme_constant_override("separation", 6)
	parent.add_child(sidebar)

	# --- Dimensions ---
	var dim_label := Label.new()
	dim_label.text = "— Dimensions —"
	dim_label.add_theme_font_size_override("font_size", 14)
	dim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sidebar.add_child(dim_label)

	var dim_row := HBoxContainer.new()
	sidebar.add_child(dim_row)

	var w_label := Label.new()
	w_label.text = "W:"
	dim_row.add_child(w_label)
	_width_spin = SpinBox.new()
	_width_spin.min_value = 5
	_width_spin.max_value = 29
	_width_spin.step = 2  # keep odd so border/pillar pattern works
	_width_spin.value = _grid_width
	_width_spin.custom_minimum_size = Vector2(70, 0)
	dim_row.add_child(_width_spin)

	var h_label := Label.new()
	h_label.text = "  H:"
	dim_row.add_child(h_label)
	_height_spin = SpinBox.new()
	_height_spin.min_value = 5
	_height_spin.max_value = 23
	_height_spin.step = 2
	_height_spin.value = _grid_height
	_height_spin.custom_minimum_size = Vector2(70, 0)
	dim_row.add_child(_height_spin)

	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(_on_apply_dimensions)
	sidebar.add_child(apply_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear Grid"
	clear_btn.pressed.connect(_on_clear_grid)
	sidebar.add_child(clear_btn)

	# --- Tile Palette ---
	var palette_label := Label.new()
	palette_label.text = "— Tiles —"
	palette_label.add_theme_font_size_override("font_size", 14)
	palette_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sidebar.add_child(palette_label)

	var palette_scroll := ScrollContainer.new()
	palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(palette_scroll)

	var palette_vbox := VBoxContainer.new()
	palette_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_vbox.add_theme_constant_override("separation", 3)
	palette_scroll.add_child(palette_vbox)

	_palette_btns.clear()
	for tile_int in TILE_LABELS:
		var tile: int = tile_int
		var btn := Button.new()
		btn.text = TILE_LABELS[tile]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", _contrast_color(TILE_COLORS[tile]))
		btn.add_theme_stylebox_override("normal", _colored_stylebox(TILE_COLORS[tile], false))
		btn.add_theme_stylebox_override("hover", _colored_stylebox(TILE_COLORS[tile], true))
		btn.add_theme_stylebox_override("pressed", _colored_stylebox(TILE_COLORS[tile], true))
		btn.pressed.connect(_on_palette_selected.bind(tile))
		palette_vbox.add_child(btn)
		_palette_btns.append(btn)

	_highlight_palette(_selected_tile)

	# --- Save / Load ---
	var save_label := Label.new()
	save_label.text = "— Save / Load —"
	save_label.add_theme_font_size_override("font_size", 14)
	save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sidebar.add_child(save_label)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Level name..."
	sidebar.add_child(_name_edit)

	var save_btn := Button.new()
	save_btn.text = "Save Level"
	save_btn.pressed.connect(_on_save_pressed)
	sidebar.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load Level…"
	load_btn.pressed.connect(_on_load_pressed)
	sidebar.add_child(load_btn)

	# --- Play / Back ---
	var play_btn := Button.new()
	play_btn.text = "Play This Level"
	play_btn.add_theme_font_size_override("font_size", 16)
	play_btn.pressed.connect(_on_play_pressed)
	sidebar.add_child(play_btn)

	var back_btn := Button.new()
	back_btn.text = "Back to Menu"
	back_btn.pressed.connect(_on_back_pressed)
	sidebar.add_child(back_btn)


func _build_grid_area(parent: HBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)

	_canvas = Control.new()
	_canvas.focus_mode = Control.FOCUS_CLICK
	_update_canvas_size()
	_canvas.draw.connect(_on_canvas_draw)
	_canvas.gui_input.connect(_on_canvas_input)
	scroll.add_child(_canvas)


func _update_canvas_size() -> void:
	_canvas.custom_minimum_size = Vector2(
		_grid_width * CELL_SIZE + 1,
		_grid_height * CELL_SIZE + 1
	)


# =============================================================================
# CANVAS DRAWING
# =============================================================================

func _on_canvas_draw() -> void:
	var font := ThemeDB.fallback_font
	for x in range(_grid_width):
		for y in range(_grid_height):
			var tile: int = _grid[x][y]
			var rect := Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			var base_color: Color = TILE_COLORS.get(tile, Color.MAGENTA)

			# Fill
			_canvas.draw_rect(rect, base_color)

			# Grid line
			_canvas.draw_rect(rect, Color(0.4, 0.4, 0.4, 0.6), false)

			# Spawn tile label
			if tile >= GameConstants.EditorTile.SPAWN_1 and tile <= GameConstants.EditorTile.SPAWN_4:
				var spawn_num := tile - GameConstants.EditorTile.SPAWN_1 + 1
				var text := str(spawn_num)
				var text_pos := rect.position + Vector2(CELL_SIZE * 0.5 - 6, CELL_SIZE * 0.5 + 8)
				_canvas.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
						_contrast_color(base_color))

			# Conveyor arrow
			elif tile >= GameConstants.EditorTile.CONVEYOR_UP and tile <= GameConstants.EditorTile.CONVEYOR_RIGHT:
				var arrow := ""
				match tile:
					GameConstants.EditorTile.CONVEYOR_UP:    arrow = "↑"
					GameConstants.EditorTile.CONVEYOR_DOWN:  arrow = "↓"
					GameConstants.EditorTile.CONVEYOR_LEFT:  arrow = "←"
					GameConstants.EditorTile.CONVEYOR_RIGHT: arrow = "→"
				var text_pos := rect.position + Vector2(CELL_SIZE * 0.5 - 8, CELL_SIZE * 0.5 + 8)
				_canvas.draw_string(font, text_pos, arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
						_contrast_color(base_color))


# =============================================================================
# CANVAS INPUT
# =============================================================================

func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			_erase_mode = false
			if mb.pressed:
				var gp := _canvas_pos_to_grid(mb.position)
				_set_tile(gp.x, gp.y, _selected_tile)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_painting = mb.pressed
			_erase_mode = true
			if mb.pressed:
				var gp := _canvas_pos_to_grid(mb.position)
				_set_tile(gp.x, gp.y, GameConstants.EditorTile.EMPTY)

	elif event is InputEventMouseMotion and _painting:
		var mm := event as InputEventMouseMotion
		var gp := _canvas_pos_to_grid(mm.position)
		var tile := GameConstants.EditorTile.EMPTY if _erase_mode else _selected_tile
		# Don't drag-paint spawn tiles (they're unique — only single placement)
		if not _erase_mode and _selected_tile >= GameConstants.EditorTile.SPAWN_1:
			return
		_set_tile(gp.x, gp.y, tile)


# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_palette_selected(tile: int) -> void:
	_selected_tile = tile
	_highlight_palette(tile)


func _on_apply_dimensions() -> void:
	var new_w := int(_width_spin.value)
	var new_h := int(_height_spin.value)
	_resize_grid(new_w, new_h)
	_canvas.queue_redraw()
	_set_status("Grid resized to %dx%d" % [new_w, new_h])


func _on_clear_grid() -> void:
	_init_grid(_grid_width, _grid_height)
	_canvas.queue_redraw()
	_set_status("Grid cleared.")


func _on_save_pressed() -> void:
	_save_level(_name_edit.text)


func _on_load_pressed() -> void:
	_show_load_popup()


func _on_play_pressed() -> void:
	var name := _name_edit.text.strip_edges()
	if name == "":
		_set_status("Save the level first, then press Play.")
		return
	var safe_name := name.replace(" ", "_")
	var path := GameConstants.LEVELS_DIR + "/" + safe_name + ".json"
	if not FileAccess.file_exists(path):
		_save_level(name)
	GameConstants.CUSTOM_LEVEL_PATH = path
	GameConstants.save_settings()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_browser.tscn")


# =============================================================================
# LOAD POPUP
# =============================================================================

func _show_load_popup() -> void:
	var popup := AcceptDialog.new()
	popup.title = "Load / Replace Grid"
	popup.get_ok_button().visible = false

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 400)
	popup.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	# Preset section
	var preset_lbl := Label.new()
	preset_lbl.text = "— Preset Levels —"
	preset_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(preset_lbl)

	const PRESET_LEVELS: Array[Dictionary] = [
		{ "name": "Classic",    "path": "res://levels/classic.json"    },
		{ "name": "Open Arena", "path": "res://levels/open_arena.json" },
		{ "name": "Ice Rink",   "path": "res://levels/ice_rink.json"   },
	]
	for entry: Dictionary in PRESET_LEVELS:
		var btn := Button.new()
		btn.text = entry["name"]
		btn.pressed.connect(_on_load_chosen.bind(entry["path"], popup, true))
		vbox.add_child(btn)

	# User levels section
	var user_levels := _get_saved_levels()
	if not user_levels.is_empty():
		var sep := HSeparator.new()
		vbox.add_child(sep)
		var custom_lbl := Label.new()
		custom_lbl.text = "— My Levels —"
		custom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(custom_lbl)

		for path: String in user_levels:
			var btn := Button.new()
			btn.text = path.get_file().get_basename()
			btn.pressed.connect(_on_load_chosen.bind(path, popup, false))
			vbox.add_child(btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(popup.queue_free)
	vbox.add_child(cancel_btn)

	add_child(popup)
	popup.popup_centered()


## is_preset=true means copying (don't pre-fill name); false means loading a user level (pre-fill).
func _on_load_chosen(path: String, popup: AcceptDialog, is_preset: bool) -> void:
	popup.queue_free()
	_load_level(path)
	if is_preset:
		_name_edit.text = ""
		_name_edit.placeholder_text = "Copy of %s" % path.get_file().get_basename()
		_set_status("Loaded preset \"%s\" — enter a name to save as your own." % path.get_file().get_basename())
	else:
		_name_edit.text = path.get_file().get_basename()


# =============================================================================
# HELPERS
# =============================================================================

func _set_status(msg: String) -> void:
	_status.text = msg


func _highlight_palette(selected_tile: int) -> void:
	var i := 0
	for tile_int in TILE_LABELS:
		var tile: int = tile_int
		if i < _palette_btns.size():
			var btn := _palette_btns[i]
			if tile == selected_tile:
				btn.add_theme_stylebox_override("normal", _colored_stylebox(TILE_COLORS[tile], true))
			else:
				btn.add_theme_stylebox_override("normal", _colored_stylebox(TILE_COLORS[tile], false))
		i += 1


func _colored_stylebox(color: Color, bright: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.lightened(0.3) if bright else color
	sb.border_width_bottom = 2
	sb.border_color = Color.WHITE if bright else Color(0.5, 0.5, 0.5)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	return sb


func _contrast_color(bg: Color) -> Color:
	var lum := bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
	return Color.BLACK if lum > 0.5 else Color.WHITE
