class_name StateChartInspector
extends RefCounted


static func sc_get_property_list(sc: StateChartExt) -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
	if sc_info == null:
		return properties

	var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
	if not params.is_empty():
		properties.append(
			{
				"name": "StateChart Parameters",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartExt.PROP_GROUP_PARAM
			}
		)

		for p_name in params:
			var ent := params[p_name] as StateChartExt.ParamEnt
			var usage := PROPERTY_USAGE_DEFAULT
			if ent.type_id == TYPE_NIL:
				usage |= PROPERTY_USAGE_NIL_IS_VARIANT
			var display_name := p_name
			if not ent.local_state.is_empty():
				display_name = ("{0}{1}{2} {3}".format(
					[
						StateChartExt.LocalParam.PREFIX,
						ent.local_state,
						StateChartExt.LocalParam.SUFFIX,
						p_name
					]
				))

			properties.append(
				{
					"name": StateChartExt.PROP_GROUP_PARAM + display_name,
					"type": ent.type_id,
					"usage": usage
				}
			)

	var events := StateChartExt._init_and_get_entries(sc_info.event, StateChartExt.EventEnt)
	if not events.is_empty():
		properties.append(
			{
				"name": "Exclude Unused Warnings",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartExt.PROP_GROUP_EXC_UNUSED
			}
		)
		for ev_name in events:
			properties.append(
				{
					"name": StateChartExt.PROP_GROUP_EXC_UNUSED + ev_name,
					"type": TYPE_BOOL,
					"usage": PROPERTY_USAGE_EDITOR
				}
			)

		properties.append(
			{
				"name": "Exclude Unknown Warnings",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartExt.PROP_GROUP_EXC_UNKNOWN
			}
		)
		for ev_name in events:
			properties.append(
				{
					"name": StateChartExt.PROP_GROUP_EXC_UNKNOWN + ev_name,
					"type": TYPE_BOOL,
					"usage": PROPERTY_USAGE_EDITOR
				}
			)

	if not sc._runtime_history.is_empty():
		properties.append(
			{
				"name": "Runtime History (Latest first)",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartExt.PROP_GROUP_HISTORY
			}
		)
		for i in range(sc._runtime_history.size()):
			properties.append(
				{
					"name": StateChartExt.PROP_GROUP_HISTORY + str(i),
					"type": TYPE_STRING,
					"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
				}
			)

	return properties


static func sc_validate_property(sc: StateChartExt, property: Dictionary) -> void:
	if property.name == "initial_expression_properties":
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "exclude_unused_event" or property.name == "exclude_warn_unknown_events":
		property.usage = PROPERTY_USAGE_STORAGE


static func sc_get_property(sc: StateChartExt, property: StringName) -> Variant:
	if property == &"e":
		return sc._e_dyn
	if property == &"p":
		return sc._p_dyn

	if property.begins_with(StateChartExt.PROP_GROUP_EXC_UNUSED):
		var ev_name := property.trim_prefix(StateChartExt.PROP_GROUP_EXC_UNUSED)
		return ev_name in sc.exclude_unused_event

	if property.begins_with(StateChartExt.PROP_GROUP_EXC_UNKNOWN):
		var ev_name := property.trim_prefix(StateChartExt.PROP_GROUP_EXC_UNKNOWN)
		return ev_name in sc.exclude_warn_unknown_events

	if property.begins_with(StateChartExt.PROP_GROUP_HISTORY):
		var idx := int(property.trim_prefix(StateChartExt.PROP_GROUP_HISTORY))
		if idx < sc._runtime_history.size():
			return sc._runtime_history[idx]
		return ""

	if property.begins_with(StateChartExt.PROP_GROUP_PARAM):
		var p_name := property.trim_prefix(StateChartExt.PROP_GROUP_PARAM)
		# Handle local param display name
		if p_name.contains(StateChartExt.LocalParam.PREFIX):
			var parts := p_name.split(" ")
			p_name = parts[-1]

		var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
		if sc_info:
			var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
			if params.has(p_name):
				return sc.get_expression_property_ext(params[p_name] as StateChartExt.ParamEnt)

	return null


static func sc_set_property(sc: StateChartExt, property: StringName, value: Variant) -> bool:
	if property == &"e":
		sc._e_dyn = value
		return true
	if property == &"p":
		sc._p_dyn = value
		return true

	if property.begins_with(StateChartExt.PROP_GROUP_EXC_UNUSED):
		var ev_name := StringName(property.trim_prefix(StateChartExt.PROP_GROUP_EXC_UNUSED))
		sc._update_exclusion_list(sc.exclude_unused_event, ev_name, value)
		return true

	if property.begins_with(StateChartExt.PROP_GROUP_EXC_UNKNOWN):
		var ev_name := StringName(property.trim_prefix(StateChartExt.PROP_GROUP_EXC_UNKNOWN))
		sc._update_exclusion_list(sc.exclude_warn_unknown_events, ev_name, value)
		return true

	if property.begins_with(StateChartExt.PROP_GROUP_PARAM):
		var p_name := property.trim_prefix(StateChartExt.PROP_GROUP_PARAM)
		if p_name.contains(StateChartExt.LocalParam.PREFIX):
			var parts := p_name.split(" ")
			p_name = parts[-1]

		var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
		if sc_info:
			var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
			if params.has(p_name):
				sc.set_expression_property_ext(params[p_name] as StateChartExt.ParamEnt, value)
				return true

	return false
