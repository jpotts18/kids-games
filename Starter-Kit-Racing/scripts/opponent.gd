extends Node

# Computer driver: steers a vehicle along the track by following waypoints

const WAYPOINT_REACHED := 2.5 # How close (units) the car gets to a waypoint before aiming at the next one
const STUCK_TIME := 1.5 # Seconds of crawling before backing up
const REVERSE_TIME := 1.0
const AVOID_DISTANCE := 3.5 # How far ahead (units) to look for vehicles to steer around

var vehicle: Vehicle
var waypoints: Array[Vector3] = [] # Points along the middle of the road, in driving order
var directions: Array[Vector3] = [] # Driving direction at each waypoint
var lane := 0.0 # Sideways offset from the middle of the road, so opponents don't drive in single file
var waypoint := 0
var cool_down := false # Finished the race: drive slowly until the player finishes too

# Pit stop: badly damaged opponents pull in to get repaired

const REPAIRED_DAMAGE := 5.0 # Leave the pit once repaired this far
const PIT_GIVE_UP := 10.0 # Seconds heading for the pit without getting repaired (blocked?) before giving up for this lap

var pit_stop: Node3D
var pit_waypoint := -1 # First waypoint past the pit box
var pitting := false
var pit_timer := 0.0

var stuck_timer := 0.0
var reverse_timer := 0.0

func _physics_process(delta):
	if !vehicle or waypoints.is_empty(): return

	var position = vehicle.sphere.global_position

	if pit_stop and pit_waypoint != -1 and vehicle.is_critical() and !cool_down: pitting = true
	if pitting and near_pit() and !past_pit(position):
		drive_into_pit(position, delta)
		return
	pit_timer = 0.0

	var target = get_target(waypoint)

	if flat(target - position).length() < WAYPOINT_REACHED:
		waypoint = (waypoint + 1) % waypoints.size()
		target = get_target(waypoint)

	var forward = flat(vehicle.vehicle_model.global_basis.z).normalized()
	target += avoid_offset(position, forward)
	var to_target = flat(target - position).normalized()
	var angle = forward.signed_angle_to(to_target, Vector3.UP)

	var steer = clamp(-angle * 2.5, -1.0, 1.0)
	var throttle = 1.0
	if abs(angle) > 0.6 and abs(vehicle.linear_speed) > 0.7: throttle = 0.3 # Ease off in sharp turns
	if cool_down: throttle *= 0.5

	# Back up if stuck against something (only once the race has started)

	if vehicle.controls_enabled and reverse_timer <= 0.0:
		if flat(vehicle.sphere.linear_velocity).length() < 1.0:
			stuck_timer += delta
		else:
			stuck_timer = 0.0
		if stuck_timer > STUCK_TIME:
			stuck_timer = 0.0
			reverse_timer = REVERSE_TIME

	if reverse_timer > 0.0:
		reverse_timer -= delta
		steer = -steer
		throttle = -1.0

	vehicle.ai_input = Vector2(steer, throttle)

# Head for the middle of the pit box, stop there and wait until repaired

func drive_into_pit(position: Vector3, delta: float):
	var forward = flat(vehicle.vehicle_model.global_basis.z).normalized()
	var to_pit = flat(pit_stop.global_position - position)
	var angle = forward.signed_angle_to(to_pit.normalized(), Vector3.UP)
	var steer = clamp(-angle * 2.5, -1.0, 1.0)
	var throttle = clamp(to_pit.length() / 12.0, 0.25, 1.0)

	if pit_stop.contains(position):
		steer = 0.0
		throttle = -1.0 if vehicle.linear_speed > 0.05 else 0.0 # Brake, but don't reverse

		# The pit crew holds the car still while it's being repaired
		vehicle.sphere.linear_velocity *= 0.9
		vehicle.sphere.angular_velocity *= 0.9

	pit_timer += delta
	if vehicle.repairing: pit_timer = 0.0

	if vehicle.damage <= REPAIRED_DAMAGE or pit_timer > PIT_GIVE_UP:
		pitting = false # Back to the race (the next waypoints lead out past the pit box)

	stuck_timer = 0.0
	vehicle.ai_input = Vector2(steer, throttle)

# Heading for the pit box (the last two waypoints before it)

func near_pit() -> bool:
	return waypoint == pit_waypoint or waypoint == (pit_waypoint - 1 + waypoints.size()) % waypoints.size()

# Already beyond the pit box (became critical too late this lap, try again next lap)

func past_pit(position: Vector3) -> bool:
	return (position - pit_stop.global_position).dot(-pit_stop.global_basis.z) > 3.0

# Steer around a vehicle that's right in front (instead of pushing it along)

func avoid_offset(position: Vector3, forward: Vector3) -> Vector3:
	var side = forward.cross(Vector3.UP)
	for other in get_tree().get_nodes_in_group("vehicles"):
		if other == vehicle: continue
		var offset = flat(other.sphere.global_position - position)
		var ahead = offset.dot(forward)
		var sideways = offset.dot(side)
		if ahead > 0.0 and ahead < AVOID_DISTANCE and abs(sideways) < 1.2:
			return side * (-1.8 if sideways > 0 else 1.8) # Go round on the other side
	return Vector3.ZERO

# Waypoint shifted sideways into this driver's lane

func get_target(index: int) -> Vector3:
	var side = directions[index].cross(Vector3.UP)
	return waypoints[index] + side * lane

# Start aiming at the first waypoint ahead of the car

func start_at_closest_waypoint():
	var position = vehicle.sphere.global_position
	var forward = flat(vehicle.vehicle_model.global_basis.z)
	var best = INF
	for i in waypoints.size():
		var offset = flat(waypoints[i] - position)
		if offset.dot(forward) > 0 and offset.length() < best:
			best = offset.length()
			waypoint = i

func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
