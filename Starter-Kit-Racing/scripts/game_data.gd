extends Node

# Saved progress: records, coins, races finished and the garage setup (autoload "GameData")

const SAVE_PATH := "user://records.cfg"

const COINS_PER_RACE := 50
const COINS_RECORD_BONUS := 150
const MOTORCYCLE_UNLOCK_RACES := 5
const MAX_UPGRADE_LEVEL := 5

const VEHICLES := {
	"truck": {
		"name": "Truck",
		"scene": "res://scenes/vehicle.tscn",
		"model": "res://models/vehicle-truck-yellow.glb",
		"paint": Color("ffcf60"), # The model's original body color (replaced by the chosen paint)
	},
	"motorcycle": {
		"name": "Motorcycle",
		"scene": "res://scenes/vehicle-motorcycle.tscn",
		"model": "res://models/vehicle-motorcycle.glb",
		"paint": Color("338562"),
	},
}

const UPGRADES := {
	"speed": {"name": "Top speed", "info": "Go faster on the straights"},
	"acceleration": {"name": "Acceleration", "info": "Get up to speed quicker"},
	"grip": {"name": "Grip", "info": "Less drifting in the turns"},
	"steering": {"name": "Steering", "info": "Turn sharper"},
	"brakes": {"name": "Brakes", "info": "Stop faster"},
}

var best_lap := 0.0 # 0 = no record yet
var best_race := 0.0
var coins := 0
var races_finished := 0
var vehicle := "truck"
var paint := Color(0, 0, 0, 0) # Transparent = the model's original color
var upgrades := {"speed": 0, "acceleration": 0, "grip": 0, "steering": 0, "brakes": 0}

func _ready():
	load_data()

# Racing results - returns the coins earned

func race_finished(race_time: float, lap_times: Array[float]) -> Dictionary:
	var result = {"coins": COINS_PER_RACE, "record": false, "new_best_race": false, "unlocked_motorcycle": false}

	var fastest_lap = lap_times.min()
	if best_lap == 0.0 or fastest_lap < best_lap:
		result.record = result.record or best_lap > 0.0 # Beating an existing record (not the very first one)
		best_lap = fastest_lap
	if best_race == 0.0 or race_time < best_race:
		result.record = result.record or best_race > 0.0
		result.new_best_race = true
		best_race = race_time

	if result.record:
		result.coins += COINS_RECORD_BONUS

	coins += result.coins
	races_finished += 1
	result.unlocked_motorcycle = races_finished == MOTORCYCLE_UNLOCK_RACES

	save_data()
	return result

func save_lap(lap_time: float):
	if best_lap == 0.0 or lap_time < best_lap:
		best_lap = lap_time
		save_data()

# Garage

func is_unlocked(vehicle_id: String) -> bool:
	return vehicle_id != "motorcycle" or races_finished >= MOTORCYCLE_UNLOCK_RACES

func upgrade_cost(upgrade_id: String) -> int:
	return 30 * (upgrades[upgrade_id] + 1) # 30, 60, 90, 120, 150

func buy_upgrade(upgrade_id: String) -> bool:
	if upgrades[upgrade_id] >= MAX_UPGRADE_LEVEL or coins < upgrade_cost(upgrade_id): return false
	coins -= upgrade_cost(upgrade_id)
	upgrades[upgrade_id] += 1
	save_data()
	return true

# Applies upgrades and paint to a vehicle in the race

func apply_to(target: Vehicle):
	target.speed_multiplier = 1.0 + 0.06 * upgrades.speed
	target.acceleration_multiplier = 1.0 + 0.25 * upgrades.acceleration
	target.grip = 2.0 * upgrades.grip
	target.steering_multiplier = 1.0 + 0.07 * upgrades.steering
	target.brake_strength = 1.2 * upgrades.brakes
	target.sphere.angular_damp = 4.0 * target.acceleration_multiplier # Same top speed, reached quicker

	apply_paint(target.get_node("Container/Model"))

# Recolors the body paint of a vehicle model (keeps windows, tires and lights as they are)

func apply_paint(model: Node):
	if paint.a == 0.0: return

	var shader = preload("res://shaders/paint.gdshader")
	var original = VEHICLES[vehicle].paint

	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var source = mesh_instance.mesh.surface_get_material(0)
		var material = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
		material.set_shader_parameter("original_paint", original)
		material.set_shader_parameter("new_paint", paint)
		material.set_shader_parameter("roughness", source.roughness)
		mesh_instance.material_override = material

# Saving and loading

func save_data():
	var config = ConfigFile.new()
	config.set_value("records", "best_lap", best_lap)
	config.set_value("records", "best_race", best_race)
	config.set_value("progress", "coins", coins)
	config.set_value("progress", "races_finished", races_finished)
	config.set_value("garage", "vehicle", vehicle)
	config.set_value("garage", "paint", paint)
	config.set_value("garage", "upgrades", upgrades)
	config.save(SAVE_PATH)

func load_data():
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) != OK: return

	best_lap = config.get_value("records", "best_lap", 0.0)
	best_race = config.get_value("records", "best_race", 0.0)
	coins = config.get_value("progress", "coins", 0)
	races_finished = config.get_value("progress", "races_finished", 0)

	# Saves from before coins existed: count the race that set the record
	if !config.has_section("progress") and best_race > 0.0:
		races_finished = 1
		coins = COINS_PER_RACE
	vehicle = config.get_value("garage", "vehicle", "truck")
	paint = config.get_value("garage", "paint", Color(0, 0, 0, 0))

	var saved_upgrades: Dictionary = config.get_value("garage", "upgrades", {})
	for key in upgrades:
		upgrades[key] = saved_upgrades.get(key, 0)

	if !VEHICLES.has(vehicle) or !is_unlocked(vehicle):
		vehicle = "truck"
