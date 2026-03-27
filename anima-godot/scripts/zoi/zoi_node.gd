## ZoiNode — the visual Shell for a single Zoi agent.
## Reads Body state from AnimaCore (ECS) and Mind decisions from the policy,
## then drives movement, animation, and debug overlays.
## Rule: keep this "dumb" — no intelligence lives here.
class_name ZoiNode
extends CharacterBody3D

# ── Exported config ───────────────────────────────────────────────────────────
@export var debug_overlay_enabled := false
@export var lod_full_distance := 40.0
@export var lod_reduced_distance := 80.0

# ── Node refs ────────────────────────────────────────────────────────────────
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var pivot: Node3D = $Pivot
@onready var debug_overlay: Node3D = $DebugOverlay
@onready var thought_label: Label3D = $DebugOverlay/ThoughtBubble
@onready var sensor_area: Area3D = $SensorArea
@onready var anim: AnimationPlayer = $AnimationPlayer

# ── Identity ──────────────────────────────────────────────────────────────────
var zoi_id: int = -1
var _age_ticks: int = 0

# ── Movement ──────────────────────────────────────────────────────────────────
const BASE_SPEED := 2.5
const GRAVITY := -9.8
var _target_position: Vector3
var _current_intent: String = "idle"
var _speed_modifier := 1.0

# ── LOD ───────────────────────────────────────────────────────────────────────
enum LOD { FULL, REDUCED, AGGREGATE }
var _lod: LOD = LOD.FULL
var _tick_skip := 0
var _tick_skip_max := 0

# ── Nearby cache ─────────────────────────────────────────────────────────────
var _nearby_food: Array[Node3D] = []
var _nearby_water: Array[Node3D] = []
var _nearby_zoi: Array[ZoiNode] = []

# ── Policy / Mind ─────────────────────────────────────────────────────────────
var _policy  # ZoiPolicy instance; set by WorldManager
var _last_obs: Array[float] = []
var _last_action: int = 0

# ── Relationship memory ───────────────────────────────────────────────────────
var memory: ZoiMemory

# ── Signals ───────────────────────────────────────────────────────────────────
signal intent_changed(zoi_id: int, intent: String)

func _ready() -> void:
	memory = ZoiMemory.new(zoi_id)
	sensor_area.body_entered.connect(_on_sensor_body_entered)
	sensor_area.body_exited.connect(_on_sensor_body_exited)
	debug_overlay.visible = debug_overlay_enabled

func initialize(id: int, policy_instance) -> void:
	zoi_id = id
	_policy = policy_instance

func _physics_process(delta: float) -> void:
	_update_lod()
	if _should_skip_tick():
		return
	_think()
	_move(delta)
	if debug_overlay_enabled:
		_update_debug_overlay()

# ── LOD ───────────────────────────────────────────────────────────────────────
func _update_lod() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var dist := global_position.distance_to(cam.global_position)
	if dist < lod_full_distance:
		_lod = LOD.FULL
		_tick_skip_max = 0
	elif dist < lod_reduced_distance:
		_lod = LOD.REDUCED
		_tick_skip_max = 3
	else:
		_lod = LOD.AGGREGATE
		_tick_skip_max = 9

func _should_skip_tick() -> bool:
	if _tick_skip_max == 0:
		return false
	_tick_skip += 1
	if _tick_skip >= _tick_skip_max:
		_tick_skip = 0
		return false
	return true

# ── Think — query Body + Mind ─────────────────────────────────────────────────
func _think() -> void:
	if zoi_id < 0:
		return
	var state := AnimaCore.get_state(zoi_id)
	if state.is_empty():
		return

	_speed_modifier = 1.0 - state.get("sleep_toxins", 0.0) * 0.5
	_update_nearby_cache()
	_last_obs = AnimaCore.get_observation_vector(zoi_id, _nearby_zoi)
	_fill_obs_distances()

	var new_intent := "idle"
	if _policy:
		_last_action = _policy.infer(_last_obs)
		new_intent = _action_to_intent(_last_action)
	else:
		new_intent = _rule_based_intent(state)

	if new_intent != _current_intent:
		_current_intent = new_intent
		intent_changed.emit(zoi_id, _current_intent)

	Telemetry.log_observation(zoi_id, _last_obs, _last_action, 0.0)

func _fill_obs_distances() -> void:
	if _last_obs.size() < 10:
		return
	var food_dist := _nearest_dist(_nearby_food)
	var water_dist := _nearest_dist(_nearby_water)
	_last_obs[7] = clampf(1.0 - food_dist / 30.0, 0.0, 1.0)
	_last_obs[8] = clampf(1.0 - water_dist / 30.0, 0.0, 1.0)
	_last_obs[9] = fmod(Time.get_ticks_msec() / 1000.0 / 120.0, 1.0)  # rough day cycle

func _nearest_dist(nodes: Array[Node3D]) -> float:
	var best := 999.0
	for n in nodes:
		var d := global_position.distance_to(n.global_position)
		if d < best:
			best = d
	return best

