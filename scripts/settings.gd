extends Node2D
## Settings screen. All UI is built in code to avoid linter stripping.

func _ready() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	canvas.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	_section(vbox, "Timing")
	_slider(vbox, "Bomb Fuse Time (s)",         "BOMB_FUSE_TIME",         GameConstants.BOMB_FUSE_TIME,         0.5,  5.0,  0.1,  false)
	_slider(vbox, "Bomb Kick Delay (s)",         "BOMB_MOVE_DELAY",        GameConstants.BOMB_MOVE_DELAY,        0.02, 0.5,  0.01, false)
	_slider(vbox, "Bomb Fly Delay (s)",          "BOMB_FLY_DELAY",         GameConstants.BOMB_FLY_DELAY,         0.02, 0.5,  0.01, false)
	_slider(vbox, "Bomb Throw Distance (tiles)", "BOMB_THROW_DISTANCE",    GameConstants.BOMB_THROW_DISTANCE,    1,    10,   1,    true)
	_slider(vbox, "Conveyor Interval (s)",       "CONVEYOR_MOVE_INTERVAL", GameConstants.CONVEYOR_MOVE_INTERVAL, 0.05, 1.0,  0.05, false)
	_slider(vbox, "Player Move Cooldown (s)",    "PLAYER_MOVE_COOLDOWN",   GameConstants.PLAYER_MOVE_COOLDOWN,   0.03, 0.3,  0.01, false)
	_slider(vbox, "Curse Duration (s)",          "CURSE_DURATION",         GameConstants.CURSE_DURATION,         2.0,  30.0, 1.0,  false)

	_section(vbox, "Visual")
	_option(vbox, "Movement Mode", "MOVEMENT_MODE",
			["Snap (grid, instant)", "Smooth (grid, interpolated)", "Free (pixel, no snap)"],
			GameConstants.MOVEMENT_MODE)
	_slider(vbox, "Player Hitbox Size (px)", "PLAYER_HITBOX_SIZE", GameConstants.PLAYER_HITBOX_SIZE, 10, 62, 2, true)

	_section(vbox, "Arena")
	_slider(vbox, "Soft Block Spawn Chance", "SOFT_BLOCK_SPAWN_CHANCE", GameConstants.SOFT_BLOCK_SPAWN_CHANCE, 0.0, 1.0, 0.05, false)
	_slider(vbox, "Powerup Drop Chance",     "POWERUP_DROP_CHANCE",     GameConstants.POWERUP_DROP_CHANCE,     0.0, 1.0, 0.05, false)

	_section(vbox, "Player Starting Stats")
	_slider(vbox, "Max Bombs",  "STARTING_MAX_BOMBS",  GameConstants.STARTING_MAX_BOMBS,  1, 10, 1, true)
	_slider(vbox, "Bomb Range", "STARTING_BOMB_RANGE", GameConstants.STARTING_BOMB_RANGE, 1, 10, 1, true)
	_check(vbox,  "Start with Kick",  "STARTING_HAS_KICK",  GameConstants.STARTING_HAS_KICK)
	_check(vbox,  "Start with Throw", "STARTING_HAS_THROW", GameConstants.STARTING_HAS_THROW)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.add_theme_font_size_override("font_size", 16)
	reset_btn.pressed.connect(_on_reset_pressed)
	outer.add_child(reset_btn)

	var back := Button.new()
	back.text = "Back to Menu"
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(_on_back_pressed)
	outer.add_child(back)


func _apply(key: String, value: Variant) -> void:
	match key:
		"BOMB_FUSE_TIME":         GameConstants.BOMB_FUSE_TIME = value
		"BOMB_MOVE_DELAY":        GameConstants.BOMB_MOVE_DELAY = value
		"BOMB_FLY_DELAY":         GameConstants.BOMB_FLY_DELAY = value
		"BOMB_THROW_DISTANCE":    GameConstants.BOMB_THROW_DISTANCE = value
		"CONVEYOR_MOVE_INTERVAL": GameConstants.CONVEYOR_MOVE_INTERVAL = value
		"PLAYER_MOVE_COOLDOWN":   GameConstants.PLAYER_MOVE_COOLDOWN = value
		"CURSE_DURATION":         GameConstants.CURSE_DURATION = value
		"SOFT_BLOCK_SPAWN_CHANCE":GameConstants.SOFT_BLOCK_SPAWN_CHANCE = value
		"POWERUP_DROP_CHANCE":    GameConstants.POWERUP_DROP_CHANCE = value
		"STARTING_MAX_BOMBS":     GameConstants.STARTING_MAX_BOMBS = value
		"STARTING_BOMB_RANGE":    GameConstants.STARTING_BOMB_RANGE = value
		"STARTING_HAS_KICK":      GameConstants.STARTING_HAS_KICK = value
		"STARTING_HAS_THROW":     GameConstants.STARTING_HAS_THROW = value
		"MOVEMENT_MODE":          GameConstants.MOVEMENT_MODE = value as GameConstants.MovementMode
		"PLAYER_HITBOX_SIZE":     GameConstants.PLAYER_HITBOX_SIZE = value


func _section(parent: VBoxContainer, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	parent.add_child(spacer)
	var label := Label.new()
	label.text = "— %s —" % text
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _slider(parent: VBoxContainer, label_text: String, key: String, current: float,
		min_val: float, max_val: float, step: float, is_int: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = current
	slider.custom_minimum_size = Vector2(200, 0)
	row.add_child(slider)

	var val_label := Label.new()
	val_label.custom_minimum_size = Vector2(52, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_label.text = _fmt(current, step)
	row.add_child(val_label)

	slider.value_changed.connect(_on_slider_changed.bind(key, is_int, val_label, step))


func _check(parent: VBoxContainer, label_text: String, key: String, current: bool) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var checkbox := CheckBox.new()
	checkbox.button_pressed = current
	checkbox.toggled.connect(_on_check_toggled.bind(key))
	row.add_child(checkbox)


func _option(parent: VBoxContainer, label_text: String, key: String,
		options: Array[String], current_idx: int) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var btn := OptionButton.new()
	for opt in options:
		btn.add_item(opt)
	btn.selected = current_idx
	btn.item_selected.connect(_on_option_selected.bind(key))
	row.add_child(btn)


func _on_slider_changed(value: float, key: String, is_int: bool, val_label: Label, step: float) -> void:
	var applied: Variant = int(value) if is_int else value
	_apply(key, applied)
	val_label.text = _fmt(value, step)


func _on_check_toggled(pressed: bool, key: String) -> void:
	_apply(key, pressed)


func _on_option_selected(index: int, key: String) -> void:
	_apply(key, index)


func _on_reset_pressed() -> void:
	GameConstants.reset_to_defaults()
	get_tree().reload_current_scene()


func _on_back_pressed() -> void:
	GameConstants.save_settings()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _fmt(value: float, step: float) -> String:
	if step >= 1.0:
		return str(int(value))
	elif step >= 0.1:
		return "%.1f" % value
	return "%.2f" % value
