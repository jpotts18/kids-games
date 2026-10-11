class_name Vehicle extends Node3D

# Nodes

@onready var sphere: RigidBody3D = $Sphere
@onready var raycast: RayCast3D = $Ground

# Vehicle elements

@onready var vehicle_model = $Container
@onready var vehicle_body = get_node_or_null("Container/Model/body")

# (Optional) wheels

@onready var wheel_fl = get_node_or_null("Container/Model/wheel-front-left")
@onready var wheel_fr = get_node_or_null("Container/Model/wheel-front-right")
@onready var wheel_bl = get_node_or_null("Container/Model/wheel-back-left")
@onready var wheel_br = get_node_or_null("Container/Model/wheel-back-right")

# Effects

@onready var trail_left = get_node_or_null("Container/TrailLeft")
@onready var trail_right = get_node_or_null("Container/TrailRight")

# Sounds

@onready var screech_sound: AudioStreamPlayer3D = $Container/ScreechSound
@onready var engine_sound: AudioStreamPlayer3D = $Container/EngineSound
@onready var impact_sound: AudioStreamPlayer3D = $Container/ImpactSound

var controls_enabled := true # Turned off during the countdown and after the race
var ai_input = null # Vector2 (steer, throttle) set by an opponent driver; null means keyboard controls

# Garage upgrades (1.0 / 0.0 = no upgrade)

var speed_multiplier := 1.0
var acceleration_multiplier := 1.0
var steering_multiplier := 1.0
var grip := 0.0 # Removes sideways sliding
var brake_strength := 0.0 # Extra braking

var input: Vector3
var normal: Vector3

var acceleration: float
var angular_speed: float
var linear_speed: float

var colliding: bool

var linear_velocity: Vector3
var prev_position: Vector3

var calculated_lean: float

# Bumping into other vehicles

const BUMP_DISTANCE := 1.1 # Distance between two vehicles' centers when they touch
const BUMP_STRENGTH := 2.0 # Base push (units/s) each vehicle gets when they touch
const BUMP_COOLDOWN := 0.35

var bump_cooldown := 0.0

# Damage: hitting walls or other vehicles hard damages the vehicle, a badly damaged vehicle is slower

const MAX_DAMAGE := 100.0
const CRITICAL_DAMAGE := 70.0 # From here on the vehicle loses top speed (and smokes)
const CRITICAL_SPEED := 0.6 # Top speed at full damage (60%)
const WALL_DAMAGE_THRESHOLD := 3.5 # Losing less speed than this (units/s) in one hit does no damage
const WALL_DAMAGE := 4.0 # Damage per unit/s above the threshold
const BUMP_DAMAGE_THRESHOLD := 3.0 # Bumping into a vehicle slower than this does no damage
const BUMP_DAMAGE := 2.5

signal damaged(amount: float)

var damage := 0.0
var in_pit := false # Set by the pit stop
var repairing := false
var flat_speed := 0.0 # Speed of the physics sphere along the ground last frame, to detect crashes
var smoke: GPUParticles3D

# Public Functions

func get_vehicle_position() -> Vector3: return vehicle_model.global_position

# Functions

func _enter_tree():
	add_to_group("vehicles")

func _physics_process(delta):

	if smoke == null and trail_left != null: create_smoke()
	check_crash()
	handle_input(delta)
	handle_bumps(delta)

	var direction = sign(linear_speed)
	if direction == 0: direction = sign(input.z) if abs(input.z) > 0.1 else 1

	var steering_grip = clamp(abs(linear_speed), 0.2, 1.0)

	var target_angular = -input.x * steering_grip * 4 * steering_multiplier * direction
	angular_speed = lerp(angular_speed, target_angular, delta * 4)

	vehicle_model.rotate_y(angular_speed * delta)

	# Ground alignment

	if raycast.is_colliding():
		if !colliding:
			if vehicle_body != null: vehicle_body.position = Vector3(0, 0.1, 0) # Bounce
			input.z = 0

		normal = raycast.get_collision_normal()

		# Orient model to colliding normal

		if normal.dot(vehicle_model.global_basis.y) > 0.5:
			var xform = align_with_y(vehicle_model.global_transform, normal)
			vehicle_model.global_transform = vehicle_model.global_transform.interpolate_with(xform, 0.2).orthonormalized()

	colliding = raycast.is_colliding()

	var target_speed = input.z

	if (target_speed < 0 and linear_speed > 0.01):
		linear_speed = lerp(linear_speed, 0.0, delta * 8)
		sphere.angular_velocity *= max(0.0, 1.0 - brake_strength * delta) # Upgraded brakes
	else:
		if (target_speed < 0):
			linear_speed = lerp(linear_speed, target_speed / 2, delta * 2)
		else:
			linear_speed = lerp(linear_speed, target_speed, delta * 6 * acceleration_multiplier)

	acceleration = lerpf(acceleration, linear_speed + (abs(sphere.angular_velocity.length() * linear_speed) / 100), delta * 1)

	# Match vehicle model to physics sphere

	vehicle_model.position = sphere.position - Vector3(0, 0.65, 0)
	raycast.position = sphere.position

	# Calculate vehicle model linear velocity

	linear_velocity = (vehicle_model.position - prev_position) / delta
	prev_position = vehicle_model.position

	# Visual and audio effects

	effect_engine(delta)
	effect_body(delta)
	effect_wheels(delta)
	effect_trails()

