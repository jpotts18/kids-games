extends PanelContainer

# Tutorial: a box at the bottom of the screen that walks through the controls
# one step at a time, on its own map (scenes/tutorial.tscn) with a frozen drone
# to practice on. Each step finishes when the player does it. Plays the first
# time the game opens on a computer (remembered in the save file); Tab skips it.
# Afterwards the real game starts

const SAVE_PATH := "user://fps_best.cfg" # Same file as the best scores (see hud.gd)

const STEPS := [
	["move", "Walk around with W A S D\n(or the arrow keys)"],
	["look", "Move the mouse to look around"],
	["jump", "Press Space to jump"],
	["shoot", "Click to shoot the frozen drone until it breaks!"],
	["switch", "Press E to switch weapons"],
	["grapple", "Press E until you have the grappling hook,\nthen hold click on the high ledge to fly up"],
	["done", "You're ready! In the real game,\ndestroy every enemy to win"],
]

const DONE_SHOW_TIME := 5.0 # The last step disappears by itself after this long
const NICE_TIME := 0.8 # How long "Nice!" shows between steps

var player: Node3D
var step := 0
var waiting := 0.0 # Counts down while "Nice!" is showing
var moved := 0.0
var looked := 0.0
var last_position: Vector3
var last_rotation: float

var count_label: Label
var text_label: Label

static func seen() -> bool:
	var save = ConfigFile.new()
	save.load(SAVE_PATH)
	return save.get_value("tutorial", "seen", false)

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE # Waits while the game is paused
	player = get_tree().get_first_node_in_group("player")
	last_position = player.global_position
	last_rotation = player.global_rotation.y
	build()
	show_step()

func _process(delta):
	if Input.is_physical_key_pressed(KEY_TAB):
		finish()
		return

	track_movement()

	if waiting > 0:
		waiting -= delta
		if waiting <= 0: next_step()
		return

	if step_completed(STEPS[step][0]):
		if STEPS[step][0] == "shoot":
			var sign = get_tree().current_scene.get_node_or_null("Signs/DroneSign")
			if sign: sign.queue_free()

		Audio.play("sounds/weapon_change.ogg")
		text_label.text = "Nice!"
		text_label.add_theme_color_override("font_color", Color("4cd964"))
		waiting = NICE_TIME

func next_step():
	if STEPS[step][0] == "done":
		finish()
		return

	step += 1
	show_step()

func step_completed(id: String) -> bool:
	match id:
		"move": return moved > 3.0
		"look": return looked > 1.5 # Radians turned (left and right both count)
		"jump": return Input.is_action_just_pressed("jump")
		"shoot": return get_tree().get_nodes_in_group("enemies").all(func(enemy): return enemy.destroyed)
		"switch": return Input.is_action_just_pressed("weapon_toggle")
		"grapple": return player.grappling
	return false

# Adds up how far the player has walked and turned

func track_movement():
	var offset = player.global_position - last_position
	moved += Vector2(offset.x, offset.z).length()
	last_position = player.global_position

	looked += abs(angle_difference(last_rotation, player.global_rotation.y))
	last_rotation = player.global_rotation.y

func show_step():
	text_label.text = STEPS[step][1]
	text_label.remove_theme_color_override("font_color")

	# Only what's done during this step counts for it
	moved = 0.0
	looked = 0.0

	if STEPS[step][0] == "done":
		waiting = DONE_SHOW_TIME # Then it goes away by itself

	var steps_to_do = STEPS.size() - 1 # The last one is just a message
	count_label.text = "TUTORIAL  %d / %d" % [step + 1, steps_to_do] if step < steps_to_do else "TUTORIAL DONE!"

# Remember it's been seen, so it doesn't show again on this computer, then
# start the real game

func finish():
	var save = ConfigFile.new()
	save.load(SAVE_PATH)
	save.set_value("tutorial", "seen", true)
	save.save(SAVE_PATH)

	set_process(false)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

func build():
	var font = preload("res://fonts/lilita_one_regular.ttf")

	var box = StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.55)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(20)
	add_theme_stylebox_override("panel", box)

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	count_label = make_label(font, 20, Color("ffcc00"))
	column.add_child(count_label)

	text_label = make_label(font, 34, Color.WHITE)
	column.add_child(text_label)

	column.add_child(make_label(font, 18, Color(1, 1, 1, 0.6), "Tab: skip tutorial"))

	# Bottom middle of the screen, a bit above the edge (sized to fit the longest step)

	text_label.text = STEPS[5][1]
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 120)

func make_label(font: Font, size: int, color: Color, text := "") -> Label:
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	return label
