## SCXML Exporter for StateCharts
## Generates SCXML compliant XML structure from StateChart nodes.
class_name StateChartScxmlExporter
extends RefCounted

const EXT_NAMESPACE_PREFIX := "statechart_ext"
const EXT_NAMESPACE_URI := "https://github.com/degarashi/godot-statecharts_ext/scxml"
const DELAY_ATTR_NAME := "%s:delay_in_seconds" % EXT_NAMESPACE_PREFIX
const NAME_ATTR_NAME := "%s:name" % EXT_NAMESPACE_PREFIX
const GUARD_JSON_ATTR_NAME := "%s:guard_json" % EXT_NAMESPACE_PREFIX

const QT_NAMESPACE_PREFIX := "qt"
const QT_NAMESPACE_URI := "http://www.qt.io/2015/02/scxml-ext"

const ExpressionGuardScript := preload("res://addons/godot_state_charts/expression_guard.gd")
const StateIsActiveGuardScript := preload(
	"res://addons/godot_state_charts/state_is_active_guard.gd"
)
const NotGuardScript := preload("res://addons/godot_state_charts/not_guard.gd")
const AllOfGuardScript := preload("res://addons/godot_state_charts/all_of_guard.gd")
const AnyOfGuardScript := preload("res://addons/godot_state_charts/any_of_guard.gd")

const HistoryStateScript := preload("res://addons/godot_state_charts/history_state.gd")


## Exports the state chart to an SCXML string
func export_to_scxml(node: Node) -> String:
	var xml_lines: Array[String] = []
	xml_lines.append('<?xml version="1.0" encoding="UTF-8"?>')

	var namespaces: Dictionary[String, String] = {
		"xmlns": "http://www.w3.org/2005/07/scxml",
		"xmlns:" + EXT_NAMESPACE_PREFIX: EXT_NAMESPACE_URI
	}

	# Detect extra namespaces from metadata
	var root_attrs: Array[String] = []
	for meta_key in node.get_meta_list():
		if meta_key.contains("__"):
			var desanitized_key := _desanitize_meta_key(meta_key)
			var parts := desanitized_key.split(":")
			if parts.size() == 2:
				if parts[0] == QT_NAMESPACE_PREFIX:
					namespaces["xmlns:" + QT_NAMESPACE_PREFIX] = QT_NAMESPACE_URI
				root_attrs.append(
					'%s="%s"' % [desanitized_key, _escape_attr(str(node.get_meta(meta_key)))]
				)

	var ns_parts: Array[String] = []
	for ns in namespaces:
		ns_parts.append('%s="%s"' % [ns, namespaces[ns]])

	xml_lines.append(
		'<scxml {ns} version="1.0" profile="ecmascript" {attrs}>'.format(
			{"ns": " ".join(ns_parts), "attrs": " ".join(root_attrs)}
		)
	)

	if node is StateChartExt:
		_export_datamodel(node, xml_lines, 1)

	_export_state(node, xml_lines, 1)

	xml_lines.append("</scxml>")
	return "\n".join(xml_lines)


func _export_datamodel(node: StateChartExt, lines: Array[String], indent: int) -> void:
	if node.initial_expression_properties.is_empty():
		return

	var spacing := "\t".repeat(indent)
	lines.append("{s}<datamodel>".format({"s": spacing}))
	for key in node.initial_expression_properties:
		var val: Variant = node.initial_expression_properties[key]
		var val_str := ""
		if val is String or val is StringName:
			val_str = "'%s'" % _escape_attr(String(val))
		else:
			val_str = _escape_attr(str(val))

		lines.append(
			'{s}\t<data id="{id}" expr="{expr}"/>'.format(
				{"s": spacing, "id": _escape_attr(String(key)), "expr": val_str}
			)
		)
	lines.append("{s}</datamodel>".format({"s": spacing}))


