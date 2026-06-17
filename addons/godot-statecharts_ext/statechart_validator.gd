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
	_check_parallel_transitions(warnings, sc)
	_check_duplicate_state_names(warnings, sc)

	if not params_m.is_empty():
		_check_unused_params(warnings, sc, params_m)

	return warnings


static func _check_duplicate_state_names(err_msg: PackedStringArray, sc: StateChartExt) -> void:
	var state_names: Dictionary[String, int] = {}
	_collect_state_names(sc, state_names)
	
	var duplicates: Array[String] = []
	for name in state_names:
		if state_names[name] > 1:
			duplicates.append(name)
	
	if not duplicates.is_empty():
		err_msg.append("Duplicate state names detected (can cause ambiguity in In() guards or local params): " + ", ".join(duplicates))


static func _collect_state_names(node: Node, dst: Dictionary[String, int]) -> void:
	if node is StateChartState:
		var name := String(node.name)
		dst[name] = dst.get(name, 0) + 1
	
	for c in node.get_children():
		_collect_state_names(c, dst)


static func _check_unused_params(
	warnings: PackedStringArray, sc: StateChartExt, params: Dictionary[String, int]
) -> void:
	var used_params: Dictionary[String, bool] = {}
	_collect_used_params(sc, used_params)
	
	var unused: Array[String] = []
	for p_name in params:
		if not used_params.has(p_name):
			unused.append(p_name)
	
	if not unused.is_empty():
		warnings.append("unused parameter(s):\n" + ", ".join(unused))


static func _collect_used_params(node: Node, dst: Dictionary[String, bool]) -> void:
	for c in node.get_children():
		if c is Transition:
			_extract_params_from_guard(c.guard, dst)
		
		# Also check metadata for onentry/onexit actions
		for action_type: String in ["onentry", "onexit"]:
			var meta_key: String = "statechart_ext__" + action_type
			if c.has_meta(meta_key):
				var actions = c.get_meta(meta_key)
				if actions is Array:
					for action in actions:
						if action is Dictionary:
							if action.get("type") == "assign":
								var loc = action.get("location", "")
								if not loc.is_empty():
									dst[loc] = true
								_extract_params_from_expr(action.get("expr", ""), dst)
							elif action.get("type") == "send":
								for p in action.get("params", []):
									if p is Dictionary:
										var p_name = p.get("name", "")
										if not p_name.is_empty():
											dst[p_name] = true
										_extract_params_from_expr(p.get("expr", ""), dst)
		
		_collect_used_params(c, dst)


static func _extract_params_from_guard(g: Guard, dst: Dictionary[String, bool]) -> void:
	if g is ExpressionGuard:
		_extract_params_from_expr(g.expression, dst)
	elif g is NotGuard:
		_extract_params_from_guard(g.guard, dst)
	elif g is AllOfGuard or g is AnyOfGuard:
		for cg in g.guards:
			_extract_params_from_guard(cg, dst)


static func _extract_params_from_expr(expr_str: String, dst: Dictionary[String, bool]) -> void:
	if expr_str.is_empty():
		return
	# Basic regex to find identifiers. Might have some false positives with strings, 
	# but it's better than nothing for an "unused" check.
	var regex := RegEx.new()
	regex.compile("\\b[a-zA-Z_][a-zA-Z0-9_]*\\b")
	for m in regex.search_all(expr_str):
		var id := m.get_string()
		if id not in ["true", "false", "null", "In", "not", "and", "or"]:
			dst[id] = true


static func _check_parallel_transitions(err_msg: PackedStringArray, sc: StateChartExt) -> void:
	_check_parallel_transitions_internal(err_msg, sc, "")


