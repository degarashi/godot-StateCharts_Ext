@tool
extends EditorInspectorPlugin

const StateChartExtScript := preload("uid://bjud7klva0cit")

var _plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _can_handle(object: Object) -> bool:
	return object is StateChartExtScript


func _parse_begin(object: Object) -> void:
	var btn_export := Button.new()
	btn_export.text = "Export to SCXML..."
	btn_export.icon = _plugin.get_editor_interface().get_base_control().get_theme_icon(
		"Save", "EditorIcons"
	)
	btn_export.pressed.connect(_plugin._on_export_scxml_requested)
	add_custom_control(btn_export)

	var btn_import := Button.new()
	btn_import.text = "Import SCXML..."
	btn_import.icon = _plugin.get_editor_interface().get_base_control().get_theme_icon(
		"Load", "EditorIcons"
	)
	btn_import.pressed.connect(_plugin._on_import_scxml_requested)
	add_custom_control(btn_import)

	if object.has_meta(StateChartConstants.SCXML_PATH_META_KEY):
		var btn_reimport := Button.new()
		btn_reimport.text = "Re-import SCXML"
		btn_reimport.icon = _plugin.get_editor_interface().get_base_control().get_theme_icon(
			"Reload", "EditorIcons"
		)
		btn_reimport.pressed.connect(object.reimport_scxml)
		add_custom_control(btn_reimport)
