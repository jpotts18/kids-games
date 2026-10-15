extends CharacterBody3D

# Bomber: a little walking bomb robot. Wanders around its platform, charges at
# the player when it spots them, lights its fuse when close and explodes.
# It never leaves the platform it starts on.
# Shoot it from a distance before it gets to you!

@export var player: Node3D

@export var wander_speed := 1.2 # Walking speed while wandering around home
@export var charge_speed := 4.5 # Running speed while chasing the player
@export var wander_radius := 2.0 # How far from home it wanders

@export var notice_radius := 8.0 # Starts charging when the player comes this close
@export var give_up_radius := 18.0 # Stops charging when the player gets this far away

@export var fuse_distance := 2.0 # Lights the fuse when this close to the player
@export var fuse_time := 1.2 # Seconds between lighting the fuse and exploding
@export var blast_radius := 3.5 # Player takes damage inside this radius
@export var blast_damage := 30 # Damage at the center of the blast (less further out)


@export_range(0, 1) var health_drop_chance := 0.5 # Chance to drop a health pickup when destroyed
@export var points := 150 # Score for destroying it

const GRAVITY := 20.0

const BODY_COLOR := Color("3a3f4b")
const EYE_COLOR := Color("ff3b30")
const SPARK_COLOR := Color("ffcc00")

var health := 60
var destroyed := false
var alerted := false # True while charging the player
var fuse_lit := false
var fuse_timer := 0.0
var beep_timer := 0.0
var time := 0.0

var home_position: Vector3
var home_platform: Object # The platform the bomber landed on; it stays on this one
var wander_target: Vector3
var wander_wait := 0.0

var visual: Node3D
var body_mesh: MeshInstance3D
var body_material: StandardMaterial3D
var eye_material: StandardMaterial3D
var spark: MeshInstance3D
var feet: Array[MeshInstance3D] = []
var alert_icon: Label3D

func _ready():
	add_to_group("enemies") # Used by the HUD to count enemies left

	if !player:
		player = get_tree().get_first_node_in_group("player") # Bombers placed inside chunks find the player themselves

	home_position = global_position
	wander_target = home_position

	var shape = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 0.45
	shape.position.y = 0.5
	add_child(shape)

	build_visual()
	build_alert_icon()

func _physics_process(delta):
	if destroyed: return

	time += delta

	if !is_on_floor():
		velocity.y -= GRAVITY * delta
	elif !home_platform:
		home_platform = platform_below(global_position)

	if global_position.y < -30: # Fell out of the world
		destroyed = true
		queue_free()
		return

	var distance_to_player = global_position.distance_to(player.global_position)

	if !alerted and distance_to_player < notice_radius and !player.is_sneaking():
		notice_player()
	elif alerted and !fuse_lit and distance_to_player > give_up_radius:
		alerted = false
		wander_target = home_position

	if fuse_lit:
		update_fuse(delta)
		walk_towards(player.global_position, charge_speed * 0.4) # Keeps creeping closer while the fuse burns
	elif alerted:
		if distance_to_player < fuse_distance:
			light_fuse()
		walk_towards(player.global_position, charge_speed)
	else:
		wander(delta)

	move_and_slide()
	animate(delta)

# Walking

func walk_towards(target: Vector3, speed: float):
	var direction = target - global_position
	direction.y = 0

	if direction.length() < 0.3:
		stop_walking(speed)
		return

	direction = direction.normalized()

	if !has_ground_ahead(direction, 0.7):
		stop_walking(speed) # Don't walk off the edge of the home platform
		return

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# Turn to face the walking direction

	var target_angle = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 0.2)

func stop_walking(speed: float):
	velocity.x = move_toward(velocity.x, 0, speed)
	velocity.z = move_toward(velocity.z, 0, speed)

func wander(delta):
	if global_position.distance_to(Vector3(wander_target.x, global_position.y, wander_target.z)) < 0.4:
		wander_wait -= delta

		if wander_wait <= 0:
			var offset = Vector2.from_angle(randf() * TAU) * randf_range(0.5, wander_radius)
			wander_target = home_position + Vector3(offset.x, 0, offset.y)
			wander_wait = randf_range(1.0, 2.5)

	walk_towards(wander_target, wander_speed)

# Checks that the home platform continues some distance ahead, so the bomber
# never walks (or hops) off it. Before it has landed anywhere, anything goes

func has_ground_ahead(direction: Vector3, distance: float) -> bool:
	if !home_platform: return true

	return platform_below(global_position + direction * distance) == home_platform

func platform_below(point: Vector3) -> Object:
	var from = point + Vector3.UP * 0.5
	var query = PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0)
	query.exclude = [get_rid()]

	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.collider if hit else null

# Spotting the player, with a "!" above the head

func notice_player():
	alerted = true

	alert_icon.visible = true
	alert_icon.scale = Vector3.ONE * 0.2

	var tween = create_tween()
	tween.tween_property(alert_icon, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.8)
	tween.tween_callback(func(): alert_icon.visible = false)

	Audio.play("sounds/jump_a.ogg")

	velocity.y = 5 # Hop in surprise

# Fuse: flashes faster and faster, then goes boom

func light_fuse():
	fuse_lit = true
	fuse_timer = fuse_time

func update_fuse(delta):
	fuse_timer -= delta

	var progress = 1.0 - fuse_timer / fuse_time
	var flash_speed = lerp(6.0, 30.0, progress)
	var flash_on = sin(time * flash_speed) > 0

	body_material.albedo_color = Color.WHITE if flash_on else BODY_COLOR
	body_material.emission_enabled = flash_on
	visual.scale = Vector3.ONE * (1.0 + progress * 0.3) # Swells up before popping

	beep_timer -= delta

	if beep_timer <= 0:
		Audio.play("sounds/weapon_change.ogg") # Beeps faster as the fuse runs out
		beep_timer = lerp(0.35, 0.1, progress)

	if fuse_timer <= 0:
		destroy(false) # Blew itself up, so no points