# Handle input when vehicle is colliding with ground

func handle_input(delta):

	if !controls_enabled:
		input = Vector3.ZERO
	elif raycast.is_colliding():
		if ai_input != null:
			input.x = ai_input.x
			input.z = ai_input.y
		else:
			input.x = Input.get_axis("left", "right")
			input.z = Input.get_axis("back", "forward")

	var roll_axis = vehicle_model.get_global_transform().basis.x
	sphere.angular_velocity += roll_axis * (linear_speed * 100 * speed_multiplier * acceleration_multiplier * damage_speed()) * delta

	# Grip: remove some of the rolling that isn't in the direction the vehicle faces (less drifting)

	if grip > 0 and raycast.is_colliding():
		var forward_roll = roll_axis * sphere.angular_velocity.dot(roll_axis)
		sphere.angular_velocity = forward_roll + (sphere.angular_velocity - forward_roll) * max(0.0, 1.0 - grip * delta)

# When two vehicles touch, push both apart (each pair is handled once, by the vehicle with the lower id)

func handle_bumps(delta):
	bump_cooldown = max(0.0, bump_cooldown - delta)

	for other in get_tree().get_nodes_in_group("vehicles"):
		if other == self or other.get_instance_id() < get_instance_id(): continue

		var offset: Vector3 = sphere.global_position - other.sphere.global_position
		if abs(offset.y) > 1.0: continue
		offset.y = 0
		if offset.length() > BUMP_DISTANCE: continue

		var away = offset.normalized() if offset.length() > 0.01 else vehicle_model.global_basis.x
		var closing_speed = max(0.0, (other.sphere.linear_velocity - sphere.linear_velocity).dot(away))

		if bump_cooldown > 0.0 or other.bump_cooldown > 0.0:
			# Still touching after a bump: gently keep them from overlapping
			bounce(away * 2.0 * delta / 0.1, false)
			other.bounce(-away * 2.0 * delta / 0.1, false)
			continue

		var push = BUMP_STRENGTH + closing_speed * 0.4
		bounce(away * push, true)
		other.bounce(-away * push, true)
		take_damage((closing_speed - BUMP_DAMAGE_THRESHOLD) * BUMP_DAMAGE)
		other.take_damage((closing_speed - BUMP_DAMAGE_THRESHOLD) * BUMP_DAMAGE)

# Push the vehicle (velocity change in units/s), optionally with a visible jolt and sound

func bounce(push: Vector3, jolt: bool):
	push.y = 0

	# The vehicle rolls on a sphere, so spin the sphere along with the push or friction cancels it out
	sphere.linear_velocity += push
	sphere.angular_velocity += Vector3.UP.cross(push) / 0.5

	if !jolt: return

	sphere.linear_velocity.y += 1.0 # Small hop
	flat_speed = Vector2(sphere.linear_velocity.x, sphere.linear_velocity.z).length() # The push isn't a crash
	linear_speed *= 0.7
	bump_cooldown = BUMP_COOLDOWN
	if vehicle_body != null: vehicle_body.position = Vector3(0, 0.1, 0)

	impact_sound.volume_db = clampf(remap(push.length(), BUMP_STRENGTH, 6.0, -8.0, 0.0), -8.0, 0.0)
	impact_sound.play()

# A sudden loss of speed means the vehicle crashed into something (usually a wall)

func check_crash():
	var speed = Vector2(sphere.linear_velocity.x, sphere.linear_velocity.z).length()
	take_damage((flat_speed - speed - WALL_DAMAGE_THRESHOLD) * WALL_DAMAGE)
	flat_speed = speed

