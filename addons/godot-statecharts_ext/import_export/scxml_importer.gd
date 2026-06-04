## SCXML Importer for StateCharts
## Imports a minimal SCXML structure into a StateChartExt node.
class_name StateChartScxmlImporter
extends RefCounted

# ------------- [Constants] -------------
const EXT_NAMESPACE_PREFIX := "statechart_ext"
const NAME_ATTR_NAME := "%s:name" % EXT_NAMESPACE_PREFIX
const GUARD_JSON_ATTR_NAME := "%s:guard_json" % EXT_NAMESPACE_PREFIX
const UID_ATTR_NAME := "%s:uid" % EXT_NAMESPACE_PREFIX
const UID_META_KEY := "statechart_ext__uid"
const SCXML_PATH_META_KEY := "statechart_ext__scxml_path"

const ExpressionGuardScript := preload("res://addons/godot_state_charts/expression_guard.gd")
const StateIsActiveGuardScript := preload(
	"res://addons/godot_state_charts/state_is_active_guard.gd"
)
const NotGuardScript := preload("res://addons/godot_state_charts/not_guard.gd")
const AllOfGuardScript := preload("res://addons/godot_state_charts/all_of_guard.gd")
const AnyOfGuardScript := preload("res://addons/godot_state_charts/any_of_guard.gd")

const HistoryStateScript := preload("res://addons/godot_state_charts/history_state.gd")


# ------------- [Defines] -------------
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


# ------------- [Private Method] -------------
func _set_owner(node: Node, owner_node: Node) -> void:
	if owner_node:
		node.owner = owner_node


