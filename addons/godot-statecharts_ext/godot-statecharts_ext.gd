@tool
## Main entry point for the Godot StateCharts Extra plugin.
## Manages .scdef file monitoring, automatic code generation triggers,
## and registration of the import plugin.
extends EditorPlugin

# ------------- [Constants] -------------
const CAT = "ScExt_Gen"
const MENU_FORCE_REGENERATE := (
	"StateChartExt: Force Regenerate all ." + StateChartExt.SCDEF_EXTENSION
)
const MENU_EXPORT_SCXML := "StateChartExt: Export current StateChart as SCXML"
const MENU_IMPORT_SCXML := "StateChartExt: Import SCXML to current StateChart"
const MENU_CONVERT_SCXML := "StateChartExt: Convert SCXML to ." + StateChartExt.SCDEF_EXTENSION

# ------------- [Private Variables] -------------
var _fs_reloading := false
var _import_plugin: EditorImportPlugin
var _scxml_import_plugin: EditorImportPlugin
var _transition_inspector_plugin: EditorInspectorPlugin
var _statechart_ext_inspector_plugin: EditorInspectorPlugin
var _context_menu_plugin: EditorContextMenuPlugin

var _scxml_export_dialog: EditorFileDialog
var _scxml_import_dialog: EditorFileDialog


# ------------- [Lifecycle Methods] -------------
func _enter_tree() -> void:
	DLogger.info("Plugin enabled.", [], CAT)

	var DummyImportPlugin := preload("uid://b70108gychlte")
	_import_plugin = DummyImportPlugin.new(
		"statechart_ext." + StateChartExt.SCDEF_EXTENSION,
		"StateChart Definition",
		[StateChartExt.SCDEF_EXTENSION]
	)
	add_import_plugin(_import_plugin)

	_scxml_import_plugin = DummyImportPlugin.new("statechart_ext.scxml", "SCXML File", ["scxml"])
	add_import_plugin(_scxml_import_plugin)

	# Wait for the editor to be fully ready before registration
	_register_inspectors_delayed()

	var fs := EditorInterface.get_resource_filesystem()
	fs.filesystem_changed.connect(_on_filesystem_changed)
	if fs.has_signal("sources_changed"):
		fs.sources_changed.connect(_on_sources_changed)

	add_tool_menu_item(MENU_FORCE_REGENERATE, _on_manual_scan_requested)
	add_tool_menu_item(MENU_CONVERT_SCXML, _on_convert_scxml_to_scdef_requested)

	_context_menu_plugin = ScExtFileSystemContextMenuPlugin.new(self)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _context_menu_plugin)

	# Wait for the filesystem to be fully loaded before initial scan
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	if _import_plugin:
		remove_import_plugin(_import_plugin)
		_import_plugin = null

	if _scxml_import_plugin:
		remove_import_plugin(_scxml_import_plugin)
		_scxml_import_plugin = null

	if _transition_inspector_plugin:
		remove_inspector_plugin(_transition_inspector_plugin)
		_transition_inspector_plugin = null

	if _statechart_ext_inspector_plugin:
		remove_inspector_plugin(_statechart_ext_inspector_plugin)
		_statechart_ext_inspector_plugin = null

	if _context_menu_plugin:
		remove_context_menu_plugin(_context_menu_plugin)
		_context_menu_plugin = null

	remove_tool_menu_item(MENU_FORCE_REGENERATE)
	remove_tool_menu_item(MENU_EXPORT_SCXML)
	remove_tool_menu_item(MENU_IMPORT_SCXML)
	remove_tool_menu_item(MENU_CONVERT_SCXML)

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
func _on_manual_scan_requested() -> void:
	DLogger.info("Manual scan started...", [], CAT)
	EditorInterface.get_resource_filesystem().scan()
	_scan_and_generate()
	DLogger.info("Manual scan finished.", [], CAT)


func _on_export_scxml_requested() -> void:
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


func _on_import_scxml_requested() -> void:
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


func _on_convert_scxml_to_scdef_requested() -> void:
	if not _scxml_import_dialog:
		_scxml_import_dialog = EditorFileDialog.new()
		_scxml_import_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_scxml_import_dialog.add_filter("*.scxml", "SCXML files")
		_scxml_import_dialog.file_selected.connect(_on_scxml_convert_file_selected)
		EditorInterface.get_base_control().add_child(_scxml_import_dialog)

	_scxml_import_dialog.popup_centered_ratio(0.5)


func _on_scxml_convert_file_selected(path: String) -> void:
	var scdef_path := path.get_basename() + "." + StateChartExt.SCDEF_EXTENSION
	var scdef_content := StateChartScxmlImporter.generate_scdef(path)

	if not scdef_content.is_empty():
		var f := FileAccess.open(scdef_path, FileAccess.WRITE)
		if f:
			f.store_string(scdef_content)
			f.close()
			DLogger.info("Generated .scdef: {0}", [scdef_path], CAT)
			EditorInterface.get_resource_filesystem().update_file(scdef_path)
			_process_scdef_file(scdef_path)
			EditorInterface.select_file(scdef_path)
		else:
			DLogger.error("Failed to write .scdef: {0}", [scdef_path], CAT)
	else:
		DLogger.error("Failed to generate .scdef from: {0}", [path], CAT)


