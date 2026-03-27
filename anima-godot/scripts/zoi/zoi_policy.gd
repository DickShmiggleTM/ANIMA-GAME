## ZoiPolicy — ONNX policy inference wrapper.
## Loads an ONNX model via GDExtension, falls back to rule-based heuristics.
## Supports habit biasing from episodic memory.
class_name ZoiPolicy
extends RefCounted

const ACTION_NAMES := ["idle", "eat", "drink", "rest", "wander", "socialize", "flee", "build", "share", "call"]
const ACTION_COUNT := 10

var _model_path: String
var _onnx_session  # OnnxSession from GDExtension or null
var _loaded := false

func _init(model_path: String = "") -> void:
	_model_path = model_path
	if model_path != "":
		_try_load(model_path)

func _try_load(path: String) -> void:
	if ClassDB.class_exists("OnnxSession"):
		_onnx_session = ClassDB.instantiate("OnnxSession")
		if _onnx_session and _onnx_session.load(path) == OK:
			_loaded = true
			print("ZoiPolicy: loaded ONNX model from %s" % path)
		else:
			push_warning("ZoiPolicy: failed to load ONNX model from %s" % path)

func infer(obs: Array[float], habit_bias: Array[float] = []) -> int:
	if _loaded and _onnx_session:
		return _onnx_infer(obs, habit_bias)
	return _heuristic_infer(obs, habit_bias)

func _onnx_infer(obs: Array[float], habit_bias: Array[float]) -> int:
	var logits: Array = _onnx_session.run(obs)
	if logits.is_empty():
		return _heuristic_infer(obs, habit_bias)
	return _sample_with_bias(logits, habit_bias)

func _heuristic_infer(obs: Array[float], habit_bias: Array[float]) -> int:
	# obs layout: [energy, hydration, sleep_toxins, cortisol, dopamine,
	#              body_temp_norm, nearby_count, food_dist_inv, water_dist_inv, time_of_day]
	if obs.size() < 9:
		return 0  # idle

	var energy: float = obs[0]
	var hydration: float = obs[1]
	var sleep_toxins: float = obs[2]
	var cortisol: float = obs[3]
	var food_signal: float = obs[7]
	var water_signal: float = obs[8]

	# Build simple logits
	var logits: Array[float] = []
	logits.resize(ACTION_COUNT)
	logits.fill(0.0)

	logits[0] = 0.1                                       # idle
	logits[1] = (1.0 - energy) * 2.0 * food_signal       # eat
	logits[2] = (1.0 - hydration) * 2.0 * water_signal   # drink
	logits[3] = sleep_toxins * 1.5                        # rest
	logits[4] = 0.3                                       # wander
	logits[5] = (1.0 - cortisol) * 0.5                   # socialize
	logits[6] = cortisol * 0.8                            # flee

	return _sample_with_bias(logits, habit_bias)

func _sample_with_bias(logits: Array, habit_bias: Array[float]) -> int:
	# Apply habit bias, then argmax (greedy)
	var best := 0
	var best_val := -INF
	for i in mini(logits.size(), ACTION_COUNT):
		var v: float = float(logits[i])
		if i < habit_bias.size():
			v += habit_bias[i] * 0.3
		if v > best_val:
			best_val = v
			best = i
	return best

func action_name(action: int) -> String:
	if action < ACTION_NAMES.size():
		return ACTION_NAMES[action]
	return "unknown"
