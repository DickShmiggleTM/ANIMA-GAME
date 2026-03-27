## ZoiMemory — per-agent episodic buffer and relationship graph.
## Stores (context, action, outcome, reward, participants, location, timestamp).
class_name ZoiMemory
extends RefCounted

const MAX_EPISODES := 256
const MAX_RELATIONS := 64

var owner_id: int

# ── Episodic buffer ───────────────────────────────────────────────────────────
# Each entry: {context, action, outcome, reward, participants, location, tick}
var _episodes: Array[Dictionary] = []

# ── Relationship graph ────────────────────────────────────────────────────────
# trust_weights[other_id] = float in [-1, 1]
var _trust_weights: Dictionary = {}

# ── Imitation templates ───────────────────────────────────────────────────────
# Behavior templates copied from high-reward neighbors
# {source_id, obs, action, reward, tick}
var _imitation_templates: Array[Dictionary] = []

# ── Language token associations ───────────────────────────────────────────────
# token_id -> {contexts: [str], count: int}
var _token_map: Dictionary = {}

func _init(id: int) -> void:
	owner_id = id

# ── Episodic API ──────────────────────────────────────────────────────────────
func record_episode(context: Dictionary, action: int, outcome: String, reward: float,
		participants: Array, location: Vector3, tick: int) -> void:
	var entry := {
		"context": context,
		"action": action,
		"outcome": outcome,
		"reward": reward,
		"participants": participants,
		"location": {"x": location.x, "y": location.y, "z": location.z},
		"tick": tick,
	}
	_episodes.append(entry)
	if _episodes.size() > MAX_EPISODES:
		_episodes.pop_front()

func get_recent_episodes(n: int = 10) -> Array[Dictionary]:
	var start := maxi(0, _episodes.size() - n)
	return _episodes.slice(start)

func get_habit_bias(action_count: int) -> Array[float]:
	"""Return a softmax-compatible bias vector from recent successful actions."""
	var bias := []
	bias.resize(action_count)
	bias.fill(0.0)
	var recent := get_recent_episodes(32)
	for ep in recent:
		var a: int = ep.get("action", 0)
		if a < action_count:
			bias[a] += ep.get("reward", 0.0)
	return bias

# ── Relationship API ──────────────────────────────────────────────────────────
func record_interaction(other_id: int, delta: float) -> void:
	var current: float = _trust_weights.get(other_id, 0.0)
	_trust_weights[other_id] = clampf(current + delta, -1.0, 1.0)
	if _trust_weights.size() > MAX_RELATIONS:
		_prune_weakest_relation()
	EventBus.relationship_updated.emit(owner_id, other_id, _trust_weights[other_id])

func get_trust(other_id: int) -> float:
	return _trust_weights.get(other_id, 0.0)

func get_trusted_allies() -> Array:
	var result := []
	for id in _trust_weights:
		if _trust_weights[id] > 0.3:
			result.append(id)
	return result

func _prune_weakest_relation() -> void:
	var weakest_id = null
	var weakest_val := INF
	for id in _trust_weights:
		var v: float = absf(_trust_weights[id])
		if v < weakest_val:
			weakest_val = v
			weakest_id = id
	if weakest_id != null:
		_trust_weights.erase(weakest_id)

# ── Imitation API ─────────────────────────────────────────────────────────────
func store_imitation_template(source_id: int, obs: Array[float], action: int,
		reward: float, tick: int) -> void:
	_imitation_templates.append({
		"source_id": source_id,
		"obs": obs,
		"action": action,
		"reward": reward,
		"tick": tick,
	})
	if _imitation_templates.size() > 32:
		_imitation_templates.pop_front()

func get_best_imitation_action(obs: Array[float], action_count: int) -> int:
	"""Return the action from the highest-reward imitation template closest to current obs."""
	var best_action := -1
	var best_reward := -INF
	for t in _imitation_templates:
		var sim := _obs_similarity(obs, t.get("obs", []))
		var weighted_reward: float = t.get("reward", 0.0) * sim
		if weighted_reward > best_reward:
			best_reward = weighted_reward
			best_action = t.get("action", 0)
	return best_action

func _obs_similarity(a: Array[float], b: Array[float]) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var dist := 0.0
	for i in a.size():
		dist += (a[i] - b[i]) * (a[i] - b[i])
	return 1.0 / (1.0 + sqrt(dist))

# ── Language token API ────────────────────────────────────────────────────────
func hear_token(token: int, context: String) -> void:
	if not _token_map.has(token):
		_token_map[token] = {"contexts": [], "count": 0}
	_token_map[token]["contexts"].append(context)
	_token_map[token]["count"] += 1
	if _token_map[token]["contexts"].size() > 16:
		_token_map[token]["contexts"].pop_front()

func get_token_context(token: int) -> String:
	if _token_map.has(token):
		var ctxs: Array = _token_map[token]["contexts"]
		if not ctxs.is_empty():
			return ctxs[-1]
	return ""

func serialize() -> Dictionary:
	return {
		"owner_id": owner_id,
		"episodes": _episodes,
		"trust_weights": _trust_weights,
		"imitation_templates": _imitation_templates,
		"token_map": _token_map,
	}

func deserialize(data: Dictionary) -> void:
	owner_id = data.get("owner_id", owner_id)
	_episodes = data.get("episodes", [])
	_trust_weights = data.get("trust_weights", {})
	_imitation_templates = data.get("imitation_templates", [])
	_token_map = data.get("token_map", {})
