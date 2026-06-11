class_name StateChartValidator
extends RefCounted

static func get_warnings(sc: StateChartExt) -> PackedStringArray:
	var warnings: PackedStringArray = []
	var sc_info := sc.get_sc_info()
	if sc_info == null:
		return warnings

	var params_m := StateChartExt.gather_params_id(sc_info.param)
	if not params_m.is_empty():
		_check_param(warnings, sc, params_m)

	var event := StateChartExt.init_and_get_entries(sc_info.event, StateChartExt.EventEnt)
	var invalid_ev: PackedStringArray = []
	var exclude_ev: PackedStringArray = []

	exclude_ev.append_array(sc.exclude_unused_event)
	exclude_ev.append_array(sc.exclude_warn_unknown_events)

	for ev_name in exclude_ev:
		if ev_name not in event:
			invalid_ev.append(ev_name)

	if not invalid_ev.is_empty():
		var err_str := "invalid event name (exclude):\n"
		err_str += ", ".join(invalid_ev)
		warnings.append(err_str)
	if not event.is_empty():
		_check_event_typo(warnings, sc, event, exclude_ev)
		_check_unused_events(warnings, sc, event, exclude_ev)

	_check_transition_overlap(warnings, sc)

	return warnings

static func _check_transition_overlap(err_msg: PackedStringArray, sc: StateChartExt) -> void:
	_check_transition_overlap_internal(err_msg, sc, "")

static func _check_transition_overlap_internal(
	err_msg: PackedStringArray, node: Node, path: String
) -> void:
	var transitions_by_event: Dictionary = {}  # event -> Array[Transition]

	for c in node.get_children():
		if c is Transition:
			var ev := StringName(c.event)
			if not transitions_by_event.has(ev):
				transitions_by_event[ev] = []
			transitions_by_event[ev].append(c)

	for ev in transitions_by_event:
		var trans_list: Array = transitions_by_event[ev]
		if trans_list.size() > 1:
			var signatures: Dictionary = {}  # sig -> Array[Transition]
			for t in trans_list:
				var sig := _get_guard_signature(t.guard)
				if not signatures.has(sig):
					signatures[sig] = []
				signatures[sig].append(t)

			for sig in signatures:
				var overlapping: Array = signatures[sig]
				if overlapping.size() > 1:
					var names: Array[String] = []
					for t in overlapping:
						names.append(t.name)
					err_msg.append(
						"Overlapping transitions (same event and guard) at [{0}]: event='{1}', guard='{2}', transitions=[{3}]"
						. format([path if not path.is_empty() else "Root", ev, sig, ", ".join(names)])
					)

	for c in node.get_children():
		if not c is Transition:
			var child_path := path + StateChartExt.PATH_SEPARATOR + c.name
			_check_transition_overlap_internal(err_msg, c, child_path)

static func _get_guard_signature(g: Guard) -> String:
	if g == null:
		return "<any>"
	if g is ExpressionGuard:
		return "expr:" + g.expression
	if g is StateIsActiveGuard:
		return "active:" + str(g.state)
	if g is NotGuard:
		return "not(" + _get_guard_signature(g.guard) + ")"
	if g is AllOfGuard:
		var parts: Array[String] = []
		for child in g.guards:
			parts.append(_get_guard_signature(child))
		parts.sort()
		return "all(" + ",".join(parts) + ")"
	if g is AnyOfGuard:
		var parts: Array[String] = []
		for child in g.guards:
			parts.append(_get_guard_signature(child))
		parts.sort()
		return "any(" + ",".join(parts) + ")"
	return str(g)

static func _check_unused_events(
	warnings: PackedStringArray, sc: StateChartExt, event: Dictionary[String, StateChartExt.EntBase], exclude_ev: PackedStringArray
) -> void:
	var using_event := _collect_using_event(sc)
	var unused_event := event.keys()
	for ev_name in using_event:
		unused_event.erase(ev_name)
	for ev_name in exclude_ev:
		unused_event.erase(ev_name)
	if unused_event.size() > 0:
		warnings.append("unused event(s):\n" + ", ".join(unused_event))

static func _collect_using_event(sc: StateChartExt) -> PackedStringArray:
	var using_set: Dictionary[String, bool] = {}
	_collect_using_event_internal(using_set, sc)
	var using_ev_str: PackedStringArray = []
	for event_name in using_set:
		using_ev_str.append(event_name)
	return using_ev_str

static func _collect_using_event_internal(dst: Dictionary[String, bool], node: Node) -> void:
	for c in node.get_children():
		if c is Transition and not c.event.is_empty():
			dst[c.event] = true
		else:
			_collect_using_event_internal(dst, c)

static func _check_param(dst: PackedStringArray, sc: StateChartExt, param_def: Dictionary[String, int]) -> void:
	_check_param_internal(dst, sc, sc, "", param_def)

static func _check_param_internal(
	dst: PackedStringArray, sc: StateChartExt, node: Node, path: String, param_def: Dictionary[String, int]
) -> void:
	for c in node.get_children():
		var child_path := path + StateChartExt.PATH_SEPARATOR + c.name
		if c is Transition:
			var g_a := _find_expression_guard(dst, child_path, c.guard)
			for g in g_a:
				_check_expression(dst, sc, child_path, g.expression, param_def)
		else:
			_check_param_internal(dst, sc, c, child_path, param_def)

static func _check_expression(
	dst: PackedStringArray, sc: StateChartExt, path: String, exp_str: String, param_def: Dictionary[String, int]
) -> void:
	var params: PackedStringArray = []
	for k in param_def.keys():
		params.append(k)

	var expr := Expression.new()
	if expr.parse(exp_str, params) != OK:
		dst.append("Expression parse error: {1}\n at [{0}]".format([path, expr.get_error_text()]))
		return

	var inputs: Array = []
	for k in param_def.keys():
		inputs.append(sc._make_zero(param_def[k]))

	expr.execute(inputs, sc)
	if expr.has_execute_failed():
		dst.append(
			"Expression execution error: {1}\n at [{0}]".format([path, expr.get_error_text()])
		)

static func _check_event_typo(
	err_msg: PackedStringArray, sc: StateChartExt, events: Dictionary[String, StateChartExt.EntBase], exclude_ev: PackedStringArray
) -> void:
	_check_event_typo_internal(err_msg, sc, sc, "", events, exclude_ev)

static func _check_event_typo_internal(
	err_msg: PackedStringArray,
	sc: StateChartExt,
	node: Node,
	path: String,
	events: Dictionary[String, StateChartExt.EntBase],
	exclude_ev: PackedStringArray
) -> void:
	for c in node.get_children():
		var child_path := path + StateChartExt.PATH_SEPARATOR + c.name
		if c is Transition:
			if not c.event.is_empty() and c.event not in events and c.event not in exclude_ev:
				err_msg.append("Unknown event: {1}\n at [{0}]".format([child_path, c.event]))
		else:
			_check_event_typo_internal(err_msg, sc, c, child_path, events, exclude_ev)

static func _find_expression_guard(
	warnings: PackedStringArray, path: String, g: Guard
) -> Array[ExpressionGuard]:
	if g is ExpressionGuard:
		return [g]
	if g is NotGuard:
		return _find_expression_guard(warnings, path, g.guard)
	if g is AllOfGuard or g is AnyOfGuard:
		if g.guards.is_empty():
			warnings.append("no guards inside\nat:{0}".format([path]))
		else:
			var ret: Array[ExpressionGuard] = []
			for gc in g.guards:
				ret.append_array(_find_expression_guard(warnings, path, gc))
			return ret
	return []
