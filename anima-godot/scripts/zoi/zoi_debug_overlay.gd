## ZoiDebugOverlay — visual debug readout attached to each ZoiNode.
extends Node3D

@onready var thought_label: Label3D = $"../DebugOverlay/ThoughtBubble"

var _zoi_node: ZoiNode

func _ready() -> void:
	_zoi_node = get_parent() as ZoiNode

func _process(_delta: float) -> void:
	if not visible or not _zoi_node:
		return
	var state := AnimaCore.get_state(_zoi_node.zoi_id)
	if state.is_empty():
		return
	thought_label.text = (
		"[%d] %s\nE:%.0f%% H:%.0f%%\nCort:%.0f%% Dopa:%.0f%%"
		% [
			_zoi_node.zoi_id,
			_zoi_node._current_intent,
			state.get("energy", 0.0) * 100,
			state.get("hydration", 0.0) * 100,
			state.get("cortisol", 0.0) * 100,
			state.get("dopamine", 0.0) * 100,
		]
	)
