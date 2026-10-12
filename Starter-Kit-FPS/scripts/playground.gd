extends Node3D

# Playground: a test arena for trying out enemies, weapons and effects without
# playing the real game. Clearing all enemies doesn't end anything here.
#
# Open scenes/playground.tscn in the editor and press F6 (Run Current Scene).
# Add new things to SPAWNABLES to make them spawnable with a number key.

const SPAWNABLES := [
	{ "name": "Bomber", "scene": "res://objects/bomber.tscn", "distance": 8.0, "height": 1.0 },
	{ "name": "Flying enemy", "scene": "res://objects/enemy.tscn", "distance": 8.0, "height": 2.5 },
	{ "name": "Health pickup", "script": "res://objects/health_pickup.gd", "distance": 3.0, "height": 1.0 },
	{ "name": "Explosion", "script": "res://objects/explosion.gd", "distance": 5.0, "height": 1.0 },
	{ "name": "Sniper pickup", "script": "res://objects/weapon_pickup.gd", "distance": 3.0, "height": 1.0 },
]

const SLOW_MOTION_SCALE := 0.25

@onready var player = $Player
@onready var spawned = $Spawned

var god_mode := false
var ai_frozen := false
var slow_motion := false

var help_label: Label
var status_label: Label

func _ready():
	build_help()
	update_status()

func _process(_delta):
	if god_mode and player.health < player.max_health:
		player.heal(player.max_health)

func _exit_tree():
	Engine.time_scale = 1.0 # Don't leave slow motion on when the scene reloads

func _unhandled_input(event):
	if !(event is InputEventKey) or !event.pressed or event.echo: return

	var key = event.physical_keycode

	if key >= KEY_1 and key < KEY_1 + SPAWNABLES.size():
		spawn(SPAWNABLES[key - KEY_1])
	else:
		match key:
			KEY_X: clear_spawned()
			KEY_G: god_mode = !god_mode
			KEY_F: set_ai_frozen(!ai_frozen)
			KEY_T: set_slow_motion(!slow_motion)
			KEY_R: get_tree().reload_current_scene.call_deferred()
			KEY_H: help_label.visible = !help_label.visible
			_: return

	update_status()
	get_viewport().set_input_as_handled()

# Spawns something in front of the player (on the ground, it falls into place)

func spawn(entry: Dictionary):
	var thing: Node3D

	if entry.has("scene"):
		thing = load(entry.scene).instantiate()
	else:
		thing = load(entry.script).new()

	var forward = -player.global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()

	# Position is set before adding (Spawned sits at the origin), so enemies save the right home position in _ready()

	thing.position = player.global_position + forward * entry.distance + Vector3.UP * entry.height
	spawned.add_child(thing)

	if ai_frozen and thing.is_in_group("enemies"):
		thing.process_mode = Node.PROCESS_MODE_DISABLED

func clear_spawned():
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	for child in spawned.get_children():
		child.queue_free()

func set_ai_frozen(frozen: bool):
	ai_frozen = frozen
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.process_mode = Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT

func set_slow_motion(enabled: bool):
	slow_motion = enabled
	Engine.time_scale = SLOW_MOTION_SCALE if enabled else 1.0

# On-screen help and status

func build_help():
	var font = preload("res://fonts/lilita_one_regular.ttf")

	var layer = CanvasLayer.new()
	add_child(layer)

	var column = VBoxContainer.new()
	column.position = Vector2(48, 40)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(column)

	var title = make_label(font, 30)
	title.text = "PLAYGROUND"
	column.add_child(title)

	var lines = []
	for i in SPAWNABLES.size():
		lines.append("%d  Spawn %s" % [i + 1, SPAWNABLES[i].name])
	lines.append_array([
		"X  Clear enemies",
		"G  God mode",
		"F  Freeze enemies",
		"T  Slow motion",
		"R  Reset",
		"H  Hide this help",
	])

	help_label = make_label(font, 20)
	help_label.text = "\n".join(lines)
	column.add_child(help_label)

	status_label = make_label(font, 20)
	status_label.modulate = Color("ffcc00")
	column.add_child(status_label)

func update_status():
	var flags = []
	if god_mode: flags.append("GOD MODE")
	if ai_frozen: flags.append("FROZEN")
	if slow_motion: flags.append("SLOW-MO")
	status_label.text = "  ".join(flags)

func make_label(font: Font, size: int) -> Label:
	var label = Label.new()
	var settings = LabelSettings.new()
	settings.font = font
	settings.font_size = size
	settings.outline_size = 8
	settings.outline_color = Color(0, 0, 0, 0.5)
	label.label_settings = settings
	return label
