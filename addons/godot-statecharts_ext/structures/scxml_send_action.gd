class_name SCXMLSendAction
extends SCXMLAction

# ------------- [Constants] -------------
class Key:
	const EVENT := "event"
	const PARAMS := "params"
	const NAME := "name"
	const EVAL_EXPR := "eval_expr"
	const EXPR := "expr"

# ------------- [Public Variable] -------------
var event: String
var params: Array


# ------------- [Public Method] -------------
func _init(data: Dictionary) -> void:
	super(StateChartExt.ACTION_TYPE_SEND)
	event = data.get(Key.EVENT, "")
	params = data.get(Key.PARAMS, [])


func execute(sc: StateChartExt) -> void:
	if params is Array:
		# パラメータリストを反復処理し、各パラメータの値を評価して割り当てる
		for p_data in params:
			if p_data is Dictionary:
				# パラメータ名と評価式を取得し、ステートチャートのプロパティを更新する
				var p_name: String = p_data.get(Key.NAME, "")
				var expr_str: String = p_data.get(Key.EVAL_EXPR, p_data.get(Key.EXPR, ""))
				if not p_name.is_empty():
					sc._evaluate_and_assign(p_name, expr_str)
	if not event.is_empty():
		sc._send_event_untyped(event)


func to_dict() -> Dictionary:
	var d := super()
	d[Key.EVENT] = event
	d[Key.PARAMS] = params
	return d