func _rule_based_intent(state: Dictionary) -> String:
	if state.get("energy", 1.0) < 0.3 and not _nearby_food.is_empty():
		return "eat"
	if state.get("hydration", 1.0) < 0.3 and not _nearby_water.is_empty():
		return "drink"
	if state.get("sleep_toxins", 0.0) > 0.7:
		return "rest"
	if not _nearby_zoi.is_empty():
		return "socialize"
	return "wander"

func _action_to_intent(action: int) -> String:
	const ACTIONS := ["idle", "eat", "drink", "rest", "wander", "socialize", "flee", "build", "share", "call"]
	if action < ACTIONS.size():
		return ACTIONS[action]
	return "idle"

# ── Movement ──────────────────────────────────────────────────────────────────
func _move(delta: float) -> void:
	match _current_intent:
		"eat":
			_navigate_to_nearest(_nearby_food)
			_try_interact_nearest(_nearby_food, "eat")
		"drink":
			_navigate_to_nearest(_nearby_water)
			_try_interact_nearest(_nearby_water, "drink")
		"rest":
			velocity = Vector3.ZERO
		"wander":
			_wander()
		"socialize":
			_navigate_to_nearest_zoi()
		"flee":
			_flee()
		_:
			velocity = Vector3.ZERO

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	move_and_slide()

	# Face movement direction
	if velocity.length() > 0.1:
		pivot.rotation.y = lerp_angle(pivot.rotation.y, atan2(-velocity.x, -velocity.z), 10.0 * delta)

func _navigate_to_nearest(targets: Array[Node3D]) -> void:
	if targets.is_empty():
		return
	var nearest: Node3D = null
	var best := INF
	for t in targets:
		var d := global_position.distance_to(t.global_position)
		if d < best:
			best = d
			nearest = t
	if nearest:
		nav_agent.set_target_position(nearest.global_position)
		_follow_nav()

func _navigate_to_nearest_zoi() -> void:
	if _nearby_zoi.is_empty():
		return
	var target := _nearby_zoi[0]
	nav_agent.set_target_position(target.global_position)
	_follow_nav()

func _follow_nav() -> void:
	if nav_agent.is_navigation_finished():
		return
	var dir := (nav_agent.get_next_path_position() - global_position).normalized()
	dir.y = 0.0
	velocity.x = dir.x * BASE_SPEED * _speed_modifier
	velocity.z = dir.z * BASE_SPEED * _speed_modifier

func _try_interact_nearest(targets: Array[Node3D], event: String) -> void:
	if targets.is_empty():
		return
	var nearest: Node3D = null
	var best := INF
	for t in targets:
		var d := global_position.distance_to(t.global_position)
		if d < best:
			best = d
			nearest = t
	if best < 1.5 and nearest:
		AnimaCore.apply_event(zoi_id, event, {"amount": 0.2})
		if nearest.has_method("consume"):
			nearest.consume(0.2)

func _wander() -> void:
	if nav_agent.is_navigation_finished():
		var rng := RandomNumberGenerator.new()
		var offset := Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
		nav_agent.set_target_position(global_position + offset)
	_follow_nav()

func _flee() -> void:
	# Move away from highest-cortisol-inducing neighbor
	var away := Vector3.ZERO
	for z in _nearby_zoi:
		away += (global_position - z.global_position).normalized()
	if away.length() > 0.1:
		velocity.x = away.normalized().x * BASE_SPEED * 1.5
		velocity.z = away.normalized().z * BASE_SPEED * 1.5

# ── Sensor callbacks ──────────────────────────────────────────────────────────
func _on_sensor_body_entered(body: Node) -> void:
	if body.is_in_group("food_resource"):
		_nearby_food.append(body)
	elif body.is_in_group("water_resource"):
		_nearby_water.append(body)
	elif body is ZoiNode and body != self:
		_nearby_zoi.append(body)

func _on_sensor_body_exited(body: Node) -> void:
	_nearby_food.erase(body)
	_nearby_water.erase(body)
	if body is ZoiNode:
		_nearby_zoi.erase(body)

func _update_nearby_cache() -> void:
	# Remove invalid references
	_nearby_food = _nearby_food.filter(func(n): return is_instance_valid(n))
	_nearby_water = _nearby_water.filter(func(n): return is_instance_valid(n))
	_nearby_zoi = _nearby_zoi.filter(func(n): return is_instance_valid(n))

# ── Debug overlay ─────────────────────────────────────────────────────────────
func _update_debug_overlay() -> void:
	var state := AnimaCore.get_state(zoi_id)
	thought_label.text = "[%s]\nE:%.0f%% H:%.0f%%\n%s" % [
		str(zoi_id),
		state.get("energy", 0.0) * 100,
		state.get("hydration", 0.0) * 100,
		_current_intent
	]

# ── Public ────────────────────────────────────────────────────────────────────
func set_debug_visible(v: bool) -> void:
	debug_overlay_enabled = v
	if debug_overlay:
		debug_overlay.visible = v
