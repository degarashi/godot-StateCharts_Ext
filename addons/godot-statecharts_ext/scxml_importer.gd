## SCXML Importer for StateCharts
## Imports a minimal SCXML structure into a StateChartExt node.
class_name StateChartScxmlImporter
extends RefCounted

const EXT_NAMESPACE_PREFIX := "statechart_ext"
const NAME_ATTR_NAME := "%s:name" % EXT_NAMESPACE_PREFIX
const GUARD_JSON_ATTR_NAME := "%s:guard_json" % EXT_NAMESPACE_PREFIX

const ExpressionGuardScript := preload("res://addons/godot_state_charts/expression_guard.gd")
const StateIsActiveGuardScript := preload(
	"res://addons/godot_state_charts/state_is_active_guard.gd"
)
const NotGuardScript := preload("res://addons/godot_state_charts/not_guard.gd")
const AllOfGuardScript := preload("res://addons/godot_state_charts/all_of_guard.gd")
const AnyOfGuardScript := preload("res://addons/godot_state_charts/any_of_guard.gd")


class ParsedTransition:
	var name: String
	var event: StringName
	var target_id: StringName
	var delay_in_seconds: String
	var guard_ast: Dictionary
	var metadata: Dictionary

	func _init(
		name_a: String = "Transition",
		event_a: StringName = &"",
		target_id_a: StringName = &"",
		delay_in_seconds_a: String = "0.0",
		guard_ast_a: Dictionary = {},
		metadata_a: Dictionary = {}
	) -> void:
		name = name_a
		event = event_a
		target_id = target_id_a
		delay_in_seconds = delay_in_seconds_a
		guard_ast = guard_ast_a
		metadata = metadata_a


class ParsedState:
	var id: StringName
	var kind: StringName
	var initial_id: StringName
	var children: Array[ParsedState] = []
	var transitions: Array[ParsedTransition] = []
	var metadata: Dictionary

	func _init(
		id_a: StringName = &"",
		kind_a: StringName = &"state",
		initial_id_a: StringName = &"",
		metadata_a: Dictionary = {}
	) -> void:
		id = id_a
		kind = kind_a
		initial_id = initial_id_a
		metadata = metadata_a


const HistoryStateScript := preload("res://addons/godot_state_charts/history_state.gd")


class PendingTransition:
	var node: Node  # Can be Transition or HistoryState
	var target_id: StringName
	var guard_ast: Dictionary
	var is_history_default := false

	func _init(
		node_a: Node, target_id_a: StringName, guard_ast_a: Dictionary = {}, is_hist: bool = false
	) -> void:
		node = node_a
		target_id = target_id_a
		guard_ast = guard_ast_a
		is_history_default = is_hist


func _set_owner(node: Node, owner_node: Node) -> void:
	if owner_node:
		node.owner = owner_node


## Imports an SCXML file into the given root node
func import_scxml(path: String, root_node: Node) -> Error:
	if not root_node is StateChartExt:
		push_error("Import target must be a StateChartExt")
		return ERR_INVALID_PARAMETER

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ERR_CANT_OPEN

	var xml := XMLParser.new()
	var parse_err := xml.open_buffer(file.get_buffer(file.get_length()))
	if parse_err != OK:
		return parse_err

	var saved_connections := _save_connections(root_node)
	_clear_existing_statechart_nodes(root_node)

	var scxml_initial := StringName()
	var scxml_name := &"Root"
	var parsed_root_states: Array[ParsedState] = []
	var initial_properties: Dictionary = {}

	while xml.read() == OK:
		if xml.get_node_type() != XMLParser.NODE_ELEMENT:
			continue

		var node_name := xml.get_node_name()
		if node_name == "scxml":
			scxml_initial = StringName(xml.get_named_attribute_value_safe("initial"))
			var scxml_name_attr := xml.get_named_attribute_value_safe("name")
			if not scxml_name_attr.is_empty():
				scxml_name = StringName(scxml_name_attr)

			# Store root attributes as metadata
			for i in range(xml.get_attribute_count()):
				var attr_name := xml.get_attribute_name(i)
				if attr_name != "initial" and attr_name != "name" and attr_name != "version":
					root_node.set_meta(_sanitize_meta_key(attr_name), xml.get_attribute_value(i))

		elif node_name == "datamodel":
			_parse_datamodel(xml, initial_properties)
		elif node_name == "state" or node_name == "parallel" or node_name == "history":
			parsed_root_states.append(_parse_state_element(xml, node_name))

	root_node.initial_expression_properties = initial_properties

	if parsed_root_states.is_empty():
		return OK

	var state_by_id: Dictionary[StringName, StateChartState] = {}
	var pending_transitions: Array[PendingTransition] = []

	if parsed_root_states.size() == 1:
		_instantiate_state_tree(parsed_root_states[0], root_node, state_by_id, pending_transitions)
	else:
		var synthetic_root := ParsedState.new(scxml_name, &"state", scxml_initial)
		synthetic_root.children = parsed_root_states
		_instantiate_state_tree(synthetic_root, root_node, state_by_id, pending_transitions)

	_resolve_pending_transitions(pending_transitions, state_by_id)
	_restore_connections(root_node, saved_connections)
	return OK