func take_damage(amount: float):
	if amount <= 0.0 or damage >= MAX_DAMAGE: return

	amount = min(amount, MAX_DAMAGE - damage)
	damage += amount
	damaged.emit(amount)

	if is_critical() and smoke != null: smoke.emitting = true

func repair(amount: float):
	damage = max(0.0, damage - amount)
	if !is_critical() and smoke != null: smoke.emitting = false

func is_critical() -> bool:
	return damage >= CRITICAL_DAMAGE

# Top speed multiplier: full speed until critical, then down to CRITICAL_SPEED at full damage

func damage_speed() -> float:
	if !is_critical(): return 1.0
	return lerp(1.0, CRITICAL_SPEED, (damage - CRITICAL_DAMAGE) / (MAX_DAMAGE - CRITICAL_DAMAGE))

# Smoke from the engine when badly damaged (a copy of the tire trail, puffing upwards)

func create_smoke():
	smoke = trail_left.duplicate()
	smoke.emitting = false
	smoke.amount = 24
	smoke.lifetime = 1.2
	smoke.position = Vector3(0, 0.6, 0.4)

	var process: ParticleProcessMaterial = smoke.process_material.duplicate()
	process.direction = Vector3.UP
	process.spread = 20.0
	process.gravity = Vector3(0, 1.0, 0)
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.0
	process.scale_min = 0.5
	process.scale_max = 0.9
	process.color = Color(0.6, 0.6, 0.63)
	smoke.process_material = process

	vehicle_model.add_child(smoke)

func effect_body(delta):
	
	calculated_lean = lerp_angle(calculated_lean, -input.x / 5 * linear_speed, delta * 5)
	
	# Slightly tilt (and move) body based on acceleration and steering
	
	if vehicle_body != null:
		
		vehicle_body.rotation.x = lerp_angle(vehicle_body.rotation.x, -(linear_speed - acceleration) / 6, delta * 10)
		vehicle_body.rotation.z = calculated_lean
		
		vehicle_body.position = vehicle_body.position.lerp(Vector3(0, 0.2, 0), delta * 5)
	
func effect_wheels(delta):

	# Rotate wheels based on acceleration

	for wheel in [wheel_fl, wheel_fr, wheel_bl, wheel_br]:
		if wheel != null:
			wheel.rotation.x += acceleration

	# Rotate front wheels based on steering direction

	if wheel_fl != null: wheel_fl.rotation.y = lerp_angle(wheel_fl.rotation.y, -input.x / 1.5, delta * 10)
	if wheel_fr != null: wheel_fr.rotation.y = lerp_angle(wheel_fr.rotation.y, -input.x / 1.5, delta * 10)

# Engine sounds

func effect_engine(delta):

	var speed_factor = clamp(abs(linear_speed), 0.0, 1.0)
	var throttle_factor = clamp(abs(input.z), 0.0, 1.0)

	var target_volume = remap(speed_factor + (throttle_factor * 0.5), 0.0, 1.5, -15.0, -5.0)
	engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * 5.0)

	var target_pitch = remap(speed_factor, 0.0, 1.0, 0.5, 3)
	if throttle_factor > 0.1: target_pitch += 0.2

	engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, delta * 2.0)

# Show trails (and play skid sound)

func effect_trails():

	var drift_intensity = abs(linear_speed - acceleration) + (abs(calculated_lean) * 2.0)
	var should_emit = drift_intensity > 0.25

	if trail_left != null: trail_left.emitting = should_emit
	if trail_right != null: trail_right.emitting = should_emit

	var target_volume = -80.0
	if should_emit: target_volume = remap(clamp(drift_intensity, 0.25, 2.0), 0.25, 2.0, -10.0, 0.0)

	screech_sound.pitch_scale = lerp(screech_sound.pitch_scale, clamp(abs(linear_speed), 1.0, 3.0), 0.1)
	screech_sound.volume_db = lerp(screech_sound.volume_db, target_volume, 10.0 * get_physics_process_delta_time())

# Align vehicle with normal

func align_with_y(xform, new_y):

	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform

# Detect collisions and play impact sound

func _on_sphere_body_entered(_body: Node) -> void:
	
	if vehicle_body == null: return
	
	if not impact_sound.playing:
		var impact_velocity := absf(linear_velocity.dot(vehicle_body.global_basis.z))
		impact_sound.volume_db = clampf(remap(impact_velocity, 0.0, 6.0, -20.0, 0.0), -20.0, 0.0)
		impact_sound.play()
