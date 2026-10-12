extends CharacterBody3D

@export_subgroup("Properties")
@export var movement_speed = 5
@export_range(0, 100) var number_of_jumps: int = 2
@export var jump_strength = 8
@export var trampoline_strength = 14

@export_subgroup("Weapons")
@export var weapons: Array[Weapon] = []

var weapon: Weapon
var weapon_index := 0

var mouse_sensitivity = 700
var gamepad_sensitivity := 0.075

var mouse_captured := true

var movement_velocity: Vector3
var rotation_target: Vector3

var input_mouse: Vector2

var health: int = 100
var max_health: int = 100
var gravity := 0.0

var previously_floored := false

var jumps_remaining: int

var container_offset = Vector3(1.2, -1.1, -2.75)

var tween: Tween

var aiming := false # True while looking through a scope
var default_fov: float
var scope_overlay: ColorRect
var reload_bar: ProgressBar
var message_label: Label

var grappling := false # True while the hook is attached and pulling
var sneak_time := 0.0 # Stays unnoticed this long after letting go of the hook

const SNEAK_AFTER_GRAPPLE := 0.5
var grapple_point: Vector3
var rope: Node3D
var hook: MeshInstance3D
var message_tween: Tween

signal health_updated

@onready var camera = $Head/Camera
@onready var raycast = $Head/Camera/RayCast
@onready var muzzle = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Muzzle
@onready var container = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Container
@onready var sound_footsteps = $SoundFootsteps
@onready var blaster_cooldown = $Cooldown

@export var crosshair: TextureRect

# Functions

func _enter_tree():
	add_to_group("player")  # Lets enemies find the player

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	weapons = weapons.duplicate() # Own copy, so picked-up weapons don't carry over to the next game
	weapon = weapons[weapon_index] # Weapon must never be nil
	initiate_change_weapon(weapon_index)

	default_fov = camera.fov
	build_scope_overlay()
	build_reload_bar()
	build_message_label()
	build_rope()
	blaster_cooldown.timeout.connect(_on_reloaded)

func _process(delta):
	# Handle functions
	handle_controls(delta)
	handle_gravity(delta)
	
	# Movement
	
	var applied_velocity: Vector3
	
	movement_velocity = transform.basis * movement_velocity # Move forward
	
	if grappling:
		applied_velocity = pull_towards_hook(delta)
	else:
		applied_velocity = velocity.lerp(movement_velocity, delta * 10)

	applied_velocity.y = - gravity
	
	velocity = applied_velocity
	move_and_slide()
	
	# Rotation 
	container.position = lerp(container.position, container_offset - (basis.inverse() * applied_velocity / 30), delta * 10)
	
	# Movement sound
	
	sound_footsteps.stream_paused = true
	
	if is_on_floor():
		if abs(velocity.x) > 1 or abs(velocity.z) > 1:
			sound_footsteps.stream_paused = false
	
	# Landing after jump or falling
	
	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	
	if is_on_floor() and gravity > 1 and !previously_floored: # Landed
		Audio.play("sounds/land.ogg")
		camera.position.y = -0.1
	
	previously_floored = is_on_floor()

	update_aiming(delta)
	update_reload_bar()
	update_rope()

	sneak_time = max(sneak_time - delta, 0.0)
	
	# Falling/respawning
	
	if position.y < -10:
		get_tree().reload_current_scene()

# Mouse movement

func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		input_mouse = event.relative / mouse_sensitivity
		var zoom = camera.fov / default_fov # Turn slower while zoomed in, so aiming is steady
		handle_rotation(event.relative.x * zoom, event.relative.y * zoom, false)

func handle_controls(delta):
	# Mouse capture
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true
	
	# (Escape is handled by the pause menu in hud.gd)

	# Movement
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * movement_speed
	
	# Handle Controller Rotation
	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	if rotation_input:
		handle_rotation(rotation_input.x * camera.fov / default_fov, rotation_input.y * camera.fov / default_fov, true, delta)
	
	# Shooting
	
	action_shoot()
	
	# Jumping
	
	if Input.is_action_just_pressed("jump"):
		if grappling:
			release_grapple()
			gravity = min(gravity, - jump_strength) # Let go with a boost
			Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg, sounds/jump_c.ogg")
		elif jumps_remaining:
			action_jump()
		
	# Weapon switching
	
	action_weapon_toggle()

# Camera rotation

