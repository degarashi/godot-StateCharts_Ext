@tool
extends EditorProperty

# ------------- [Private Variable] -------------
var _option_button: OptionButton
var _updating := false


# ------------- [Callbacks] -------------
func _init() -> void:
	_option_button = OptionButton.new()
	_option_button.clip_text = true
	_option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_option_button)
	add_focusable(_option_button)
	_option_button.item_selected.connect(_on_item_selected)


func _update_property() -> void:
	var current_value: StringName = get_edited_object()[get_edited_property()]
	if _updating:
		return
	_updating = true

	_option_button.clear()
	_option_button.add_item("(No Event)", 0)

	var events := _get_available_events()
	var selected_idx := 0
	for i in range(events.size()):
		var ev_name := events[i]
		_option_button.add_item(ev_name, i + 1)
		if ev_name == current_value:
			selected_idx = i + 1

	if selected_idx == 0 and not current_value.is_empty():
		_option_button.add_item(String(current_value), events.size() + 1)
		selected_idx = events.size() + 1

	_option_button.select(selected_idx)
	_updating = false


# ------------- [Private Method] -------------
func _on_item_selected(idx: int) -> void:
	if _updating:
		return
	var value := &""
	if idx > 0:
		value = StringName(_option_button.get_item_text(idx))
	emit_changed(get_edited_property(), value)


func _get_available_events() -> Array[StringName]:
	var events: Array[StringName] = []
	var node := get_edited_object() as Node
	if not node:
		return events

	var sc: Node = node.get_parent()
	while sc != null and not sc is StateChart:
		sc = sc.get_parent()

	if sc != null and sc.has_method("get_sc_info"):
		var info: Variant = sc.get_sc_info()
		if info != null and "event" in info and info.event != null:
			var event_script: Script = info.event
			var props := event_script.get_property_list()
			for p in props:
				if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					events.append(StringName(p.name))
	return events
