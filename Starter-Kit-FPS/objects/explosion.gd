extends Node3D

# Explosion effect: a big flash plus flying debris, removes itself when done

func _ready():
	# Flash (reuses the muzzle flash animation, scaled up)

	var flash = AnimatedSprite3D.new()
	flash.sprite_frames = preload("res://sprites/burst_animation.tres")
	flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flash.pixel_size = 0.016
	flash.speed_scale = 0.3
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	flash.play("default")

	# Debris (small glowing cubes flying outwards)

	var debris = CPUParticles3D.new()
	debris.emitting = false
	debris.one_shot = true
	debris.local_coords = true # Follow the explosion (it gets moved into place right after being added)
	debris.explosiveness = 1.0
	debris.amount = 24
	debris.lifetime = 0.9
	debris.direction = Vector3.UP
	debris.spread = 180
	debris.initial_velocity_min = 4
	debris.initial_velocity_max = 9
	debris.gravity = Vector3(0, -15, 0)
	debris.scale_amount_min = 0.6
	debris.scale_amount_max = 1.2

	var curve = Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	debris.scale_amount_curve = curve

	var gradient = Gradient.new()
	gradient.set_color(0, Color("ffe066"))
	gradient.set_color(1, Color("ff5a1f"))
	debris.color_ramp = gradient

	var mesh = BoxMesh.new()
	mesh.size = Vector3.ONE * 0.3
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	debris.mesh = mesh

	add_child(debris)
	debris.emitting = true

	# Remove once the debris has landed

	get_tree().create_timer(debris.lifetime + 0.2).timeout.connect(queue_free)
