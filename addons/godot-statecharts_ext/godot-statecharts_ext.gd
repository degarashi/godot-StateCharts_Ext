@tool
extends EditorPlugin

const CAT = "ScExt_Gen"
var _fs_reloading := false


func _enter_tree() -> void:
	DLogger.info("Plugin enabled.", [], CAT)
	var fs := EditorInterface.get_resource_filesystem()
	fs.filesystem_changed.connect(_on_filesystem_changed)
	if fs.has_signal("sources_changed"):
		fs.sources_changed.connect(_on_sources_changed)

	add_tool_menu_item("StateChartExt: Force Regenerate all .scdef", _manual_scan)

	# Initial scan after a delay to ensure the filesystem is fully loaded
	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(_on_filesystem_changed)


func _on_sources_changed(_exist: bool) -> void:
	_on_filesystem_changed()


func _manual_scan() -> void:
	DLogger.info("Manual scan started...", [], CAT)
	EditorInterface.get_resource_filesystem().scan()
	_scan_and_generate()
	DLogger.info("Manual scan finished.", [], CAT)


func _on_filesystem_changed() -> void:
	if _fs_reloading:
		return

	_fs_reloading = true
	_scan_and_generate()
	await get_tree().create_timer(1.0).timeout
	_fs_reloading = false


func _scan_and_generate() -> void:
	_scan_dir_recursive("res://")


func _scan_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		DLogger.error("Could not open directory: {0}", [path], CAT)
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
			DLogger.error("Could not open gd for writing: {0}", [gd_path], CAT)
