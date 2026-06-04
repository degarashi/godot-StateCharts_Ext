class_name SCXMLAssignAction
extends SCXMLAction

var location: String
var expr: String


func _init(data: Dictionary) -> void:
	super(StateChartExt.ACTION_TYPE_ASSIGN)
	location = data.get("location", "")
	expr = data.get("expr", "")


func execute(sc: StateChartExt) -> void:
	if not location.is_empty():
		sc._evaluate_and_assign(location, expr)


func to_dict() -> Dictionary:
	var d := super()
	d["location"] = location
	d["expr"] = expr
	return d
