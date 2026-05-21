## [STAux]
## Auxiliary functions for StateChartExt
class_name STAux


# --------------------------------------------------
# [Private Method]
static func _st_proc_value(
	st: StateChartExt, param_ent: StateChartExt.ParamEnt, validator: Callable, proc: Callable
) -> void:
	var v = st.get_expression_property_ext(param_ent)
	if not validator.call(v):
		push_error("ERROR")
		return
	proc.call(v)
	# For notification functions
	st.set_expression_property_ext(param_ent, v)


# --- Checkers ---
static func _is_array(ar) -> bool:
	return ar is Array


static func _is_dict(ar) -> bool:
	return ar is Dictionary


# --- Checkers - END ---

# --------------------------------------------------
# [Static Method]


# --- Initialization ---
# [Dictionary]
static func st_init_dict(st: StateChartExt, param_ent: StateChartExt.ParamEnt) -> void:
	st.set_expression_property_ext(param_ent, {})


# [Array]
static func st_init_array(st: StateChartExt, param_ent: StateChartExt.ParamEnt) -> void:
	st.set_expression_property_ext(param_ent, [])


# --- Initialization - END ---


# --- Value Modification ---
# [Dictionary]
static func st_insert_dict(
	st: StateChartExt, param_ent: StateChartExt.ParamEnt, key, value
) -> void:
	_st_proc_value(st, param_ent, _is_dict, func(di: Dictionary) -> void: di[key] = value)


# [Array]
static func st_add_array(st: StateChartExt, param_ent: StateChartExt.ParamEnt, value) -> void:
	_st_proc_value(st, param_ent, _is_array, func(ar: Array) -> void: ar.append(value))


# [int]
static func st_add_value(
	st: StateChartExt, param_ent: StateChartExt.ParamEnt, value_to_add
) -> Array:
	var orig = st.get_expression_property_ext(param_ent)
	var after = orig + value_to_add
	st.set_expression_property_ext(param_ent, after)
	return [orig, after]


# --- Value Modification - END ---


## Bind multiple signals to StateChart events at once
## @param st The target StateChart
## @param conns A dictionary with signals as keys and EventEnt as values
static func bind_signals_to_events(
	st: StateChartExt, conns: Dictionary[Signal, StateChartExt.EventEnt]
) -> void:
	for sig in conns:
		sig.connect(dispatch_event.bind(st, conns[sig]))


## Dispatch an event to the StateChart
## @param st The target StateChart
## @param ev The event entry to dispatch
static func dispatch_event(st: StateChartExt, ev: StateChartExt.EventEnt) -> void:
	st.send_event_ext(ev)
