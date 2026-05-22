## SCXML Importer for StateCharts
## Imports a minimal SCXML structure into a StateChartExt node.
class_name StateChartScxmlImporter
extends RefCounted

const EXT_NAMESPACE_PREFIX := "statechart_ext"
const DELAY_ATTR_NAME := "%s:delay_in_seconds" % EXT_NAMESPACE_PREFIX
const NAME_ATTR_NAME := "%s:name" % EXT_NAMESPACE_PREFIX
const GUARD_JSON_ATTR_NAME := "%s:guard_json" % EXT_NAMESPACE_PREFIX

const ExpressionGuardScript := preload("res://addons/godot_state_charts/expression_guard.gd")
const StateIsActiveGuardScript := preload("res://addons/godot_state_charts/state_is_active_guard.gd")
const NotGuardScript := preload("res://addons/godot_state_charts/not_guard.gd")
const AllOfGuardScript := preload("res://addons/godot_state_charts/all_of_guard.gd")
const AnyOfGuardScript := preload("res://addons/godot_state_charts/any_of_guard.gd")


class ParsedTransition:
	var name: String
	var event: StringName
	var target_id: StringName
	var delay_in_seconds: String
	var guard_ast: Dictionary

	func _init(
		name_a: String = "Transition",
		event_a: StringName = &"",
		target_id_a: StringName = &"",
		delay_in_seconds_a: String = "0.0",
		guard_ast_a: Dictionary = {}
	) -> void:
		name = name_a
		event = event_a
		target_id = target_id_a
		delay_in_seconds = delay_in_seconds_a
		guard_ast = guard_ast_a


class ParsedState:
	var id: StringName
	var kind: StringName
	var initial_id: StringName
	var children: Array[ParsedState] = []
	var transitions: Array[ParsedTransition] = []

	func _init(
		id_a: StringName = &"", kind_a: StringName = &"state", initial_id_a: StringName = &""
	) -> void:
		id = id_a
		kind = kind_a
		initial_id = initial_id_a


class PendingTransition:
	var node: Transition
	var target_id: StringName
	var guard_ast: Dictionary

	func _init(node_a: Transition, target_id_a: StringName, guard_ast_a: Dictionary = {}) -> void:
		node = node_a
		target_id = target_id_a
		guard_ast = guard_ast_a


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

	_clear_existing_statechart_nodes(root_node)

	var scxml_initial := StringName()
	var scxml_name := &"Root"
	var parsed_root_states: Array[ParsedState] = []

	while xml.read() == OK:
		if xml.get_node_type() != XMLParser.NODE_ELEMENT:
			continue

		var node_name := xml.get_node_name()
		if node_name == "scxml":
			scxml_initial = StringName(xml.get_named_attribute_value_safe("initial"))
			var scxml_name_attr := xml.get_named_attribute_value_safe("name")
			if not scxml_name_attr.is_empty():
				scxml_name = StringName(scxml_name_attr)
		elif node_name == "state" or node_name == "parallel":
			parsed_root_states.append(_parse_state_element(xml, node_name))

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
	return OK


func _clear_existing_statechart_nodes(root_node: Node) -> void:
	for child in root_node.get_children():
		if child is StateChartState or child is Transition:
			root_node.remove_child(child)
			child.queue_free()


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

	if xml.is_empty():
		return parsed

	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name := xml.get_node_name()
				if node_name == "state" or node_name == "parallel":
					parsed.children.append(_parse_state_element(xml, node_name))
				elif node_name == "transition":
					parsed.transitions.append(
						ParsedTransition.new(
							_parse_transition_name(xml),
							StringName(xml.get_named_attribute_value_safe("event")),
							_parse_transition_target(xml.get_named_attribute_value_safe("target")),
							_parse_transition_delay(xml),
							_parse_transition_guard_ast(xml)
						)
					)
			XMLParser.NODE_ELEMENT_END:
				if xml.get_node_name() == element_name:
					return parsed

	return parsed


func _parse_transition_name(xml: XMLParser) -> String:
	var name_attr := xml.get_named_attribute_value_safe(NAME_ATTR_NAME)
	if not name_attr.is_empty():
		return name_attr
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


func _parse_transition_delay(xml: XMLParser) -> String:
	var delay_attr := xml.get_named_attribute_value_safe(DELAY_ATTR_NAME)
	if not delay_attr.is_empty():
		return delay_attr
	return "0.0"


func _parse_transition_guard_ast(xml: XMLParser) -> Dictionary:
	var guard_json := xml.get_named_attribute_value_safe(GUARD_JSON_ATTR_NAME)
	if not guard_json.is_empty():
		var parsed_json := JSON.parse_string(guard_json)
		if parsed_json is Dictionary:
			return parsed_json
		push_warning("Invalid SCXML guard JSON encountered. Ignoring custom guard data.")

	var cond := xml.get_named_attribute_value_safe("cond")
	if not cond.is_empty():
		return {"type": "expression", "expression": cond}
	return {}


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

	for child_parsed in parsed.children:
		_instantiate_state_tree(child_parsed, state_node, state_by_id, pending_transitions)

	for parsed_transition in parsed.transitions:
		var transition := Transition.new()
		transition.name = parsed_transition.name
		transition.event = parsed_transition.event
		transition.delay_in_seconds = parsed_transition.delay_in_seconds
		state_node.add_child(transition)
		_set_owner(transition, state_node.owner if state_node.owner else state_node)
		pending_transitions.append(
			PendingTransition.new(transition, parsed_transition.target_id, parsed_transition.guard_ast)
		)

	if state_node is CompoundState:
		_assign_initial_state(state_node as CompoundState, parsed)

	return state_node


func _create_state_node(parsed: ParsedState) -> StateChartState:
	var state_node: StateChartState
	if parsed.kind == &"parallel":
		state_node = ParallelState.new()
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
		if target_state != null:
			pending.node.to = pending.node.get_path_to(target_state)
		pending.node.guard = _guard_from_ast(pending.guard_ast)


func _guard_from_ast(ast: Dictionary) -> Guard:
	if ast.is_empty():
		return null

	match String(ast.get("type", "")):
		"expression":
			var guard := ExpressionGuardScript.new()
			guard.expression = String(ast.get("expression", ""))
			return guard
		"state_is_active":
			var guard := StateIsActiveGuardScript.new()
			guard.state = NodePath(String(ast.get("state", "")))
			return guard
		"not":
			var guard := NotGuardScript.new()
			guard.guard = _guard_from_ast(ast.get("guard", {}))
			return guard
		"all_of":
			var guard := AllOfGuardScript.new()
			guard.guards = _guards_from_ast_array(ast.get("guards", []))
			return guard
		"any_of":
			var guard := AnyOfGuardScript.new()
			guard.guards = _guards_from_ast_array(ast.get("guards", []))
			return guard

	push_warning("Unsupported SCXML guard type '%s'. Guard was ignored." % String(ast.get("type", "")))
	return null


func _guards_from_ast_array(items: Array) -> Array[Guard]:
	var guards: Array[Guard] = []
	for item in items:
		if item is Dictionary:
			var guard := _guard_from_ast(item)
			if guard != null:
				guards.append(guard)
	return guards
