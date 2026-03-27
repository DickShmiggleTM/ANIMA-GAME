## HUD — heads-up display: toolbar, Zoi inspector panel, world info.
extends CanvasLayer

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var zoi_count_label: Label = $Panel/ZoiCount
@onready var time_label: Label = $Panel/TimeLabel
@onready var weather_label: Label = $Panel/WeatherLabel
@onready var inspector_panel: PanelContainer = $InspectorPanel
@onready var inspector_name: Label = $InspectorPanel/VBox/Name
@onready var energy_bar: ProgressBar = $InspectorPanel/VBox/EnergyBar
@onready var hydration_bar: ProgressBar = $InspectorPanel/VBox/HydrationBar
@onready var cortisol_bar: ProgressBar = $InspectorPanel/VBox/CortisolBar
@onready var dopamine_bar: ProgressBar = $InspectorPanel/VBox/DopamineBar
@onready var intent_label: Label = $InspectorPanel/VBox/Intent
@onready var tool_buttons: HBoxContainer = $ToolBar/HBox

var _selected_zoi_id: int = -1
var _wm: Node  # WorldManager ref

func _ready() -> void:
	EventBus.player_selected_zoi.connect(_on_zoi_selected)
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.time_of_day_changed.connect(_on_time_changed)
	_build_toolbar()
	if inspector_panel:
		inspector_panel.visible = false
	_wm = get_tree().get_first_node_in_group("world_manager")

func _process(_delta: float) -> void:
	if zoi_count_label and _wm:
		zoi_count_label.text = "Zoi: %d" % _wm.get_zoi_count()
	if _selected_zoi_id >= 0:
		_refresh_inspector()

func _on_zoi_selected(zoi_id: int) -> void:
	_selected_zoi_id = zoi_id
	if inspector_panel:
		inspector_panel.visible = true

func _on_weather_changed(weather: String, intensity: float) -> void:
	if weather_label:
		weather_label.text = "Weather: %s (%.0f%%)" % [weather.capitalize(), intensity * 100]

func _on_time_changed(hour: float) -> void:
	if time_label:
		var h := int(hour)
		var m := int(fmod(hour, 1.0) * 60)
		time_label.text = "%02d:%02d" % [h, m]

func _refresh_inspector() -> void:
	var state := AnimaCore.get_state(_selected_zoi_id)
	if state.is_empty():
		return
	if inspector_name:
		inspector_name.text = "Zoi #%d" % _selected_zoi_id
	if energy_bar:
		energy_bar.value = state.get("energy", 0.0) * 100
	if hydration_bar:
		hydration_bar.value = state.get("hydration", 0.0) * 100
	if cortisol_bar:
		cortisol_bar.value = state.get("cortisol", 0.0) * 100
	if dopamine_bar:
		dopamine_bar.value = state.get("dopamine", 0.0) * 100

func _build_toolbar() -> void:
	if not tool_buttons:
		return
	var tools := [
		["Select", "1"],
		["Drop Food", "2"],
		["Drop Water", "3"],
		["Bless", "4"],
		["Curse", "5"],
		["Rain", "6"],
		["Debug F1", "F1"],
	]
	for t in tools:
		var btn := Button.new()
		btn.text = t[0]
		btn.tooltip_text = "Key: %s" % t[1]
		btn.custom_minimum_size = Vector2(80, 44)  # touch-friendly
		tool_buttons.add_child(btn)
