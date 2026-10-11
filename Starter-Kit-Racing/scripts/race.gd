extends CanvasLayer

# Race: countdown, lap timing (with checkpoints), finish screen, pause menu

const LAPS := 3
const CHECKPOINT_SLACK := 2 # How many track tiles you may skip (small corner cuts are fine, big shortcuts aren't)

@export var vehicle: Vehicle
@export var gridmap: GridMap

var font = preload("res://fonts/lilita_one_regular.ttf")

var track: Array[Vector2i] = [] # Track tiles in driving order, starting with the finish line
var next_checkpoint := 1

var racing := false
var finished := false
var lap := 1
var race_time := 0.0
var lap_start_time := 0.0
var lap_times: Array[float] = []

var best_lap := 0.0 # Best lap including this race (the saved record lives in GameData)

var lap_label: Label
var time_label: Label
var lap_time_label: Label
var best_label: Label
var big_label: Label # Countdown and "Lap 2!" messages
var pause_menu: Control
var finish_menu: Control
var finish_details: Label
var garage_button: Button

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep running while the game is paused
	
	# Set up once the level has finished loading (swapping the vehicle isn't allowed while it loads)
	setup.call_deferred()

func setup():
	use_garage_setup()
	best_lap = GameData.best_lap
	build_track_order()
	build_hud()
	pause_menu = build_menu("PAUSED", [["Resume", func(): set_paused(false)], ["Restart", restart], ["Quit", func(): get_tree().quit()]])
	finish_menu = build_menu("FINISHED!", [["Race again", restart], ["Garage", open_garage], ["Quit", func(): get_tree().quit()]])
	finish_details = make_label(30)
	finish_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var finish_column = finish_menu.get_child(0).get_child(0)
	finish_column.add_child(finish_details)
	finish_column.move_child(finish_details, 1)
	
	garage_button = Button.new()
	garage_button.text = "GARAGE"
	garage_button.add_theme_font_override("font", font)
	garage_button.add_theme_font_size_override("font_size", 30)
	garage_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	garage_button.offset_left = -220
	garage_button.offset_top = 30
	garage_button.offset_right = -40
	garage_button.offset_bottom = 90
	garage_button.visible = false # Only shows up after finishing a race
	garage_button.pressed.connect(open_garage)
	add_child(garage_button)

	update_hud()
	countdown()

# Countdown (3, 2, 1, GO!) - the car can't move until GO

func countdown():
	vehicle.controls_enabled = false

	for number in ["3", "2", "1"]:
		show_big_text(number, Color.WHITE)
		play_beep(440)
		await get_tree().create_timer(1.0, false).timeout

	show_big_text("GO!", Color("4cd964"))
	play_beep(880)
	vehicle.controls_enabled = true
	racing = true

# Lap timing

func _physics_process(delta):
	if !racing or get_tree().paused: return

	race_time += delta
	check_progress()
	update_hud()

func check_progress():
	var map_position = gridmap.local_to_map(gridmap.to_local(vehicle.sphere.global_position))
	var cell = Vector2i(map_position.x, map_position.z)

	# Checkpoints must be reached in order (index track.size() is the finish line again)

	for index in range(next_checkpoint, next_checkpoint + CHECKPOINT_SLACK + 1):
		if index > track.size(): break
		if track[index % track.size()] != cell: continue

		if index == track.size():
			complete_lap()
		else:
			next_checkpoint = index + 1
		return

func complete_lap():
	var lap_time = race_time - lap_start_time
	lap_times.append(lap_time)
	lap_start_time = race_time
	next_checkpoint = 1

	var new_best = best_lap == 0.0 or lap_time < best_lap
	if new_best:
		best_lap = lap_time

	if lap >= LAPS:
		finish_race()
		return

	lap += 1
	if new_best:
		show_big_text("BEST LAP!", Color("ffcc00"))
	elif lap == LAPS:
		show_big_text("FINAL LAP!", Color.WHITE)
	else:
		show_big_text("LAP %d" % lap, Color.WHITE)

func finish_race():
	racing = false
	finished = true
	vehicle.controls_enabled = false
	
	var result = GameData.race_finished(race_time, lap_times)
	
	var lines = ["Total time: " + format_time(race_time) + ("   NEW RECORD!" if result.new_best_race else "")]
	for i in lap_times.size():
		lines.append("Lap %d: %s" % [i + 1, format_time(lap_times[i])])
	lines.append("Best lap ever: " + format_time(GameData.best_lap))
	lines.append("")
	lines.append("+%d coins" % GameData.COINS_PER_RACE + ("   +%d RECORD BONUS!" % GameData.COINS_RECORD_BONUS if result.record else ""))
	if result.unlocked_motorcycle:
		lines.append("MOTORCYCLE UNLOCKED! Try it in the garage")
	finish_details.text = "\n".join(lines)
	
	update_hud()
	finish_menu.visible = true
	garage_button.visible = true

# Garage (only after finishing a race)