static func _check_parallel_transitions_internal(
	err_msg: PackedStringArray, node: Node, path: String
) -> void:
	if node is ParallelState:
		for region in node.get_children():
			if not region is StateChartState:
				continue
			_check_illegal_exits(err_msg, region, node, region, path + StateChartConstants.PATH_SEPARATOR + region.name)

	for c in node.get_children():
		if not c is Transition:
			var child_path := path + StateChartConstants.PATH_SEPARATOR + c.name
			_check_parallel_transitions_internal(err_msg, c, child_path)


static func _check_illegal_exits(
	err_msg: PackedStringArray, current_node: Node, parallel_root: Node, region_root: Node, path: String
) -> void:
	for c in current_node.get_children():
		if c is Transition:
			if c.to.is_empty():
				continue
			var target := c.get_node_or_null(c.to)
			if target != null and parallel_root.is_ancestor_of(target):
				if not region_root.is_ancestor_of(target) and target != region_root:
					err_msg.append(
						(
							"Parallel state cross-transition detected at [{0}]: target '{1}' is in another region of parallel state '{2}'"
							. format([path + StateChartConstants.PATH_SEPARATOR + c.name, target.name, parallel_root.name])
						)
					)
		else:
			_check_illegal_exits(err_msg, c, parallel_root, region_root, path + StateChartConstants.PATH_SEPARATOR + c.name)


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
					(
						err_msg
						. append(
							(
								"Overlapping transitions (same event and guard) at [{0}]: event='{1}', guard='{2}', transitions=[{3}]"
								. format(
									[
										path if not path.is_empty() else "Root",
										ev,
										sig,
										", ".join(names)
									]
								)
							)
						)
					)

	for c in node.get_children():
		if not c is Transition:
			var child_path := path + StateChartConstants.PATH_SEPARATOR + c.name
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
	warnings: PackedStringArray,
	sc: StateChartExt,
	event: Dictionary[String, StateChartExt.EntBase],
	exclude_ev: PackedStringArray
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


static func _check_param(
	dst: PackedStringArray, sc: StateChartExt, param_def: Dictionary[String, int]
) -> void:
	_check_param_internal(dst, sc, sc, "", param_def)


static func _check_param_internal(
	dst: PackedStringArray,
	sc: StateChartExt,
	node: Node,
	path: String,
	param_def: Dictionary[String, int]
) -> void:
	for c in node.get_children():
		var child_path := path + StateChartConstants.PATH_SEPARATOR + c.name
		if c is Transition:
			var g_a := _find_expression_guard(dst, child_path, c.guard)
			for g in g_a:
				_check_expression(dst, sc, child_path, g.expression, param_def)
			_check_state_active_guard(dst, sc, child_path, c.guard, c)
		else:
			_check_param_internal(dst, sc, c, child_path, param_def)


static func _check_state_active_guard(
	dst: PackedStringArray, sc: StateChartExt, path: String, g: Guard, context_transition: Transition
) -> void:
	if g is StateIsActiveGuard:
		if g.state.is_empty():
			dst.append("StateIsActiveGuard has empty state path at [{0}]".format([path]))
		else:
			var target := context_transition.get_node_or_null(g.state)
			if target == null:
				dst.append(
					"StateIsActiveGuard target not found: '{1}' at [{0}]".format([path, g.state])
				)
			elif not target is StateChartState:
				dst.append(
					"StateIsActiveGuard target is not a state: '{1}' at [{0}]".format([path, g.state])
				)
	elif g is NotGuard:
		_check_state_active_guard(dst, sc, path, g.guard, context_transition)
	elif g is AllOfGuard or g is AnyOfGuard:
		for cg in g.guards:
			_check_state_active_guard(dst, sc, path, cg, context_transition)


static func _check_expression(
	dst: PackedStringArray,
	sc: StateChartExt,
	path: String,
	exp_str: String,
	param_def: Dictionary[String, int]
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
	err_msg: PackedStringArray,
	sc: StateChartExt,
	events: Dictionary[String, StateChartExt.EntBase],
	exclude_ev: PackedStringArray
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
		var child_path := path + StateChartConstants.PATH_SEPARATOR + c.name
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
