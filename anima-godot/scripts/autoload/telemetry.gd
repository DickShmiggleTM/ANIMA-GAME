## Telemetry — structured JSON event logging for debugging and training data.
## Writes to local file on device; no external network calls.
extends Node

const LOG_VERSION := "1.0"
const MAX_BUFFER_SIZE := 512

var _log_file: FileAccess
var _buffer: Array[Dictionary] = []
var _session_id: String
var _tick: int = 0

func _ready() -> void:
	_session_id = _generate_session_id()
	var path := _get_log_path()
	_log_file = FileAccess.open(path, FileAccess.WRITE)
	if not _log_file:
		push_warning("Telemetry: could not open log file at %s" % path)
	_log_event("session_start", {"version": LOG_VERSION, "session_id": _session_id})
	EventBus.telemetry_event.connect(_on_telemetry_event)

func _on_telemetry_event(event: Dictionary) -> void:
	_log_event(event.get("type", "unknown"), event)

func tick() -> void:
	_tick += 1

func log_birth(zoi_id: int, parent_ids: Array, genetics: Dictionary) -> void:
	_log_event("birth", {"zoi_id": zoi_id, "parent_ids": parent_ids, "genetics": genetics})

func log_death(zoi_id: int, cause: String, age_ticks: int, final_state: Dictionary) -> void:
	_log_event("death", {"zoi_id": zoi_id, "cause": cause, "age_ticks": age_ticks, "final_state": final_state})

func log_interaction(actor: int, target: int, type: String, outcome: Dictionary) -> void:
	_log_event("interaction", {"actor": actor, "target": target, "type": type, "outcome": outcome})

func log_resource(zoi_id: int, resource_type: String, amount: float, before: float, after: float) -> void:
	_log_event("resource_consumed", {"zoi_id": zoi_id, "resource_type": resource_type, "amount": amount, "before": before, "after": after})

func log_reward(zoi_id: int, reward: float, source: String) -> void:
	_log_event("reward", {"zoi_id": zoi_id, "reward": reward, "source": source})

func log_observation(zoi_id: int, obs: Array[float], action: int, reward: float) -> void:
	_log_event("obs_action", {"zoi_id": zoi_id, "obs": obs, "action": action, "reward": reward})

func log_language_token(zoi_id: int, token: int, context: String) -> void:
	_log_event("language_token", {"zoi_id": zoi_id, "token": token, "context": context})

func flush() -> void:
	if _buffer.is_empty():
		return
	if not _log_file:
		_buffer.clear()
		return
	for entry in _buffer:
		_log_file.store_line(JSON.stringify(entry))
	_log_file.flush()
	_buffer.clear()

func _log_event(type: String, data: Dictionary) -> void:
	var entry := {
		"t": _tick,
		"ts": Time.get_unix_time_from_system(),
		"type": type,
		"session": _session_id,
		"data": data
	}
	_buffer.append(entry)
	if _buffer.size() >= MAX_BUFFER_SIZE:
		flush()

func _get_log_path() -> String:
	var base := "user://telemetry"
	DirAccess.make_dir_recursive_absolute(base)
	return "%s/anima_%s.jsonl" % [base, _session_id]

func _generate_session_id() -> String:
	return "%d_%d" % [Time.get_unix_time_from_system(), randi()]

func _exit_tree() -> void:
	_log_event("session_end", {"total_ticks": _tick})
	flush()
	if _log_file:
		_log_file.close()