func _clear_existing_statechart_nodes(root_node: Node) -> void:
	for child in root_node.get_children():
		if child is StateChartState or child is Transition:
			root_node.remove_child(child)
			child.queue_free()


func _parse_datamodel(xml: XMLParser, properties: Dictionary) -> void:
	if xml.is_empty():
		return

	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				if xml.get_node_name() == "data":
					var id := xml.get_named_attribute_value_safe("id")
					var expr := xml.get_named_attribute_value_safe("expr")
					if not id.is_empty():
						properties[id] = _parse_value(expr)
			XMLParser.NODE_ELEMENT_END:
				if xml.get_node_name() == "datamodel":
					return


func _parse_value(expr: String) -> Variant:
	expr = expr.strip_edges()
	if expr.is_empty():
		return null

	# Handle strings in quotes
	if (
		(expr.begins_with("'") and expr.ends_with("'"))
		or (expr.begins_with('"') and expr.ends_with('"'))
	):
		return expr.substr(1, expr.length() - 2)

	# Handle boolean
	if expr.to_lower() == "true":
		return true
	if expr.to_lower() == "false":
		return false

	# Handle numbers
	if expr.is_valid_float():
		return expr.to_float()

	return expr


func _parse_state_element(xml: XMLParser, element_name: String) -> ParsedState:
	var state_id := xml.get_named_attribute_value_safe("id")
	if state_id.is_empty():
		state_id = xml.get_named_attribute_value_safe("name")
	if state_id.is_empty():
		state_id = "State"

	var parsed := ParsedState.new(
		StringName(state_id),
		StringName(element_name),
		StringName(xml.get_named_attribute_value_safe("initial"))
	)

	# Store state attributes as metadata (excluding standard ones)
	for i in range(xml.get_attribute_count()):
		var attr_name := xml.get_attribute_name(i)
		if attr_name != "id" and attr_name != "name" and attr_name != "initial":
			parsed.metadata[_sanitize_meta_key("attr:" + attr_name)] = xml.get_attribute_value(i)

	if xml.is_empty():
		return parsed

	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name := xml.get_node_name()
				if node_name == "state" or node_name == "parallel" or node_name == "history":
					parsed.children.append(_parse_state_element(xml, node_name))
				elif node_name == "transition":
					var trans_meta := {}
					for i in range(xml.get_attribute_count()):
						var attr_name := xml.get_attribute_name(i)
						if not (
							attr_name
							in [
								"event",
								"target",
								"cond",
								"type",
								NAME_ATTR_NAME,
								GUARD_JSON_ATTR_NAME
							]
						):
							trans_meta[_sanitize_meta_key("attr:" + attr_name)] = (
								xml.get_attribute_value(i)
							)

					var event_attr := xml.get_named_attribute_value_safe("event")
					var events := event_attr.split(" ", false)
					if events.is_empty():
						events = [""]

					var trans_target := _parse_transition_target(
						xml.get_named_attribute_value_safe("target")
					)
					var trans_name_attr := xml.get_named_attribute_value_safe(NAME_ATTR_NAME)
					var trans_delay := "0.0"
					var trans_guard := _parse_transition_guard_ast(xml)

					if not xml.is_empty():
						while xml.read() == OK:
							match xml.get_node_type():
								XMLParser.NODE_ELEMENT:
									var t_node_name := xml.get_node_name()
									if t_node_name.contains(":"):
										trans_meta[_sanitize_meta_key("tag:" + t_node_name)] = (_extract_element_metadata(
											xml
										))
								XMLParser.NODE_ELEMENT_END:
									if xml.get_node_name() == "transition":
										break

					for e in events:
						var final_event := e
						var final_delay := trans_delay

						if e.contains("@"):
							var parts := e.split("@")
							final_event = parts[0]
							# If trans_delay is default, use the one from the event name
							if final_delay == "0.0" or final_delay == "":
								final_delay = parts[1]

						var trans_name := trans_name_attr
						if trans_name.is_empty():
							trans_name = _generate_transition_name(
								final_event, xml.get_named_attribute_value_safe("target")
							)
						elif events.size() > 1:
							trans_name += (
								"_" + (final_event if not final_event.is_empty() else "Auto")
							)

						parsed.transitions.append(
							ParsedTransition.new(
								trans_name,
								StringName(final_event),
								trans_target,
								final_delay,
								trans_guard,
								trans_meta
							)
						)

				elif node_name.contains(":"):
					# Likely foreign metadata (e.g. qt:editorinfo)
					parsed.metadata[_sanitize_meta_key("tag:" + node_name)] = _extract_element_metadata(
						xml
					)

			XMLParser.NODE_ELEMENT_END:
				if xml.get_node_name() == element_name:
					return parsed

	return parsed


