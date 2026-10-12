extends StaticBody3D

# Turret: sits on a high platform, turns to follow the player and fires slow
# glowing balls at them. The barrel glows brighter just before each shot, so
# watch for it and dodge! The balls can also be shot out of the air

@export var player: Node3D

@export var notice_radius := 22.0 # Starts shooting when it can see the player this close
@export var turn_speed := 2.5 # How quickly it turns to follow the player
@export var fire_interval := 2.0 # Seconds between shots
@export var charge_time := 0.6 # The barrel glows for this long before firing
@export var shot_speed := 9.0 # How fast its balls fly
@export var shot_damage := 12 # Damage when a ball hits the player

@export_range(0, 1) var health_drop_chance := 0.5 # Chance to drop a health pickup when destroyed

const BODY_COLOR := Color("3a3f4b")
const TRIM_COLOR := Color("ff9500")
const GLOW_COLOR := Color("ff2d55")

var health := 150
var destroyed := false
var alerted := false # True while it can see the player
var fire_timer := 0.0
var time := 0.0

var head: Node3D
var muzzle: Node3D
var body_material: StandardMaterial3D
var glow_material: StandardMaterial3D
var alert_icon: Label3D

func _ready():
	add_to_group("enemies") # Used by the HUD to count enemies left

	if !player:
		player = get_tree().get_first_node_in_group("player") # Turrets placed inside chunks find the player themselves

	var shape = CollisionShape3D.new()
	shape.shape = CylinderShape3D.new()
	shape.shape.radius = 0.55
	shape.shape.height = 1.3
	shape.position.y = 0.65
	add_child(shape)

	build_visual()
	build_alert_icon()

	fire_timer = fire_interval
	snap_to_ground.call_deferred()

func _physics_process(delta):
	if destroyed: return

	time += delta

	var can_see = can_see_player()

	if !alerted and player.is_sneaking():
		can_see = false # Zipping past on the grappling hook doesn't wake it up

	if can_see and !alerted:
		notice_player()
	alerted = can_see

	if !alerted:
		head.rotate_y(0.4 * delta) # Slowly scans around
		set_charge(0.0)
		fire_timer = fire_interval * 0.5 # First shot comes quickly after spotting the player
		return

	aim_at_player(delta)

	fire_timer -= delta
	set_charge(1.0 - clamp(fire_timer / charge_time, 0.0, 1.0))

	if fire_timer <= 0:
		fire()
		fire_timer = fire_interval

# Sits on whatever is below it (so it can be placed roughly in the editor)

func snap_to_ground():
	var from = global_position + Vector3.UP * 0.5
	var query = PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 5)
	query.exclude = [get_rid()]

	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit: global_position = hit.position

# Only shoots when there's a clear line to the player

func can_see_player() -> bool:
	var target = player.global_position + Vector3.UP
	if muzzle.global_position.distance_to(target) > notice_radius: return false

	var query = PhysicsRayQueryParameters3D.create(muzzle.global_position, target)
	query.exclude = [get_rid()]

	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return hit and hit.collider == player

# Turns smoothly, so a moving player can stay ahead of it

func aim_at_player(delta):
	var target = player.global_position + Vector3.UP * 0.8
	if head.global_position.distance_to(target) < 0.5: return

	var current = head.global_basis.orthonormalized() # Tiny rounding errors from the rotated chunks would upset slerp
	var wanted = Basis.looking_at(target - head.global_position, Vector3.UP)
	head.global_basis = current.slerp(wanted, min(turn_speed * delta, 1.0))

func fire():
	var shot = preload("res://objects/turret_shot.gd").new()
	shot.damage_amount = shot_damage
	shot.speed = shot_speed
	shot.shooter = self
	get_tree().current_scene.add_child(shot)
	shot.global_position = muzzle.global_position
	shot.direction = -head.global_basis.z

	head.position.z = 0.15 # Recoil
	create_tween().tween_property(head, "position:z", 0.0, 0.2)

	Audio.play("sounds/enemy_attack.ogg")

# The barrel glows brighter while charging up a shot

func set_charge(amount: float):
	glow_material.emission_energy_multiplier = lerp(0.5, 4.0, amount)
	muzzle.scale = Vector3.ONE * lerp(1.0, 1.6, amount)

func notice_player():
	alert_icon.visible = true
	alert_icon.scale = Vector3.ONE * 0.2

	var tween = create_tween()
	tween.tween_property(alert_icon, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.8)
	tween.tween_callback(func(): alert_icon.visible = false)

