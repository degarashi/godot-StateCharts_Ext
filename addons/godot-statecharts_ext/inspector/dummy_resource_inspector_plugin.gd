@tool
extends EditorInspectorPlugin

var _plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _can_handle(object: Object) -> bool:
	return object is StateChartDefinition or object is StateChartSCXML


func _parse_begin(object: Object) -> void:

	# Also add a button to open in external editor for convenience
	var btn := Button.new()
	btn.text = "Open in External Editor"
	btn.icon = _plugin.get_editor_interface().get_base_control().get_theme_icon(
		"ExternalLink", "EditorIcons"
	)
	btn.pressed.connect(func(): _plugin._open_in_external_editor(object.resource_path))
	add_custom_control(btn)
