@tool
## Context menu plugin for the FileSystem dock.
extends EditorContextMenuPlugin

var _plugin: EditorPlugin


func _init(p: EditorPlugin) -> void:
	_plugin = p


func _popup_menu(paths: PackedStringArray) -> void:
	var scxml_paths: PackedStringArray = []
	var scdef_paths: PackedStringArray = []
	for path in paths:
		if path.ends_with(".scxml"):
			scxml_paths.append(path)
		elif path.ends_with("." + StateChartConstants.SCDEF_EXTENSION):
			scdef_paths.append(path)

	if not scxml_paths.is_empty():
		var icon := _plugin.get_editor_interface().get_base_control().get_theme_icon(
			"Object", "EditorIcons"
		)
		add_context_menu_item(
			"Convert SCXML to ." + StateChartConstants.SCDEF_EXTENSION,
			_on_convert_clicked.bind(scxml_paths).unbind(1),
			icon
		)

	if not scdef_paths.is_empty():
		var icon := _plugin.get_editor_interface().get_base_control().get_theme_icon(
			"Script", "EditorIcons"
		)
		add_context_menu_item(
			"Regenerate GDScript", _on_regenerate_clicked.bind(scdef_paths).unbind(1), icon
		)


func _on_convert_clicked(paths: PackedStringArray) -> void:
	for path in paths:
		_plugin.call("_on_scxml_convert_file_selected", path)


func _on_regenerate_clicked(paths: PackedStringArray) -> void:
	for path in paths:
		_plugin.call("_process_scdef_file", path)
