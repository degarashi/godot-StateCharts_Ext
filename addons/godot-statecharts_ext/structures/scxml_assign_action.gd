class_name SCXMLAssignAction
extends SCXMLAction

# ------------- [Constants] -------------
class Key:
	const LOCATION := "location"
	const EXPR := "expr"

# ------------- [Public Variable] -------------
var location: String
var expr: String

# ------------- [Callbacks] -------------
func _init(data: Dictionary) -> void:
	super(StateChartConstants.ACTION_TYPE_ASSIGN)
	location = data.get(Key.LOCATION, "")
	expr = data.get(Key.EXPR, "")

# ------------- [Public Method] -------------
func execute(sc: StateChartExt) -> void:
	if not location.is_empty():
		sc._evaluate_and_assign(location, expr)


func to_dict() -> Dictionary:
	var d := super()
	d[Key.LOCATION] = location
	d[Key.EXPR] = expr
	return d
