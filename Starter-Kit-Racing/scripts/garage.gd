extends Control

# Garage: pick a vehicle, paint it any color and buy upgrades with coins

const PRESET_COLORS := ["ff3b30", "ff9500", "ffcc00", "4cd964", "34aadc", "5856d6", "ff2d92", "ffffff", "2b2b2b"]

var font = preload("res://fonts/lilita_one_regular.ttf")

var coins_label: Label
var vehicle_buttons := {}
var color_button: ColorPickerButton
var upgrade_rows := {}

var turntable: Node3D

func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # Fill the whole screen

	var theme_override = Theme.new()
	theme_override.default_font = font
	theme_override.default_font_size = 22
	theme = theme_override

	var background = ColorRect.new()
	background.color = Color(0.09, 0.11, 0.2)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var layout = HBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 40
	layout.offset_top = 30
	layout.offset_right = -40
	layout.offset_bottom = -30
	layout.add_theme_constant_override("separation", 40)
	add_child(layout)

	layout.add_child(build_preview())
	layout.add_child(build_options())

	refresh()

func _process(delta):
	if turntable: turntable.rotate_y(delta * 0.8)

# Left side: the vehicle spinning on a turntable

func build_preview() -> Control:
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title = make_label("GARAGE", 64)
	column.add_child(title)

	var container = SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(container)

	var viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	container.add_child(viewport)

	var environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.78, 0.9)
	environment.environment.ambient_light_energy = 0.8
	viewport.add_child(environment)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	viewport.add_child(light)

	var camera = Camera3D.new()
	camera.position = Vector3(0, 1.5, 3.4)
	camera.rotation_degrees = Vector3(-18, 0, 0)
	camera.fov = 45
	viewport.add_child(camera)

	var turntable_floor = MeshInstance3D.new()
	turntable_floor.mesh = CylinderMesh.new()
	turntable_floor.mesh.top_radius = 1.6
	turntable_floor.mesh.bottom_radius = 1.6
	turntable_floor.mesh.height = 0.1
	var floor_material = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.25, 0.28, 0.4)
	turntable_floor.mesh.material = floor_material
	turntable_floor.position.y = -0.05
	viewport.add_child(turntable_floor)

	turntable = Node3D.new()
	turntable.rotation_degrees.y = -30
	viewport.add_child(turntable)

	return column

func update_preview():
	for child in turntable.get_children():
		child.queue_free()

	var model = load(GameData.VEHICLES[GameData.vehicle].model).instantiate()
	turntable.add_child(model)
	GameData.apply_paint(model)

# Right side: coins, vehicle, paint, upgrades

func build_options() -> Control:
	var column = VBoxContainer.new()
	column.custom_minimum_size.x = 600
	column.add_theme_constant_override("separation", 10)

	coins_label = make_label("", 36)
	coins_label.modulate = Color("ffcc00")
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(coins_label)

	# Vehicle

	column.add_child(make_label("VEHICLE", 26))
	var vehicle_row = HBoxContainer.new()
	vehicle_row.add_theme_constant_override("separation", 10)
	column.add_child(vehicle_row)
	for vehicle_id in GameData.VEHICLES:
		var button = Button.new()
		button.custom_minimum_size = Vector2(0, 46)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(func(): choose_vehicle(vehicle_id))
		vehicle_row.add_child(button)
		vehicle_buttons[vehicle_id] = button

	# Paint

	column.add_child(make_label("PAINT", 26))
	var paint_row = HBoxContainer.new()
	paint_row.add_theme_constant_override("separation", 6)
	column.add_child(paint_row)

	for hex in PRESET_COLORS:
		var swatch = Button.new()
		swatch.custom_minimum_size = Vector2(40, 40)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(hex)
		style.set_corner_radius_all(20)
		style.set_border_width_all(2)
		style.border_color = Color(1, 1, 1, 0.5)
		for state in ["normal", "hover", "pressed", "focus"]:
			swatch.add_theme_stylebox_override(state, style)
		swatch.pressed.connect(func(): choose_paint(Color(hex)))
		paint_row.add_child(swatch)

	color_button = ColorPickerButton.new()
	color_button.text = "Any color..."
	color_button.edit_alpha = false
	color_button.custom_minimum_size = Vector2(150, 40)
	color_button.color_changed.connect(choose_paint)
	paint_row.add_child(color_button)

	var original_button = Button.new()
	original_button.text = "Original"
	original_button.pressed.connect(func(): choose_paint(Color(0, 0, 0, 0)))
	paint_row.add_child(original_button)

	# Upgrades

	column.add_child(make_label("UPGRADES", 26))
	for upgrade_id in GameData.UPGRADES:
		column.add_child(build_upgrade_row(upgrade_id))

	# Race button

	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var race_button = Button.new()
	race_button.text = "RACE!"
	race_button.custom_minimum_size = Vector2(0, 64)
	race_button.add_theme_font_size_override("font_size", 36)
	race_button.pressed.connect(start_race)
	column.add_child(race_button)

	return column

func build_upgrade_row(upgrade_id: String) -> Control:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var text = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", -4)
	text.add_child(make_label(GameData.UPGRADES[upgrade_id].name, 22))
	var info = make_label(GameData.UPGRADES[upgrade_id].info, 15)
	info.modulate = Color(1, 1, 1, 0.6)
	text.add_child(info)
	row.add_child(text)

	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in GameData.MAX_UPGRADE_LEVEL:
		var block = ColorRect.new()
		block.custom_minimum_size = Vector2(22, 22)
		block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_child(block)
	row.add_child(bar)

	var buy = Button.new()
	buy.custom_minimum_size = Vector2(170, 44)
	buy.pressed.connect(func():
		GameData.buy_upgrade(upgrade_id)
		refresh())
	row.add_child(buy)

	upgrade_rows[upgrade_id] = {"bar": bar, "button": buy}
	return row

# Actions

func choose_vehicle(vehicle_id: String):
	if GameData.is_unlocked(vehicle_id):
		GameData.vehicle = vehicle_id
		GameData.save_data()
	refresh()

func choose_paint(color: Color):
	GameData.paint = color
	GameData.save_data()
	update_preview()

func start_race():
	GameData.save_data()
	get_tree().paused = false
	get_tree().reload_current_scene()

func refresh():
	coins_label.text = "COINS: %d" % GameData.coins

	for vehicle_id in vehicle_buttons:
		var button: Button = vehicle_buttons[vehicle_id]
		var vehicle_name = GameData.VEHICLES[vehicle_id].name
		if GameData.is_unlocked(vehicle_id):
			button.text = vehicle_name
			button.disabled = false
		else:
			button.text = "%s (locked: %d / %d races)" % [vehicle_name, GameData.races_finished, GameData.MOTORCYCLE_UNLOCK_RACES]
			button.disabled = true
		button.set_pressed_no_signal(GameData.vehicle == vehicle_id)

	if GameData.paint.a > 0: color_button.color = GameData.paint

	for upgrade_id in upgrade_rows:
		var level = GameData.upgrades[upgrade_id]
		var blocks = upgrade_rows[upgrade_id].bar.get_children()
		for i in blocks.size():
			blocks[i].color = Color("4cd964") if i < level else Color(1, 1, 1, 0.15)

		var button: Button = upgrade_rows[upgrade_id].button
		if level >= GameData.MAX_UPGRADE_LEVEL:
			button.text = "MAX"
			button.disabled = true
		else:
			button.text = "Upgrade: %d" % GameData.upgrade_cost(upgrade_id)
			button.disabled = GameData.coins < GameData.upgrade_cost(upgrade_id)

	update_preview()

func make_label(text: String, size: int) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label
