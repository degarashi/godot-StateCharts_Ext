class_name SCXMLAction
extends RefCounted

var type: String


func _init(p_type: String) -> void:
	type = p_type


func execute(_sc: StateChartExt) -> void:
	pass


func to_dict() -> Dictionary:
	return {"type": type}
