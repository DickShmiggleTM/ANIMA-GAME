## WorldManager — orchestrates Zoi spawning, environment, and ecology.
extends Node

# ── Config ────────────────────────────────────────────────────────────────────
@export var initial_zoi_count: int = 5
@export var max_zoi: int = 50
@export var spawn_area_size: Vector2 = Vector2(20.0, 20.0)
@export var debug_overlays: bool = false

# ── Day/night cycle ───────────────────────────────────────────────────────────
var time_of_day := 0.0          # 0..24 (hours)
var day_length_seconds := 120.0 # real-time seconds per in-game day

# ── Weather ───────────────────────────────────────────────────────────────────
enum Weather { CLEAR, CLOUDY, RAIN, STORM, SNOW }
var current_weather: Weather = Weather.CLEAR
var weather_intensity := 0.0
var _weather_timer := 0.0
var _weather_duration := 60.0

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var zoi_spawn_root: Node3D = $"../World/ZoiSpawnPoints"
@onready var resource_root: Node3D = $"../World/ResourceNodes"
@onready var dir_light: DirectionalLight3D = $"../World/DirectionalLight"

var _zoi_scene := preload("res://scenes/zoi.tscn")
var _resource_scene := preload("res://scenes/resource_node.tscn")

var _active_zoi: Dictionary = {}  # zoi_id -> ZoiNode
var _shared_policy: ZoiPolicy

func _ready() -> void:
	_shared_policy = ZoiPolicy.new("res://data/models/baseline_policy.onnx")
	_spawn_initial_resources()
	_spawn_initial_zoi()
	EventBus.zoi_died.connect(_on_zoi_died)

func _process(delta: float) -> void:
	_update_day_night(delta)
	_update_weather(delta)

# ── Day/Night ─────────────────────────────────────────────────────────────────
func _update_day_night(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta * 24.0 / day_length_seconds, 24.0)
	var t := time_of_day / 24.0
	# Sun angle
	if dir_light:
		dir_light.rotation_degrees.x = lerpf(-90.0, 270.0, t) - 90.0
		var brightness := clampf(sin(t * PI), 0.0, 1.0)
		dir_light.light_energy = 0.2 + brightness * 1.3
	EventBus.time_of_day_changed.emit(time_of_day)

# ── Weather ───────────────────────────────────────────────────────────────────
func _update_weather(delta: float) -> void:
	_weather_timer += delta
	if _weather_timer >= _weather_duration:
		_weather_timer = 0.0
		_weather_duration = randf_range(30.0, 120.0)
		_transition_weather()

func _transition_weather() -> void:
	var roll := randf()
	var new_weather: Weather
	if roll < 0.5:
		new_weather = Weather.CLEAR
	elif roll < 0.7:
		new_weather = Weather.CLOUDY
	elif roll < 0.85:
		new_weather = Weather.RAIN
	elif roll < 0.95:
		new_weather = Weather.STORM
	else:
		new_weather = Weather.SNOW
	if new_weather != current_weather:
		current_weather = new_weather
		weather_intensity = randf_range(0.3, 1.0)
		_apply_weather_effects()
		var name_map := {
			Weather.CLEAR: "clear", Weather.CLOUDY: "cloudy",
			Weather.RAIN: "rain", Weather.STORM: "storm", Weather.SNOW: "snow"
		}
		EventBus.weather_changed.emit(name_map[current_weather], weather_intensity)

func _apply_weather_effects() -> void:
	# Apply temperature effects to all Zoi bodies via AnimaCore
	var temp_delta := 0.0
	match current_weather:
		Weather.RAIN:   temp_delta = -0.05 * weather_intensity
		Weather.STORM:  temp_delta = -0.1 * weather_intensity
		Weather.SNOW:   temp_delta = -0.2 * weather_intensity
		_:              temp_delta = 0.0
	for zoi_id in _active_zoi:
		AnimaCore.apply_event(zoi_id, "temperature_change", {"delta": temp_delta})

# ── Spawning ──────────────────────────────────────────────────────────────────
func _spawn_initial_zoi() -> void:
	for i in initial_zoi_count:
		spawn_zoi()

func spawn_zoi(parent_ids: Array = [], genetics: Dictionary = {}) -> ZoiNode:
	if _active_zoi.size() >= max_zoi:
		return null
	genetics["parent_ids"] = parent_ids
	var zoi_id := AnimaCore.create_entity("zoi", genetics)
	var node: ZoiNode = _zoi_scene.instantiate()
	var pos := Vector3(
		randf_range(-spawn_area_size.x * 0.5, spawn_area_size.x * 0.5),
		0.5,
		randf_range(-spawn_area_size.y * 0.5, spawn_area_size.y * 0.5)
	)
	node.global_position = pos
	node.initialize(zoi_id, _shared_policy)
	node.debug_overlay_enabled = debug_overlays
	get_parent().add_child(node)
	_active_zoi[zoi_id] = node
	EventBus.zoi_spawned.emit(node)
	return node

func _spawn_initial_resources() -> void:
	_spawn_resource_cluster(Vector3(-5, 0, -5), "food", 4)
	_spawn_resource_cluster(Vector3(5, 0, 5), "water", 4)
	_spawn_resource_cluster(Vector3(-5, 0, 5), "food", 2)
	_spawn_resource_cluster(Vector3(5, 0, -5), "water", 2)

func _spawn_resource_cluster(center: Vector3, type: String, count: int) -> void:
	for i in count:
		var node: Node3D = _resource_scene.instantiate()
		var offset := Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		node.global_position = center + offset
		node.set_meta("resource_type", type)
		node.add_to_group("%s_resource" % type)
		resource_root.add_child(node)

func _on_zoi_died(zoi_id: int, _cause: String) -> void:
	var node: ZoiNode = _active_zoi.get(zoi_id)
	if node:
		node.queue_free()
		_active_zoi.erase(zoi_id)

func get_zoi_count() -> int:
	return _active_zoi.size()

func get_all_zoi() -> Array:
	return _active_zoi.values()
