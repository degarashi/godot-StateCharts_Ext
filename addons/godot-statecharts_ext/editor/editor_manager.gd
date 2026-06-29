@tool
## Manager for editor-side operations like SCXML conversion and code generation.
class_name StateChartEditorManager
extends RefCounted

const CAT = "ScExt_Editor"

var _plugin: EditorPlugin
var _scxml_export_dialog: EditorFileDialog
var _scxml_import_dialog: EditorFileDialog
## Cache for .scdef file content hashes to avoid redundant processing [path] -> md5
var _scdef_hash_cache: Dictionary = {}


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func manual_scan() -> void:
	DLogger.info("Manual scan started...", [], CAT)
	_scdef_hash_cache.clear()
	EditorInterface.get_resource_filesystem().scan()
	scan_dir_recursive("res://")
	DLogger.info("Manual scan finished.", [], CAT)


func scan_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				scan_dir_recursive(path.path_join(file_name))
		else:
			var full_path := path.path_join(file_name)
			if file_name.ends_with("." + StateChartConstants.SCDEF_EXTENSION):
				process_scdef_file(full_path)
			elif file_name.ends_with(".scxml"):
				convert_scxml_to_scdef_if_needed(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()


func convert_scxml_to_scdef_if_needed(scxml_path: String) -> void:
	var scdef_path := scxml_path.get_basename() + "." + StateChartConstants.SCDEF_EXTENSION
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
			_create_scdef_import_files(scdef_path)
			process_scdef_file(scdef_path)


func process_scdef_file(scdef_path: String) -> void:
	var gd_path := scdef_path.get_basename() + "." + StateChartConstants.GD_EXTENSION

	var f_scdef := FileAccess.open(scdef_path, FileAccess.READ)
	if not f_scdef:
		return
	var content := f_scdef.get_as_text()
	f_scdef.close()

	# Skip if content hash hasn't changed
	var content_hash := content.md5_text()
	if _scdef_hash_cache.get(scdef_path) == content_hash:
		return
	_scdef_hash_cache[scdef_path] = content_hash

	var old_content := ""
	if FileAccess.file_exists(gd_path):
		var f_gd := FileAccess.open(gd_path, FileAccess.READ)
		if f_gd:
			old_content = f_gd.get_as_text()
			f_gd.close()

	var fallback_name := scdef_path.get_file().get_basename().to_pascal_case() + "SC"
	var result := StateChartGenerator.parse_and_generate(content, fallback_name)

	if not result.error.is_empty():
		var err_msg: String = "Syntax error in {0}:\n{1}".format([scdef_path, result.error])
		DLogger.error("{0}", [err_msg], CAT)
		if Engine.is_editor_hint():
			var dialog := AcceptDialog.new()
			dialog.title = "StateChartExt Compile Error"
			dialog.dialog_text = err_msg
			EditorInterface.get_base_control().add_child(dialog)
			dialog.popup_centered()
			# Automatically queue free when closed
			dialog.visibility_changed.connect(
				func():
					if not dialog.visible:
						dialog.queue_free()
			)
		return

	if result.code != old_content:
		var f_out := FileAccess.open(gd_path, FileAccess.WRITE)
		if f_out:
			f_out.store_string(result.code)
			f_out.close()
			DLogger.info("Generated StateChart code for {0}", [fallback_name], CAT)
			EditorInterface.get_resource_filesystem().update_file(gd_path)


func request_export_scxml() -> void:
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


func request_import_scxml() -> void:
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


func request_convert_scxml_to_scdef() -> void:
	if not _scxml_import_dialog:
		_scxml_import_dialog = EditorFileDialog.new()
		_scxml_import_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_scxml_import_dialog.add_filter("*.scxml", "SCXML files")
		_scxml_import_dialog.file_selected.connect(on_scxml_convert_file_selected)
		EditorInterface.get_base_control().add_child(_scxml_import_dialog)

	_scxml_import_dialog.popup_centered_ratio(0.5)


func on_scxml_convert_file_selected(path: String) -> void:
	var scdef_path := path.get_basename() + "." + StateChartConstants.SCDEF_EXTENSION
	var scdef_content := StateChartScxmlImporter.generate_scdef(path)

	if not scdef_content.is_empty():
		var f := FileAccess.open(scdef_path, FileAccess.WRITE)
		if f:
			f.store_string(scdef_content)
			f.close()
			DLogger.info("Generated .scdef: {0}", [scdef_path], CAT)
			_create_scdef_import_files(scdef_path)
			process_scdef_file(scdef_path)
			EditorInterface.select_file(scdef_path)


func _on_scxml_export_file_selected(path: String) -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExt:
		return

	var exporter := StateChartScxmlExporter.new()
	var err := exporter.export_and_save(selected_nodes[0], path)
	if err == OK:
		DLogger.info("SCXML exported to: {0}", [path], CAT)

		_create_scxml_import_files(path)
		call_deferred("_on_scxml_export_complete", path)


func _create_scxml_import_files(source_path: String) -> void:
	# .godot/imported ディレクトリを確保
	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive(".godot/imported")

	# キャッシュパスを計算 (Godot の EditorFileSystem._get_cache_path 相当)
	var file := source_path.get_file()
	var md5 := source_path.md5_text()
	var cache_path := "res://.godot/imported/%s-%s.res" % [file, md5]

	# .res を直接生成 (非同期インポートを待たずに開ける)
	var res := StateChartSCXML.new()
	var f := FileAccess.open(source_path, FileAccess.READ)
	if f:
		res.source_code = f.get_as_text()
		f.close()
	ResourceSaver.save(res, cache_path)

	# .import ファイルを生成
	var import_path := source_path + ".import"
	var content := "[remap]\n\n"
	content += "importer=\"statechart_ext_scxml\"\n"
	content += "type=\"Resource\"\n"
	content += "path=\"%s\"\n\n" % cache_path
	content += "[deps]\n\n"
	content += "source_file=\"%s\"\n" % source_path
	content += "dest_files=[\"%s\"]\n\n" % cache_path
	content += "[params]\n"
	var fi := FileAccess.open(import_path, FileAccess.WRITE)
	if fi:
		fi.store_string(content)
		fi.close()

	EditorInterface.get_resource_filesystem().update_file(source_path)


func _create_scdef_import_files(source_path: String) -> void:
	# .godot/imported ディレクトリを確保
	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive(".godot/imported")

	# キャッシュパスを計算
	var file := source_path.get_file()
	var md5 := source_path.md5_text()
	var cache_path := "res://.godot/imported/%s-%s.res" % [file, md5]

	# .res を直接生成 (非同期インポートを待たずに開ける)
	var res := StateChartDefinition.new()
	var f := FileAccess.open(source_path, FileAccess.READ)
	if f:
		res.source_code = f.get_as_text()
		f.close()
	ResourceSaver.save(res, cache_path)

	# .import ファイルを生成
	var import_path := source_path + ".import"
	var content := "[remap]\n\n"
	content += "importer=\"statechart_ext_scdef\"\n"
	content += "type=\"Resource\"\n"
	content += "path=\"%s\"\n\n" % cache_path
	content += "[deps]\n\n"
	content += "source_file=\"%s\"\n" % source_path
	content += "dest_files=[\"%s\"]\n\n" % cache_path
	content += "[params]\n"
	var fi := FileAccess.open(import_path, FileAccess.WRITE)
	if fi:
		fi.store_string(content)
		fi.close()

	EditorInterface.get_resource_filesystem().update_file(source_path)


# ファイルシステムのインポート完了後にファイルを選択する
func _on_scxml_export_complete(path: String) -> void:
	EditorInterface.select_file(path)


func import_scxml_to_node(scxml_path: String, target_node: Node) -> void:
	if not target_node is StateChartExt:
		DLogger.warn("Target node must be a StateChartExt.", [], CAT)
		return

	var scdef_path := scxml_path.get_basename() + "." + StateChartConstants.SCDEF_EXTENSION
	var scdef_content := StateChartScxmlImporter.generate_scdef(scxml_path)
	if not scdef_content.is_empty():
		var f_scdef := FileAccess.open(scdef_path, FileAccess.WRITE)
		if f_scdef:
			f_scdef.store_string(scdef_content)
			f_scdef.close()
			_create_scdef_import_files(scdef_path)
			process_scdef_file(scdef_path)

	var importer := StateChartScxmlImporter.new()
	var err := importer.import_scxml(scxml_path, target_node)
	if err == OK:
		var gd_path := scdef_path.get_basename() + "." + StateChartConstants.GD_EXTENSION
		var script := load(gd_path) as Script
		if script:
			target_node.set_script(script)


func _on_scxml_import_file_selected(path: String) -> void:
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	if selected_nodes.is_empty() or not selected_nodes[0] is StateChartExt:
		return
	import_scxml_to_node(path, selected_nodes[0])


func get_watch_files() -> PackedStringArray:
	var files := PackedStringArray()
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		_collect_files_recursive(fs.get_filesystem(), files)
	return files


func _collect_files_recursive(dir: EditorFileSystemDirectory, files: PackedStringArray) -> void:
	if not dir:
		return
	for i in range(dir.get_subdir_count()):
		_collect_files_recursive(dir.get_subdir(i), files)
	for i in range(dir.get_file_count()):
		var file_name := dir.get_file(i)
		if (
			file_name.ends_with("." + StateChartConstants.SCDEF_EXTENSION)
			or file_name.ends_with(".scxml")
		):
			files.append(dir.get_file_path(i))
