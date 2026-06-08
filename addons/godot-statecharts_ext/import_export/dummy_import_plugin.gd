@tool
## Generic import plugin to make Godot recognize custom file extensions as dummy resources.
extends EditorImportPlugin

# ------------- [Private Variables] -------------
var _importer_name: String
var _visible_name: String
var _extensions: PackedStringArray
var _resource_type: String


# ------------- [Lifecycle Methods] -------------
func _init(
	p_importer_name: String,
	p_visible_name: String,
	p_extensions: PackedStringArray,
	p_resource_type: String = "Resource"
) -> void:
	_importer_name = p_importer_name
	_visible_name = p_visible_name
	_extensions = p_extensions
	_resource_type = p_resource_type


# ------------- [Public Method] -------------
func _get_importer_name() -> String:
	return _importer_name


func _get_visible_name() -> String:
	return _visible_name


func _get_recognized_extensions() -> PackedStringArray:
	return _extensions


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_preset_count() -> int:
	return 0


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _import(
	source_file: String,
	save_path: String,
	_options: Dictionary,
	_platform_variants: Array[String],
	_gen_files: Array[String]
) -> Error:
	var res := Resource.new()
	if _resource_type != "Resource":
		# Try to find the class in the global class list (GDScript class_name)
		var script_path := ""
		for gd_class in ProjectSettings.get_global_class_list():
			if gd_class["class"] == _resource_type:
				script_path = gd_class["path"]
				break

		if not script_path.is_empty():
			res.set_script(load(script_path))
		elif ClassDB.can_instantiate(_resource_type):
			# If it's a built-in type, we can't just set_script, so we replace res
			res = ClassDB.instantiate(_resource_type)

	if res.get_script() and "source_code" in res:
		res.source_code = FileAccess.get_file_as_string(source_file)

	return ResourceSaver.save(res, "%s.%s" % [save_path, _get_save_extension()])
