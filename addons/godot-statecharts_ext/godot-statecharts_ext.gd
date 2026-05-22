@tool
## Main entry point for the Godot StateCharts Extra plugin.
## Manages .scdef file monitoring, automatic code generation triggers,
## and registration of the import plugin.
extends EditorPlugin

# ------------- [Constants] -------------
const CAT = "ScExt_Gen"

# ------------- [Private Variables] -------------
var _fs_reloading := false
var _import_plugin: RefCounted
var _inspector_plugin: EditorInspectorPlugin


# ------------- [Lifecycle Methods] -------------
func _enter_tree() -> void:
	DLogger.info("Plugin enabled.", [], CAT)

	_import_plugin = preload("scdef_import_plugin.gd").new()
	add_import_plugin(_import_plugin)

	# Wait for the editor to be fully ready before registration
	_register_inspector_delayed()

	var fs := EditorInterface.get_resource_filesystem()
	fs.filesystem_changed.connect(_on_filesystem_changed)
	if fs.has_signal("sources_changed"):
		fs.sources_changed.connect(_on_sources_changed)

	add_tool_menu_item("StateChartExt: Force Regenerate all .scdef", _manual_scan)
	add_tool_menu_item("StateChartExt: Export current StateChart as SCXML", _manual_export_scxml)
	add_tool_menu_item("StateChartExt: Import SCXML to current StateChart", _manual_import_scxml)

	# Wait for the filesystem to be fully loaded before initial scan
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	if _import_plugin:
		remove_import_plugin(_import_plugin)
		_import_plugin = null

	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null

	remove_tool_menu_item("StateChartExt: Force Regenerate all .scdef")
	remove_tool_menu_item("StateChartExt: Export current StateChart as SCXML")
	remove_tool_menu_item("StateChartExt: Import SCXML to current StateChart")

	var fs := EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)
	if fs.has_signal("sources_changed") and fs.sources_changed.is_connected(_on_sources_changed):
		fs.sources_changed.disconnect(_on_sources_changed)


# ------------- [Callbacks] -------------
func _on_filesystem_changed() -> void:
	if _fs_reloading:
		return

	_fs_reloading = true
	_scan_and_generate()
	await get_tree().create_timer(1.0).timeout
	_fs_reloading = false


func _on_sources_changed(_exist: bool) -> void:
	_on_filesystem_changed()


# ------------- [Private Methods] -------------
func _manual_scan() -> void:
	DLogger.info("Manual scan started...", [], CAT)
	EditorInterface.get_resource_filesystem().scan()
	_scan_and_generate()
	DLogger.info("Manual scan finished.", [], CAT)


var _scxml_export_dialog: EditorFileDialog
var _scxml_import_dialog: EditorFileDialog

func _manual_export_scxml() -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExt:
		DLogger.warn("Select a StateChartExt node to export.", [], CAT)
		return

	var node := selected_nodes[0]
	if not _scxml_export_dialog:
		_scxml_export_dialog = EditorFileDialog.new()
		_scxml_export_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_scxml_export_dialog.add_filter("*.scxml", "SCXML files")
		_scxml_export_dialog.file_selected.connect(_on_scxml_export_file_selected)
		EditorInterface.get_base_control().add_child(_scxml_export_dialog)

	_scxml_export_dialog.current_file = node.name + ".scxml"
	_scxml_export_dialog.popup_centered_ratio(0.5)


func _on_scxml_export_file_selected(path: String) -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExt:
		return

	var exporter := StateChartScxmlExporter.new()
	var err := exporter.export_and_save(selected_nodes[0], path)
	if err == OK:
		DLogger.info("SCXML exported to: {0}", [path], CAT)
	else:
		DLogger.error("Failed to export SCXML: {0}", [err], CAT)


func _manual_import_scxml() -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExt:
		DLogger.warn("Select a StateChartExt node to import SCXML into.", [], CAT)
		return

	if not _scxml_import_dialog:
		_scxml_import_dialog = EditorFileDialog.new()
		_scxml_import_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_scxml_import_dialog.add_filter("*.scxml", "SCXML files")
		_scxml_import_dialog.file_selected.connect(_on_scxml_import_file_selected)
		EditorInterface.get_base_control().add_child(_scxml_import_dialog)

	_scxml_import_dialog.popup_centered_ratio(0.5)


func _on_scxml_import_file_selected(path: String) -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExt:
		return

	var importer := StateChartScxmlImporter.new()
	var err := importer.import_scxml(path, selected_nodes[0])
	if err == OK:
		DLogger.info("SCXML imported successfully: {0}", [path], CAT)
	else:
		DLogger.error("Failed to import SCXML: {0}", [err], CAT)



func _process_scdef_file(scdef_path: String) -> void:
	var gd_path := scdef_path.get_basename() + ".gd"

	var f_scdef := FileAccess.open(scdef_path, FileAccess.READ)
	if not f_scdef:
		DLogger.error("Could not open scdef for reading: {0}", [scdef_path], CAT)
		return
	var content := f_scdef.get_as_text()
	f_scdef.close()

	var old_content := ""
	if FileAccess.file_exists(gd_path):
		var f_gd := FileAccess.open(gd_path, FileAccess.READ)
		if f_gd:
			old_content = f_gd.get_as_text()
			f_gd.close()

	var fallback_name := scdef_path.get_file().get_basename().to_pascal_case() + "SC"
	var result := StateChartGenerator.parse_and_generate(content, fallback_name)

	if not result.error.is_empty():
		DLogger.error("Syntax error in {0}:\n{1}", [scdef_path, result.error], CAT)
		return

	var generated_code: String = result.code

	if generated_code != old_content:
		var f_out := FileAccess.open(gd_path, FileAccess.WRITE)
		if f_out:
			f_out.store_string(generated_code)
			f_out.close()
			DLogger.info("Generated: {0}", [gd_path], CAT)
			EditorInterface.get_resource_filesystem().update_file(gd_path)
		else:
			DLogger.error("Could not open gd for writing: {0}".format([gd_path]), [], CAT)


func _register_inspector_delayed() -> void:
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame

	if _inspector_plugin:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null

	_inspector_plugin = preload("transition_inspector_plugin.gd").new()
	add_inspector_plugin(_inspector_plugin)
	DLogger.info("Transition Inspector Plugin registered safely.", [], CAT)


func _scan_and_generate() -> void:
	_scan_dir_recursive("res://")


func _scan_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		DLogger.error("Could not open directory: {0}".format([path]), [], CAT)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_scan_dir_recursive(path.path_join(file_name))
		else:
			if file_name.ends_with(".scdef"):
				var full_path := path.path_join(file_name)
				_process_scdef_file(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()
