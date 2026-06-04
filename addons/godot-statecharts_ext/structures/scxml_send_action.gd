class_name SCXMLSendAction
extends SCXMLAction

# ------------- [Constants] -------------
const KEY_EVENT := "event"
const KEY_PARAMS := "params"
const KEY_NAME := "name"
const KEY_EVAL_EXPR := "eval_expr"
const KEY_EXPR := "expr"

# ------------- [Public Variable] -------------
var event: String
var params: Array


# ------------- [Public Method] -------------
func _init(data: Dictionary) -> void:
	super(StateChartExt.ACTION_TYPE_SEND)
	event = data.get(KEY_EVENT, "")
	params = data.get(KEY_PARAMS, [])


func execute(sc: StateChartExt) -> void:
	if params is Array:
		for p_data in params:
			if p_data is Dictionary:
				var p_name: String = p_data.get(KEY_NAME, "")
				var expr_str: String = p_data.get(KEY_EVAL_EXPR, p_data.get(KEY_EXPR, ""))
				if not p_name.is_empty():
					sc._evaluate_and_assign(p_name, expr_str)
	if not event.is_empty():
		sc._send_event_untyped(event)


func to_dict() -> Dictionary:
	var d := super()
	d[KEY_EVENT] = event
	d[KEY_PARAMS] = params
	return d
