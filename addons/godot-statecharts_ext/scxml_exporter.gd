## SCXML Exporter for StateCharts
## Generates SCXML compliant XML structure from StateChart nodes.
class_name StateChartScxmlExporter
extends RefCounted

const EXT_NAMESPACE_PREFIX := "statechart_ext"
const EXT_NAMESPACE_URI := "https://github.com/degarashi/godot-statecharts_ext/scxml"
const DELAY_ATTR_NAME := "%s:delay_in_seconds" % EXT_NAMESPACE_PREFIX
const NAME_ATTR_NAME := "%s:name" % EXT_NAMESPACE_PREFIX
const GUARD_JSON_ATTR_NAME := "%s:guard_json" % EXT_NAMESPACE_PREFIX

const ExpressionGuardScript := preload("res://addons/godot_state_charts/expression_guard.gd")
const StateIsActiveGuardScript := preload(
	"res://addons/godot_state_charts/state_is_active_guard.gd"
)
const NotGuardScript := preload("res://addons/godot_state_charts/not_guard.gd")
const AllOfGuardScript := preload("res://addons/godot_state_charts/all_of_guard.gd")
const AnyOfGuardScript := preload("res://addons/godot_state_charts/any_of_guard.gd")


## Exports the state chart to an SCXML string
func export_to_scxml(node: Node) -> String:
	var xml_lines: Array[String] = []
	xml_lines.append('<?xml version="1.0" encoding="UTF-8"?>')
	(
		xml_lines
		. append(
			(
				'<scxml xmlns="http://www.w3.org/2005/07/scxml" xmlns:{prefix}="{uri}" version="1.0" profile="ecmascript">'
				. format({"prefix": EXT_NAMESPACE_PREFIX, "uri": EXT_NAMESPACE_URI})
			)
		)
	)

	_export_state(node, xml_lines, 1)

	xml_lines.append("</scxml>")
	return "\n".join(xml_lines)


## Exports a state and its children recursively
func _export_state(node: Node, lines: Array[String], indent: int) -> void:
	var spacing := "\t".repeat(indent)

	if node is StateChartState:
		var tag_name := _state_tag_name(node)
		lines.append(
			'{s}<{tag} id="{id}">'.format(
				{"s": spacing, "tag": tag_name, "id": _escape_attr(node.name)}
			)
		)

		for child in node.get_children():
			if child is StateChartState:
				_export_state(child, lines, indent + 1)
			elif child is Transition:
				_export_transition(child, lines, indent + 1)

		lines.append("{s}</{tag}>".format({"s": spacing, "tag": tag_name}))
	elif node is StateChartExt:
		for child in node.get_children():
			if child is StateChartState:
				_export_state(child, lines, indent)


func _state_tag_name(node: StateChartState) -> String:
	if node is ParallelState:
		return "parallel"
	return "state"


## Exports a transition
func _export_transition(node: Transition, lines: Array[String], indent: int) -> void:
	var spacing := "\t".repeat(indent)
	var target := ""
	if node.to:
		var target_node := node.get_node_or_null(node.to)
		if target_node:
			target = target_node.name

	var attrs: Array[String] = []
	attrs.append('event="%s"' % _escape_attr(String(node.event)))
	attrs.append('target="%s"' % _escape_attr(target))
	attrs.append('%s="%s"' % [DELAY_ATTR_NAME, _escape_attr(node.delay_in_seconds)])
	attrs.append('%s="%s"' % [NAME_ATTR_NAME, _escape_attr(node.name)])

	var guard_attrs := _export_guard_attrs(node)
	for attr in guard_attrs:
		attrs.append(attr)

	lines.append("{s}<transition {attrs}/>".format({"s": spacing, "attrs": " ".join(attrs)}))


func _export_guard_attrs(node: Transition) -> Array[String]:
	var attrs: Array[String] = []
	if node.guard == null:
		return attrs

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

	if guard_ast.get("type", "") == "expression":
		attrs.append('cond="%s"' % _escape_attr(String(guard_ast.get("expression", ""))))

	var json := JSON.stringify(guard_ast, "")
	attrs.append('%s="%s"' % [GUARD_JSON_ATTR_NAME, _escape_attr(json)])
	return attrs


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


## Exports to file
func export_and_save(node: Node, path: String) -> Error:
	var scxml_data := export_to_scxml(node)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(scxml_data)
	return OK