func open_garage():
	finish_menu.visible = false
	garage_button.visible = false
	add_child(preload("res://scripts/garage.gd").new())

# Swaps in the chosen vehicle and applies its paint and upgrades

func use_garage_setup():
	var scene_path = GameData.VEHICLES[GameData.vehicle].scene
	
	if vehicle.scene_file_path != scene_path:
		var replacement: Vehicle = load(scene_path).instantiate()
		replacement.transform = vehicle.transform
		var parent = vehicle.get_parent()
		var old_vehicle = vehicle
		parent.remove_child(old_vehicle)
		old_vehicle.queue_free()
		replacement.name = "Vehicle"
		parent.add_child(replacement)
		vehicle = replacement
		parent.get_node("View").target = replacement
	
	GameData.apply_to(vehicle)

# Works out the order of track tiles by following the road from the finish line

func build_track_order():
	var library = gridmap.mesh_library
	var track_cells = {}
	var finish := Vector2i.ZERO

	for c in gridmap.get_used_cells():
		var item_name = library.get_item_name(gridmap.get_cell_item(c))
		if item_name.begins_with("track"):
			track_cells[Vector2i(c.x, c.z)] = true
			if item_name == "track-finish": finish = Vector2i(c.x, c.z)

	# The first step is in the direction the car faces at the start

	var forward = vehicle.vehicle_model.global_basis.z
	var first_step = Vector2i(roundi(forward.x), roundi(forward.z))

	track = [finish]
	var previous = finish
	var current = finish + first_step

	while current != finish and track_cells.has(current) and track.size() < 1000:
		track.append(current)
		var next = current
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor = current + step
			if neighbor != previous and track_cells.has(neighbor) and (neighbor == finish or !track.has(neighbor)):
				next = neighbor
				break
		previous = current
		current = next

# Pause menu (Escape or P)

func _unhandled_input(event):
	if finished or !pause_menu: return

	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_P):
		set_paused(!get_tree().paused)
		get_viewport().set_input_as_handled()

func set_paused(paused: bool):
	get_tree().paused = paused
	pause_menu.visible = paused

func restart():
	get_tree().paused = false
	get_tree().reload_current_scene()

# HUD

func update_hud():
	lap_label.text = "LAP %d / %d" % [lap, LAPS]
	time_label.text = format_time(race_time)
	lap_time_label.text = "This lap: " + format_time(race_time - lap_start_time)
	best_label.text = "Best lap: " + (format_time(best_lap) if best_lap > 0.0 else "--")

func format_time(seconds: float) -> String:
	return "%d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]

func show_big_text(text: String, color: Color):
	big_label.text = text
	big_label.modulate = color
	big_label.scale = Vector2.ONE * 1.6

	var tween = create_tween()
	tween.tween_property(big_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.6)
	tween.tween_property(big_label, "modulate:a", 0.0, 0.2)

func build_hud():
	var column = VBoxContainer.new()
	column.position = Vector2(40, 30)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	lap_label = make_label(44)
	time_label = make_label(36)
	lap_time_label = make_label(24)
	best_label = make_label(24)
	for label in [lap_label, time_label, lap_time_label, best_label]:
		column.add_child(label)

	# Speedometer (bottom-right corner)

	var speedometer = preload("res://scripts/speedometer.gd").new()
	speedometer.vehicle = vehicle
	speedometer.font = font
	speedometer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speedometer.offset_left = -280
	speedometer.offset_top = -280
	speedometer.offset_right = -40
	speedometer.offset_bottom = -40
	add_child(speedometer)

	big_label = make_label(140)
	big_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big_label.modulate.a = 0.0
	add_child(big_label)
	big_label.resized.connect(func(): big_label.pivot_offset = big_label.size / 2) # Scale from the middle

func make_label(size: int) -> Label:
	var label = Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", size / 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# Dimmed screen with a title and buttons

func build_menu(title_text: String, buttons: Array) -> Control:
	var menu = ColorRect.new()
	menu.color = Color(0, 0, 0, 0.5)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.visible = false
	add_child(menu)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	var title = make_label(72)
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	for button_info in buttons:
		var button = Button.new()
		button.text = button_info[0]
		button.custom_minimum_size = Vector2(260, 56)
		button.add_theme_font_override("font", font)
		button.add_theme_font_size_override("font_size", 32)
		button.pressed.connect(button_info[1])
		column.add_child(button)

	return menu

# Short beep sound (made in code, no sound file needed)

func play_beep(frequency: float):
	var sample_rate := 22050
	var length := 0.18
	var data := PackedByteArray()
	data.resize(int(sample_rate * length) * 2)

	for i in int(sample_rate * length):
		var fade = 1.0 - float(i) / (sample_rate * length)
		var sample = sin(TAU * frequency * i / sample_rate) * 0.4 * fade
		data.encode_s16(i * 2, int(sample * 32767))

	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = data

	var player = AudioStreamPlayer.new()
	player.stream = wav
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