func _on_scxml_import_file_selected(path: String) -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExt:
		return

	# Auto-generate and save .scdef from SCXML
	var scdef_path := path.get_basename() + "." + StateChartExt.SCDEF_EXTENSION
	var scdef_content := StateChartScxmlImporter.generate_scdef(path)
	if not scdef_content.is_empty():
		var f_scdef := FileAccess.open(scdef_path, FileAccess.WRITE)
		if f_scdef:
			f_scdef.store_string(scdef_content)
			f_scdef.close()
			DLogger.info("Auto-generated .scdef: {0}", [scdef_path], CAT)
			EditorInterface.get_resource_filesystem().update_file(scdef_path)
			_process_scdef_file(scdef_path)  # Generate .gd immediately

	var importer := StateChartScxmlImporter.new()
	var err := importer.import_scxml(path, selected_nodes[0])
	if err == OK:
		DLogger.info("SCXML imported successfully: {0}", [path], CAT)
		# Automatically attach generated GDScript to node
		var gd_path := scdef_path.get_basename() + "." + StateChartExt.GD_EXTENSION
		var script := load(gd_path) as Script
		if script:
			selected_nodes[0].set_script(script)
			DLogger.info("Attached generated script: {0}", [gd_path], CAT)
	else:
		DLogger.error("Failed to import SCXML: {0}", [err], CAT)


func _convert_scxml_to_scdef_if_needed(scxml_path: String) -> void:
	var scdef_path := scxml_path.get_basename() + "." + StateChartExt.SCDEF_EXTENSION
	var scdef_content := StateChartScxmlImporter.generate_scdef(scxml_path)

	if scdef_content.is_empty():
		return

	var old_content := ""
	if FileAccess.file_exists(scdef_path):
		var f := FileAccess.open(scdef_path, FileAccess.READ)
		if f:
			old_content = f.get_as_text()
			f.close()

	if scdef_content != old_content:
		var f := FileAccess.open(scdef_path, FileAccess.WRITE)
		if f:
			f.store_string(scdef_content)
			f.close()
			DLogger.info("Auto-generated .scdef from .scxml: {0}", [scdef_path], CAT)
			EditorInterface.get_resource_filesystem().update_file(scdef_path)
			_process_scdef_file(scdef_path)
		else:
			DLogger.error("Failed to write auto-generated .scdef: {0}", [scdef_path], CAT)


func _process_scdef_file(scdef_path: String) -> void:
	var gd_path := scdef_path.get_basename() + "." + StateChartExt.GD_EXTENSION

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


func _register_inspectors_delayed() -> void:
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame

	if _transition_inspector_plugin:
		remove_inspector_plugin(_transition_inspector_plugin)
		_transition_inspector_plugin = null

	if _statechart_ext_inspector_plugin:
		remove_inspector_plugin(_statechart_ext_inspector_plugin)
		_statechart_ext_inspector_plugin = null

	_transition_inspector_plugin = preload("uid://c2pho7wt7vtg4").new()
	add_inspector_plugin(_transition_inspector_plugin)

	_statechart_ext_inspector_plugin = preload("uid://b3tq0e06y60t3").new(self)
	add_inspector_plugin(_statechart_ext_inspector_plugin)

	DLogger.info("Inspector Plugins registered safely.", [], CAT)


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
			var full_path := path.path_join(file_name)
			if file_name.ends_with("." + StateChartExt.SCDEF_EXTENSION):
				_process_scdef_file(full_path)
			elif file_name.ends_with(".scxml"):
				_convert_scxml_to_scdef_if_needed(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()


# ------------- [Inner Classes] -------------
class ScExtFileSystemContextMenuPlugin:
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
			elif path.ends_with("." + StateChartExt.SCDEF_EXTENSION):
				scdef_paths.append(path)

		if not scxml_paths.is_empty():
			var icon := _plugin.get_editor_interface().get_base_control().get_theme_icon(
				"Object", "EditorIcons"
			)
			add_context_menu_item(
				"Convert SCXML to ." + StateChartExt.SCDEF_EXTENSION,
				_on_convert_clicked.bind(scxml_paths),
				icon
			)

		if not scdef_paths.is_empty():
			var icon := _plugin.get_editor_interface().get_base_control().get_theme_icon(
				"Script", "EditorIcons"
			)
			add_context_menu_item(
				"Regenerate GDScript", _on_regenerate_clicked.bind(scdef_paths), icon
			)

	func _on_convert_clicked(paths: PackedStringArray) -> void:
		for path in paths:
			_plugin.call("_on_scxml_convert_file_selected", path)

	func _on_regenerate_clicked(paths: PackedStringArray) -> void:
		for path in paths:
			_plugin.call("_process_scdef_file", path)
