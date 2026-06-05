@tool
## Context menu plugin for the Scene Tree dock.
extends EditorContextMenuPlugin

var _plugin: EditorPlugin


func _init(p: EditorPlugin) -> void:
	_plugin = p


func _popup_menu(paths: PackedStringArray) -> void:
	var edited_root := _plugin.get_editor_interface().get_edited_scene_root()
	if not edited_root:
		return

	var target_nodes: Array[Node] = []
	for path in paths:
		var node := edited_root.get_node_or_null(path)
		if node is StateChartExt:
			target_nodes.append(node)

	if not target_nodes.is_empty():
		var icon_export := _plugin.get_editor_interface().get_base_control().get_theme_icon(
			"Save", "EditorIcons"
		)
		add_context_menu_item(
			"Export to SCXML...", _on_export_clicked.bind(target_nodes).unbind(1), icon_export
		)

		var icon_import := _plugin.get_editor_interface().get_base_control().get_theme_icon(
			"Load", "EditorIcons"
		)
		add_context_menu_item(
			"Import SCXML...", _on_import_clicked.bind(target_nodes).unbind(1), icon_import
		)

		var icon_open := _plugin.get_editor_interface().get_base_control().get_theme_icon(
			"Edit", "EditorIcons"
		)
		add_context_menu_item(
			"Open associated .scdef", _on_open_scdef_clicked.bind(target_nodes).unbind(1), icon_open
		)


func _on_export_clicked(nodes: Array[Node]) -> void:
	var selection := _plugin.get_editor_interface().get_selection()
	selection.clear()
	for node in nodes:
		selection.add_node(node)
	_plugin.call("_on_export_scxml_requested")


func _on_import_clicked(nodes: Array[Node]) -> void:
	var selection := _plugin.get_editor_interface().get_selection()
	selection.clear()
	for node in nodes:
		selection.add_node(node)
	_plugin.call("_on_import_scxml_requested")


func _on_open_scdef_clicked(nodes: Array[Node]) -> void:
	for node in nodes:
		var script := node.get_script() as Script
		if not script:
			continue
		var script_path := script.get_path()
		var scdef_path := script_path.get_basename() + "." + StateChartExt.SCDEF_EXTENSION
		if FileAccess.file_exists(scdef_path):
			_plugin.get_editor_interface().edit_resource(load(scdef_path))
			break
