extends Area3D

# Health pickup: drops to the ground, spins, heals the player on touch

@export var heal_amount := 25

var visual: Node3D
var time := 0.0

func _ready():
	collision_layer = 0 # Invisible to raycasts (so it never blocks shots)
	collision_mask = 1 # Detects the player
	monitorable = false

	var shape = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 0.8
	add_child(shape)

	build_visual()
	body_entered.connect(_on_body_entered)

	drop_to_ground.call_deferred()

func _process(delta):
	time += delta
	visual.rotation.y += 2 * delta
	visual.position.y = 0.6 + sin(time * 3) * 0.15

# Fall onto the platform below (if there is one, otherwise float in place)

func drop_to_ground():
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 30)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)

	if hit:
		var fall_time = clamp(global_position.distance_to(hit.position) / 8, 0.15, 1.0)
		var tween = create_tween()
		tween.tween_property(self, "global_position", hit.position, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _on_body_entered(body):
	if body.has_method("heal") and body.health < body.max_health:
		body.heal(heal_amount)
		Audio.play("sounds/weapon_change.ogg")
		queue_free()

# A glowing green plus sign

func build_visual():
	visual = Node3D.new()
	add_child(visual)

	var material = StandardMaterial3D.new()
	material.albedo_color = Color("4cd964")
	material.emission_enabled = true
	material.emission = Color("4cd964")
	material.emission_energy_multiplier = 0.6

	for size in [Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2)]:
		var bar = MeshInstance3D.new()
		bar.mesh = BoxMesh.new()
		bar.mesh.size = size
		bar.mesh.material = material
		visual.add_child(bar)
