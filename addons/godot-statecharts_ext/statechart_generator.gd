@tool
class_name StateChartGenerator
extends RefCounted

const TYPE_MAP: Dictionary[String, String] = {
	"float": "TYPE_FLOAT",
	"int": "TYPE_INT",
	"bool": "TYPE_BOOL",
	"string": "TYPE_STRING",
	"vector2": "TYPE_VECTOR2",
	"vector3": "TYPE_VECTOR3",
	"color": "TYPE_COLOR",
	"rect2": "TYPE_RECT2",
	"array": "TYPE_ARRAY",
	"dict": "TYPE_DICTIONARY",
	"dictionary": "TYPE_DICTIONARY",
	"variant": "TYPE_NIL"
}


static func generate_script(class_name_str: String, events: Array, params: Array) -> String:
	var lines: Array[String] = []
	lines.append("# [StateChartExt] Generated boilerplate. Do not edit manually.")
	lines.append("@tool")
	lines.append("class_name %s extends StateChartExt" % class_name_str)
	lines.append("")

	# Event class
	lines.append("class Event:")
	lines.append("\textends StateChartExt.Event")
	if events.is_empty():
		lines.append("\tpass")
	else:
		for ev in events:
			if not ev.comment.is_empty():
				lines.append("\t## %s" % ev.comment)
			lines.append("\tstatic var %s := e()" % ev.name)
	lines.append("")

	# Param class
	lines.append("class Param:")
	lines.append("\textends StateChartExt.Param")
	if params.is_empty():
		lines.append("\tpass")
	else:
		for p in params:
			if not p.comment.is_empty():
				lines.append("\t## %s" % p.comment)
			var type_str: String = TYPE_MAP.get(p.type, "TYPE_NIL")
			var notify_str := ""
			if not p.notify.is_empty():
				var notify_parts: Array[String] = []
				for ev_name in p.notify:
					var val = p.notify[ev_name]
					notify_parts.append(
						"%s.Event.%s: %s" % [class_name_str, ev_name, str(val).to_lower()]
					)
				notify_str = ", {%s}" % ", ".join(notify_parts)

			lines.append("\tstatic var %s := p(%s%s)" % [p.name, type_str, notify_str])
	lines.append("")

	# get_sc_info
	lines.append("# [Override]")
	lines.append("func get_sc_info() -> SCInfo:")
	lines.append("\treturn SCInfo.new(Param, Event)")

	return "\n".join(lines)


## Parses scdef text and returns a Dictionary with "code" (String) and "error" (String, empty if OK).
static func parse_and_generate(
	text: String, fallback_name: String = "GeneratedStateChart"
) -> Dictionary:
	var lines := text.split("\n")
	var class_name_str := fallback_name
	var events: Array[Dictionary] = []
	var params: Array[Dictionary] = []
	var error_msg := ""
	var pending_comments: Array[String] = []

	for i in range(lines.size()):
		var raw_line := lines[i].strip_edges()

		# Collect documentation comments
		if raw_line.begins_with("##"):
			pending_comments.append(raw_line.substr(2).strip_edges())
			continue

		# Regular comments or empty lines break the doc-comment block
		if raw_line.begins_with("#") or raw_line.is_empty():
			pending_comments.clear()
			continue

		# Parse command line
		var comment_start := raw_line.find("##")
		var line_content := raw_line
		if comment_start != -1:
			var inline_comment := raw_line.substr(comment_start + 2).strip_edges()
			pending_comments.append(inline_comment)
			line_content = raw_line.substr(0, comment_start).strip_edges()

		var parts := line_content.split(" ", false)
		if parts.size() < 2:
			error_msg = "Line %d: Invalid syntax. Expected 'command name'." % (i + 1)
			break

		var cmd := parts[0].to_lower()
		var name := parts[1]
		var final_comment := "\n\t## ".join(pending_comments)
		pending_comments.clear()

		if cmd == "class":
			class_name_str = name
		elif cmd == "event":
			events.append({"name": name, "comment": final_comment})
		elif cmd == "param":
			var p_type := "variant"
			if parts.size() >= 3:
				p_type = parts[2].to_lower()

			if not p_type in TYPE_MAP:
				error_msg = "Line %d: Unknown type '%s'." % [i + 1, p_type]
				break

			var notify: Dictionary[String, bool] = {}
			var brace_start := line_content.find("{")
			if brace_start != -1:
				var brace_end := line_content.find("}", brace_start)
				if brace_end == -1:
					error_msg = "Line %d: Missing closing brace '}'." % (i + 1)
					break

				var dict_content := line_content.substr(
					brace_start + 1, brace_end - brace_start - 1
				)
				var pairs := dict_content.split(",", false)
				for pair in pairs:
					var kv := pair.split(":", false)
					if kv.size() == 2:
						var k := kv[0].strip_edges()
						var v := kv[1].strip_edges().to_lower() == "true"
						notify[k] = v
					else:
						error_msg = "Line %d: Invalid notification map syntax." % (i + 1)
						break
				if not error_msg.is_empty():
					break

			params.append(
				{"name": name, "type": p_type, "notify": notify, "comment": final_comment}
			)
		else:
			error_msg = "Line %d: Unknown command '%s'." % [i + 1, cmd]
			break

	if not error_msg.is_empty():
		return {"code": "", "error": error_msg}

	return {"code": generate_script(class_name_str, events, params), "error": ""}
