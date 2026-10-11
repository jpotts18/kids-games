extends CanvasLayer

# Race: countdown, lap timing (with checkpoints), finish screen, pause menu

const LAPS := 3
const CHECKPOINT_SLACK := 2 # How many track tiles you may skip (small corner cuts are fine, big shortcuts aren't)

# Computer opponents: grid spot (sideways, forward) relative to the player, top speed and lane on the road

const OPPONENTS := [
	{"name": "Red", "model": "res://models/vehicle-truck-red.glb", "grid": Vector2(1.6, 0.0), "speed": 1.0, "lane": 0.8},
	{"name": "Green", "model": "res://models/vehicle-truck-green.glb", "grid": Vector2(0.0, -2.6), "speed": 0.97, "lane": 0.0},
	{"name": "Purple", "model": "res://models/vehicle-truck-purple.glb", "grid": Vector2(1.6, -2.6), "speed": 0.94, "lane": -0.8},
]

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

var pit_stop: Node3D
var opponents: Array[Dictionary] = [] # {vehicle, driver, lap, next_checkpoint, finished}
var finish_order := 0 # How many racers have crossed the finish line after the last lap
var place := 0 # The player's finishing place

var lap_label: Label
var position_label: Label
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
	build_pit_stop()
	spawn_opponents()
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
	set_controls(false)

	for number in ["3", "2", "1"]:
		show_big_text(number, Color.WHITE)
		play_beep(440)
		await get_tree().create_timer(1.0, false).timeout

	show_big_text("GO!", Color("4cd964"))
	play_beep(880)
	set_controls(true)
	racing = true

func set_controls(enabled: bool):
	vehicle.controls_enabled = enabled
	for opponent in opponents:
		opponent.vehicle.controls_enabled = enabled

# Lap timing

func _physics_process(delta):
	if !racing or get_tree().paused: return

	race_time += delta
	check_progress()
	check_opponents()
	update_hud()

func check_progress():
	var index = reached_checkpoint(vehicle, next_checkpoint)
	if index == track.size():
		complete_lap()
	elif index > 0:
		next_checkpoint = index + 1

# Returns the checkpoint the vehicle is on (0 if none)
# Checkpoints must be reached in order (index track.size() is the finish line again)

func reached_checkpoint(racer: Vehicle, next: int) -> int:
	var map_position = gridmap.local_to_map(gridmap.to_local(racer.sphere.global_position))
	var cell = Vector2i(map_position.x, map_position.z)

	for index in range(next, next + CHECKPOINT_SLACK + 1):
		if index > track.size(): break
		if track[index % track.size()] == cell: return index
	return 0

func check_opponents():
	for opponent in opponents:
		if opponent.finished: continue

		var index = reached_checkpoint(opponent.vehicle, opponent.next_checkpoint)
		if index == track.size():
			opponent.next_checkpoint = 1
			opponent.lap += 1
			if opponent.lap > LAPS:
				opponent.finished = true
				opponent.driver.cool_down = true
				finish_order += 1
		elif index > 0:
			opponent.next_checkpoint = index + 1

# How far along the race a racer is (in track tiles), used to work out the player's position

func race_progress(racer: Vehicle, racer_lap: int, next: int) -> float:
	var target = gridmap.to_global(gridmap.map_to_local(Vector3i(track[next % track.size()].x, 0, track[next % track.size()].y)))
	var tile_size = gridmap.cell_size.x * gridmap.global_basis.x.length()
	var distance = Vector2(target.x - racer.sphere.global_position.x, target.z - racer.sphere.global_position.z).length()
	var closeness = clamp(1.0 - distance / tile_size, 0.0, 1.0)
	return (racer_lap - 1) * track.size() + next - 1 + closeness

func player_position() -> int:
	if finished: return place

	var mine = race_progress(vehicle, lap, next_checkpoint)
	var ahead = 0
	for opponent in opponents:
		if opponent.finished or race_progress(opponent.vehicle, opponent.lap, opponent.next_checkpoint) > mine:
			ahead += 1
	return ahead + 1

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
	finish_order += 1
	place = finish_order
	finished = true
	set_controls(false) # Everyone coasts to a stop, the race is over
	
	var result = GameData.race_finished(race_time, lap_times)
	
	var lines = ["You finished %s of %d!" % [ordinal(place), opponents.size() + 1],"Total time: " + format_time(race_time) + ("   NEW RECORD!" if result.new_best_race else "")]
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

func ordinal(number: int) -> String:
	match number:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % number

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

# Computer opponents: same truck with a different model, driven by the opponent script

