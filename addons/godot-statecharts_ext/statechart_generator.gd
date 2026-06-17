@tool
## Generator class that parses .scdef files and produces GDScript boilerplate.
## Handles the definition of the Proxy API, event/parameter classes, and initialization code.
class_name StateChartGenerator
extends RefCounted

# ------------- [Private Static Method] -------------
## Generates GDScript source code from given data
static func _generate_script(
	class_name_str: String, events: Array[Dictionary], params: Array[Dictionary]
) -> String:
	var lines: Array[String] = []
	lines.append("# [StateChartExt] Generated boilerplate. Do not edit manually.")
	lines.append("@tool")
	lines.append("class_name {0} extends StateChartExt".format([class_name_str]))
	lines.append("")

	# --- Proxy Variables (for IDE completion) ---
	lines.append("var e: GEventProxy")
	lines.append("var p: GParamProxy")
	lines.append("")

	# --- Event class ---
	lines.append("class Event:")
	lines.append("\textends StateChartExt.Event")
	if events.is_empty():
		pass
	else:
		for ev in events:
			if not ev.comment.is_empty():
				lines.append("\t## {0}".format([ev.comment]))
			lines.append("\tstatic var {0} := e()".format([ev.name]))
	lines.append("")

	# --- Param class ---
	lines.append("class Param:")
	lines.append("\textends StateChartExt.Param")
	if params.is_empty():
		pass
	else:
		for p_data in params:
			if not p_data.comment.is_empty():
				lines.append("\t## {0}".format([p_data.comment]))
			var type_str: String = StateChartConstants.TYPE_MAP.get(p_data.type, "TYPE_NIL")

			var notify_map_code := "{}"
			if not p_data.notify.is_empty():
				var notify_parts: Array[String] = []
				for ev_name in p_data.notify:
					var val = p_data.notify[ev_name]
					notify_parts.append(
						"{0}.Event.{1}: {2}".format([class_name_str, ev_name, str(val).to_lower()])
					)
				notify_map_code = "{ {0} }".format([", ".join(notify_parts)])

			var init_val_code := "StateChartExt._s_none_value"
			if not p_data.init.is_empty():
				init_val_code = p_data.init

			var local_state_code := '&""'
			if not p_data.local_state.is_empty():
				local_state_code = '&"{0}"'.format([p_data.local_state])

			lines.append(
				"\tstatic var {0} := p({1}, {2}, {3}, {4})".format(
					[p_data.name, type_str, notify_map_code, init_val_code, local_state_code]
				)
			)
	lines.append("")

	# --- Specialized Proxies ---
	lines.append("class GEventProxy extends StateChartExt.EventProxy:")

	var event_names: Array[String] = []
	for ev in events:
		event_names.append('"{0}"'.format([ev.name]))
	lines.append(
		"\tfunc has(name: String) -> bool: return name in [{0}]".format([", ".join(event_names)])
	)

	if events.is_empty():
		pass
	else:
		for ev in events:
			lines.append(
				"\tfunc {0}() -> void: _sc.send_event_ext({1}.Event.{2})".format(
					[ev.name, class_name_str, ev.name]
				)
			)
	lines.append("")

	lines.append("class GParamProxy extends StateChartExt.ParamProxy:")

	var param_names: Array[String] = []
	for p_data in params:
		param_names.append('"{0}"'.format([p_data.name]))

	lines.append("\tfunc has(name: String) -> bool:")
	lines.append("\t\tif not name in [{0}]: return false".format([", ".join(param_names)]))
	lines.append("\t\treturn _sc._expression_properties.has(name)")
	lines.append("")

	if params.is_empty():
		pass
	else:
		for p_data in params:
			var gd_type := StateChartConstants.GD_TYPE_MAP.get(p_data.type, "Variant")
			lines.append("\tvar {0}: {1}:".format([p_data.name, gd_type]))

			var default_val_code := "null"
			if p_data.type in StateChartConstants.GD_TYPE_MAP:
				default_val_code = "_sc._make_zero({0})".format([StateChartConstants.TYPE_MAP[p_data.type]])

			lines.append(
				"\t\tget: return _sc.get_expression_property_ext({0}.Param.{1}, {2})".format(
					[class_name_str, p_data.name, default_val_code]
				)
			)
			lines.append(
				"\t\tset(v): _sc.set_expression_property_ext({0}.Param.{1}, v)".format(
					[class_name_str, p_data.name]
				)
			)
	lines.append("")

	# --- _init ---
	lines.append("func _init() -> void:")
	lines.append("\te = GEventProxy.new(self)")
	lines.append("\tp = GParamProxy.new(self)")
	lines.append("")

	# --- get_sc_info ---
	lines.append("# [Override]")
	lines.append("func get_sc_info() -> SCInfo:")
	lines.append("\treturn SCInfo.new(Param, Event)")

	return "\n".join(lines)


