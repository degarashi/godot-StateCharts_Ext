class_name SCXMLSendAction
extends SCXMLAction

var event: String
var params: Array


func _init(data: Dictionary) -> void:
	super(StateChartExt.ACTION_TYPE_SEND)
	event = data.get("event", "")
	params = data.get("params", [])


func execute(sc: StateChartExt) -> void:
	if params is Array:
		for p_data in params:
			if p_data is Dictionary:
				var p_name: String = p_data.get("name", "")
				var expr_str: String = p_data.get("eval_expr", p_data.get("expr", ""))
				if not p_name.is_empty():
					sc._evaluate_and_assign(p_name, expr_str)
	if not event.is_empty():
		sc._send_event_untyped(event)


func to_dict() -> Dictionary:
	var d := super()
	d["event"] = event
	d["params"] = params
	return d