func spawn_opponents():
	var path = build_waypoints()

	for info in OPPONENTS:
		var car: Vehicle = preload("res://scenes/vehicle.tscn").instantiate()
		var container = car.get_node("Container")
		var old_model = container.get_node("Model")
		container.remove_child(old_model)
		old_model.free()
		var model = load(info.model).instantiate()
		model.name = "Model"
		container.add_child(model)
		container.move_child(model, 0)

		car.name = "Opponent" + info.name
		car.transform = vehicle.transform
		car.position += vehicle.vehicle_model.global_basis.x * info.grid.x + vehicle.vehicle_model.global_basis.z * info.grid.y
		car.speed_multiplier = info.speed
		car.controls_enabled = false
		car.ai_input = Vector2.ZERO
		vehicle.get_parent().add_child(car)

		var driver = preload("res://scripts/opponent.gd").new()
		driver.vehicle = car
		driver.waypoints = path.points
		driver.directions = path.directions
		driver.lane = info.lane
		driver.pit_stop = pit_stop
		driver.pit_waypoint = pit_waypoint(path.points)
		car.add_child(driver)
		driver.start_at_closest_waypoint()

		opponents.append({"vehicle": car, "driver": driver, "lap": 1, "next_checkpoint": 1, "finished": false})

# Pit stop: on a straight around the middle of the lap, in the lane next to an empty patch of grass (where the tents go)

func build_pit_stop():
	var library = gridmap.mesh_library
	var best = -1

	for i in range(1, track.size() - 1):
		if !is_straight(i - 1) or !is_straight(i) or !is_straight(i + 1): continue
		if empty_side(i) == Vector2i.ZERO: continue
		if best == -1 or abs(i - track.size() / 2) < abs(best - track.size() / 2): best = i

	if best == -1: return # No room for a pit stop on this track

	var side = empty_side(best)
	gridmap.set_cell_item(Vector3i(track[best].x + side.x, 0, track[best].y + side.y), library.find_item_by_name("decoration-tents"))

	var center = cell_position(track[best])
	var direction = (cell_position(track[best + 1]) - center).normalized()
	var side_direction = Vector3(side.x, 0, side.y)

	pit_stop = preload("res://scripts/pit_stop.gd").new()
	pit_stop.name = "PitStop"
	gridmap.get_parent().add_child(pit_stop)
	pit_stop.global_transform = Transform3D(Basis.looking_at(direction), center + side_direction * 1.4)

func is_straight(index: int) -> bool:
	var cell = track[index]
	return gridmap.mesh_library.get_item_name(gridmap.get_cell_item(Vector3i(cell.x, 0, cell.y))) == "track-straight"

# Which side of a track tile has an empty grass tile next to it (zero if none)

func empty_side(index: int) -> Vector2i:
	var along = track[index + 1] - track[index]
	for side in [Vector2i(-along.y, along.x), Vector2i(along.y, -along.x)]:
		var neighbor = track[index] + side
		var item = gridmap.get_cell_item(Vector3i(neighbor.x, 0, neighbor.y))
		if item != -1 and gridmap.mesh_library.get_item_name(item) == "decoration-empty":
			return side
	return Vector2i.ZERO

func cell_position(cell: Vector2i) -> Vector3:
	var point = gridmap.to_global(gridmap.map_to_local(Vector3i(cell.x, 0, cell.y)))
	return Vector3(point.x, 0, point.z)

# The first opponent waypoint past the pit box (where opponents rejoin the race after repairing)

func pit_waypoint(points: Array[Vector3]) -> int:
	if !pit_stop: return -1
	var forward = -pit_stop.global_basis.z
	var best = -1
	for i in points.size():
		var offset = points[i] - pit_stop.global_position
		if offset.dot(forward) > 0 and (best == -1 or offset.length() < (points[best] - pit_stop.global_position).length()):
			best = i
	return best

# Points along the middle of the road for opponents to drive to: where tiles meet, plus the middle of each corner

func build_waypoints() -> Dictionary:
	var points: Array[Vector3] = []
	var directions: Array[Vector3] = []
	var half = gridmap.cell_size.x * gridmap.global_basis.x.length() / 2

	var centers = []
	for cell in track:
		var center = gridmap.to_global(gridmap.map_to_local(Vector3i(cell.x, 0, cell.y)))
		centers.append(Vector3(center.x, 0, center.z))

	for i in centers.size():
		var center = centers[i]
		var previous = centers[i - 1]
		var next = centers[(i + 1) % centers.size()]
		var direction_in = (center - previous).normalized()
		var direction_out = (next - center).normalized()

		if direction_in.dot(direction_out) < 0.5: # Corner: the road is a quarter circle around one corner of the tile
			var pivot = center - direction_in * half + direction_out * half
			points.append(pivot + (center - pivot).normalized() * half)
			directions.append((direction_in + direction_out).normalized())

		points.append((center + next) / 2)
		directions.append(direction_out)

	return {"points": points, "directions": directions}

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
	position_label.text = "POS %d / %d" % [player_position(), opponents.size() + 1]
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
	position_label = make_label(44)
	time_label = make_label(36)
	lap_time_label = make_label(24)
	best_label = make_label(24)
	for label in [lap_label, position_label, time_label, lap_time_label, best_label]:
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

	# Health bar (bottom-left corner)

	var damage_meter = preload("res://scripts/damage_meter.gd").new()
	damage_meter.font = font
	damage_meter.set_vehicle(vehicle)
	damage_meter.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	damage_meter.offset_left = 40
	damage_meter.offset_top = -130
	damage_meter.offset_right = 360
	damage_meter.offset_bottom = -40
	add_child(damage_meter)

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
