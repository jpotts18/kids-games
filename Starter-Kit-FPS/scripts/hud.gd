extends CanvasLayer

@export var win_when_cleared := true # Turned off in the playground, where clearing all enemies shouldn't end the game

const MAX_HEALTH := 100.0

const BAR_SIZE := Vector2(320, 34)

const COLOR_HEALTHY := Color("4cd964")
const COLOR_HURT := Color("ffcc00")
const COLOR_DANGER := Color("ff3b30")

var pause_menu: Control
var win_menu: Control
var win_time_label: Label

var enemy_counter: Label
var timer_label: Label
var total_enemies := 0
var elapsed_time := 0.0
var game_won := false

var health_fill: ProgressBar # Current health
var health_trail: ProgressBar # Lags behind to show recent damage
var health_number: Label
var damage_flash: TextureRect

var fill_style: StyleBoxFlat
var trail_tween: Tween
var flash_tween: Tween

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep running while the game is paused
	build_health_bar()
	build_goal_display()
	build_pause_menu()
	build_win_menu()

# Enemy counter, timer and winning

func _process(delta):
	if get_tree().paused or game_won: return

	elapsed_time += delta
	timer_label.text = format_time(elapsed_time)

	var enemies_left = 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if !enemy.destroyed: enemies_left += 1

	total_enemies = max(total_enemies, enemies_left)
	enemy_counter.text = "Enemies: %d / %d" % [enemies_left, total_enemies]

	if win_when_cleared and total_enemies > 0 and enemies_left == 0:
		win()

func win():
	game_won = true
	get_tree().paused = true
	win_time_label.text = "Time: " + format_time(elapsed_time)
	win_menu.visible = true
	$Crosshair.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func format_time(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func build_goal_display():
	var font = preload("res://fonts/lilita_one_regular.ttf")

	var column = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.offset_left = -360
	column.offset_right = -48
	column.offset_top = 40
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	enemy_counter = make_hud_label(font, 34)
	column.add_child(enemy_counter)

	timer_label = make_hud_label(font, 26)
	timer_label.text = "0:00"
	column.add_child(timer_label)

func make_hud_label(font: Font, size: int) -> Label:
	var label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	return label

# Health bar

func _on_health_updated(health):
	var value = clamp(health, 0, MAX_HEALTH)
	var lost_health = value < health_fill.value

	health_fill.value = value
	health_number.text = str(int(value))
	fill_style.bg_color = health_color(value / MAX_HEALTH)

	# Damage trail drains after a short delay

	if trail_tween: trail_tween.kill()
	trail_tween = create_tween()
	trail_tween.tween_interval(0.3)
	trail_tween.tween_property(health_trail, "value", value, 0.4)

	if lost_health:
		flash_damage()

# Green when healthy, yellow when hurt, red when in danger

func health_color(ratio: float) -> Color:
	if ratio > 0.5:
		return COLOR_HURT.lerp(COLOR_HEALTHY, (ratio - 0.5) * 2)
	return COLOR_DANGER.lerp(COLOR_HURT, ratio * 2)

# Short red flash around the screen edges when hit

func flash_damage():
	if flash_tween: flash_tween.kill()
	damage_flash.modulate.a = 1.0
	flash_tween = create_tween()
	flash_tween.tween_property(damage_flash, "modulate:a", 0.0, 0.35)

func build_health_bar():
	var font = preload("res://fonts/lilita_one_regular.ttf")

	$Health.visible = false # Replaced by the bar below

	# Red screen-edge flash (drawn behind everything else on the HUD)

	var gradient = Gradient.new()
	gradient.set_offset(0, 0.45)
	gradient.set_color(0, Color(1, 0.1, 0.05, 0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1, 0.1, 0.05, 0.6))

	var vignette = GradientTexture2D.new()
	vignette.gradient = gradient
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.5)
	vignette.fill_to = Vector2(1.1, 1.1)

	damage_flash = TextureRect.new()
	damage_flash.texture = vignette
	damage_flash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	damage_flash.stretch_mode = TextureRect.STRETCH_SCALE
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash.modulate.a = 0.0
	add_child(damage_flash)
	move_child(damage_flash, 0)

	# Bar container (bottom-left corner)

	var bar = Control.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 48
	bar.offset_right = 48 + BAR_SIZE.x
	bar.offset_top = -48 - BAR_SIZE.y
	bar.offset_bottom = -48
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	health_trail = make_bar(Color(1, 1, 1, 0.85), make_box(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.6)))
	bar.add_child(health_trail)

	fill_style = make_box(COLOR_HEALTHY)
	health_fill = make_bar(COLOR_HEALTHY, StyleBoxEmpty.new())
	health_fill.add_theme_stylebox_override("fill", fill_style)
	bar.add_child(health_fill)

	# Number on top of the bar

	health_number = Label.new()
	health_number.text = str(int(MAX_HEALTH))
	health_number.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	health_number.add_theme_font_override("font", font)
	health_number.add_theme_font_size_override("font_size", 26)
	health_number.add_theme_constant_override("outline_size", 8)
	health_number.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	bar.add_child(health_number)

func make_bar(fill_color: Color, background: StyleBox) -> ProgressBar:
	var progress = ProgressBar.new()
	progress.max_value = MAX_HEALTH
	progress.value = MAX_HEALTH
	progress.show_percentage = false
	progress.set_anchors_preset(Control.PRESET_FULL_RECT)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_theme_stylebox_override("background", background)
	progress.add_theme_stylebox_override("fill", make_box(fill_color))
	return progress

func make_box(color: Color, border_color := Color.TRANSPARENT) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(10)
	if border_color.a > 0:
		box.border_color = border_color
		box.set_border_width_all(3)
		box.set_expand_margin_all(3)
	return box

# Pausing (Escape or P)

func _unhandled_input(event):
	if game_won: return

	if event.is_action_pressed("mouse_capture_exit") or (event is InputEventKey and event.pressed and !event.echo and event.physical_keycode == KEY_P):
		set_paused(!get_tree().paused)
		get_viewport().set_input_as_handled()

func set_paused(paused: bool):
	get_tree().paused = paused
	pause_menu.visible = paused
	$Crosshair.visible = !paused

	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Pause and win menus (dimmed screen, title and buttons)

func build_pause_menu():
	var font = preload("res://fonts/lilita_one_regular.ttf")
	var column = build_menu("PAUSED")
	pause_menu = column.get_parent().get_parent()

	column.add_child(make_button("Resume", font, func(): set_paused(false)))
	column.add_child(make_button("Quit", font, func(): get_tree().quit()))

func build_win_menu():
	var font = preload("res://fonts/lilita_one_regular.ttf")
	var column = build_menu("YOU WIN!")
	win_menu = column.get_parent().get_parent()

	win_time_label = Label.new()
	win_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_time_label.add_theme_font_override("font", font)
	win_time_label.add_theme_font_size_override("font_size", 36)
	column.add_child(win_time_label)

	column.add_child(make_button("Play again", font, play_again))
	column.add_child(make_button("Quit", font, func(): get_tree().quit()))

func play_again():
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

# Returns the column that buttons go into

func build_menu(title_text: String) -> VBoxContainer:
	var font = preload("res://fonts/lilita_one_regular.ttf")

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

	var title = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 72)
	column.add_child(title)

	return column

func make_button(text: String, font: Font, on_pressed: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 56)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 32)
	button.pressed.connect(on_pressed)
	return button