func handle_rotation(xRot: float, yRot: float, isController: bool, delta: float = 0.0):
	if isController:
		rotation_target -= Vector3(-yRot, -xRot, 0).limit_length(1.0) * gamepad_sensitivity
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
		rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)
	else:
		rotation_target += (Vector3(-yRot, -xRot, 0) / mouse_sensitivity)
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = rotation_target.x;
		rotation.y = rotation_target.y;
	
# Handle gravity

func handle_gravity(delta):
	gravity += 20 * delta

	if gravity < 0 and is_on_ceiling():
		gravity = 0
	
	if gravity > 0 and is_on_floor():
		jumps_remaining = number_of_jumps
		gravity = 0

		if is_on_trampoline():
			action_bounce()

# Trampolines (the orange platforms) bounce the player back up

func is_on_trampoline() -> bool:
	for i in get_slide_collision_count():
		var collider = get_slide_collision(i).get_collider()
		if collider and collider.is_in_group("trampoline"):
			return true
	return false

func action_bounce():
	Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg, sounds/jump_c.ogg")
	gravity = - trampoline_strength

# Jumping

func action_jump():
	Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg, sounds/jump_c.ogg")
	gravity = - jump_strength
	jumps_remaining -= 1

# Shooting

func action_shoot():
	if weapon.grapple:
		action_grapple()
		return

	if Input.is_action_pressed("shoot"):
		if !blaster_cooldown.is_stopped(): return # Cooldown for shooting
		
		Audio.play(weapon.sound_shoot)
		
		# Set muzzle flash position, play animation
		
		muzzle.play("default")
		
		muzzle.rotation_degrees.z = randf_range(-45, 45)
		muzzle.scale = Vector3.ONE * randf_range(0.40, 0.75)
		muzzle.position = container.position - weapon.muzzle_position
		
		blaster_cooldown.start(weapon.cooldown)
		
		# Shoot the weapon, amount based on shot count
		
		for n in weapon.shot_count:
			raycast.target_position.x = randf_range(-weapon.spread, weapon.spread)
			raycast.target_position.y = randf_range(-weapon.spread, weapon.spread)
			
			raycast.force_raycast_update()
			
			if !raycast.is_colliding(): continue # Don't create impact when raycast didn't hit
			
			var collider = raycast.get_collider()
			
			# Hitting an enemy
			
			if collider.has_method("damage"):
				collider.damage(weapon.damage)
			
			# Creating an impact animation
			
			var impact = preload("res://objects/impact.tscn")
			var impact_instance = impact.instantiate()
			
			impact_instance.play("shot")
			
			get_tree().root.add_child(impact_instance)
			
			impact_instance.position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
			impact_instance.look_at(camera.global_transform.origin, Vector3.UP, true)
			
		var knockback = random_vec2(weapon.min_knockback, weapon.max_knockback)
		# print('knockback', knockback)
		container.position.z += 0.25 # Knockback of weapon visual
		camera.rotation.x += knockback.x # Knockback of camera
		rotation.y += knockback.y
		rotation_target.x += knockback.x
		rotation_target.y += knockback.y
		movement_velocity += Vector3(0, 0, weapon.knockback) # Knockback

# Toggle between available weapons (listed in 'weapons')

func action_weapon_toggle():
	if Input.is_action_just_pressed("weapon_toggle"):
		weapon_index = wrap(weapon_index + 1, 0, weapons.size())
		initiate_change_weapon(weapon_index)
		
		Audio.play("sounds/weapon_change.ogg")

# Initiates the weapon changing animation (tween)

func initiate_change_weapon(index):
	weapon_index = index
	release_grapple()
	
	tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(container, "position", container_offset - Vector3(0, 1, 0), 0.1)
	tween.tween_callback(change_weapon) # Changes the model

# Switches the weapon model (off-screen)

func change_weapon():
	weapon = weapons[weapon_index]

	# Step 1. Remove previous weapon model(s) from container
	
	for n in container.get_children():
		container.remove_child(n)
	
	# Step 2. Place new weapon model in container
	
	var weapon_model = weapon.model.instantiate()
	container.add_child(weapon_model)
	
	weapon_model.position = weapon.position
	weapon_model.rotation_degrees = weapon.rotation
	weapon_model.scale = weapon.scale

	if weapon.tint.a > 0:
		var tint = StandardMaterial3D.new()
		tint.albedo_color = weapon.tint
		tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for mesh in weapon_model.find_children("*", "MeshInstance3D"):
			mesh.material_overlay = tint
	
	# Step 3. Set model to only render on layer 2 (the weapon camera)
	
	for child in weapon_model.find_children("*", "MeshInstance3D"):
		child.layers = 2
		
	# Set weapon data
	
	raycast.target_position = Vector3(0, 0, -1) * weapon.max_distance
	crosshair.texture = weapon.crosshair
	crosshair.modulate = Color.WHITE

