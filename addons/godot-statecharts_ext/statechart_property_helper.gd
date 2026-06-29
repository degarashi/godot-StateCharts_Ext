class_name StateChartPropertyHelper
extends RefCounted


## Builds the inspector property list for StateChartExt.
## Includes parameters, warning exclusion toggles, and runtime history.
static func sc_get_property_list(sc: StateChartExt) -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
	if sc_info == null:
		return properties

	# Fetch parameter definitions to display in the inspector
	var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
	if not params.is_empty():
		properties.append(
			{
				"name": "StateChart Parameters",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartConstants.PropGroup.PARAM
			}
		)

		# Build property definitions for each parameter
		for p_name in params:
			var ent := params[p_name] as StateChartExt.ParamEnt
			var usage := PROPERTY_USAGE_DEFAULT
			if ent.type_id == TYPE_NIL:
				usage |= PROPERTY_USAGE_NIL_IS_VARIANT
			var display_name := p_name
			if not ent.local_state.is_empty():
				display_name = ("{0}{1}{2} {3}".format(
					[
						StateChartConstants.LocalParam.PREFIX,
						ent.local_state,
						StateChartConstants.LocalParam.SUFFIX,
						p_name
					]
				))

			# Append the parameter property definition
			properties.append(
				{
					"name": StateChartConstants.PropGroup.PARAM + display_name,
					"type": ent.type_id,
					"usage": usage
				}
			)

	# Fetch event definitions to display in the inspector
	var events := StateChartExt._init_and_get_entries(sc_info.event, StateChartExt.EventEnt)
	if not events.is_empty():
		# Add the "exclude unused event warnings" group
		properties.append(
			{
				"name": "Exclude Unused Warnings",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartConstants.PropGroup.EXC_UNUSED
			}
		)
		# Add per-event exclude toggle properties
		for ev_name in events:
			properties.append(
				{
					"name": StateChartConstants.PropGroup.EXC_UNUSED + ev_name,
					"type": TYPE_BOOL,
					"usage": PROPERTY_USAGE_EDITOR
				}
			)

		# Add the "exclude unknown event warnings" group
		properties.append(
			{
				"name": "Exclude Unknown Warnings",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartConstants.PropGroup.EXC_UNKNOWN
			}
		)
		# Add per-event exclude toggle properties
		for ev_name in events:
			properties.append(
				{
					"name": StateChartConstants.PropGroup.EXC_UNKNOWN + ev_name,
					"type": TYPE_BOOL,
					"usage": PROPERTY_USAGE_EDITOR
				}
			)

	# Show runtime history in the inspector
	if not sc._runtime_history.is_empty():
		# Add the runtime history display group
		properties.append(
			{
				"name": "Runtime History (Latest first)",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartConstants.PropGroup.HISTORY
			}
		)
		# Add property for each history entry
		for i in range(sc._runtime_history.size()):
			properties.append(
				{
					"name": StateChartConstants.PropGroup.HISTORY + str(i),
					"type": TYPE_STRING,
					"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
				}
			)

	return properties


## Property validation.
## Controls inspector display settings for specific properties (e.g. storage-only).
static func sc_validate_property(_sc: StateChartExt, property: Dictionary) -> void:
	if property.name == "initial_expression_properties":
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "exclude_unused_event" or property.name == "exclude_warn_unknown_events":
		property.usage = PROPERTY_USAGE_STORAGE


## Retrieves property values.
## Returns the appropriate value based on the property name accessed from the inspector.
static func sc_get_property(sc: StateChartExt, property: StringName) -> Variant:
	if property == &"e":
		return sc._e_dyn
	if property == &"p":
		return sc._p_dyn

	# Get exclude-unused-event setting
	if property.begins_with(StateChartConstants.PropGroup.EXC_UNUSED):
		var ev_name := property.trim_prefix(StateChartConstants.PropGroup.EXC_UNUSED)
		return ev_name in sc.exclude_unused_event

	# Get exclude-unknown-event setting
	if property.begins_with(StateChartConstants.PropGroup.EXC_UNKNOWN):
		var ev_name := property.trim_prefix(StateChartConstants.PropGroup.EXC_UNKNOWN)
		return ev_name in sc.exclude_warn_unknown_events

	# Get runtime history entry
	if property.begins_with(StateChartConstants.PropGroup.HISTORY):
		var idx := int(property.trim_prefix(StateChartConstants.PropGroup.HISTORY))
		if idx < sc._runtime_history.size():
			return sc._runtime_history[idx]
		return ""

	# Get parameter value
	if property.begins_with(StateChartConstants.PropGroup.PARAM):
		var p_name := property.trim_prefix(StateChartConstants.PropGroup.PARAM)
		# Handle local param display name
		if p_name.contains(StateChartConstants.LocalParam.PREFIX):
			var parts := p_name.split(" ")
			p_name = parts[-1]

		# Look up state chart info
		var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
		if sc_info:
			var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
			if params.has(p_name):
				var ent := params[p_name] as StateChartExt.ParamEnt
				var val := sc.get_expression_property_ext(ent)
				if val == null and ent.type_id == TYPE_STRING:
					return ""
				return val

	return null


## Sets property values.
## Updates the StateChartExt internal state based on the property name changed in the inspector.
static func sc_set_property(sc: StateChartExt, property: StringName, value: Variant) -> bool:
	if property == &"e":
		sc._e_dyn = value
		return true
	if property == &"p":
		sc._p_dyn = value
		return true

	# Update exclude-unused-event setting
	if property.begins_with(StateChartConstants.PropGroup.EXC_UNUSED):
		var ev_name := StringName(property.trim_prefix(StateChartConstants.PropGroup.EXC_UNUSED))
		sc._update_exclusion_list(sc.exclude_unused_event, ev_name, value)
		return true

	# Update exclude-unknown-event setting
	if property.begins_with(StateChartConstants.PropGroup.EXC_UNKNOWN):
		var ev_name := StringName(property.trim_prefix(StateChartConstants.PropGroup.EXC_UNKNOWN))
		sc._update_exclusion_list(sc.exclude_warn_unknown_events, ev_name, value)
		return true

	# Update parameter value
	if property.begins_with(StateChartConstants.PropGroup.PARAM):
		var p_name := property.trim_prefix(StateChartConstants.PropGroup.PARAM)
		if p_name.contains(StateChartConstants.LocalParam.PREFIX):
			var parts := p_name.split(" ")
			p_name = parts[-1]

		# Look up state chart info
		var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
		if sc_info:
			var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
			if params.has(p_name):
				sc.set_expression_property_ext(params[p_name] as StateChartExt.ParamEnt, value)
				return true

	return false
