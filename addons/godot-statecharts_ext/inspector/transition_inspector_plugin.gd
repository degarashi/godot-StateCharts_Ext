@tool
extends EditorInspectorPlugin


func _can_handle(object: Object) -> bool:
	if object == null:
		return false
	var scr: Script = object.get_script()
	if scr != null:
		var path := scr.resource_path
		if path.ends_with("transition.gd") and "godot_state_charts" in path:
			return true

	# Consider cases where it is not registered as a global class name
	if object.is_class("Transition") or object.get_class() == "Transition":
		DLogger.debug("MATCH via class type!", [], "state_chart", self)
		return true
	return false


func _parse_property(
	_object: Object,
	_type: int,
	name: String,
	_hint_type: int,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if name == "event":
		var ep := preload("uid://c2btctwyvhbml").new()
		add_property_editor(name, ep)
		return true
	return false
