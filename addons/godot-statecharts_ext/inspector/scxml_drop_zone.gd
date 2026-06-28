@tool
extends Panel

var _target_node: Node
var _plugin: EditorPlugin
var _label: Label
var _is_drag_hovering := false


func setup(target_node: Node, plugin: EditorPlugin) -> void:
	_target_node = target_node
	_plugin = plugin

	custom_minimum_size = Vector2(0, 36)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("panel", _make_panel_style())

	_label = Label.new()
	_label.text = "Drop SCXML here to import"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.anchors_preset = Control.PRESET_FULL_RECT
	add_child(_label)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var drag_type = data.get("type", "")
	if drag_type != "files" and drag_type != "files_and_dirs":
		return false
	var files: PackedStringArray = data.get("files", PackedStringArray())
	for f in files:
		if f.ends_with(".scxml"):
			if not _is_drag_hovering:
				_is_drag_hovering = true
				_update_drag_appearance()
			return true
	if _is_drag_hovering:
		_is_drag_hovering = false
		_update_drag_appearance()
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_is_drag_hovering = false
	_update_drag_appearance()

	var files: PackedStringArray = data.get("files", PackedStringArray())
	for f in files:
		if f.ends_with(".scxml"):
			_import_scxml(f)
			return


func _import_scxml(scxml_path: String) -> void:
	if not _target_node or not _plugin:
		return
	_label.text = "Importing..."
	_plugin.import_scxml_to_node(scxml_path, _target_node)
	_label.text = "Import complete"
	if _plugin.get_editor_interface() and is_inside_tree():
		var base := _plugin.get_editor_interface().get_base_control()
		if base:
			var timer := base.get_tree().create_timer(2.0)
			timer.timeout.connect(
				func():
					if is_inside_tree():
						_label.text = "Drop SCXML here to import"
			)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.17, 0.5)
	style.border_color = Color(0.4, 0.4, 0.45, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _update_drag_appearance() -> void:
	if _is_drag_hovering:
		self_modulate = Color(0.9, 0.95, 1.0, 0.9)
		_label.add_theme_color_override("font_color", Color(0.2, 0.5, 1.0))
	else:
		self_modulate = Color.WHITE
		_label.add_theme_color_override("font_color", Color.WHITE)
