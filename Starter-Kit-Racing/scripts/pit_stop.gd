extends Node3D

# Pit stop: a box on one side of the road, vehicles that (almost) stop inside it get repaired

const WIDTH := 2.2 # Across the road
const LENGTH := 6.0 # Along the road
const MAX_SPEED := 2.5 # Slower than this (units/s, about 30 km/h) to get repaired
const REPAIR_RATE := 30.0 # Damage repaired per second

const BOX_COLOR := Color(1.0, 0.8, 0.0, 0.35)
const REPAIR_COLOR := Color(0.3, 0.85, 0.4, 0.55)

var font = preload("res://fonts/lilita_one_regular.ttf")

var floor_material: StandardMaterial3D
var time := 0.0

func _ready():
	build()

func _physics_process(delta):
	time += delta
	var someone_repairing := false

	for vehicle in get_tree().get_nodes_in_group("vehicles"):
		var inside = contains(vehicle.sphere.global_position)
		var slow = Vector2(vehicle.sphere.linear_velocity.x, vehicle.sphere.linear_velocity.z).length() < MAX_SPEED

		vehicle.in_pit = inside
		vehicle.repairing = inside and slow and vehicle.damage > 0.0
		if vehicle.repairing:
			vehicle.repair(REPAIR_RATE * delta)
			someone_repairing = true

	# Floor pulses green while repairing

	if someone_repairing:
		floor_material.albedo_color = BOX_COLOR.lerp(REPAIR_COLOR, 0.5 + 0.5 * sin(time * 10))
	else:
		floor_material.albedo_color = BOX_COLOR

func contains(point: Vector3) -> bool:
	var local = to_local(point)
	return abs(local.x) < WIDTH / 2 and abs(local.z) < LENGTH / 2 and abs(local.y) < 1.5

# Painted box with "PIT" written in it, and a floating sign

func build():
	floor_material = StandardMaterial3D.new()
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_material.albedo_color = BOX_COLOR

	var floor_mesh = PlaneMesh.new()
	floor_mesh.size = Vector2(WIDTH, LENGTH)
	floor_mesh.material = floor_material
	var floor = MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.position.y = 0.03
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor)

	# White border lines

	var line_material = StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color.WHITE

	for line in [
		[Vector3(WIDTH / 2, 0, 0), Vector3(0.12, 0.02, LENGTH)],
		[Vector3(-WIDTH / 2, 0, 0), Vector3(0.12, 0.02, LENGTH)],
		[Vector3(0, 0, LENGTH / 2), Vector3(WIDTH + 0.12, 0.02, 0.12)],
		[Vector3(0, 0, -LENGTH / 2), Vector3(WIDTH + 0.12, 0.02, 0.12)],
	]:
		var box = BoxMesh.new()
		box.size = line[1]
		box.material = line_material
		var mesh = MeshInstance3D.new()
		mesh.mesh = box
		mesh.position = line[0] + Vector3(0, 0.04, 0)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

	# "PIT" painted on the road

	var painted = make_label("PIT", 160)
	painted.rotation = Vector3(-PI / 2, 0, 0) # Flat on the road, readable when driving in
	painted.position.y = 0.06
	add_child(painted)

	# Floating sign

	var sign = make_label("PIT STOP", 110)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = Vector3(0, 2.8, 0)
	sign.modulate = Color("ffcc00")
	add_child(sign)

func make_label(text: String, size: int) -> Label3D:
	var label = Label3D.new()
	label.text = text
	label.font = font
	label.font_size = size
	label.outline_size = size / 5
	label.outline_modulate = Color(0, 0, 0, 0.6)
	label.pixel_size = 0.005
	return label