## Exports a state and its children recursively
func _export_state(node: Node, lines: Array[String], indent: int) -> void:
	var spacing := "\t".repeat(indent)

	if node is StateChartState:
		var tag_name := _state_tag_name(node)
		var state_attrs: Array[String] = []
		state_attrs.append('id="%s"' % _escape_attr(node.name))

		# Initial state for compound states
		if node is CompoundState:
			var initial_node := node.get_node_or_null(node.initial_state)
			if initial_node:
				state_attrs.append('initial="%s"' % _escape_attr(initial_node.name))

		if node is HistoryStateScript:
			var h_state := node as HistoryState
			# Only add type if not already in metadata as attr__type
			if not node.has_meta("attr__type"):
				state_attrs.append('type="%s"' % ("deep" if h_state.deep else "shallow"))

		var extra_tags: Array[String] = []
		for meta_key in node.get_meta_list():
			if meta_key.begins_with("attr__"):
				state_attrs.append(
					(
						'%s="%s"'
						% [
							_desanitize_meta_key(meta_key.substr(6)),
							_escape_attr(str(node.get_meta(meta_key)))
						]
					)
				)
			elif meta_key.begins_with("tag__"):
				var tag_info: Dictionary = node.get_meta(meta_key)
				var tag_full_name := _desanitize_meta_key(meta_key.substr(5))
				var tag_attrs: Array[String] = []
				for k in tag_info:
					tag_attrs.append('%s="%s"' % [k, _escape_attr(str(tag_info[k]))])
				extra_tags.append(
					"{s}\t<{tag} {attrs}/>".format(
						{"s": spacing, "tag": tag_full_name, "attrs": " ".join(tag_attrs)}
					)
				)

		if node is HistoryStateScript:
			var default_node = node.get_node_or_null((node as HistoryState).default_state)
			if default_node:
				extra_tags.append(
					'%s\t<transition target="%s"/>' % [spacing, _escape_attr(default_node.name)]
				)

		lines.append(
			"{s}<{tag} {attrs}>".format(
				{"s": spacing, "tag": tag_name, "attrs": " ".join(state_attrs)}
			)
		)

		for t in extra_tags:
			lines.append(t)

		for child in node.get_children():
			if child is StateChartState:
				_export_state(child, lines, indent + 1)

		_export_transitions(node, lines, indent + 1)

		lines.append("{s}</{tag}>".format({"s": spacing, "tag": tag_name}))
	elif node is StateChartExt:
		for child in node.get_children():
			if child is StateChartState:
				_export_state(child, lines, indent)


func _state_tag_name(node: StateChartState) -> String:
	if node is ParallelState:
		return "parallel"
	if node is HistoryStateScript:
		return "history"
	return "state"


## Exports transitions of a state, grouping identical ones
func _export_transitions(state_node: Node, lines: Array[String], indent: int) -> void:
	var spacing := "\t".repeat(indent)
	var trans_groups: Array[Dictionary] = []  # Array of { "key": Dict, "events": Array[String] }

	for child in state_node.get_children():
		if not child is Transition:
			continue

		var t := child as Transition
		var target := ""
		if t.to:
			var target_node := t.get_node_or_null(t.to)
			if target_node:
				target = target_node.name

		# Metadata & Extra tags
		var attrs: Dictionary = {}
		var extra_tags: Array[String] = []
		for meta_key in t.get_meta_list():
			if meta_key.begins_with("attr__"):
				attrs[_desanitize_meta_key(meta_key.substr(6))] = str(t.get_meta(meta_key))
			elif meta_key.begins_with("tag__"):
				var tag_info: Dictionary = t.get_meta(meta_key)
				var tag_full_name := _desanitize_meta_key(meta_key.substr(5))
				var tag_attrs: Array[String] = []
				for k in tag_info:
					tag_attrs.append('%s="%s"' % [k, _escape_attr(str(tag_info[k]))])
				extra_tags.append(
					"\t<{tag} {attrs}/>".format(
						{"tag": tag_full_name, "attrs": " ".join(tag_attrs)}
					)
				)

		var group_key := {
			"target": target,
			"delay": t.delay_in_seconds,
			"guard_cond": _guard_to_cond(t.guard, t),
			"guard_ast": _guard_to_ast(t.guard, t),
			"attrs": attrs,
			"extra_tags": extra_tags
		}

		var found := false
		for group in trans_groups:
			if _is_same_group(group.key, group_key):
				if not String(t.event).is_empty():
					group.events.append(String(t.event))
				found = true
				break

		if not found:
			var events: Array[String] = []
			if not String(t.event).is_empty():
				events.append(String(t.event))
			trans_groups.append({"key": group_key, "events": events, "original_name": t.name})  # Use first transition's name if not combined

	for group in trans_groups:
		var key: Dictionary = group.key
		var events: Array[String] = group.events
		var attrs: Array[String] = []

		attrs.append('event="%s"' % _escape_attr(" ".join(events)))
		attrs.append('target="%s"' % _escape_attr(key.target))
		attrs.append('%s="%s"' % [DELAY_ATTR_NAME, _escape_attr(key.delay)])

		# If it's a combined transition, we don't really have a single Godot name.
		# But we can try to restore the original name if there's only one.
		if events.size() <= 1:
			attrs.append('%s="%s"' % [NAME_ATTR_NAME, _escape_attr(group.original_name)])

		if not key.guard_cond.is_empty():
			attrs.append('cond="%s"' % _escape_attr(key.guard_cond))
		if not key.guard_ast.is_empty():
			attrs.append(
				'%s="%s"' % [GUARD_JSON_ATTR_NAME, _escape_attr(JSON.stringify(key.guard_ast))]
			)

		for attr_name in key.attrs:
			attrs.append('%s="%s"' % [attr_name, _escape_attr(key.attrs[attr_name])])

		if key.extra_tags.is_empty():
			lines.append(
				"{s}<transition {attrs}/>".format({"s": spacing, "attrs": " ".join(attrs)})
			)
		else:
			lines.append("{s}<transition {attrs}>".format({"s": spacing, "attrs": " ".join(attrs)}))
			for tag in key.extra_tags:
				lines.append(spacing + tag)
			lines.append("{s}</transition>".format({"s": spacing}))