func _sanitize_meta_key(key: String) -> String:
	return key.replace(":", "__")


func _extract_element_metadata(xml: XMLParser) -> Dictionary:
	var meta := {}
	for i in range(xml.get_attribute_count()):
		meta[xml.get_attribute_name(i)] = xml.get_attribute_value(i)
	return meta


func _generate_transition_name(event: String, target: String) -> String:
	if not event.is_empty() and not target.is_empty():
		return event.to_pascal_case() + "To" + target.to_pascal_case()
	if not event.is_empty():
		return event.to_pascal_case()
	if not target.is_empty():
		return "To" + target.to_pascal_case()

	return "Transition"


func _parse_transition_target(target_attr: String) -> StringName:
	var target_ids := target_attr.split(" ", false)
	if target_ids.is_empty():
		return &""
	if target_ids.size() > 1:
		push_warning(
			"Multiple SCXML transition targets are not supported yet. Using the first target."
		)
	return StringName(target_ids[0])


func _parse_transition_guard_ast(xml: XMLParser) -> Dictionary:
	var guard_json := xml.get_named_attribute_value_safe(GUARD_JSON_ATTR_NAME)
	if not guard_json.is_empty():
		var parsed_json := JSON.parse_string(guard_json)
		if parsed_json is Dictionary:
			return parsed_json
		push_warning("Invalid SCXML guard JSON encountered. Ignoring custom guard data.")

	var cond := xml.get_named_attribute_value_safe("cond")
	if not cond.is_empty():
		return _cond_to_ast(cond)
	return {}


func _cond_to_ast(cond: String) -> Dictionary:
	cond = cond.strip_edges()
	if cond.is_empty():
		return {}

	# Handle top-level AND
	var parts_and := _split_top_level(cond, " && ")
	if parts_and.size() > 1:
		var guards: Array = []
		for p in parts_and:
			var ast := _cond_to_ast(_unwrap_parens(p))
			if not ast.is_empty():
				guards.append(ast)
		return {"type": "all_of", "guards": guards}

	# Handle top-level OR
	var parts_or := _split_top_level(cond, " || ")
	if parts_or.size() > 1:
		var guards: Array = []
		for p in parts_or:
			var ast := _cond_to_ast(_unwrap_parens(p))
			if not ast.is_empty():
				guards.append(ast)
		return {"type": "any_of", "guards": guards}

	# Handle NOT
	if cond.begins_with("!") and cond.ends_with(")"):
		var first_paren := cond.find("(")
		if first_paren == 1:
			var inner := cond.substr(first_paren + 1, cond.length() - first_paren - 2)
			if _is_balanced(inner):
				return {"type": "not", "guard": _cond_to_ast(inner)}

	# Handle In('...')
	if cond.begins_with("In('") and cond.ends_with("')"):
		var state_id := cond.substr(4, cond.length() - 6)
		return {"type": "state_is_active", "state": state_id}

	# Handle unwrapping parens (A) -> A
	if cond.begins_with("(") and cond.ends_with(")"):
		var unwrapped := _unwrap_parens(cond)
		if unwrapped != cond:
			return _cond_to_ast(unwrapped)

	# Default to expression
	return {"type": "expression", "expression": cond}