# ------------- [Public Method] -------------
## Generates .scdef text from an SCXML file
static func generate_scdef(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""

	var xml := XMLParser.new()
	if xml.open_buffer(file.get_buffer(file.get_length())) != OK:
		return ""

	var class_name_str := path.get_file().get_basename().to_pascal_case() + "SC"
	var events: Dictionary[String, bool] = {}
	var params: Array[Dictionary] = []
	var state_stack: Array[String] = []

	while xml.read() == OK:
		var node_type := xml.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var node_name := xml.get_node_name()
			if node_name == "state" or node_name == "parallel":
				if not xml.is_empty():
					var state_id := xml.get_named_attribute_value_safe("id")
					if state_id.is_empty():
						state_id = xml.get_named_attribute_value_safe("name")
					state_stack.append(state_id)
			elif node_name == "scxml":
				var scxml_name := xml.get_named_attribute_value_safe("name")
				if not scxml_name.is_empty():
					class_name_str = scxml_name.to_pascal_case() + "SC"
			elif node_name == "data":
				var id := xml.get_named_attribute_value_safe("id")
				var expr := xml.get_named_attribute_value_safe("expr").strip_edges()
				if not id.is_empty():
					_add_param_from_xml(id, expr, params, state_stack)
			elif node_name == "transition":
				var event_attr := xml.get_named_attribute_value_safe("event")
				for ev in event_attr.split(" ", false):
					var ev_name := ev
					if ev.contains("@"):
						ev_name = ev.split("@")[0]
					if not ev_name.is_empty():
						events[ev_name] = true

				var cond_attr := xml.get_named_attribute_value_safe("cond")
				if not cond_attr.is_empty():
					_extract_params_from_cond(cond_attr, params)
			elif node_name == "onentry" or node_name == "onexit":
				_extract_events_from_executable_content(xml, node_name, events, params, state_stack)
		elif node_type == XMLParser.NODE_ELEMENT_END:
			var node_name := xml.get_node_name()
			if node_name == "state" or node_name == "parallel":
				if not state_stack.is_empty():
					state_stack.pop_back()

	var lines: Array[String] = []
	lines.append("class %s" % class_name_str)
	lines.append("")
	for ev in events:
		lines.append("event %s" % ev)
	if not events.is_empty():
		lines.append("")
	for p in params:
		var opt_str := ""
		if not p["local"].is_empty():
			opt_str = ' {local: "%s"}' % p["local"]
		if p["expr"].is_empty() or p["expr"] == "null":
			lines.append("param %s %s%s" % [p["name"], p["type"], opt_str])
		else:
			lines.append("param %s %s = %s%s" % [p["name"], p["type"], p["expr"], opt_str])

	return "\n".join(lines)


static func _add_param_from_xml(
	id: String, expr: String, params: Array[Dictionary], state_stack: Array[String]
) -> void:
	var type_str := "variant"
	var val_str := expr
	if (
		(expr.begins_with("'") and expr.ends_with("'"))
		or (expr.begins_with('"') and expr.ends_with('"'))
	):
		type_str = "string"
		val_str = expr
	elif expr.to_lower() == "true" or expr.to_lower() == "false":
		type_str = "bool"
	elif expr.is_valid_int():
		type_str = "int"
	elif expr.is_valid_float():
		type_str = "float"
	else:
		# Default to string for unquoted identifiers/literals to avoid compile errors
		type_str = "string"
		val_str = '"%s"' % expr.replace('"', '\\"')

	var local_state := ""
	if not state_stack.is_empty():
		local_state = state_stack.back()

	# Unify by name to avoid duplicate definitions in .scdef (which Proxy API doesn't allow)
	for p in params:
		if p["name"] == id:
			# Update type and initial expression with the concrete definition from <data>
			if p["type"] == "variant" or type_str != "variant":
				p["type"] = type_str
			if p["expr"].is_empty() or p["expr"] == "null":
				p["expr"] = val_str

			# Resolve local state scope
			if p["local"].is_empty():
				p["local"] = local_state
			elif p["local"] != local_state:
				# If name is used in multiple scopes, make it global
				p["local"] = ""
			return

	params.append({"name": id, "type": type_str, "expr": val_str, "local": local_state})


static func _extract_events_from_executable_content(
	xml: XMLParser,
	element_name: String,
	events: Dictionary[String, bool],
	params: Array[Dictionary],
	state_stack: Array[String]
) -> void:
	if xml.is_empty():
		return
	while xml.read() == OK:
		var node_type := xml.get_node_type()
		if node_type == XMLParser.NODE_ELEMENT:
			var node_name := xml.get_node_name()
			if node_name == "send":
				var event := xml.get_named_attribute_value_safe("event")
				if not event.is_empty():
					events[event] = true
			elif node_name == "param":
				var id := xml.get_named_attribute_value_safe("name")
				if id.is_empty():
					id = xml.get_named_attribute_value_safe("id")
				var expr := xml.get_named_attribute_value_safe("expr").strip_edges()
				if not id.is_empty():
					_add_param_from_xml(id, expr, params, state_stack)
		elif node_type == XMLParser.NODE_ELEMENT_END:
			if xml.get_node_name() == element_name:
				return


static func _extract_params_from_cond(cond: String, params: Array[Dictionary]) -> void:
	# Remove strings to avoid picking up identifiers inside them
	var string_regex := RegEx.new()
	string_regex.compile("(['\"])(?:(?=(\\\\?))\\2.)*?\\1")
	var stripped_cond := string_regex.sub(cond, " ", true)

	var regex := RegEx.new()
	regex.compile("\\b[a-zA-Z_][a-zA-Z0-9_]*\\b")
	var matches := regex.search_all(stripped_cond)

	var known_params: Dictionary[String, bool] = {}
	for p in params:
		known_params[p["name"]] = true

	var reserved := ["true", "false", "null", "In", "not", "and", "or"]

	for m in matches:
		var name := m.get_string()
		if name in reserved:
			continue
		if name in known_params:
			continue

		# Check if it's a function call (next char is '(' in the stripped cond)
		var end_pos := m.get_end()
		if end_pos < stripped_cond.length() and stripped_cond[end_pos] == "(":
			continue

		# Add as variant parameter (global)
		params.append({"name": name, "type": "variant", "expr": "null", "local": ""})
		known_params[name] = true


## Imports an SCXML file into the given root node
func import_scxml(path: String, root_node: Node) -> Error:
	DLogger.info("Starting SCXML import from: {0}", [path], "scxml_importer")
	if not root_node is StateChartExt:
		push_error("Import target must be a StateChartExt")
		return ERR_INVALID_PARAMETER

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		DLogger.error("Failed to open SCXML file: {0}", [path], "scxml_importer")
		return ERR_CANT_OPEN

	var xml := XMLParser.new()
	var parse_err := xml.open_buffer(file.get_buffer(file.get_length()))
	if parse_err != OK:
		return parse_err

	var is_in_tree := root_node.is_inside_tree()
	if is_in_tree:
		root_node.set_block_signals(true)

	var saved_connections := _save_connections(root_node)

	if root_node is StateChartExt:
		root_node.reset_internal_state()

	_clear_existing_statechart_nodes(root_node)
	root_node.set_meta(SCXML_PATH_META_KEY, path)

	var scxml_initial := StringName()
	var scxml_name := &"Root"
	var parsed_root_states: Array[ParsedState] = []
	var initial_properties: Dictionary = {}
	var params: Array[Dictionary] = []  # Discovered params during state parsing

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
			parsed_root_states.append(
				_parse_state_element(xml, node_name, initial_properties, params)
			)

	root_node.initial_expression_properties = initial_properties
	DLogger.debug(
		"Parsed {0} root states, {1} initial properties",
		[parsed_root_states.size(), initial_properties.size()],
		"scxml_importer"
	)

	if not parsed_root_states.is_empty():
		var state_by_id: Dictionary[StringName, StateChartState] = {}
		var pending_transitions: Array[PendingTransition] = []

		var needs_synthetic_root := true
		if parsed_root_states.size() == 1:
			var single_root := parsed_root_states[0]
			# If there's only one root state and its name matches the scxml name,
			# we don't need the synthetic wrapper.
			if scxml_name == single_root.id:
				needs_synthetic_root = false
				# Transfer scxml-level initial state if the single root doesn't have its own
				if not scxml_initial.is_empty() and single_root.initial_id.is_empty():
					single_root.initial_id = scxml_initial
				_instantiate_state_tree(single_root, root_node, state_by_id, pending_transitions)

		if needs_synthetic_root:
			var synthetic_root := ParsedState.new(scxml_name, &"state", scxml_initial)
			synthetic_root.children = parsed_root_states
			_instantiate_state_tree(synthetic_root, root_node, state_by_id, pending_transitions)

		_resolve_pending_transitions(pending_transitions, state_by_id)
		DLogger.debug(
			"Resolved {0} pending transitions", [pending_transitions.size()], "scxml_importer"
		)
		_restore_connections(root_node, saved_connections)

	if root_node is StateChartExt:
		root_node.connect_internal_signals()

	if is_in_tree:
		root_node.set_block_signals(false)
		if root_node.has_signal("child_order_changed"):
			root_node.emit_signal("child_order_changed")

	DLogger.info("SCXML import completed successfully: {0}", [path], "scxml_importer")
	return OK


func _clear_existing_statechart_nodes(root_node: Node) -> void:
	for child in root_node.get_children():
		if child is StateChartState or child is Transition:
			root_node.remove_child(child)
			child.free()


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


func _parse_state_element(
	xml: XMLParser, element_name: String, initial_properties: Dictionary, params: Array[Dictionary]
) -> ParsedState:
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
		if attr_name == UID_ATTR_NAME:
			parsed.metadata[UID_META_KEY] = xml.get_attribute_value(i)
		elif attr_name != "id" and attr_name != "name" and attr_name != "initial":
			parsed.metadata[_sanitize_meta_key("attr:" + attr_name)] = xml.get_attribute_value(i)

	if xml.is_empty():
		return parsed

	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name := xml.get_node_name()
				if node_name == "state" or node_name == "parallel" or node_name == "history":
					parsed.children.append(
						_parse_state_element(xml, node_name, initial_properties, params)
					)
				elif node_name == "datamodel":
					_parse_datamodel(xml, initial_properties)
				elif node_name == "initial":
					# Parse initial element's transition
					if not xml.is_empty():
						while xml.read() == OK:
							match xml.get_node_type():
								XMLParser.NODE_ELEMENT:
									if xml.get_node_name() == "transition":
										parsed.initial_id = _parse_transition_target(
											xml.get_named_attribute_value_safe("target")
										)
								XMLParser.NODE_ELEMENT_END:
									if xml.get_node_name() == "initial":
										break
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

				elif node_name == "onentry" or node_name == "onexit":
					var actions := _parse_executable_content(xml, node_name, params)
					if not actions.is_empty():
						parsed.metadata["statechart_ext__" + node_name] = actions.map(
							func(a): return a.to_dict()
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


func _parse_executable_content(
	xml: XMLParser, element_name: String, params: Array[Dictionary] = []
) -> Array[SCXMLAction]:
	var actions: Array[SCXMLAction] = []
	if xml.is_empty():
		return actions

	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name := xml.get_node_name()
				if node_name == "send":
					var event := xml.get_named_attribute_value_safe("event")
					var send_params: Array[Dictionary] = []
					if not xml.is_empty():
						# Read children of send (e.g. <param>)
						while xml.read() == OK:
							var child_type := xml.get_node_type()
							if child_type == XMLParser.NODE_ELEMENT:
								if xml.get_node_name() == "param":
									var p_name := xml.get_named_attribute_value_safe("name")
									if p_name.is_empty():
										p_name = xml.get_named_attribute_value_safe("id")
									var p_expr := (
										xml.get_named_attribute_value_safe("expr").strip_edges()
									)
									var p_eval_expr := _sanitize_assign_expression(p_expr, params)
									if not p_name.is_empty():
										var p_data := {"name": p_name, "expr": p_expr}
										if p_eval_expr != p_expr:
											p_data["eval_expr"] = p_eval_expr
										send_params.append(p_data)
										# Add assigned location to known params if not exists
										var found := false
										for p in params:
											if p.name == p_name:
												found = true
												break
										if not found:
											params.append(
												{
													"name": p_name,
													"type": "variant",
													"expr": "null",
													"local": ""
												}
											)
							elif child_type == XMLParser.NODE_ELEMENT_END:
								if xml.get_node_name() == "send":
									break

					actions.append(SCXMLSendAction.new({"event": event, "params": send_params}))
				elif node_name == "assign":
					var location := xml.get_named_attribute_value_safe("location")
					var expr := _sanitize_assign_expression(
						xml.get_named_attribute_value_safe("expr"), params
					)
					if not location.is_empty():
						actions.append(SCXMLAssignAction.new({"location": location, "expr": expr}))
						# Add assigned location to known params if not exists
						var found := false
						for p in params:
							if p.name == location:
								found = true
								break
						if not found:
							params.append(
								{"name": location, "type": "variant", "expr": "null", "local": ""}
							)
				# Other elements could be added here later
			XMLParser.NODE_ELEMENT_END:
				if xml.get_node_name() == element_name:
					return actions
	return actions


static func _sanitize_assign_expression(expr: String, params: Array[Dictionary]) -> String:
	expr = expr.strip_edges()
	if expr.is_empty():
		return expr

	# Already quoted?
	if (
		(expr.begins_with("'") and expr.ends_with("'"))
		or (expr.begins_with('"') and expr.ends_with('"'))
	):
		return expr

	# Reserved words or literals
	if expr.to_lower() in ["true", "false", "null"] or expr.is_valid_float() or expr.is_valid_int():
		return expr

	# If it's a simple identifier (like Title, Playing)
	var identifier_regex := RegEx.new()
	identifier_regex.compile("^[a-zA-Z_][a-zA-Z0-9_]*$")
	if identifier_regex.search(expr):
		# Check if it matches a known parameter name
		var is_param := false
		for p in params:
			if p.get("name") == expr:
				is_param = true
				break
		if not is_param:
			# Treat as a string literal and quote it
			return '"%s"' % expr.replace('"', '\\"')

	return expr


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
		DLogger.warn(
			"Multiple SCXML transition targets are not supported yet. Using the first target.",
			[],
			"scxml_importer",
			self
		)
	return StringName(target_ids[0])


func _parse_transition_guard_ast(xml: XMLParser) -> Dictionary:
	var guard_json := xml.get_named_attribute_value_safe(GUARD_JSON_ATTR_NAME)
	if not guard_json.is_empty():
		var parsed_json := JSON.parse_string(guard_json)
		if parsed_json is Dictionary:
			return parsed_json
		DLogger.warn(
			"Invalid SCXML guard JSON encountered. Ignoring custom guard data.",
			[],
			"scxml_importer",
			self
		)

	var cond := xml.get_named_attribute_value_safe("cond")
	if not cond.is_empty():
		return _cond_to_ast(cond)
	return {}


func _cond_to_ast(cond: String) -> Dictionary:
	cond = cond.strip_edges()
	if cond.is_empty():
		return {}

	# Handle top-level AND
	var parts_and := _split_top_level(cond, "&&")
	if parts_and.size() > 1:
		var guards: Array = []
		for p in parts_and:
			var ast := _cond_to_ast(_unwrap_parens(p))
			if not ast.is_empty():
				guards.append(ast)
		return {"type": "all_of", "guards": guards}

	# Handle top-level OR
	var parts_or := _split_top_level(cond, "||")
	if parts_or.size() > 1:
		var guards: Array = []
		for p in parts_or:
			var ast := _cond_to_ast(_unwrap_parens(p))
			if not ast.is_empty():
				guards.append(ast)
		return {"type": "any_of", "guards": guards}

	# Handle NOT (allow spaces: ! (...))
	if cond.begins_with("!"):
		var inner := cond.substr(1).strip_edges()
		if inner.begins_with("(") and inner.ends_with(")"):
			var content := inner.substr(1, inner.length() - 2)
			if _is_balanced(content):
				return {"type": "not", "guard": _cond_to_ast(content)}

	# Handle In('...') with RegEx for robustness (quotes and spaces)
	var in_regex := RegEx.new()
	in_regex.compile("^\\s*In\\s*\\(\\s*(['\"])(.*?)\\1\\s*\\)\\s*$")
	var in_match := in_regex.search(cond)
	if in_match:
		return {"type": "state_is_active", "state": in_match.get_string(2)}

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

	if state_node is CompoundState:
		# Set a dummy initial state to prevent automatic assignment of the last child
		# during import in the editor. CompoundState has a deferred call to set
		# initial_state if it's empty when a child is added.
		state_node.initial_state = ^"."

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
		_assign_initial_state(state_node as CompoundState, parsed, state_by_id)

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


func _assign_initial_state(
	state_node: CompoundState,
	parsed: ParsedState,
	state_by_id: Dictionary[StringName, StateChartState]
) -> void:
	var child_states: Array[StateChartState] = []
	for child in state_node.get_children():
		if child is StateChartState:
			child_states.append(child)

	if child_states.is_empty():
		return

	var initial_target: StateChartState = null
	if not parsed.initial_id.is_empty():
		# Try direct child first
		for child_state in child_states:
			if child_state.name == String(parsed.initial_id):
				initial_target = child_state
				break

		# If not a direct child, try finding it in the descendants
		if initial_target == null and parsed.initial_id in state_by_id:
			var target := state_by_id[parsed.initial_id]
			# Ensure it is actually a descendant of state_node
			var current := target
			var path_to_target: Array[StateChartState] = []
			while current != null and current != state_node:
				path_to_target.append(current)
				current = current.get_parent() as StateChartState

			if current == state_node:
				# It is a descendant. Trace back to set all intermediate initial states
				# The last element in path_to_target is the direct child of state_node
				initial_target = path_to_target[-1]

				# Set intermediate initial states
				var prev := state_node as StateChartState
				for i in range(path_to_target.size() - 1, 0, -1):
					var parent := path_to_target[i]
					if parent is CompoundState:
						var child := path_to_target[i - 1]
						(parent as CompoundState).initial_state = parent.get_path_to(child)

		if initial_target == null:
			push_warning(
				(
					"Initial state '%s' was not found as a descendant of '%s'. Falling back to the first child."
					% [parsed.initial_id, parsed.id]
				)
			)

	if initial_target == null or initial_target == state_node:
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


func _collect_uids_recursive(node: Node, dst: Dictionary[String, Node]) -> void:
	if node.has_meta(UID_META_KEY):
		var uid := str(node.get_meta(UID_META_KEY))
		if not uid.is_empty():
			dst[uid] = node

	for child in node.get_children():
		_collect_uids_recursive(child, dst)


func _collect_connections_recursive(node: Node, root_node: Node, saved: Array) -> void:
	var rel_path := root_node.get_path_to(node)
	var uid := ""
	if node.has_meta(UID_META_KEY):
		uid = str(node.get_meta(UID_META_KEY))

	var internal_methods := [
		"_on_state_entered_context",
		"_on_state_exited_cleanup",
		"_on_state_entered",
		"_on_state_exited",
		"_on_event_received"
	]

	for sig_info in node.get_signal_list():
		var sig_name: String = sig_info["name"]
		var sig := Signal(node, sig_name)
		for conn in sig.get_connections():
			var callable: Callable = conn["callable"]

			# Skip internal connections of StateChartExt
			if callable.get_object() == root_node:
				if callable.get_method() in internal_methods:
					continue

			saved.append(
				{
					"source_path": rel_path,
					"source_uid": uid,
					"signal_name": sig_name,
					"callable": callable,
					"flags": conn["flags"]
				}
			)

	for child in node.get_children():
		_collect_connections_recursive(child, root_node, saved)


func _restore_connections(root_node: Node, saved: Array) -> void:
	# Build a UID to Node map for fast lookup
	var uid_to_node: Dictionary[String, Node] = {}
	_collect_uids_recursive(root_node, uid_to_node)

	for data in saved:
		var source: Node = null

		# Try restoring by UID first
		var s_uid = data.get("source_uid", "")
		if not str(s_uid).is_empty():
			source = uid_to_node.get(str(s_uid))

		# Fallback to path if UID lookup failed or node doesn't have a UID
		if not source:
			source = root_node.get_node_or_null(data["source_path"])

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
