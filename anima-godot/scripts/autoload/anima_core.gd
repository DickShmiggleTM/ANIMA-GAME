## AnimaCore — bridge to the C++ GDExtension ECS body simulation.
## Falls back to a pure GDScript simulator when the extension is unavailable
## (useful for development without a compiled GDExtension).
extends Node

# ── Constants ────────────────────────────────────────────────────────────────
const TICK_RATE_HZ := 15.0
const TICK_DT := 1.0 / TICK_RATE_HZ

# ── State ────────────────────────────────────────────────────────────────────
var _extension_loaded := false
var _accumulator := 0.0
var _next_id := 1
var _entities: Dictionary = {}   # id -> SimBody (fallback)

# ── Extension object (set when GDExtension loads) ────────────────────────────
var _ecs  # AnimaCoreECS instance or null

func _ready() -> void:
	_try_load_extension()
	if not _extension_loaded:
		push_warning("AnimaCore: GDExtension not found; using GDScript fallback simulator.")

func _try_load_extension() -> void:
	if ClassDB.class_exists("AnimaCoreECS"):
		_ecs = ClassDB.instantiate("AnimaCoreECS")
		if _ecs:
			add_child(_ecs)
			_extension_loaded = true
			print("AnimaCore: C++ GDExtension loaded.")

func _process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= TICK_DT:
		_accumulator -= TICK_DT
		_tick(TICK_DT)
	Telemetry.tick()

func _tick(dt: float) -> void:
	if _extension_loaded:
		_ecs.batch_step(dt)
	else:
		_fallback_tick(dt)

# ── Public API (mirrors C++ API) ──────────────────────────────────────────────
func create_entity(species: String = "zoi", genetics: Dictionary = {}) -> int:
	var id := _next_id
	_next_id += 1
	if _extension_loaded:
		_ecs.create_entity(id, species, genetics)
	else:
		_entities[id] = SimBody.new(id, species)
	Telemetry.log_birth(id, genetics.get("parent_ids", []), genetics)
	return id

func destroy_entity(id: int, cause: String = "unknown") -> void:
	if _extension_loaded:
		_ecs.destroy_entity(id)
	else:
		_entities.erase(id)
	Telemetry.log_death(id, cause, 0, {})
	EventBus.zoi_died.emit(id, cause)

func get_state(id: int) -> Dictionary:
	if _extension_loaded:
		return _ecs.get_state(id)
	var body: SimBody = _entities.get(id)
	if body:
		return body.to_dict()
	return {}

func apply_event(id: int, event: String, params: Dictionary = {}) -> void:
	if _extension_loaded:
		_ecs.apply_event(id, event, params)
	else:
		var body: SimBody = _entities.get(id)
		if body:
			body.apply_event(event, params)

func get_observation_vector(id: int, nearby: Array) -> Array[float]:
	"""Return normalized observation vector for RL policy inference."""
	var s := get_state(id)
	if s.is_empty():
		return []
	var obs: Array[float] = [
		s.get("energy", 0.5),
		s.get("hydration", 0.5),
		s.get("sleep_toxins", 0.0),
		s.get("cortisol", 0.0),
		s.get("dopamine", 0.5),
		s.get("body_temp_norm", 0.5),
		float(nearby.size()) / 10.0,
		0.0,  # nearest_food_dist_norm (filled by ZoiNode)
		0.0,  # nearest_water_dist_norm
		0.0,  # time_of_day_norm (filled by WorldManager)
	]
	return obs

# ── GDScript fallback simulation ─────────────────────────────────────────────
func _fallback_tick(dt: float) -> void:
	for id in _entities:
		(_entities[id] as SimBody).tick(dt)

## Minimal in-GDScript body simulator used when GDExtension is absent.
class SimBody:
	var id: int
	var species: String
	# Core vitals (normalized 0..1)
	var energy := 0.8
	var hydration := 0.8
	var sleep_toxins := 0.0
	var cortisol := 0.1
	var dopamine := 0.5
	var body_temp := 37.0   # °C
	var age_ticks := 0

	# Metabolism rates (per tick at TICK_RATE_HZ)
	const ENERGY_DECAY := 0.0005
	const HYDRATION_DECAY := 0.0007
	const SLEEP_TOXIN_RATE := 0.0003
	const TEMP_BASELINE := 37.0

	func _init(p_id: int, p_species: String) -> void:
		id = p_id
		species = p_species

	func tick(dt: float) -> void:
		age_ticks += 1
		energy = maxf(0.0, energy - ENERGY_DECAY * dt * TICK_RATE_HZ)
		hydration = maxf(0.0, hydration - HYDRATION_DECAY * dt * TICK_RATE_HZ)
		sleep_toxins = minf(1.0, sleep_toxins + SLEEP_TOXIN_RATE * dt * TICK_RATE_HZ)
		# Cortisol rises under stress
		var stress := (1.0 - energy) * 0.3 + (1.0 - hydration) * 0.3
		cortisol = lerpf(cortisol, stress, 0.05)
		dopamine = lerpf(dopamine, 1.0 - cortisol, 0.02)
		# Emit critical signals
		if energy < 0.15:
			EventBus.hunger_critical.emit(id, energy)
		if hydration < 0.15:
			EventBus.thirst_critical.emit(id, hydration)
		if sleep_toxins > 0.8:
			EventBus.fatigue_critical.emit(id, sleep_toxins)

	func apply_event(event: String, params: Dictionary) -> void:
		match event:
			"eat":
				energy = minf(1.0, energy + params.get("amount", 0.2))
				dopamine = minf(1.0, dopamine + 0.1)
			"drink":
				hydration = minf(1.0, hydration + params.get("amount", 0.25))
			"sleep":
				sleep_toxins = maxf(0.0, sleep_toxins - params.get("rate", 0.05))
			"damage":
				energy = maxf(0.0, energy - params.get("amount", 0.1))
				cortisol = minf(1.0, cortisol + 0.2)
			"player_reward":
				dopamine = minf(1.0, dopamine + params.get("delta", 0.1))
			"player_punish":
				cortisol = minf(1.0, cortisol + params.get("delta", 0.1))

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"species": species,
			"energy": energy,
			"hydration": hydration,
			"sleep_toxins": sleep_toxins,
			"cortisol": cortisol,
			"dopamine": dopamine,
			"body_temp": body_temp,
			"body_temp_norm": (body_temp - 30.0) / 20.0,
			"age_ticks": age_ticks,
		}
