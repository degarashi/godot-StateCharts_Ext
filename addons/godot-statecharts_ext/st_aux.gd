## Utility functions to assist with StateChartExt operations.
## Provides type-safe parameter manipulation and signal-to-event binding features.
class_name STAux


# ------------- [Private Static Method] -------------
static func _st_proc_value(
	st: StateChartExt, param_ent: StateChartExt.ParamEnt, validator: Callable, proc: Callable
) -> void:
	var v: Variant = st.get_expression_property_ext(param_ent)
	if not validator.call(v):
		DLogger.error("Value validation failed for parameter: {0}", [param_ent.name], "st_aux")
		return
	proc.call(v)
	st.set_expression_property_ext(param_ent, v)


static func _is_array(ar: Variant) -> bool:
	return ar is Array


static func _is_dict(ar: Variant) -> bool:
	return ar is Dictionary


# ------------- [Public Method] -------------
## Initializes a dictionary-type parameter with an empty dictionary.
static func st_init_dict(st: StateChartExt, param_ent: StateChartExt.ParamEnt) -> void:
	st.set_expression_property_ext(param_ent, {})


## Initializes an array-type parameter with an empty array.
static func st_init_array(st: StateChartExt, param_ent: StateChartExt.ParamEnt) -> void:
	st.set_expression_property_ext(param_ent, [])


## Adds or updates a key and value in a dictionary-type parameter.
static func st_insert_dict(
	st: StateChartExt, param_ent: StateChartExt.ParamEnt, key: Variant, value: Variant
) -> void:
	_st_proc_value(st, param_ent, _is_dict, func(di: Dictionary) -> void: di[key] = value)


## Adds a value to an array-type parameter.
static func st_add_array(
	st: StateChartExt, param_ent: StateChartExt.ParamEnt, value: Variant
) -> void:
	_st_proc_value(st, param_ent, _is_array, func(ar: Array) -> void: ar.append(value))


## Adds a value to a parameter and returns an array of [previous_value, new_value].
static func st_add_value(
	st: StateChartExt, param_ent: StateChartExt.ParamEnt, value_to_add: Variant
) -> Array:
	var orig: Variant = st.get_expression_property_ext(param_ent)
	var after: Variant = orig + value_to_add
	st.set_expression_property_ext(param_ent, after)
	return [orig, after]


## Binds multiple signals to StateChart events at once.
## @param conns A dictionary in the format { Signal: EventEnt }.
static func bind_signals_to_events(
	st: StateChartExt, conns: Dictionary[Signal, StateChartExt.EventEnt]
) -> void:
	for sig in conns:
		if not sig.is_connected(dispatch_event):
			sig.connect(dispatch_event.bind(st, conns[sig]))


## Sends an event to the StateChart (for binding to signals).
static func dispatch_event(st: StateChartExt, ev: StateChartExt.EventEnt) -> void:
	st.send_event_ext(ev)


## Returns all current expression properties as a dictionary.
## Useful for saving game state or debugging.
static func st_get_all_params_as_dict(st: StateChartExt) -> Dictionary:
	return st._expression_properties.duplicate()


## Splits a command-line string into arguments, respecting quotes and escaped characters.
static func split_args(flags: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var current := ""
	var quote_char := ""  # Empty, ' or "
	var escaped := false

	for i in range(flags.length()):
		var c := flags[i]
		if escaped:
			current += c
			escaped = false
		elif c == "\\":
			escaped = true
		elif quote_char != "":
			if c == quote_char:
				quote_char = ""
			else:
				current += c
		elif c == "\"" or c == "'":
			quote_char = c
		elif c == " ":
			if not current.is_empty():
				result.append(current)
				current = ""
		else:
			current += c

	if not current.is_empty():
		result.append(current)

	return result
