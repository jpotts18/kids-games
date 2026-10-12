extends Area3D

# Turret shot: a slow glowing ball. Hurts the player on touch, pops when it
# hits anything else. It can be shot out of the air

var direction := Vector3.FORWARD
var speed := 9.0
var damage_amount := 12
var shooter: Node # The turret that fired it (never hits its own turret)

const COLOR := Color("ff2d55")
const LIFETIME := 6.0

var age := 0.0
var popped := false
var visual: MeshInstance3D

func _ready():
	collision_mask = 1 # The world and the player

	var shape = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 0.25
	add_child(shape)

	var material = StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	visual = MeshInstance3D.new()
	visual.mesh = SphereMesh.new()
	visual.mesh.radius = 0.22
	visual.mesh.height = 0.44
	visual.mesh.material = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

	var light = OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 1.5
	light.omni_range = 2.5
	add_child(light)

	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if popped: return

	age += delta
	global_position += direction * speed * delta
	visual.scale = Vector3.ONE * (1.0 + sin(age * 20) * 0.1) # Wobble

	if age > LIFETIME: pop()

func _on_body_entered(body):
	if popped or body == shooter: return

	pop()

	if body.has_method("damage") and body.is_in_group("player"):
		body.damage.call_deferred(damage_amount) # After the physics step (the scene may reload if the player dies)

# Shooting the ball pops it

func damage(_amount):
	Audio.play("sounds/enemy_hurt.ogg")
	pop()

func pop():
	if popped or !is_inside_tree(): return
	popped = true

	var explosion = preload("res://objects/explosion.gd").new()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	explosion.scale = Vector3.ONE * 0.5

	queue_free()
