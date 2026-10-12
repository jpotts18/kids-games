extends Resource
class_name Weapon

@export var display_name: String # Shown when the weapon is picked up

@export_subgroup("Model")
@export var model: PackedScene # Model of the weapon
@export var position: Vector3 # On-screen position
@export var rotation: Vector3 # On-screen rotation
@export var scale: Vector3 = Vector3.ONE # On-screen scale (stretch a model to make it look different)
@export var tint: Color = Color(0, 0, 0, 0) # Colors the model (leave transparent for no tint)
@export var muzzle_position: Vector3 # On-screen position of muzzle flash

@export_subgroup("Properties")
@export_range(0.1, 3) var cooldown: float = 0.1 # Firerate (long cooldowns show a reload bar)
@export_range(1, 150) var max_distance: int = 10 # Fire distance
@export_range(0, 100) var damage: float = 25 # Damage per hit
@export_range(0, 5) var spread: float = 0 # Spread of each shot
@export_range(1, 5) var shot_count: int = 1 # Amount of shots
@export_range(0, 50) var knockback: int = 20 # Amount of knockback

@export var min_knockback: Vector2 = Vector2(0.001, 0.001) # x for vertical knockback, y for horizontal knockback
@export var max_knockback: Vector2 = Vector2(0.0025, 0.002) # x for vertical knockback, y for horizontal knockback

@export_subgroup("Sounds")
@export var sound_shoot: String # Sound path

@export_subgroup("Grappling hook")
@export var grapple: bool = false # Shooting fires a hook that pulls the player instead of doing damage
@export var grapple_pull_speed: float = 18.0 # How fast the hook reels the player in

@export_subgroup("Aiming")
@export var can_aim: bool = false # Hold the aim button to look through a scope
@export_range(5, 80) var aim_fov: float = 20 # Field of view while aiming (smaller = more zoom)

@export_subgroup("Crosshair")
@export var crosshair: Texture2D # Image of crosshair on-screen
