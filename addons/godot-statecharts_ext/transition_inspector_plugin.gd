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
	object: Object,
	type: int,
	name: String,
	hint_type: int,
	hint_string: String,
	usage_flags: int,
	wide: bool
) -> bool:
	if name == "event":
		var ep := preload("transition_event_editor_property.gd").new()
		add_property_editor(name, ep)
		return true
	return false
