extends Node3D

@export var player: Node3D

@export var chase_speed := 2.5 # How fast the enemy flies towards the player
@export var stop_distance := 3.5 # Stops this close to the player (must be within RayCast range to shoot)
@export var hover_height := 1.0 # Height above the player the enemy flies at

@export var notice_radius := 10.0 # Starts chasing when the player comes this close
@export var give_up_radius := 20.0 # Stops chasing and flies home when the player gets this far away

@export_range(0, 1) var accuracy_standing := 0.9 # Chance to hit when the player stands still
@export_range(0, 1) var accuracy_moving := 0.3 # Chance to hit when the player moves at full speed
@export var player_full_speed := 5.0 # Player speed that counts as "full speed"

@export_range(0, 1) var health_drop_chance := 0.35 # Chance to drop a health pickup when destroyed
@export var shot_damage := 5 # Damage per hit on the player
@export var strafe_speed := 0.0 # Circles around the player while shooting (0 = doesn't)

@onready var raycast = $RayCast
@onready var muzzle_a = $MuzzleA
@onready var muzzle_b = $MuzzleB

var health := 100
var time := 0.0
var target_position: Vector3
var destroyed := false
var home_position: Vector3
var alerted := false # True while chasing the player
var alert_icon: Label3D
var carried_weapon: Weapon # Dropped when destroyed (see carry_weapon)
var max_health := 100
var health_bar: Sprite3D # Only the golden drone has one
var health_bar_fill: Sprite3D
var strafe_direction := 1.0
var strafe_timer := 0.0

# When ready, save the initial position

func _ready():
	add_to_group("enemies")  # Used by the HUD to count enemies left

	if !player:
		player = get_tree().get_first_node_in_group("player")  # Enemies placed inside chunks find the player themselves

	target_position = global_position
	home_position = global_position
	build_alert_icon()


func _process(delta):
	var distance_to_player = global_position.distance_to(player.global_position)

	if !alerted and distance_to_player < notice_radius:
		notice_player()
	elif alerted and distance_to_player > give_up_radius:
		alerted = false

	if alerted:
		self.look_at(player.global_position + Vector3(0, 0.5, 0), Vector3.UP, true)  # Look at player

		# Fly towards the player until close enough to shoot

		var chase_target = player.global_position + Vector3(0, hover_height, 0)

		if target_position.distance_to(chase_target) > stop_distance:
			target_position = target_position.move_toward(chase_target, chase_speed * delta)

		if strafe_speed > 0:
			strafe(chase_target, delta)
	else:
		rotate_y(0.5 * delta)  # Slowly look around

		# Fly back home

		target_position = target_position.move_toward(home_position, chase_speed * delta)

	target_position.y += (cos(time * 5) * 1) * delta  # Sine movement (up and down)

	time += delta

	global_position = target_position

# Take damage from player

func damage(amount):
	Audio.play("sounds/enemy_hurt.ogg")

	health -= amount
	update_health_bar()

	if !alerted:
		notice_player()  # Getting shot gets the enemy's attention

	if health <= 0 and !destroyed:
		destroy()

# Start chasing the player, with a "!" above the enemy's head

func notice_player():
	alerted = true

	alert_icon.visible = true
	alert_icon.scale = Vector3.ONE * 0.2

	var tween = create_tween()
	tween.tween_property(alert_icon, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.8)
	tween.tween_callback(func(): alert_icon.visible = false)

func build_alert_icon():
	alert_icon = Label3D.new()
	alert_icon.text = "!"
	alert_icon.font = preload("res://fonts/lilita_one_regular.ttf")
	alert_icon.font_size = 160
	alert_icon.outline_size = 36
	alert_icon.modulate = Color("ff3b30")
	alert_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert_icon.no_depth_test = true
	alert_icon.position = Vector3(0, 1.3, 0)
	alert_icon.visible = false
	add_child(alert_icon)

# Destroy the enemy when out of health

func destroy():
	Audio.play("sounds/enemy_destroy.ogg")

	destroyed = true

	var explosion = preload("res://objects/explosion.gd").new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position

	if carried_weapon:
		var weapon_pickup = preload("res://objects/weapon_pickup.gd").new()
		weapon_pickup.weapon = carried_weapon
		get_tree().current_scene.add_child(weapon_pickup)
		weapon_pickup.global_position = global_position
	elif randf() < health_drop_chance:
		var pickup = preload("res://objects/health_pickup.gd").new()
		get_tree().current_scene.add_child(pickup)
		pickup.global_position = global_position

	queue_free()