func _is_balanced(s: String) -> bool:
	var depth := 0
	for c in s:
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth < 0:
				return false
	return depth == 0


func _unwrap_parens(s: String) -> String:
	s = s.strip_edges()
	if s.length() >= 2 and s.begins_with("(") and s.ends_with(")"):
		var inner := s.substr(1, s.length() - 2)
		if _is_balanced(inner):
			return inner
	return s


func _split_top_level(s: String, op: String) -> Array[String]:
	var parts: Array[String] = []
	var depth := 0
	var last_start := 0
	var i := 0
	while i <= s.length() - op.length():
		if s[i] == "(":
			depth += 1
		elif s[i] == ")":
			depth -= 1
		elif depth == 0 and s.substr(i, op.length()) == op:
			parts.append(s.substr(last_start, i - last_start).strip_edges())
			i += op.length()
			last_start = i
			continue
		i += 1
	parts.append(s.substr(last_start).strip_edges())
	return parts


func _instantiate_state_tree(
	parsed: ParsedState,
	parent: Node,
	state_by_id: Dictionary[StringName, StateChartState],
	pending_transitions: Array[PendingTransition]
) -> StateChartState:
	var state_node := _create_state_node(parsed)
	parent.add_child(state_node)
	_set_owner(state_node, parent.owner if parent.owner else parent)

	if parsed.id in state_by_id:
		push_warning(
			"Duplicate SCXML state id '%s'. Transition resolution may be ambiguous." % parsed.id
		)
	state_by_id[parsed.id] = state_node

	# Apply metadata to state node
	for key in parsed.metadata:
		state_node.set_meta(key, parsed.metadata[key])

	if state_node is HistoryStateScript:
		var h_state := state_node as HistoryState
		var type_meta = parsed.metadata.get(_sanitize_meta_key("attr:type"), "shallow")
		h_state.deep = (type_meta == "deep")

	for child_parsed in parsed.children:
		_instantiate_state_tree(child_parsed, state_node, state_by_id, pending_transitions)

	for parsed_transition in parsed.transitions:
		if state_node is HistoryStateScript:
			# Transitions in history are default targets
			pending_transitions.append(
				PendingTransition.new(state_node, parsed_transition.target_id, {}, true)
			)
			continue

		var transition := Transition.new()
		transition.name = parsed_transition.name
		transition.event = parsed_transition.event
		transition.delay_in_seconds = parsed_transition.delay_in_seconds

		# Apply metadata to transition node
		for key in parsed_transition.metadata:
			transition.set_meta(key, parsed_transition.metadata[key])

		state_node.add_child(transition)
		_set_owner(transition, state_node.owner if state_node.owner else state_node)
		pending_transitions.append(
			PendingTransition.new(
				transition, parsed_transition.target_id, parsed_transition.guard_ast
			)
		)

	if state_node is CompoundState:
		_assign_initial_state(state_node as CompoundState, parsed)

	return state_node


func _create_state_node(parsed: ParsedState) -> StateChartState:
	var state_node: StateChartState
	if parsed.kind == &"parallel":
		state_node = ParallelState.new()
	elif parsed.kind == &"history":
		state_node = HistoryStateScript.new()
	elif parsed.children.is_empty():
		state_node = AtomicState.new()
	else:
		state_node = CompoundState.new()
	state_node.name = String(parsed.id)
	return state_node


