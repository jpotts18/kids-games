extends Area3D

# Weapon pickup: dropped by the golden drone. Floats down, spins and glows.
# Touch it to add the weapon to your loadout

@export var weapon: Weapon = preload("res://weapons/sniper.tres")

const GOLD := Color("ffcc00")

var visual: Node3D
var time := 0.0
var player: Node3D
var flying_to_player := false # Used when there's no platform below to land on

func _ready():
	collision_layer = 0 # Invisible to raycasts (so it never blocks shots)
	collision_mask = 1 # Detects the player
	monitorable = false

	player = get_tree().get_first_node_in_group("player")

	var shape = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 1.0
	add_child(shape)

	build_visual()
	body_entered.connect(_on_body_entered)

	drop_to_ground.call_deferred()

func _process(delta):
	time += delta
	visual.rotation.y += 2 * delta
	visual.position.y = 0.8 + sin(time * 3) * 0.15

	if flying_to_player:
		global_position = global_position.move_toward(player.global_position, 15 * delta)

# Fall onto the platform below. If it was dropped over the void, it flies to the
# player instead, so it can never get lost

func drop_to_ground():
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * 30)
	query.collide_with_areas = false
	var hit = get_world_3d().direct_space_state.intersect_ray(query)

	if hit:
		var fall_time = clamp(global_position.distance_to(hit.position) / 8, 0.15, 1.0)
		var tween = create_tween()
		tween.tween_property(self, "global_position", hit.position, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif player:
		flying_to_player = true

func _on_body_entered(body):
	if body.has_method("pick_up_weapon"):
		body.pick_up_weapon(weapon)
		queue_free()

# The weapon's own model, with a golden glow and a light

func build_visual():
	visual = Node3D.new()
	add_child(visual)

	var model = weapon.model.instantiate()
	model.scale = weapon.scale * 1.0
	visual.add_child(model)

	var glow = StandardMaterial3D.new()
	glow.albedo_color = Color(GOLD, 0.35)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = GOLD
	glow.emission_energy_multiplier = 0.8

	for mesh in model.find_children("*", "MeshInstance3D"):
		mesh.material_overlay = glow

	var light = OmniLight3D.new()
	light.light_color = GOLD
	light.light_energy = 2.0
	light.omni_range = 3.0
	visual.add_child(light)