# Take damage from player

func damage(amount):
	if destroyed: return

	Audio.play("sounds/enemy_hurt.ogg")

	health -= amount

	# Flash white when hit

	body_material.emission_enabled = true
	create_tween().tween_callback(end_hit_flash).set_delay(0.08)

	if !alerted:
		notice_player() # Getting shot gets the bomber's attention

	if health <= 0:
		destroy()

func end_hit_flash():
	if !fuse_lit: body_material.emission_enabled = false

# Explode! Hurts the player if they're too close

func destroy(shot_by_player := true):
	if destroyed: return

	destroyed = true

	if shot_by_player:
		get_tree().call_group("hud", "add_score", points, global_position + Vector3.UP * 0.5)

	Audio.play("sounds/enemy_destroy.ogg")

	var explosion = preload("res://objects/explosion.gd").new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position + Vector3.UP * 0.5
	explosion.scale = Vector3.ONE * 1.5

	var distance_to_player = global_position.distance_to(player.global_position)

	if distance_to_player < blast_radius and player.has_method("damage"):
		var falloff = 1.0 - distance_to_player / blast_radius
		player.damage(int(blast_damage * lerp(0.4, 1.0, falloff)))

	if randf() < health_drop_chance:
		var pickup = preload("res://objects/health_pickup.gd").new()
		get_tree().current_scene.add_child(pickup)
		pickup.global_position = global_position + Vector3.UP * 0.5

	queue_free()

# Waddle, bob and sparkle

func animate(delta):
	var speed = Vector2(velocity.x, velocity.z).length()
	var step = time * (6.0 + speed * 3.0)

	body_mesh.position.y = 0.55 + abs(sin(step)) * 0.06 * min(speed, 1.0)
	visual.rotation.z = sin(step) * 0.12 * min(speed, 1.0)

	for i in feet.size():
		var side = 1.0 if i == 0 else -1.0
		feet[i].position.z = sin(step + PI * i) * 0.15 * min(speed, 1.0)
		feet[i].position.x = 0.2 * side

	spark.scale = Vector3.ONE * randf_range(0.7, 1.3)
	spark.rotation.y += 10 * delta

# The bomber is built from simple shapes: a round body with a fuse, eyes and feet

func build_visual():
	visual = Node3D.new()
	add_child(visual)

	body_material = StandardMaterial3D.new()
	body_material.albedo_color = BODY_COLOR
	body_material.roughness = 0.4
	body_material.emission = Color.WHITE
	body_material.emission_energy_multiplier = 0.8

	eye_material = make_glow_material(EYE_COLOR)

	# Body

	body_mesh = MeshInstance3D.new()
	body_mesh.mesh = SphereMesh.new()
	body_mesh.mesh.radius = 0.45
	body_mesh.mesh.height = 0.9
	body_mesh.mesh.material = body_material
	body_mesh.position.y = 0.55
	visual.add_child(body_mesh)

	# Eyes (angry slits)

	for side in [-1, 1]:
		var eye = MeshInstance3D.new()
		eye.mesh = BoxMesh.new()
		eye.mesh.size = Vector3(0.14, 0.06, 0.05)
		eye.mesh.material = eye_material
		eye.position = Vector3(0.14 * side, 0.1, 0.41)
		eye.rotation.z = -0.3 * side
		body_mesh.add_child(eye)

	# Fuse cap and fuse

	var cap = MeshInstance3D.new()
	cap.mesh = CylinderMesh.new()
	cap.mesh.top_radius = 0.14
	cap.mesh.bottom_radius = 0.16
	cap.mesh.height = 0.12
	cap.mesh.material = body_material
	cap.position.y = 0.45
	body_mesh.add_child(cap)

	var fuse_material = StandardMaterial3D.new()
	fuse_material.albedo_color = Color("c8a165")

	var fuse = MeshInstance3D.new()
	fuse.mesh = CylinderMesh.new()
	fuse.mesh.top_radius = 0.03
	fuse.mesh.bottom_radius = 0.03
	fuse.mesh.height = 0.25
	fuse.mesh.material = fuse_material
	fuse.position = Vector3(0, 0.6, -0.04)
	fuse.rotation.x = -0.35
	body_mesh.add_child(fuse)

	# Spark on the tip of the fuse

	spark = MeshInstance3D.new()
	spark.mesh = SphereMesh.new()
	spark.mesh.radius = 0.07
	spark.mesh.height = 0.14
	spark.mesh.material = make_glow_material(SPARK_COLOR)
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spark.position = Vector3(0, 0.73, -0.09)
	body_mesh.add_child(spark)

	# Feet

	var foot_material = StandardMaterial3D.new()
	foot_material.albedo_color = Color("ff9500")

	for i in 2:
		var foot = MeshInstance3D.new()
		foot.mesh = BoxMesh.new()
		foot.mesh.size = Vector3(0.18, 0.12, 0.28)
		foot.mesh.material = foot_material
		foot.position = Vector3(0.2 if i == 0 else -0.2, 0.06, 0)
		visual.add_child(foot)
		feet.append(foot)

func make_glow_material(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func build_alert_icon():
	alert_icon = Label3D.new()
	alert_icon.text = "!"
	alert_icon.font = preload("res://fonts/lilita_one_regular.ttf")
	alert_icon.font_size = 160
	alert_icon.outline_size = 36
	alert_icon.modulate = Color("ff3b30")
	alert_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert_icon.no_depth_test = true
	alert_icon.position = Vector3(0, 1.6, 0)
	alert_icon.visible = false
	add_child(alert_icon)
