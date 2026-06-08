@tool
## Main entry point for the Godot StateCharts Extra plugin.
## Manages .scdef file monitoring, automatic code generation triggers,
## and registration of the various editor plugins.
extends EditorPlugin

# ------------- [Constants] -------------
const CAT = "ScExt_Gen"
const MENU_FORCE_REGENERATE := (
	"StateChartExt: Force Regenerate all ." + StateChartExt.SCDEF_EXTENSION
)
const MENU_EXPORT_SCXML := "StateChartExt: Export current StateChart as SCXML"
const MENU_IMPORT_SCXML := "StateChartExt: Import SCXML to current StateChart"
const MENU_CONVERT_SCXML := "StateChartExt: Convert SCXML to ." + StateChartExt.SCDEF_EXTENSION

const FileSystemContextMenuScript := preload(
	"res://addons/godot-statecharts_ext/editor/context_menu_filesystem.gd"
)
const SceneTreeContextMenuScript := preload(
	"res://addons/godot-statecharts_ext/editor/context_menu_scene_tree.gd"
)

# ------------- [Private Variables] -------------
var _fs_reloading := false
var _import_plugin: EditorImportPlugin
var _scxml_import_plugin: EditorImportPlugin
var _transition_inspector_plugin: EditorInspectorPlugin
var _statechart_ext_inspector_plugin: EditorInspectorPlugin
var _dummy_resource_inspector_plugin: EditorInspectorPlugin
var _context_menu_plugin: EditorContextMenuPlugin
var _scene_tree_context_menu_plugin: EditorContextMenuPlugin
var _editor_manager: StateChartEditorManager
var _fs_icon_manager: RefCounted  # (FileSystemIconManager)


# ------------- [Lifecycle Methods] -------------
func _enter_tree() -> void:
	DLogger.info("Plugin enabled.", [], CAT)

	_editor_manager = StateChartEditorManager.new(self)
	_init_settings()

	var FSIconManager := preload(
		"res://addons/godot-statecharts_ext/editor/file_system_icon_manager.gd"
	)
	_fs_icon_manager = FSIconManager.new(self)

	var DummyImportPlugin := preload("uid://b70108gychlte")
	_import_plugin = DummyImportPlugin.new(
		"statechart_ext_scdef",
		"StateChart Definition",
		[StateChartExt.SCDEF_EXTENSION],
		"StateChartDefinition"
	)
	add_import_plugin(_import_plugin)

	_scxml_import_plugin = DummyImportPlugin.new(
		"statechart_ext_scxml", "SCXML File", ["scxml"], "StateChartSCXML"
	)
	add_import_plugin(_scxml_import_plugin)

	# Wait for the editor to be fully ready before registration
	_register_inspectors_delayed()

	var fs := EditorInterface.get_resource_filesystem()
	fs.filesystem_changed.connect(_on_filesystem_changed)
	if fs.has_signal("sources_changed"):
		fs.sources_changed.connect(_on_sources_changed)

	add_tool_menu_item(MENU_FORCE_REGENERATE, _on_manual_scan_requested)
	add_tool_menu_item(MENU_EXPORT_SCXML, _on_export_scxml_requested)
	add_tool_menu_item(MENU_IMPORT_SCXML, _on_import_scxml_requested)
	add_tool_menu_item(MENU_CONVERT_SCXML, _on_convert_scxml_to_scdef_requested)

	_context_menu_plugin = FileSystemContextMenuScript.new(self)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _context_menu_plugin)

	_scene_tree_context_menu_plugin = SceneTreeContextMenuScript.new(self)
	add_context_menu_plugin(
		EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE, _scene_tree_context_menu_plugin
	)

	# Wait for the filesystem to be fully loaded before initial scan
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	if _fs_icon_manager:
		_fs_icon_manager.cleanup()
		_fs_icon_manager = null

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

	if _dummy_resource_inspector_plugin:
		remove_inspector_plugin(_dummy_resource_inspector_plugin)
		_dummy_resource_inspector_plugin = null

	if _context_menu_plugin:
		remove_context_menu_plugin(_context_menu_plugin)
		_context_menu_plugin = null

	if _scene_tree_context_menu_plugin:
		remove_context_menu_plugin(_scene_tree_context_menu_plugin)
		_scene_tree_context_menu_plugin = null

	remove_tool_menu_item(MENU_FORCE_REGENERATE)
	remove_tool_menu_item(MENU_EXPORT_SCXML)
	remove_tool_menu_item(MENU_IMPORT_SCXML)
	remove_tool_menu_item(MENU_CONVERT_SCXML)

	var fs := EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)
	if fs.has_signal("sources_changed") and fs.sources_changed.is_connected(_on_sources_changed):
		fs.sources_changed.disconnect(_on_sources_changed)

	_editor_manager = null


