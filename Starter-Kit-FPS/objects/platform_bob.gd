extends Node3D

# Trampoline platforms float slowly up and down. Each one starts at a random
# point in its bob, so they don't all move together

@export var height := 0.75 # How far up and down it moves from its starting spot
@export var cycle_time := 8.0 # Seconds for one full up-and-down

var start_y: float
var time := 0.0

func _ready():
	start_y = position.y
	time = randf() * cycle_time

func _physics_process(delta):
	time += delta
	position.y = start_y + sin(time / cycle_time * TAU) * height
