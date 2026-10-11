extends Control

# Health bar: goes down as the vehicle takes damage, turns red and flashes when critical

const HEALTHY := Color("4cd964")
const WORN := Color("ffcc00")
const CRITICAL := Color("ff3b30")

var vehicle: Vehicle
var font: Font

var shown_health := 1.0 # Smoothed, 0 to 1
var hit_flash := 0.0 # Briefly brightens the bar after a hit
var time := 0.0

func _ready():
	custom_minimum_size = Vector2(320, 90)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_vehicle(new_vehicle: Vehicle):
	vehicle = new_vehicle
	vehicle.damaged.connect(func(_amount): hit_flash = 1.0)

func _process(delta):
	if !vehicle: return

	time += delta
	hit_flash = max(0.0, hit_flash - delta * 3)
	shown_health = lerp(shown_health, health(), clamp(delta * 6, 0, 1))
	queue_redraw()

func health() -> float:
	return 1.0 - vehicle.damage / vehicle.MAX_DAMAGE

func _draw():
	var critical = vehicle != null and vehicle.is_critical()
	var color = HEALTHY
	if critical: color = CRITICAL
	elif shown_health < 0.6: color = WORN

	# Title, with a flashing warning when critical

	var title = "HEALTH"
	var title_color = Color.WHITE
	if vehicle.repairing:
		title = "REPAIRING..."
		title_color = HEALTHY
		color = HEALTHY.lerp(Color.WHITE, 0.3 + 0.3 * sin(time * 10))
	elif vehicle.in_pit and vehicle.damage > 0.0:
		title = "SLOW DOWN TO REPAIR"
		title_color = WORN
	elif vehicle.in_pit:
		title = "ALL FIXED!"
		title_color = HEALTHY
	elif critical:
		title = "CRITICAL - GO TO THE PIT!"
		title_color = CRITICAL if fmod(time, 0.6) < 0.3 else Color.WHITE
	draw_string_outline(font, Vector2(0, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 8, Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(0, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, title_color)

	# Bar

	var bar = Rect2(0, 44, size.x, 34)
	draw_rect(bar.grow(4), Color(0, 0, 0, 0.55))
	draw_rect(bar, Color(1, 1, 1, 0.15))
	var fill = Rect2(bar.position, Vector2(bar.size.x * clamp(shown_health, 0, 1), bar.size.y))
	draw_rect(fill, color.lerp(Color.WHITE, hit_flash * 0.6))

	# Critical line marker

	var critical_x = bar.size.x * (1.0 - vehicle.CRITICAL_DAMAGE / vehicle.MAX_DAMAGE) if vehicle else 0.0
	draw_line(Vector2(critical_x, bar.position.y), Vector2(critical_x, bar.end.y), Color(0, 0, 0, 0.6), 3)

	var percent = "%d%%" % roundi(shown_health * 100)
	var text_position = Vector2(bar.position.x + 10, bar.end.y - 7)
	draw_string_outline(font, text_position, percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0, 0, 0, 0.55))
	draw_string(font, text_position, percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
