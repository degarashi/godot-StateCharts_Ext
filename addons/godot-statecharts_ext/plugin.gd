@tool
extends EditorPlugin

# ------------- [Constants] -------------

const ICON_ON_STATE_ENTERED = preload("res://addons/godot-statecharts_ext/icons/icon_on_state_entered.svg")
const ICON_ON_STATE_EXITED = preload("res://addons/godot-statecharts_ext/icons/icon_on_state_exited.svg")
const ICON_ON_EVENT_RECEIVED = preload("res://addons/godot-statecharts_ext/icons/icon_on_event_received.svg")
const ICON_ON_STATE_PROCESSING = preload("res://addons/godot-statecharts_ext/icons/icon_on_state_processing.svg")
const ICON_ON_PHYSICS_STATE_PROCESSING = preload("res://addons/godot-statecharts_ext/icons/icon_on_physics_state_processing.svg")

# ------------- [Private Method] -------------


func _enter_tree() -> void:
	pass


func _exit_tree() -> void:
	pass


func _get_plugin_name() -> String:
	return "StateChartsExt"


func _get_plugin_icon() -> Texture2D:
	return preload("res://addons/godot-statecharts_ext/icons/statechart_ext.svg")


## FileSystemタブ等で特定のパスに対して表示するアイコンを制御する
func _get_export_icon_for_path(path: String) -> Texture2D:
	if path.ends_with(".scdef") or path.ends_with(".scxml"):
		return preload("res://addons/godot-statecharts_ext/icons/statechart_ext.svg")
	return null
