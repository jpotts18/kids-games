extends Node3D

# Randomizes the outer chunks every game so the world doesn't look copy-pasted.
# The center chunk (where the player starts) is left as-is.

const CHUNK_CENTER := Vector3(3.18, 0, -0.25) # Middle of a chunk's footprint (turning around this keeps it in its grid cell)
const HEIGHT_OFFSETS := [-1.0, 0.0, 1.0]

const CENTER_CHUNK_NAME := "Chunk_1_1"

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
