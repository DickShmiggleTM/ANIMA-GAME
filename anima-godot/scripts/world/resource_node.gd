## ResourceNode — a consumable resource (food or water) with regeneration.
class_name ResourceNode
extends Node3D

@export var resource_type: String = "food"
@export var max_amount: float = 1.0
@export var regen_time: float = 30.0
@export var nutrition_value: float = 0.2

var _amount: float
var _depleted := false
@onready var mesh: MeshInstance3D = $Mesh
@onready var regen_timer: Timer = $SpawnTimer

const TYPE_COLORS := {
	"food":  Color(0.2, 0.8, 0.2),
	"water": Color(0.2, 0.4, 1.0),
}

func _ready() -> void:
	_amount = max_amount
	resource_type = get_meta("resource_type", resource_type)
	_update_visual()
	regen_timer.wait_time = regen_time
	regen_timer.timeout.connect(_on_regen)
	add_to_group("%s_resource" % resource_type)

func consume(amount: float) -> float:
	if _depleted:
		return 0.0
	var taken := minf(amount, _amount)
	_amount -= taken
	Telemetry.log_resource(-1, resource_type, taken, _amount + taken, _amount)
	if _amount <= 0.0:
		_deplete()
	else:
		_update_visual()
	return taken

func _deplete() -> void:
	_depleted = true
	mesh.visible = false
	remove_from_group("%s_resource" % resource_type)
	regen_timer.start()
	EventBus.resource_depleted.emit(get_instance_id(), resource_type)

func _on_regen() -> void:
	_amount = max_amount
	_depleted = false
	mesh.visible = true
	add_to_group("%s_resource" % resource_type)
	_update_visual()
	EventBus.resource_respawned.emit(get_instance_id())

func _update_visual() -> void:
	if not mesh:
		return
	var mat: StandardMaterial3D = mesh.get_surface_override_material(0)
	if not mat:
		mat = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, mat)
	var base_color: Color = TYPE_COLORS.get(resource_type, Color.WHITE)
	var fill := _amount / max_amount
	mat.albedo_color = base_color.lerp(Color.GRAY, 1.0 - fill)
	mesh.scale = Vector3.ONE * (0.4 + fill * 0.6)
