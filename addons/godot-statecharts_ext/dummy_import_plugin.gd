@tool
## Generic import plugin to make Godot recognize custom file extensions as dummy resources.
extends EditorImportPlugin

# ------------- [Private Variables] -------------
var _importer_name: String
var _visible_name: String
var _extensions: PackedStringArray


# ------------- [Lifecycle Methods] -------------
func _init(
	p_importer_name: String, p_visible_name: String, p_extensions: PackedStringArray
) -> void:
	_importer_name = p_importer_name
	_visible_name = p_visible_name
	_extensions = p_extensions


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
	_source_file: String,
	save_path: String,
	_options: Dictionary,
	_platform_variants: Array[String],
	_gen_files: Array[String]
) -> Error:
	var res := Resource.new()
	return ResourceSaver.save(res, "%s.%s" % [save_path, _get_save_extension()])