# Makes this the golden drone: glowing gold, much tougher than the others, and
# drops the weapon when destroyed

func carry_weapon(weapon: Weapon):
	carried_weapon = weapon

	health = 600 # 6x a normal drone
	max_health = health
	chase_speed = 4.5 # Faster, hard to outrun
	strafe_speed = 4.0 # Circles around the player, so it's hard to hit
	shot_damage = 10 # Hits harder
	accuracy_standing = 1.0 # Never misses a player who stands still
	accuracy_moving = 0.45 # And hits more often while you run
	notice_radius = 14.0 # Spots you from further away
	give_up_radius = 30.0 # And chases you for longer
	$Timer.wait_time = 0.15 # Shoots faster

	build_health_bar()

	var gold = Color("ffcc00")

	var glow = StandardMaterial3D.new()
	glow.albedo_color = Color(gold, 0.45)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = gold
	glow.emission_energy_multiplier = 0.6

	for mesh in find_children("*", "MeshInstance3D"):
		mesh.material_overlay = glow

	var light = OmniLight3D.new()
	light.light_color = gold
	light.light_energy = 3.0
	light.omni_range = 4.0
	add_child(light)

# Circles sideways around the player, switching direction now and then

func strafe(chase_target: Vector3, delta):
	strafe_timer -= delta
	if strafe_timer <= 0:
		strafe_direction = [-1.0, 1.0].pick_random()
		strafe_timer = randf_range(0.8, 2.0)

	var around = (target_position - chase_target)
	around.y = 0
	var sideways = around.cross(Vector3.UP).normalized()

	target_position += sideways * strafe_direction * strafe_speed * delta

# Health bar floating over the head (always faces the camera)

func build_health_bar():
	var image = Image.create_empty(100, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture = ImageTexture.create_from_image(image)

	health_bar = make_bar_sprite(texture, Color(0, 0, 0, 0.6)) # The empty part
	health_bar.position = Vector3(0, 1.1, 0)
	add_child(health_bar)

	health_bar_fill = make_bar_sprite(texture, Color("ffcc00"))
	health_bar_fill.position = health_bar.position
	add_child(health_bar_fill) # Not a child of the background, or it would inherit its dark color

	update_health_bar()

func make_bar_sprite(texture: Texture2D, color: Color) -> Sprite3D:
	var sprite = Sprite3D.new()
	sprite.texture = texture
	sprite.modulate = color
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.pixel_size = 0.014
	sprite.centered = false
	sprite.offset = Vector2(-50, -6) # Left edge stays put as the fill shrinks
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 100, 12)
	return sprite

func update_health_bar():
	if !health_bar: return

	var ratio = clamp(float(health) / max_health, 0.0, 1.0)
	var filled = max(100.0 * ratio, 0.01)

	# Fill on the left, empty part on the right (side by side, so they never overlap)

	health_bar_fill.region_rect.size.x = filled
	health_bar.region_rect.size.x = max(100.0 - filled, 0.01)
	health_bar.offset.x = -50 + filled
	health_bar_fill.modulate = Color("ff3b30") if ratio < 0.3 else Color("ffcc00")

# Shoot when timer hits 0

func _on_timer_timeout():
	if !alerted: return  # Only shoot once the player has been noticed

	raycast.force_raycast_update()

	if raycast.is_colliding():
		var collider = raycast.get_collider()

		if collider == player:  # Raycast collides with player (not other enemies)
			
			# Play muzzle flash animation(s)

			muzzle_a.frame = 0
			muzzle_a.play("default")
			muzzle_a.rotation_degrees.z = randf_range(-45, 45)

			muzzle_b.frame = 0
			muzzle_b.play("default")
			muzzle_b.rotation_degrees.z = randf_range(-45, 45)

			Audio.play("sounds/enemy_attack.ogg")

			if randf() < hit_chance():
				collider.damage(shot_damage)  # Apply damage to player

# The faster the player moves, the more likely the enemy misses

func hit_chance() -> float:
	var speed = Vector2(player.velocity.x, player.velocity.z).length()
	var movement = clamp(speed / player_full_speed, 0.0, 1.0)

	return lerp(accuracy_standing, accuracy_moving, movement)