# Grappling hook: hold shoot to fire the hook and get reeled in, let go (or
# jump) to release. The crosshair turns green when there's something to grab

func action_grapple():
	var target = find_grapple_target()
	crosshair.modulate = Color("4cd964") if target != null or grappling else Color.WHITE

	if Input.is_action_just_pressed("shoot") and !grappling:
		if target == null:
			Audio.play("sounds/weapon_change.ogg") # Nothing to grab
			return

		grappling = true
		grapple_point = target
		jumps_remaining = number_of_jumps # Jumps refill, so you can chain swings

		Audio.play("sounds/blaster.ogg")
		container.position.z += 0.25 # Kick of the weapon visual

	elif grappling and !Input.is_action_pressed("shoot"):
		release_grapple()

# Hooks onto the level only (not enemies or pickups). Returns null when out of range

func find_grapple_target():
	var from = camera.global_position
	var to = from - camera.global_basis.z * weapon.max_distance

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]

	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit and hit.collider is StaticBody3D and !hit.collider.has_method("damage"):
		return hit.position
	return null

func pull_towards_hook(delta) -> Vector3:
	var to_hook = grapple_point - (global_position + Vector3.UP * 0.5)

	if to_hook.length() < 1.2: # Arrived
		release_grapple()
		gravity = min(gravity, - jump_strength * 0.5) # Little hop onto the ledge
		return velocity

	var pull = to_hook.normalized() * weapon.grapple_pull_speed + movement_velocity * 0.3 # A bit of steering
	var new_velocity = velocity.lerp(pull, min(delta * 6, 1.0))

	gravity = - new_velocity.y # Gravity is replaced by the pull while hooked
	return new_velocity

func release_grapple():
	if !grappling: return
	grappling = false
	sneak_time = SNEAK_AFTER_GRAPPLE
	if is_instance_valid(crosshair): crosshair.modulate = Color.WHITE

# Sleeping enemies don't notice the player zipping past on the hook (but
# enemies that are already chasing keep chasing, and shooting one still wakes it)

func is_sneaking() -> bool:
	return grappling or sneak_time > 0

# The rope: a thin cylinder from the gun to the hook

func build_rope():
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("c8a165")

	rope = Node3D.new()
	rope.top_level = true
	add_child(rope)

	var line = MeshInstance3D.new()
	line.mesh = CylinderMesh.new()
	line.mesh.top_radius = 0.025
	line.mesh.bottom_radius = 0.025
	line.mesh.height = 1.0
	line.mesh.material = material
	line.rotation.x = PI / 2 # Lie along the rope's forward axis
	line.position.z = -0.5
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rope.add_child(line)

	var hook_material = StandardMaterial3D.new()
	hook_material.albedo_color = Color("4cd964")
	hook_material.emission_enabled = true
	hook_material.emission = Color("4cd964")

	hook = MeshInstance3D.new()
	hook.mesh = SphereMesh.new()
	hook.mesh.radius = 0.12
	hook.mesh.height = 0.24
	hook.mesh.material = hook_material
	hook.top_level = true
	add_child(hook)

	rope.visible = false
	hook.visible = false

func update_rope():
	rope.visible = grappling
	hook.visible = grappling
	if !grappling: return

	var start = camera.global_transform * Vector3(0.25, -0.25, -0.6) # Near the gun
	var direction = grapple_point - start
	var up = Vector3.UP if abs(direction.normalized().y) < 0.99 else Vector3.FORWARD

	var rope_basis = Basis.looking_at(direction, up)
	rope_basis.z *= direction.length() # Stretch to reach the hook
	rope.global_transform = Transform3D(rope_basis, start)

	hook.global_position = grapple_point

# Aiming: hold the aim button with a scoped weapon to zoom in

func update_aiming(delta):
	aiming = weapon.can_aim and Input.is_action_pressed("aim") and mouse_captured

	var target_fov = weapon.aim_fov if aiming else default_fov
	camera.fov = lerp(camera.fov, target_fov, min(delta * 15, 1.0))

	var zoomed_in = aiming and camera.fov < default_fov - 10
	scope_overlay.visible = zoomed_in
	container.visible = !zoomed_in # Hide the weapon model while looking through the scope
	muzzle.visible = !zoomed_in
	crosshair.visible = !zoomed_in

