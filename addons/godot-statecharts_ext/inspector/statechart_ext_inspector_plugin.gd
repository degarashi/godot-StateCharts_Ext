@tool
extends EditorInspectorPlugin

const StateChartExtScript := preload("uid://bjud7klva0cit")

var _plugin: EditorPlugin
var _doc_dialog: EditorFileDialog


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
	btn_export.pressed.connect(_plugin._manual_export_scxml)
	add_custom_control(btn_export)

	var btn_import := Button.new()
	btn_import.text = "Import SCXML..."
	btn_import.icon = _plugin.get_editor_interface().get_base_control().get_theme_icon(
		"Load", "EditorIcons"
	)
	btn_import.pressed.connect(_plugin._manual_import_scxml)
	add_custom_control(btn_import)

	if object.has_meta(StateChartExtScript.SCXML_PATH_META_KEY):
		var btn_reimport := Button.new()
		btn_reimport.text = "Re-import SCXML"
		btn_reimport.icon = _plugin.get_editor_interface().get_base_control().get_theme_icon(
			"Reload", "EditorIcons"
		)
		btn_reimport.pressed.connect(object.reimport_scxml)
		add_custom_control(btn_reimport)

	var btn_doc := Button.new()
	btn_doc.text = "Generate Markdown Doc..."
	btn_doc.icon = _plugin.get_editor_interface().get_base_control().get_theme_icon(
		"FileDoc", "EditorIcons"
	)
	btn_doc.pressed.connect(_on_generate_doc_pressed)
	add_custom_control(btn_doc)


func _on_generate_doc_pressed() -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExtScript:
		return

	var node := selected_nodes[0]
	var script := node.get_script()

	var gd_path: String = script.resource_path
	var scdef_path: String = gd_path.get_basename() + "." + StateChartExtScript.SCDEF_EXTENSION

	if not FileAccess.file_exists(scdef_path):
		printerr("Could not find .", StateChartExtScript.SCDEF_EXTENSION, " for this StateChart: ", scdef_path)
		return

	if not _doc_dialog:
		_doc_dialog = EditorFileDialog.new()
		_doc_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_doc_dialog.add_filter("*.md", "Markdown files")
		_doc_dialog.file_selected.connect(_on_doc_file_selected)
		_plugin.get_editor_interface().get_base_control().add_child(_doc_dialog)

	_doc_dialog.current_file = scdef_path.get_file().get_basename() + "_api.md"
	_doc_dialog.popup_centered_ratio(0.5)


func _on_doc_file_selected(path: String) -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExtScript:
		return

	var gd_path: String = selected_nodes[0].get_script().resource_path
	var scdef_path: String = gd_path.get_basename() + "." + StateChartExtScript.SCDEF_EXTENSION

	var f := FileAccess.open(scdef_path, FileAccess.READ)
	if not f:
		return
	var content := f.get_as_text()
	f.close()

	var parse_result := StateChartGenerator.parse_scdef(content)
	if not parse_result.error.is_empty():
		printerr("Failed to parse .scdef: ", parse_result.error)
		return

	var markdown := StateChartGenerator.generate_markdown_doc(
		parse_result.class_name, parse_result.events, parse_result.params
	)

	var f_out := FileAccess.open(path, FileAccess.WRITE)
	if f_out:
		f_out.store_string(markdown)
		f_out.close()
		print("API Documentation saved to: ", path)
