## EventBus — global signal hub for decoupled cross-system communication.
## All game-wide events flow through here; systems subscribe as needed.
extends Node

# ── Zoi lifecycle ────────────────────────────────────────────────────────────
signal zoi_born(zoi_id: int, parent_ids: Array)
signal zoi_died(zoi_id: int, cause: String)
signal zoi_spawned(zoi_node: Node)

# ── Needs / biochemistry ─────────────────────────────────────────────────────
signal hunger_critical(zoi_id: int, energy: float)
signal thirst_critical(zoi_id: int, hydration: float)
signal fatigue_critical(zoi_id: int, sleep_toxins: float)
signal temperature_extreme(zoi_id: int, body_temp: float)

# ── Social ───────────────────────────────────────────────────────────────────
signal interaction_occurred(actor_id: int, target_id: int, type: String, delta: float)
signal relationship_updated(a: int, b: int, new_trust: float)
signal token_emitted(zoi_id: int, token: int, context: Dictionary)

# ── World ────────────────────────────────────────────────────────────────────
signal weather_changed(new_weather: String, intensity: float)
signal time_of_day_changed(hour: float)
signal resource_depleted(node_id: int, resource_type: String)
signal resource_respawned(node_id: int)
signal predator_attack(predator_id: int, target_id: int, damage: float)

# ── Player ───────────────────────────────────────────────────────────────────
signal player_dropped_resource(position: Vector3, resource_type: String, amount: float)
signal player_selected_zoi(zoi_id: int)
signal player_reward_applied(zoi_id: int, delta: float)

# ── Telemetry ────────────────────────────────────────────────────────────────
signal telemetry_event(event: Dictionary)