# The scope: a dark screen with a round window and crosshair lines

func build_scope_overlay():
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float radius = 0.42;

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = (UV - 0.5) * size / size.y; // Centered, corrected for screen shape
	float d = length(p);

	float outside = smoothstep(radius - 0.004, radius, d);
	float ring = smoothstep(radius - 0.012, radius - 0.008, d);
	float lines = (abs(p.x) < 0.0015 || abs(p.y) < 0.0015) && d < radius ? 1.0 : 0.0;
	float gap = d < 0.02 ? 0.0 : 1.0; // Leaves the very center open

	COLOR = vec4(0.0, 0.0, 0.0, max(max(outside, ring * 0.8), lines * gap * 0.85));
}
"""

	scope_overlay = ColorRect.new()
	scope_overlay.material = ShaderMaterial.new()
	scope_overlay.material.shader = shader
	scope_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_overlay.visible = false
	crosshair.get_parent().add_child(scope_overlay)
	crosshair.get_parent().move_child(scope_overlay, 0) # Behind the rest of the HUD

	var dot = ColorRect.new() # Red dot in the middle of the scope
	dot.color = Color("ff3b30")
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = -2; dot.offset_right = 2
	dot.offset_top = -2; dot.offset_bottom = 2
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_overlay.add_child(dot)

# Reloading: weapons with a long cooldown show a bar under the crosshair

func build_reload_bar():
	reload_bar = ProgressBar.new()
	reload_bar.show_percentage = false
	reload_bar.set_anchors_preset(Control.PRESET_CENTER)
	reload_bar.offset_left = -45; reload_bar.offset_right = 45
	reload_bar.offset_top = 40; reload_bar.offset_bottom = 48 # Just below the crosshair
	reload_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reload_bar.max_value = 1.0

	var background = StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.5)
	background.set_corner_radius_all(4)
	reload_bar.add_theme_stylebox_override("background", background)

	var fill = StyleBoxFlat.new()
	fill.bg_color = Color("ffcc00")
	fill.set_corner_radius_all(4)
	reload_bar.add_theme_stylebox_override("fill", fill)

	reload_bar.visible = false
	crosshair.get_parent().add_child(reload_bar)

func update_reload_bar():
	var reloading = weapon.cooldown >= 0.5 and !blaster_cooldown.is_stopped()

	reload_bar.visible = reloading
	if reloading:
		reload_bar.value = 1.0 - blaster_cooldown.time_left / blaster_cooldown.wait_time

func _on_reloaded():
	if weapon.cooldown >= 0.5:
		Audio.play("sounds/weapon_change.ogg") # Click! Ready to fire again

# Picking up a new weapon adds it to the loadout and switches to it

func pick_up_weapon(new_weapon: Weapon):
	if !weapons.has(new_weapon):
		weapons.append(new_weapon)

	initiate_change_weapon(weapons.find(new_weapon))
	Audio.play("sounds/weapon_change.ogg")

	var hint = "  Hold right-click to aim!" if new_weapon.can_aim else ""
	show_message("You got the " + new_weapon.display_name + "!" + hint)

# Big message at the top of the screen that fades away

func build_message_label():
	message_label = Label.new()
	message_label.add_theme_font_override("font", preload("res://fonts/lilita_one_regular.ttf"))
	message_label.add_theme_font_size_override("font_size", 36)
	message_label.add_theme_color_override("font_color", Color("ffcc00"))
	message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	message_label.add_theme_constant_override("outline_size", 12)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.offset_left = -500; message_label.offset_right = 500
	message_label.offset_top = 120; message_label.offset_bottom = 170
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.modulate.a = 0
	crosshair.get_parent().add_child(message_label)

func show_message(text: String):
	message_label.text = text
	message_label.modulate.a = 1

	if message_tween: message_tween.kill()
	message_tween = create_tween()
	message_tween.tween_interval(3.0)
	message_tween.tween_property(message_label, "modulate:a", 0.0, 1.0)

func damage(amount):
	health -= amount
	health_updated.emit(health) # Update health on HUD
	
	if health < 0:
		get_tree().reload_current_scene() # Reset when out of health

func heal(amount):
	health = min(health + amount, max_health)
	health_updated.emit(health) # Update health on HUD

# Create a random knockback vector
static func random_vec2(_min: Vector2, _max: Vector2) -> Vector2:
	var _sign = -1 if randi() % 2 == 0 else 1
	return Vector2(randf_range(_min.x, _max.x), randf_range(_min.y, _max.y) * _sign)
