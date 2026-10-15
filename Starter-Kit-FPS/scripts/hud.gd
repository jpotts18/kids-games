extends CanvasLayer

@export var win_when_cleared := true # Turned off in the playground, where clearing all enemies shouldn't end the game

const MAX_HEALTH := 100.0

const BAR_SIZE := Vector2(320, 34)

const COLOR_HEALTHY := Color("4cd964")
const COLOR_HURT := Color("ffcc00")
const COLOR_DANGER := Color("ff3b30")

const COMBO_WINDOW := 3.0 # Seconds to get the next kill and keep the combo going
const MAX_COMBO := 5 # Highest score multiplier
const PAR_TIME := 600.0 # Winning faster than this (in seconds) earns a time bonus
const TIME_BONUS_PER_SECOND := 10 # Bonus points for every second under par
const SAVE_PATH := "user://fps_best.cfg"

const CONTROLS := [ # Shown next to the pause and win menus
	["Move", "W A S D / Arrows"],
	["Look", "Mouse"],
	["Jump", "Space"],
	["Shoot", "Left click"],
	["Grapple", "Hold left click"],
	["Zoom (sniper)", "Right click"],
	["Switch weapon", "E"],
	["Pause", "Esc / P"],
]

var pause_menu: Control
var win_menu: Control
var death_menu: Control
var death_score_label: Label
var death_best_label: Label
var win_score_label: Label
var win_time_label: Label
var win_total_label: Label
var win_best_label: Label

var enemy_counter: Label
var timer_label: Label
var total_enemies := 0
var elapsed_time := 0.0
var game_over := false # Won or died; stops the timer, score and pausing

var score_label: Label
var combo_label: Label
var score := 0
var combo := 0 # Kills in a row, each within COMBO_WINDOW of the last
var combo_timer := 0.0
var score_tween: Tween

var health_fill: ProgressBar # Current health
var health_trail: ProgressBar # Lags behind to show recent damage
var health_number: Label
var damage_flash: TextureRect

var fill_style: StyleBoxFlat
var trail_tween: Tween
var flash_tween: Tween

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep running while the game is paused
	add_to_group("hud") # Enemies call add_score() when they're destroyed
	build_health_bar()
	build_goal_display()
	build_pause_menu()
	build_win_menu()
	build_death_menu()

# Enemy counter, timer and winning

func _process(delta):
	if get_tree().paused or game_over: return

	elapsed_time += delta
	timer_label.text = format_time(elapsed_time)

	if combo_timer > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			combo = 0
			combo_label.visible = false

	var enemies_left = 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if !enemy.destroyed: enemies_left += 1

	total_enemies = max(total_enemies, enemies_left)
	enemy_counter.text = "Enemies: %d / %d" % [enemies_left, total_enemies]

	if win_when_cleared and total_enemies > 0 and enemies_left == 0:
		win()

func win():
	game_over = true
	get_tree().paused = true

	var time_bonus = int(max(0, PAR_TIME - elapsed_time)) * TIME_BONUS_PER_SECOND
	var total = score + time_bonus

	# Compare with the best game so far, and save if this one beat it

	var save = ConfigFile.new()
	save.load(SAVE_PATH) # Fine if it doesn't exist yet
	var best_score = save.get_value("best", "score", 0)
	var best_time = save.get_value("best", "time", INF)
	var new_best_score = total > best_score
	var new_best_time = elapsed_time < best_time

	if new_best_score: save.set_value("best", "score", total)
	if new_best_time: save.set_value("best", "time", elapsed_time)
	if new_best_score or new_best_time: save.save(SAVE_PATH)

	win_score_label.text = "Score: %d" % score
	win_time_label.text = "Time: %s   (bonus +%d)" % [format_time(elapsed_time), time_bonus]
	win_total_label.text = "Total: %d" % total

	if new_best_score:
		win_best_label.text = "NEW BEST SCORE!"
		win_best_label.add_theme_color_override("font_color", Color("ffcc00"))
	else:
		win_best_label.text = "Best: %d   Best time: %s" % [best_score, format_time(min(best_time, elapsed_time))]

	if new_best_time and !new_best_score:
		win_best_label.text = "NEW BEST TIME!   Best score: %d" % best_score

	win_menu.visible = true
	$Crosshair.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# Called by enemies when the player destroys them. Quick kills in a row
# multiply the points (x2, x3, ... up to MAX_COMBO)