func _assign_initial_state(state_node: CompoundState, parsed: ParsedState) -> void:
	var child_states: Array[StateChartState] = []
	for child in state_node.get_children():
		if child is StateChartState:
			child_states.append(child)

	if child_states.is_empty():
		return

	var initial_target: StateChartState = null
	if not parsed.initial_id.is_empty():
		for child_state in child_states:
			if child_state.name == String(parsed.initial_id):
				initial_target = child_state
				break
		if initial_target == null:
			push_warning(
				(
					"Initial state '%s' was not found under '%s'. Falling back to the first child."
					% [parsed.initial_id, parsed.id]
				)
			)

	if initial_target == null:
		initial_target = child_states[0]

	state_node.initial_state = state_node.get_path_to(initial_target)


func _resolve_pending_transitions(
	pending_transitions: Array[PendingTransition],
	state_by_id: Dictionary[StringName, StateChartState]
) -> void:
	for pending in pending_transitions:
		var target_state := state_by_id.get(pending.target_id) as StateChartState
		if not pending.target_id.is_empty() and target_state == null:
			push_warning(
				"Transition target '%s' was not found in imported SCXML." % pending.target_id
			)
			continue

		if pending.is_history_default:
			if target_state != null:
				(pending.node as HistoryState).default_state = pending.node.get_path_to(
					target_state
				)
			continue

		if target_state != null:
			pending.node.to = pending.node.get_path_to(target_state)
		pending.node.guard = _guard_from_ast(pending.guard_ast, pending.node, state_by_id)


func _guard_from_ast(
	ast: Dictionary, context_transition: Transition, state_by_id: Dictionary
) -> Guard:
	if ast.is_empty():
		return null

	match String(ast.get("type", "")):
		"expression":
			var guard := ExpressionGuardScript.new()
			guard.expression = String(ast.get("expression", ""))
			return guard
		"state_is_active":
			var guard := StateIsActiveGuardScript.new()
			var state_id := String(ast.get("state", ""))
			var target_state := state_by_id.get(StringName(state_id)) as StateChartState
			if target_state:
				guard.state = context_transition.get_path_to(target_state)
			else:
				guard.state = NodePath(state_id)
			return guard
		"not":
			var guard := NotGuardScript.new()
			guard.guard = _guard_from_ast(ast.get("guard", {}), context_transition, state_by_id)
			return guard
		"all_of":
			var guard := AllOfGuardScript.new()
			guard.guards = _guards_from_ast_array(
				ast.get("guards", []), context_transition, state_by_id
			)
			return guard
		"any_of":
			var guard := AnyOfGuardScript.new()
			guard.guards = _guards_from_ast_array(
				ast.get("guards", []), context_transition, state_by_id
			)
			return guard

	push_warning(
		"Unsupported SCXML guard type '%s'. Guard was ignored." % String(ast.get("type", ""))
	)
	return null


func _guards_from_ast_array(
	items: Array, context_transition: Transition, state_by_id: Dictionary
) -> Array[Guard]:
	var guards: Array[Guard] = []
	for item in items:
		if item is Dictionary:
			var guard := _guard_from_ast(item, context_transition, state_by_id)
			if guard != null:
				guards.append(guard)
	return guards


func _save_connections(root_node: Node) -> Array:
	var saved: Array = []
	for child in root_node.get_children():
		if child is StateChartState or child is Transition:
			_collect_connections_recursive(child, root_node, saved)
	return saved


func _collect_connections_recursive(node: Node, root_node: Node, saved: Array) -> void:
	var rel_path := root_node.get_path_to(node)
	for sig_info in node.get_signal_list():
		var sig_name: String = sig_info["name"]
		var sig := Signal(node, sig_name)
		for conn in sig.get_connections():
			saved.append(
				{
					"source_path": rel_path,
					"signal_name": sig_name,
					"callable": conn["callable"],
					"flags": conn["flags"]
				}
			)

	for child in node.get_children():
		_collect_connections_recursive(child, root_node, saved)


func _restore_connections(root_node: Node, saved: Array) -> void:
	for data in saved:
		var source := root_node.get_node_or_null(data["source_path"])
		if not source:
			continue

		if not source.has_signal(data["signal_name"]):
			continue

		var sig := Signal(source, data["signal_name"])
		var callable: Callable = data["callable"]

		if not callable.is_valid():
			continue

		if not sig.is_connected(callable):
			sig.connect(callable, data["flags"])
