## PlayerController — handles player input and dispatches world interventions.
## The player is a "Guiding Spirit": no direct unit control; only environmental nudges.
extends Node

# ── State ─────────────────────────────────────────────────────────────────────
enum Tool { SELECT, DROP_FOOD, DROP_WATER, BLESS, CURSE, RAIN, TERRAIN_RAISE, TERRAIN_LOWER }
var active_tool: Tool = Tool.SELECT
var selected_zoi_id: int = -1

# ── Input mapping (touch + keyboard) ─────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		_handle_mouse(event as InputEventMouseButton)
	elif event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)

func _handle_key(event: InputEventKey) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_1: active_tool = Tool.SELECT
		KEY_2: active_tool = Tool.DROP_FOOD
		KEY_3: active_tool = Tool.DROP_WATER
		KEY_4: active_tool = Tool.BLESS
		KEY_5: active_tool = Tool.CURSE
		KEY_6: active_tool = Tool.RAIN
		KEY_F1: _toggle_debug_overlays()

func _handle_mouse(event: InputEventMouseButton) -> void:
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	_use_tool_at_screen(event.position)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if not event.pressed:
		return
	_use_tool_at_screen(event.position)

func _use_tool_at_screen(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var world_pos := _raycast_ground(from, dir)

	match active_tool:
		Tool.SELECT:
			_try_select_zoi(screen_pos)
		Tool.DROP_FOOD:
			_drop_resource(world_pos, "food")
		Tool.DROP_WATER:
			_drop_resource(world_pos, "water")
		Tool.BLESS:
			if selected_zoi_id >= 0:
				_apply_player_reward(selected_zoi_id, 0.2)
		Tool.CURSE:
			if selected_zoi_id >= 0:
				_apply_player_reward(selected_zoi_id, -0.2)
		Tool.RAIN:
			EventBus.weather_changed.emit("rain", 0.7)

func _raycast_ground(from: Vector3, dir: Vector3) -> Vector3:
	var t := -from.y / dir.y if dir.y != 0.0 else 0.0
	return from + dir * t

func _try_select_zoi(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var space := get_viewport().get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = cam.project_ray_origin(screen_pos)
	params.to = params.from + cam.project_ray_normal(screen_pos) * 100.0
	params.collision_mask = 1
	var result := space.intersect_ray(params)
	if result and result.collider is ZoiNode:
		var zoi: ZoiNode = result.collider
		selected_zoi_id = zoi.zoi_id
		EventBus.player_selected_zoi.emit(selected_zoi_id)

func _drop_resource(pos: Vector3, type: String) -> void:
	EventBus.player_dropped_resource.emit(pos, type, 1.0)
	var wm: Node = get_tree().get_first_node_in_group("world_manager")
	if wm and wm.has_method("spawn_resource_at"):
		wm.spawn_resource_at(pos, type, 1.0)

func _apply_player_reward(zoi_id: int, delta: float) -> void:
	var event := "player_reward" if delta > 0.0 else "player_punish"
	AnimaCore.apply_event(zoi_id, event, {"delta": absf(delta)})
	EventBus.player_reward_applied.emit(zoi_id, delta)

func _toggle_debug_overlays() -> void:
	var wm: Node = get_tree().get_first_node_in_group("world_manager")
	if wm:
		wm.debug_overlays = not wm.debug_overlays
		for zoi in wm.get_all_zoi():
			if zoi.has_method("set_debug_visible"):
				zoi.set_debug_visible(wm.debug_overlays)