# ------------- [Public Method] -------------
## Parses scdef text and returns a Dictionary with "events", "params", "class_name", and "error".
static func parse_scdef(text: String, fallback_name: String = "GeneratedStateChart") -> Dictionary:
	var lines := text.split("\n")
	var class_name_str := fallback_name
	var events: Array[Dictionary] = []
	var params: Array[Dictionary] = []
	var error_msg := ""
	var pending_comments: Array[String] = []

	var used_names: Dictionary[String, int] = {}

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
			error_msg = "Line {0}: Invalid syntax. Expected 'command name'.".format([i + 1])
			break

		var cmd := parts[0].to_lower()
		var name := parts[1]
		var final_comment := "\n\t## ".join(pending_comments)
		pending_comments.clear()

		if cmd != "class":
			if used_names.has(name):
				error_msg = (
					"Line {0}: Duplicate name '{1}' (previously defined at line {2})."
					. format([i + 1, name, used_names[name]])
				)
				break
			used_names[name] = i + 1

		if cmd == "class":
			class_name_str = name
		elif cmd == "event":
			events.append({"name": name, "comment": final_comment})
		elif cmd == "param":
			var p_name := name
			var p_type := "variant"
			var p_init := ""
			var p_notify: Dictionary[String, bool] = {}
			var p_local_state := ""

			# Robustly extract brace options from the end of the line.
			# Rule: The last { ... } block is options IF it's not preceded by an '='.
			var line_without_brace := line_content
			var brace_content := ""

			if line_content.ends_with("}"):
				var depth := 0
				var brace_start := -1
				for j in range(line_content.length() - 1, -1, -1):
					var c := line_content[j]
					if c == "}":
						depth += 1
					elif c == "{":
						depth -= 1
						if depth == 0:
							brace_start = j
							break

				if brace_start != -1:
					# Check if this brace block is preceded by '='
					var prefix := line_content.substr(0, brace_start).strip_edges()
					if not prefix.ends_with("="):
						brace_content = line_content.substr(
							brace_start + 1, line_content.length() - brace_start - 2
						)
						line_without_brace = prefix

			if not brace_content.is_empty():
				var pairs := brace_content.split(",", false)
				for pair in pairs:
					var kv := pair.split(":", false)
					if kv.size() == 2:
						var k := kv[0].strip_edges()
						var v_str := kv[1].strip_edges()
						if k == "local":
							p_local_state = (
								v_str
								. strip_edges()
								. trim_prefix('"')
								. trim_suffix('"')
								. trim_prefix("'")
								. trim_suffix("'")
							)
						else:
							p_notify[k] = v_str.to_lower() == "true"
					else:
						error_msg = "Line {0}: Invalid notification/option map syntax.".format(
							[i + 1]
						)
						break

			if not error_msg.is_empty():
				break

			# Extract initial value
			var eq_pos := line_without_brace.find("=")
			var line_before_eq := line_without_brace
			if eq_pos != -1:
				p_init = line_without_brace.substr(eq_pos + 1).strip_edges()
				line_before_eq = line_without_brace.substr(0, eq_pos).strip_edges()

			# Extract type
			var p_parts := line_before_eq.split(" ", false)
			if p_parts.size() >= 3:
				p_type = p_parts[2].to_lower()

			if not p_type in StateChartConstants.TYPE_MAP:
				error_msg = "Line {0}: Unknown type '{1}'.".format([i + 1, p_type])
				break

			params.append(
				{
					"name": p_name,
					"type": p_type,
					"init": p_init,
					"notify": p_notify,
					"local_state": p_local_state,
					"comment": final_comment
				}
			)
		else:
			error_msg = "Line {0}: Unknown command '{1}'.".format([i + 1, cmd])
			break

	if not error_msg.is_empty():
		DLogger.error("scdef parse error: {0}".format([error_msg]), [], "scdef_generator")
		return {"error": error_msg}

	return {"class_name": class_name_str, "events": events, "params": params, "error": ""}


## Parses scdef text and returns a Dictionary with "code" (String) and "error" (String, empty if OK).
static func parse_and_generate(
	text: String, fallback_name: String = "GeneratedStateChart"
) -> Dictionary:
	var result := parse_scdef(text, fallback_name)
	if not result.error.is_empty():
		return {"code": "", "error": result.error}

	return {"code": _generate_script(result.class_name, result.events, result.params), "error": ""}
