extends Node3D

# Randomizes the outer chunks every game so the world doesn't look copy-pasted.
# The center chunk (where the player starts) is left as-is.

const CHUNK_CENTER := Vector3(3.18, 0, -0.25) # Middle of a chunk's footprint (turning around this keeps it in its grid cell)
const HEIGHT_OFFSETS := [-1.0, 0.0, 1.0]

const CENTER_CHUNK_NAME := "Chunk_1_1"
const SAFE_START_RADIUS := 13.0 # No enemies start this close to the player

# Runs before the chunks' enemies save their home positions in _ready()

func _enter_tree():
	for chunk in get_children():
		if chunk.name == CENTER_CHUNK_NAME: continue

		# Turn around (180°) half of the time

		if randf() < 0.5:
			chunk.rotate_y(PI)
			chunk.position += Vector3(CHUNK_CENTER.x * 2, 0, CHUNK_CENTER.z * 2)

		# Raise or lower slightly

		chunk.position.y += HEIGHT_OFFSETS.pick_random()

# Clears enemies away from the start so nobody attacks the player right away
# (must be wider than the enemies' notice radius)

func _ready():
	var player = get_tree().get_first_node_in_group("player")
	if !player: return

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.global_position.distance_to(player.global_position) < SAFE_START_RADIUS:
			enemy.free() # Right away, so the HUD never counts them

	thin_out_enemies()
	choose_golden_drone(player)

# Easy keeps only some of the enemies (picked at random each game)

func thin_out_enemies():
	var enemies = get_tree().get_nodes_in_group("enemies")
	enemies.shuffle()

	var keep = int(round(enemies.size() * Difficulty.enemy_share()))
	for enemy in enemies.slice(keep):
		enemy.free()

# One random flying drone carries the sniper. Destroy it to get the weapon

func choose_golden_drone(player):
	var drones = get_tree().get_nodes_in_group("enemies").filter(func(enemy): return enemy.has_method("carry_weapon"))
	if drones.is_empty(): return

	drones.pick_random().carry_weapon(preload("res://weapons/sniper.tres"))
	if Difficulty.chosen(): # Not behind the start screen
		player.show_message.call_deferred("A golden drone has a sniper. Destroy it!") # Once the player's HUD is ready