# Take damage from player

func damage(amount):
	if destroyed: return

	Audio.play("sounds/enemy_hurt.ogg")

	health -= amount

	# Flash white when hit

	body_material.emission_enabled = true
	create_tween().tween_callback(func(): body_material.emission_enabled = false).set_delay(0.08)

	if health <= 0:
		destroy()

func destroy():
	if destroyed: return

	destroyed = true

	Audio.play("sounds/enemy_destroy.ogg")

	var explosion = preload("res://objects/explosion.gd").new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position + Vector3.UP * 0.8
	explosion.scale = Vector3.ONE * 1.5

	if randf() < health_drop_chance:
		var pickup = preload("res://objects/health_pickup.gd").new()
		get_tree().current_scene.add_child(pickup)
		pickup.global_position = global_position + Vector3.UP * 0.5

	queue_free()

# Built from simple shapes: a round base, a turning head with a barrel and an eye

func build_visual():
	body_material = StandardMaterial3D.new()
	body_material.albedo_color = BODY_COLOR
	body_material.roughness = 0.4
	body_material.emission = Color.WHITE
	body_material.emission_energy_multiplier = 0.8

	var trim_material = StandardMaterial3D.new()
	trim_material.albedo_color = TRIM_COLOR

	glow_material = StandardMaterial3D.new()
	glow_material.albedo_color = GLOW_COLOR
	glow_material.emission_enabled = true
	glow_material.emission = GLOW_COLOR
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Base

	var base = MeshInstance3D.new()
	base.mesh = CylinderMesh.new()
	base.mesh.top_radius = 0.4
	base.mesh.bottom_radius = 0.55
	base.mesh.height = 0.5
	base.mesh.material = body_material
	base.position.y = 0.25
	add_child(base)

	var ring = MeshInstance3D.new()
	ring.mesh = CylinderMesh.new()
	ring.mesh.top_radius = 0.45
	ring.mesh.bottom_radius = 0.45
	ring.mesh.height = 0.08
	ring.mesh.material = trim_material
	ring.position.y = 0.52
	add_child(ring)

	# Head (turns to follow the player)

	var pivot = Node3D.new()
	pivot.position.y = 0.85
	add_child(pivot)

	head = Node3D.new()
	pivot.add_child(head)

	var dome = MeshInstance3D.new()
	dome.mesh = SphereMesh.new()
	dome.mesh.radius = 0.4
	dome.mesh.height = 0.7
	dome.mesh.material = body_material
	head.add_child(dome)

	var eye = MeshInstance3D.new()
	eye.mesh = BoxMesh.new()
	eye.mesh.size = Vector3(0.3, 0.07, 0.05)
	eye.mesh.material = glow_material
	eye.position = Vector3(0, 0.12, -0.36)
	head.add_child(eye)

	# Barrel, pointing forward (-Z)

	var barrel = MeshInstance3D.new()
	barrel.mesh = CylinderMesh.new()
	barrel.mesh.top_radius = 0.09
	barrel.mesh.bottom_radius = 0.12
	barrel.mesh.height = 0.7
	barrel.mesh.material = body_material
	barrel.rotation.x = -PI / 2
	barrel.position = Vector3(0, -0.05, -0.55)
	head.add_child(barrel)

	var tip = MeshInstance3D.new()
	tip.mesh = CylinderMesh.new()
	tip.mesh.top_radius = 0.13
	tip.mesh.bottom_radius = 0.13
	tip.mesh.height = 0.1
	tip.mesh.material = trim_material
	tip.rotation.x = -PI / 2
	tip.position = Vector3(0, -0.05, -0.88)
	head.add_child(tip)

	# Glowing muzzle (also where the balls come out)

	muzzle = MeshInstance3D.new()
	muzzle.mesh = SphereMesh.new()
	muzzle.mesh.radius = 0.08
	muzzle.mesh.height = 0.16
	muzzle.mesh.material = glow_material
	muzzle.position = Vector3(0, -0.05, -0.95)
	head.add_child(muzzle)

func build_alert_icon():
	alert_icon = Label3D.new()
	alert_icon.text = "!"
	alert_icon.font = preload("res://fonts/lilita_one_regular.ttf")
	alert_icon.font_size = 160
	alert_icon.outline_size = 36
	alert_icon.modulate = Color("ff3b30")
	alert_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert_icon.no_depth_test = true
	alert_icon.position = Vector3(0, 2.0, 0)
	alert_icon.visible = false
	add_child(alert_icon)
