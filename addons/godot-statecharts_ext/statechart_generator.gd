@tool
class_name StateChartGenerator
extends RefCounted

const TYPE_MAP = {
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
	var lines = []
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
			lines.append("\tstatic var %s := e()" % ev)
	lines.append("")

	# Param class
	lines.append("class Param:")
	lines.append("\textends StateChartExt.Param")
	if params.is_empty():
		lines.append("\tpass")
	else:
		for p in params:
			var type_str = TYPE_MAP.get(p.type, "TYPE_NIL")
			var notify_str = ""
			if not p.notify.is_empty():
				var notify_parts = []
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


static func parse_and_generate(
	text: String, fallback_name: String = "GeneratedStateChart"
) -> String:
	var lines = text.split("\n")
	var class_name_str = fallback_name
	var events = []
	var params = []

	for line in lines:
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		var parts = line.split(" ", false)
		if parts.size() < 2:
			continue

		var cmd = parts[0].to_lower()
		if cmd == "class":
			class_name_str = parts[1]
		elif cmd == "event":
			events.append(parts[1])
		elif cmd == "param":
			var p_name = parts[1]
			var p_type = "variant"
			if parts.size() >= 3:
				p_type = parts[2].to_lower()

			var notify = {}
			# Check for notify map { event: true, ... }
			var brace_start = line.find("{")
			if brace_start != -1:
				var brace_end = line.find("}", brace_start)
				if brace_end != -1:
					var dict_content = line.substr(brace_start + 1, brace_end - brace_start - 1)
					var pairs = dict_content.split(",", false)
					for pair in pairs:
						var kv = pair.split(":", false)
						if kv.size() == 2:
							var k = kv[0].strip_edges()
							var v = kv[1].strip_edges().to_lower() == "true"
							notify[k] = v

			params.append({"name": p_name, "type": p_type, "notify": notify})

	return generate_script(class_name_str, events, params)