func _handles(object: Object) -> bool:
	return object is StateChartDefinition or object is StateChartSCXML


func _edit(object: Object) -> void:
	if object is Resource:
		DLogger.info("Editing resource via _edit: {0}", [object.resource_path], CAT)
		_open_in_external_editor(object.resource_path)


# ------------- [Callbacks] -------------
func _on_filesystem_changed() -> void:
	if _fs_reloading:
		return

	_fs_reloading = true
	_editor_manager.scan_dir_recursive("res://")
	await get_tree().create_timer(1.0).timeout
	_fs_reloading = false


func _on_sources_changed(_exist: bool) -> void:
	_on_filesystem_changed()


# ------------- [Private Methods] -------------
func _on_manual_scan_requested() -> void:
	_editor_manager.manual_scan()


func _init_settings() -> void:
	var es := EditorInterface.get_editor_settings()
	var setting_path := "state_charts_ext/scxml_editor_path"
	if not es.has_setting(setting_path):
		es.set_setting(setting_path, "")
		es.set_initial_value(setting_path, "", false)
		es.add_property_info(
			{
				"name": setting_path,
				"type": TYPE_STRING,
				"hint": PROPERTY_HINT_GLOBAL_FILE,
			}
		)


func _open_in_external_editor(path: String) -> void:
	var global_path := ProjectSettings.globalize_path(path)
	var es := EditorInterface.get_editor_settings()

	var editor_path: String = es.get_setting("state_charts_ext/scxml_editor_path")

	if not editor_path.is_empty():
		DLogger.info("Attempting to open {0} with custom editor: {1}", [global_path, editor_path], CAT)
		var pid := OS.create_process(editor_path, [global_path])
		if pid == -1:
			DLogger.error(
				"Failed to start process: {0}. Check if the path is correct and executable.",
				[editor_path],
				CAT
			)
		else:
			DLogger.info("Process started with PID: {0}", [pid], CAT)
			return

	# Fallback to system default
	DLogger.info("Opening {0} with system default.", [global_path], CAT)
	OS.shell_open(global_path)


func _on_export_scxml_requested() -> void:
	_editor_manager.request_export_scxml()


func _on_import_scxml_requested() -> void:
	_editor_manager.request_import_scxml()


func _on_convert_scxml_to_scdef_requested() -> void:
	_editor_manager.request_convert_scxml_to_scdef()


func _on_scxml_convert_file_selected(path: String) -> void:
	_editor_manager.on_scxml_convert_file_selected(path)


func _process_scdef_file(scdef_path: String) -> void:
	_editor_manager.process_scdef_file(scdef_path)


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

	if _dummy_resource_inspector_plugin:
		remove_inspector_plugin(_dummy_resource_inspector_plugin)
		_dummy_resource_inspector_plugin = null

	_transition_inspector_plugin = preload("uid://c2pho7wt7vtg4").new()
	add_inspector_plugin(_transition_inspector_plugin)

	_statechart_ext_inspector_plugin = preload("uid://b3tq0e06y60t3").new(self)
	add_inspector_plugin(_statechart_ext_inspector_plugin)

	var DummyResourceInspectorPlugin := preload(
		"res://addons/godot-statecharts_ext/inspector/dummy_resource_inspector_plugin.gd"
	)
	_dummy_resource_inspector_plugin = DummyResourceInspectorPlugin.new(self)
	add_inspector_plugin(_dummy_resource_inspector_plugin)

	DLogger.info("Inspector Plugins registered safely.", [], CAT)
