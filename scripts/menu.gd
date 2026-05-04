extends Node2D
## Main menu. UI is built in code to keep the scene file minimal.

func _ready() -> void:
	# Make sure match state is cleared when returning to menu
	GameConstants.MATCH_ACTIVE = false

	var canvas := CanvasLayer.new()
	add_child(canvas)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 16)
	canvas.add_child(vbox)

	var title := Label.new()
	title.text = "BomberReborn"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Show active custom level if one is set
	if GameConstants.CUSTOM_LEVEL_PATH != "":
		var level_label := Label.new()
		var level_name: String = GameConstants.CUSTOM_LEVEL_PATH.get_file().get_basename()
		level_label.text = "Level: %s" % level_name
		level_label.add_theme_font_size_override("font_size", 14)
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(level_label)

		var clear_btn := Button.new()
		clear_btn.text = "Clear Custom Level"
		clear_btn.add_theme_font_size_override("font_size", 14)
		clear_btn.pressed.connect(_on_clear_level_pressed)
		vbox.add_child(clear_btn)

	# Primary: multi-level match setup
	var match_btn := Button.new()
	match_btn.text = "Play Match"
	match_btn.add_theme_font_size_override("font_size", 24)
	match_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/level_selection.tscn")
	)
	vbox.add_child(match_btn)

	# Quick single game (uses whatever CUSTOM_LEVEL_PATH is set, or procedural)
	var normal_btn := Button.new()
	normal_btn.text = "Quick Game"
	normal_btn.add_theme_font_size_override("font_size", 20)
	normal_btn.pressed.connect(_on_quick_game_pressed)
	vbox.add_child(normal_btn)

	var test_btn := Button.new()
	test_btn.text = "Test Arena"
	test_btn.add_theme_font_size_override("font_size", 20)
	test_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/test_main.tscn")
	)
	vbox.add_child(test_btn)

	var levels_btn := Button.new()
	levels_btn.text = "Levels"
	levels_btn.add_theme_font_size_override("font_size", 20)
	levels_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/level_browser.tscn")
	)
	vbox.add_child(levels_btn)

	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.add_theme_font_size_override("font_size", 20)
	settings_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/settings.tscn")
	)
	vbox.add_child(settings_btn)


func _on_quick_game_pressed() -> void:
	# Single round, no match tracking — ensure match state is clean
	GameConstants.MATCH_ACTIVE = false
	GameConstants.MATCH_SCORES.clear()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_clear_level_pressed() -> void:
	GameConstants.CUSTOM_LEVEL_PATH = ""
	GameConstants.save_settings()
	get_tree().reload_current_scene()