func _is_same_group(a: Dictionary, b: Dictionary) -> bool:
	if a.target != b.target:
		return false
	if a.delay != b.delay:
		return false
	if a.guard_cond != b.guard_cond:
		return false
	if str(a.guard_ast) != str(b.guard_ast):
		return false
	if str(a.attrs) != str(b.attrs):
		return false
	if str(a.extra_tags) != str(b.extra_tags):
		return false
	return true


func _export_guard_attrs(node: Transition) -> Array[String]:
	var attrs: Array[String] = []
	if node.guard == null:
		return attrs

	var cond := _guard_to_cond(node.guard, node)
	if not cond.is_empty():
		attrs.append('cond="%s"' % _escape_attr(cond))

	var guard_ast := _guard_to_ast(node.guard, node)
	if guard_ast.is_empty():
		push_warning(
			(
				"Unsupported guard type '%s' for transition '%s'. Guard was not exported."
				% [
					(
						node.guard.get_script().resource_path
						if node.guard.get_script()
						else node.guard.get_class()
					),
					node.name
				]
			)
		)
		return attrs

	var json := JSON.stringify(guard_ast, "")
	attrs.append('%s="%s"' % [GUARD_JSON_ATTR_NAME, _escape_attr(json)])
	return attrs


func _guard_to_cond(guard: Guard, context_transition: Transition) -> String:
	if guard == null:
		return ""
	if guard is ExpressionGuardScript:
		return guard.expression
	if guard is StateIsActiveGuardScript:
		var target_node := context_transition.get_node_or_null(guard.state)
		if target_node:
			return "In('%s')" % target_node.name
		return "In('%s')" % String(guard.state)
	if guard is NotGuardScript:
		var inner := _guard_to_cond(guard.guard, context_transition)
		if inner.is_empty():
			return ""
		return "!(%s)" % inner
	if guard is AllOfGuardScript:
		var parts: Array[String] = []
		for g in guard.guards:
			var s := _guard_to_cond(g, context_transition)
			if not s.is_empty():
				parts.append("(%s)" % s)
		if parts.is_empty():
			return ""
		return " && ".join(parts)
	if guard is AnyOfGuardScript:
		var parts: Array[String] = []
		for g in guard.guards:
			var s := _guard_to_cond(g, context_transition)
			if not s.is_empty():
				parts.append("(%s)" % s)
		if parts.is_empty():
			return ""
		return " || ".join(parts)
	return ""


func _guard_to_ast(guard: Guard, context_transition: Transition) -> Dictionary:
	if guard == null:
		return {}
	if guard is ExpressionGuardScript:
		return {"type": "expression", "expression": guard.expression}
	if guard is StateIsActiveGuardScript:
		var target_node := context_transition.get_node_or_null(guard.state)
		if target_node == null:
			return {"type": "state_is_active", "state": String(guard.state)}
		return {
			"type": "state_is_active", "state": String(context_transition.get_path_to(target_node))
		}
	if guard is NotGuardScript:
		return {"type": "not", "guard": _guard_to_ast(guard.guard, context_transition)}
	if guard is AllOfGuardScript:
		return {"type": "all_of", "guards": _guards_to_ast_array(guard.guards, context_transition)}
	if guard is AnyOfGuardScript:
		return {"type": "any_of", "guards": _guards_to_ast_array(guard.guards, context_transition)}
	return {}


func _guards_to_ast_array(guards: Array[Guard], context_transition: Transition) -> Array:
	var result: Array = []
	for guard in guards:
		var ast := _guard_to_ast(guard, context_transition)
		if not ast.is_empty():
			result.append(ast)
	return result


func _escape_attr(value: String) -> String:
	return value.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;").replace(
		">", "&gt;"
	)


func _desanitize_meta_key(key: String) -> String:
	return key.replace("__", ":")


## Exports to file
func export_and_save(node: Node, path: String) -> Error:
	var scxml_data := export_to_scxml(node)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(scxml_data)
	return OK
