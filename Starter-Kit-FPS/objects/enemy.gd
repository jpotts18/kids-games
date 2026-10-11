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

	if randf() < health_drop_chance:
		var pickup = preload("res://objects/health_pickup.gd").new()
		get_tree().current_scene.add_child(pickup)
		pickup.global_position = global_position

	queue_free()

# Shoot when timer hits 0

func _on_timer_timeout():
	if !alerted: return  # Only shoot once the player has been noticed

	raycast.force_raycast_update()

	if raycast.is_colliding():
		var collider = raycast.get_collider()

		if collider.has_method("damage"):  # Raycast collides with player
			
			# Play muzzle flash animation(s)

			muzzle_a.frame = 0
			muzzle_a.play("default")
			muzzle_a.rotation_degrees.z = randf_range(-45, 45)

			muzzle_b.frame = 0
			muzzle_b.play("default")
			muzzle_b.rotation_degrees.z = randf_range(-45, 45)

			Audio.play("sounds/enemy_attack.ogg")

			if randf() < hit_chance():
				collider.damage(5)  # Apply damage to player

# The faster the player moves, the more likely the enemy misses

func hit_chance() -> float:
	var speed = Vector2(player.velocity.x, player.velocity.z).length()
	var movement = clamp(speed / player_full_speed, 0.0, 1.0)

	return lerp(accuracy_standing, accuracy_moving, movement)
