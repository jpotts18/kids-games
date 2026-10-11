extends Control

# Round speedometer: dial with ticks, needle and the speed as a number

const MAX_SPEED := 180.0 # Highest number on the dial (km/h) - upgraded vehicles go faster than 140
const KMH_PER_UNIT := 12.0 # Game units per second -> km/h (top speed is about 10 units/s, so about 124 km/h)
const START_ANGLE := deg_to_rad(135.0) # Dial goes from bottom-left...
const END_ANGLE := deg_to_rad(405.0) # ...around the top to bottom-right
const RED_ZONE := 150.0 # Speeds above this are drawn red

var vehicle: Vehicle
var font: Font

var speed := 0.0 # Smoothed, in km/h

func _ready():
	custom_minimum_size = Vector2(240, 240)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta):
	if !vehicle: return

	var velocity = vehicle.linear_velocity
	var target = Vector2(velocity.x, velocity.z).length() * KMH_PER_UNIT
	speed = lerp(speed, target, clamp(delta * 8, 0, 1))
	queue_redraw()

func _draw():
	var center = size / 2
	var radius = min(size.x, size.y) / 2 - 8

	# Background

	draw_circle(center, radius + 6, Color(0, 0, 0, 0.55))
	draw_arc(center, radius - 10, START_ANGLE, angle_for(RED_ZONE), 48, Color(1, 1, 1, 0.25), 8, true)
	draw_arc(center, radius - 10, angle_for(RED_ZONE), END_ANGLE, 16, Color("ff3b30", 0.8), 8, true)

	# Filled arc showing the current speed

	var fill_color = Color("ff3b30") if speed > RED_ZONE else Color("ffcc00")
	if speed > 1:
		draw_arc(center, radius - 10, START_ANGLE, angle_for(speed), 48, fill_color, 8, true)

	# Ticks and numbers every 20 km/h

	for value in range(0, int(MAX_SPEED) + 1, 10):
		var direction = Vector2.from_angle(angle_for(value))
		var major = value % 20 == 0
		var inner = radius - (32 if major else 24)
		draw_line(center + direction * inner, center + direction * (radius - 16), Color.WHITE, 3 if major else 2, true)

		if major and font:
			var text = str(value)
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			var text_center = center + direction * (radius - 46)
			draw_string(font, text_center + Vector2(-text_size.x / 2, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))

	# Needle

	var needle_direction = Vector2.from_angle(angle_for(speed))
	draw_line(center - needle_direction * 12, center + needle_direction * (radius - 20), Color("ff5a1f"), 5, true)
	draw_circle(center, 9, Color("ff5a1f"))

	# Speed number and units

	if font:
		var number = str(int(round(speed)))
		draw_text_centered(number, center + Vector2(0, 58), 44)
		var units = "R  km/h" if vehicle and vehicle.linear_speed < -0.05 else "km/h"
		draw_text_centered(units, center + Vector2(0, 84), 18)

func angle_for(value: float) -> float:
	return lerp(START_ANGLE, END_ANGLE, clamp(value / MAX_SPEED, 0.0, 1.0))

func draw_text_centered(text: String, at: Vector2, font_size: int):
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string_outline(font, at - Vector2(text_size.x / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.6))
	draw_string(font, at - Vector2(text_size.x / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
