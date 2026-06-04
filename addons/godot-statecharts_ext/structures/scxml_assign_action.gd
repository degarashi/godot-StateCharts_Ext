class_name SCXMLAssignAction
extends SCXMLAction

# ------------- [Constants] -------------
const KEY_LOCATION := "location"
const KEY_EXPR := "expr"

# ------------- [Public Variable] -------------
var location: String
var expr: String

# ------------- [Callbacks] -------------
func _init(data: Dictionary) -> void:
	super(StateChartExt.ACTION_TYPE_ASSIGN)
	location = data.get(KEY_LOCATION, "")
	expr = data.get(KEY_EXPR, "")

# ------------- [Public Method] -------------
func execute(sc: StateChartExt) -> void:
	if not location.is_empty():
		sc._evaluate_and_assign(location, expr)


func to_dict() -> Dictionary:
	var d := super()
	d[KEY_LOCATION] = location
	d[KEY_EXPR] = expr
	return d