func add_score(points: int, world_position: Vector3):
	if game_over: return

	combo = combo + 1 if combo_timer > 0 else 1
	combo_timer = COMBO_WINDOW

	var multiplier = min(combo, MAX_COMBO)
	var gained = points * multiplier
	score += gained
	score_label.text = "Score: %d" % score

	if multiplier > 1:
		combo_label.text = "Combo x%d!" % multiplier
		combo_label.visible = true

	# Score bumps up in size for a moment

	score_label.pivot_offset = score_label.size * Vector2(1, 0.5)
	if score_tween: score_tween.kill()
	score_tween = create_tween()
	score_tween.tween_property(score_label, "scale", Vector2.ONE * 1.25, 0.06)
	score_tween.tween_property(score_label, "scale", Vector2.ONE, 0.2)

	show_floating_points(gained, multiplier, world_position)

# "+100" that rises and fades where the enemy was destroyed

func show_floating_points(gained: int, multiplier: int, world_position: Vector3):
	var label = Label3D.new()
	label.text = "+%d" % gained
	label.font = preload("res://fonts/lilita_one_regular.ttf")
	label.font_size = 96 + 16 * (multiplier - 1) # Bigger for bigger combos
	label.outline_size = 24
	label.modulate = Color("ffcc00") if multiplier > 1 else Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	get_tree().current_scene.add_child(label)
	label.global_position = world_position + Vector3.UP * 0.5

	var tween = label.create_tween().set_parallel()
	tween.tween_property(label, "global_position:y", label.global_position.y + 1.5, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)

# Called by the player when out of health

func die():
	if game_over: return

	game_over = true
	get_tree().paused = true

	var save = ConfigFile.new()
	save.load(SAVE_PATH)
	var best_score = save.get_value("best", "score", 0)

	death_score_label.text = "Score: %d   Time: %s" % [score, format_time(elapsed_time)]
	death_best_label.text = "Best score: %d" % best_score if best_score > 0 else "Clear every enemy to set a best score!"

	death_menu.visible = true
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

	score_label = make_hud_label(font, 34)
	score_label.text = "Score: 0"
	column.add_child(score_label)

	combo_label = make_hud_label(font, 28)
	combo_label.add_theme_color_override("font_color", Color("ffcc00"))
	combo_label.visible = false
	column.add_child(combo_label)

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
	if game_over: return

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
	pause_menu = menu_of(column)

	column.add_child(make_button("Resume", font, func(): set_paused(false)))
	column.add_child(make_button("Quit", font, func(): get_tree().quit()))

func build_win_menu():
	var font = preload("res://fonts/lilita_one_regular.ttf")
	var column = build_menu("YOU WIN!")
	win_menu = menu_of(column)

	win_score_label = make_menu_label(font, 36)
	column.add_child(win_score_label)
	win_time_label = make_menu_label(font, 36)
	column.add_child(win_time_label)
	win_total_label = make_menu_label(font, 48)
	column.add_child(win_total_label)
	win_best_label = make_menu_label(font, 30)
	column.add_child(win_best_label)

	column.add_child(make_button("Play again", font, play_again))
	column.add_child(make_button("Quit", font, func(): get_tree().quit()))

func make_menu_label(font: Font, size: int) -> Label:
	var label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	return label

func build_death_menu():
	var font = preload("res://fonts/lilita_one_regular.ttf")
	var column = build_menu("YOU DIED")
	death_menu = menu_of(column)
	column.get_child(0).add_theme_color_override("font_color", COLOR_DANGER) # Red title

	death_score_label = make_menu_label(font, 36)
	column.add_child(death_score_label)
	death_best_label = make_menu_label(font, 30)
	column.add_child(death_best_label)

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

	# Menu on the left, controls on the right

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 64)
	center.add_child(row)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)

	row.add_child(build_controls(font))

	var title = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 72)
	column.add_child(title)

	return column

func menu_of(column: VBoxContainer) -> Control:
	return column.get_parent().get_parent().get_parent() # Column -> row -> center -> menu

# Panel listing what every key and button does

func build_controls(font: Font) -> Control:
	var panel = PanelContainer.new()
	var box = make_box(Color(0, 0, 0, 0.45))
	box.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", box)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title = make_menu_label(font, 36)
	title.text = "CONTROLS"
	column.add_child(title)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)

	for control in CONTROLS:
		var action = make_menu_label(font, 24)
		action.text = control[0]
		action.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		action.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		grid.add_child(action)

		var key = make_menu_label(font, 24)
		key.text = control[1]
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.add_theme_color_override("font_color", Color("ffcc00"))
		grid.add_child(key)

	return panel

func make_button(text: String, font: Font, on_pressed: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 56)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 32)
	button.pressed.connect(on_pressed)
	return button
