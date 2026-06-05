@icon("uid://wutp82auwys2")
@tool
## StateChart extension with static type safety.
## Provides automatic code generation from .scdef files, intuitive access via Proxy objects,
## and editor-side validation features.
@abstract class_name StateChartExt
extends StateChart

# ------------- [Constants] -------------
const CAT := "state_chart"
const LOCAL_PARAM_PREFIX := "[L: "
const LOCAL_PARAM_SUFFIX := "] "
const PATH_SEPARATOR := "/"
const SCDEF_EXTENSION := "scdef"
const GD_EXTENSION := "gd"
const SCXML_PATH_META_KEY := "statechart_ext__scxml_path"
const PROP_GROUP_PARAM := "p/"
const PROP_GROUP_EXC_UNUSED := "exc_unused/"
const PROP_GROUP_EXC_UNKNOWN := "exc_unknown/"
const ACTION_TYPE_SEND := "send"
const ACTION_TYPE_ASSIGN := "assign"
const META_ON_ENTRY := "statechart_ext__onentry"
const META_ON_EXIT := "statechart_ext__onexit"


# ------------- [Defines] -------------
## Class to inherit user-defined parameters
class Param:
	extends SCInfoBase

	## Helper to simplify parameter definition
	static func p(
		typ: int,
		notify_map: Dictionary = {},
		init_val: Variant = StateChartExt._s_none_value,
		loc_state: StringName = &""
	) -> ParamEnt:
		return ParamEnt.new(typ, notify_map, init_val, loc_state)


## Class to inherit user-defined events
class Event:
	extends SCInfoBase

	## Helper to simplify event definition
	static func e() -> EventEnt:
		return EventEnt.new()


## Enumeration of StateChart parameters and events
class SCInfo:
	var param: Script  # (class Param)
	var event: Script  # (class Event)

	func _init(param_a: Script, event_a: Script) -> void:
		param = param_a
		event = event_a


## Internal: Class representing "no value"
class NoneValue:
	pass


## Internal: Base class for SCInfo related classes
class SCInfoBase:
	const SCINFO_BASE = 0

	## Check if the script inherits from SCInfoBase
	static func is_infobase(s: Script) -> bool:
		return "SCINFO_BASE" in s.get_script_constant_map()


## Internal: Base class for event or parameter entries
class EntBase:
	extends Resource
	@export var name: StringName


## Internal: Single event entry
class EventEnt:
	extends EntBase
	const ENT_TYPE = "EVENT"


## Internal: Single parameter entry
class ParamEnt:
	extends EntBase
	const ENT_TYPE = "PARAM"
	var type_id: int
	var notify: Array[NotifyEnt]
	var initial_value: Variant
	var local_state: StringName

	func _init(
		typ: int = TYPE_NIL,
		notify_map: Dictionary = {},
		init_val: Variant = StateChartExt._s_none_value,
		loc_state: StringName = &""
	) -> void:
		type_id = typ
		initial_value = init_val
		local_state = loc_state

		notify = []
		# [EventEnt] -> (bool | Callable)
		for ev_ent in notify_map:
			notify.append(NotifyEnt.new(ev_ent, notify_map[ev_ent]))


## Internal: Configuration items for parameter notifications
class NotifyEnt:
	extends EntBase
	const ENT_TYPE = "NOTIFY"
	## Target event to monitor
	var event: EventEnt
	## Notification determination function (func(prev, current) -> bool)
	var checker: Callable

	func _init(event_a: EventEnt, checker_a: Variant) -> void:
		assert(is_instance_valid(event_a), "event_a must be a valid instance")
		event = event_a
		# Default: Always send event
		checker = func(_prev: Variant, _current: Variant) -> bool: return true
		if checker_a is bool:
			if checker_a:
				# Send event only when the value changes
				checker = func(prev: Variant, current: Variant) -> bool: return prev != current
		else:
			# Custom determination function
			checker = checker_a


## Proxy base for event dispatching
class EventProxy:
	var _sc: StateChartExt

	func _init(sc: StateChartExt) -> void:
		_sc = sc

	## Returns true if the event exists
	func has(_event_name: String) -> bool:
		return false


## Proxy base for parameter operations
class ParamProxy:
	var _sc: StateChartExt

	func _init(sc: StateChartExt) -> void:
		_sc = sc

	## Returns true if the parameter exists
	func has(_param_name: String) -> bool:
		return false


## Proxy for operating local parameters tied to a state
class StateChartLocalProxy:
	var _sc: StateChartExt
	var _state: StateChartState

	func _init(sc: StateChartExt, state: StateChartState) -> void:
		_sc = sc
		_state = state

	## Sets a local parameter
	func set_param(
		param_ent: ParamEnt, value: Variant, suppress_notify := false
	) -> StateChartLocalProxy:
		_sc.set_expression_property_local(param_ent, value, _state, suppress_notify)
		return self

	## Dispatches an event
	func send_event(event_ent: EventEnt) -> StateChartLocalProxy:
		_sc.send_event_ext(event_ent)
		return self


## Dynamic event proxy implementation
class DynamicEventProxy:
	extends EventProxy
	var _cache: Dictionary[String, EntBase]

	func _init(sc: StateChartExt, event_script: Script) -> void:
		super(sc)
		_cache = StateChartExt._init_and_get_entries(event_script, EventEnt)

	func has(event_name: String) -> bool:
		return event_name in _cache

	func _get(property: StringName) -> Variant:
		if property in _cache:
			return _sc.send_event_ext.bind(_cache[property] as EventEnt)
		return null

	func _call(method: StringName, _args: Array) -> Variant:
		if method in _cache:
			_sc.send_event_ext(_cache[method] as EventEnt)
			return true
		return null


## Dynamic parameter proxy implementation
class DynamicParamProxy:
	extends ParamProxy
	var _cache: Dictionary[String, EntBase]

	func _init(sc: StateChartExt, param_script: Script) -> void:
		super(sc)
		_cache = StateChartExt._init_and_get_entries(param_script, ParamEnt)

	func has(param_name: String) -> bool:
		if param_name in _cache:
			var ent := _cache[param_name] as ParamEnt
			return _sc._expression_properties.has(ent.name)
		return false

	func _get(property: StringName) -> Variant:
		if property in _cache:
			return _sc.get_expression_property_ext(_cache[property] as ParamEnt)
		return null

	func _set(property: StringName, value: Variant) -> bool:
		if property in _cache:
			_sc.set_expression_property_ext(_cache[property] as ParamEnt, value)
			return true
		return false


# ------------- [Static Variable] -------------
static var _s_none_value := NoneValue.new()
## Entry cache per script [Script] -> [EntryTypeName] -> Dictionary[String, EntBase]
static var _entries_cache: Dictionary = {}

# ------------- [Exports] -------------
## Whether to output state transition logs
@export var debug_log := false:
	set(value):
		debug_log = value
		_update_debug_log_connections(self)

## Whether to output event reception logs
@export var debug_event := false:
	set(value):
		debug_event = value
		_update_debug_event_connection()

## Exception list for unused event warnings
@export var exclude_unused_event: Array[StringName] = []:
	set(value):
		exclude_unused_event = value
		update_configuration_warnings()

## Exception list for unknown event warnings
@export var exclude_warn_unknown_events: Array[StringName] = []:
	set(value):
		exclude_warn_unknown_events = value
		update_configuration_warnings()

@export_tool_button("Check errors", "Callable")
var check_errors_btn := func() -> void: check_errors()
@export_tool_button("Clear all metadata", "Callable")
var clear_metadata_btn := func() -> void: clear_all_metadata()

# ------------- [Private Variable] -------------
## Whether at least one state has been entered
var _any_state_entered := false
## Stack of currently active states (supports nesting)
var _context_state_stack: Array[StateChartState] = []
## Local parameters managed per state [StateChartState] -> Array[ParamEnt]
var _state_local_params: Dictionary = {}
## Internal: Dynamic event proxy
var _e_dyn: EventProxy
## Internal: Dynamic parameter proxy
var _p_dyn: ParamProxy


# ------------- [Callbacks] -------------
func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var sc_info := get_sc_info()
	if sc_info == null:
		return properties

	var params := _init_and_get_entries(sc_info.param, ParamEnt)
	if not params.is_empty():
		properties.append(
			{
				"name": "StateChart Parameters",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": PROP_GROUP_PARAM
			}
		)

		for p_name in params:
			var ent := params[p_name] as ParamEnt
			var usage := PROPERTY_USAGE_DEFAULT
			if ent.type_id == TYPE_NIL:
				usage |= PROPERTY_USAGE_NIL_IS_VARIANT
			var display_name := p_name
			if not ent.local_state.is_empty():
				display_name = (
					"%s%s%s %s" % [LOCAL_PARAM_PREFIX, ent.local_state, LOCAL_PARAM_SUFFIX, p_name]
				)

			properties.append({"name": PROP_GROUP_PARAM + display_name, "type": ent.type_id, "usage": usage})

	var events := _init_and_get_entries(sc_info.event, EventEnt)
	if not events.is_empty():
		properties.append(
			{
				"name": "Exclude Unused Warnings",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": PROP_GROUP_EXC_UNUSED
			}
		)
		for ev_name in events:
			properties.append(
				{"name": PROP_GROUP_EXC_UNUSED + ev_name, "type": TYPE_BOOL, "usage": PROPERTY_USAGE_EDITOR}
			)

		properties.append(
			{
				"name": "Exclude Unknown Warnings",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": PROP_GROUP_EXC_UNKNOWN
			}
		)
		for ev_name in events:
			properties.append(
				{
					"name": PROP_GROUP_EXC_UNKNOWN + ev_name,
					"type": TYPE_BOOL,
					"usage": PROPERTY_USAGE_EDITOR
				}
			)

	return properties


func _validate_property(property: Dictionary) -> void:
	if property.name == "initial_expression_properties":
		# Hide the base dictionary from the inspector since we have the p/ properties.
		# We keep STORAGE so it's still saved and the base class can use it.
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "exclude_unused_event" or property.name == "exclude_warn_unknown_events":
		property.usage = PROPERTY_USAGE_STORAGE


func _get(property: StringName) -> Variant:
	if property == &"e":
		return _e_dyn
	if property == &"p":
		return _p_dyn

	if property.begins_with(PROP_GROUP_EXC_UNUSED):
		return property.trim_prefix(PROP_GROUP_EXC_UNUSED) in exclude_unused_event

	if property.begins_with(PROP_GROUP_EXC_UNKNOWN):
		return property.trim_prefix(PROP_GROUP_EXC_UNKNOWN) in exclude_warn_unknown_events

	if property.begins_with(PROP_GROUP_PARAM):
		var p_name := property.trim_prefix(PROP_GROUP_PARAM)
		if p_name.begins_with(LOCAL_PARAM_PREFIX):
			var close_bracket := p_name.find(LOCAL_PARAM_SUFFIX)
			if close_bracket != -1:
				p_name = p_name.substr(close_bracket + LOCAL_PARAM_SUFFIX.length())
		var sc_info := get_sc_info()
		if sc_info != null:
			var params := _init_and_get_entries(sc_info.param, ParamEnt)
			if p_name in params:
				var ent := params[p_name] as ParamEnt
				var val = get_expression_property_ext(ent)
				if val == null:
					if not ent.initial_value is NoneValue:
						return ent.initial_value
					return _make_zero(ent.type_id)
				return val
	else:
		var sc_info := get_sc_info()
		if sc_info != null:
			var params := _init_and_get_entries(sc_info.param, ParamEnt)
			if property in params:
				var ent := params[property] as ParamEnt
				var val = get_expression_property_ext(ent)
				if val == null:
					if not ent.initial_value is NoneValue:
						return ent.initial_value
					return _make_zero(ent.type_id)
				return val
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"e":
		_e_dyn = value
		return true
	if property == &"p":
		_p_dyn = value
		return true

	if property.begins_with(PROP_GROUP_EXC_UNUSED):
		var ev_name := property.trim_prefix(PROP_GROUP_EXC_UNUSED)
		_update_exclusion_list(exclude_unused_event, ev_name, value)
		update_configuration_warnings()
		return true

	if property.begins_with(PROP_GROUP_EXC_UNKNOWN):
		var ev_name := property.trim_prefix(PROP_GROUP_EXC_UNKNOWN)
		_update_exclusion_list(exclude_warn_unknown_events, ev_name, value)
		update_configuration_warnings()
		return true

	if property.begins_with(PROP_GROUP_PARAM):
		var p_name := property.trim_prefix(PROP_GROUP_PARAM)
		if p_name.begins_with(LOCAL_PARAM_PREFIX):
			var close_bracket := p_name.find(LOCAL_PARAM_SUFFIX)
			if close_bracket != -1:
				p_name = p_name.substr(close_bracket + LOCAL_PARAM_SUFFIX.length())
		var sc_info := get_sc_info()
		if sc_info != null:
			var params := _init_and_get_entries(sc_info.param, ParamEnt)
			if p_name in params:
				var ent := params[p_name] as ParamEnt
				if Engine.is_editor_hint():
					if (
						not initial_expression_properties.has(ent.name)
						or initial_expression_properties[ent.name] != value
					):
						initial_expression_properties[ent.name] = value
						# Ensure the dictionary is marked as changed
						initial_expression_properties = initial_expression_properties
						notify_property_list_changed()
				set_expression_property_ext(ent, value)
				return true
	else:
		var sc_info := get_sc_info()
		if sc_info != null:
			var params := _init_and_get_entries(sc_info.param, ParamEnt)
			if property in params:
				var ent := params[property] as ParamEnt
				if Engine.is_editor_hint():
					if (
						not initial_expression_properties.has(ent.name)
						or initial_expression_properties[ent.name] != value
					):
						initial_expression_properties[ent.name] = value
						initial_expression_properties = initial_expression_properties
						notify_property_list_changed()
				set_expression_property_ext(ent, value)
				return true
	return false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	_connect_state_signals_early(self)


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return

	var sc_info := get_sc_info()
	if sc_info != null:
		var params := _init_and_get_entries(sc_info.param, ParamEnt)
		_init_and_get_entries(sc_info.event, EventEnt)

		for p_name in params:
			var ent := params[p_name] as ParamEnt
			if ent.local_state.is_empty() and not ent.initial_value is NoneValue:
				# Only apply the initial value if it's not already set via inspector
				if not initial_expression_properties.has(ent.name):
					set_expression_property_ext(ent, ent.initial_value, true)

		if get(&"e") == null:
			set(&"e", DynamicEventProxy.new(self, sc_info.event))
		if get(&"p") == null:
			set(&"p", DynamicParamProxy.new(self, sc_info.param))

	_connect_state_signals_late(self)
	_update_debug_log_connections(self)
	_update_debug_event_connection()

	if debug_log:
		DLogger.debug("Initialized", [], CAT, self)

	if OS.is_debug_build():
		for ev_name in exclude_warn_unknown_events:
			_valid_event_names.append(ev_name)


func _on_state_entered(state: Node) -> void:
	DLogger.debug("State entered (Post): {0}", [state.name], CAT, self)


func _on_state_exited(state: Node) -> void:
	DLogger.debug("State exited (Post): {0}", [state.name], CAT, self)


func _evaluate_and_assign(location: String, expr_str: String) -> void:
	var expr := Expression.new()
	# Collect all current properties as context for expression evaluation
	var props := _expression_properties
	var prop_names := props.keys()
	var prop_values: Array = []
	for p in prop_names:
		prop_values.append(props[p])

	var err := expr.parse(expr_str, prop_names)
	if err == OK:
		var result: Variant = expr.execute(prop_values, self)
		if not expr.has_execute_failed():
			_set_expression_property_untyped(location, result)
		else:
			push_error(
				(
					"StateChartExt: Failed to execute assign expression: "
					+ expr_str
					+ " Error: "
					+ expr.get_error_text()
				)
			)
	else:
		push_error(
			(
				"StateChartExt: Failed to parse assign expression: "
				+ expr_str
				+ " Error: "
				+ expr.get_error_text()
			)
		)


func _on_state_action(action: Dictionary) -> void:
	match action.get("type"):
		ACTION_TYPE_SEND:
			var event: String = action.get("event", "")
			var send_params = action.get("params", [])
			if send_params is Array:
				for p_data in send_params:
					if p_data is Dictionary:
						var p_name: String = p_data.get("name", "")
						var expr_str: String = p_data.get("eval_expr", p_data.get("expr", ""))
						if not p_name.is_empty():
							_evaluate_and_assign(p_name, expr_str)
			if not event.is_empty():
				_send_event_untyped(event)
		ACTION_TYPE_ASSIGN:
			var location: String = action.get("location", "")
			var expr_str: String = action.get("expr", "")
			if not location.is_empty():
				_evaluate_and_assign(location, expr_str)


func _on_state_entered_actions(state: Node) -> void:
	if state.has_meta(META_ON_ENTRY):
		var actions = state.get_meta(META_ON_ENTRY)
		if actions is Array:
			for action in actions:
				if action is Dictionary:
					_on_state_action(action)


func _on_state_exited_actions(state: Node) -> void:
	if state.has_meta(META_ON_EXIT):
		var actions = state.get_meta(META_ON_EXIT)
		if actions is Array:
			for action in actions:
				if action is Dictionary:
					_on_state_action(action)


func _set_expression_property_untyped(value_name: StringName, value: Variant) -> void:
	# Internal helper to call the base class set_expression_property and bypass the safety assert.
	# This is used for SCXML-imported actions or internal logic.
	super.set_expression_property(value_name, value)


func _send_event_untyped(event: StringName) -> void:
	# Internal helper to call the base class send_event and bypass the safety assert.
	# This is used for SCXML-imported actions or internal logic.
	super.send_event(event)


func _on_state_entered_context(state: StateChartState) -> void:
	_any_state_entered = true
	if state not in _context_state_stack:
		_context_state_stack.append(state)

	var sc_info := get_sc_info()
	if sc_info != null:
		var params := _init_and_get_entries(sc_info.param, ParamEnt)
		for p_name in params:
			var ent := params[p_name] as ParamEnt
			var is_match := false
			if ent.local_state == state.name:
				is_match = true
			elif not ent.local_state.is_empty():
				# Check relative path from this node to the state
				var rel_path := str(get_path_to(state))
				if (
					rel_path == str(ent.local_state)
					or rel_path.ends_with(PATH_SEPARATOR + str(ent.local_state))
				):
					is_match = true

			if is_match:
				var init_val: Variant = ent.initial_value
				if init_val is NoneValue:
					init_val = _make_zero(ent.type_id)
				set_expression_property_local(ent, init_val, state, true)


func _on_state_exited_cleanup(state: StateChartState) -> void:
	_context_state_stack.erase(state)
	if state in _state_local_params:
		var params: Array = _state_local_params[state]
		for param_ent in params:
			if _expression_properties.has(param_ent.name):
				if initial_expression_properties.has(param_ent.name):
					_expression_properties[param_ent.name] = initial_expression_properties[
						param_ent.name
					]
				else:
					_expression_properties.erase(param_ent.name)
				_property_change_pending = true
		_state_local_params.erase(state)
		if _property_change_pending and not _locked_down:
			_run_changes()


func _on_event_received(event: StringName) -> void:
	DLogger.debug("Event received: {0}", [event], CAT, self)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	var sc_info := get_sc_info()
	var params_m := gather_params_id(sc_info.param)
	if not params_m.is_empty():
		_check_param(warnings, params_m)

	var event := _init_and_get_entries(sc_info.event, EventEnt)
	var invalid_ev: PackedStringArray = []
	var exclude_ev: PackedStringArray = []

	exclude_ev.append_array(exclude_unused_event)
	exclude_ev.append_array(exclude_warn_unknown_events)

	for ev_name in exclude_ev:
		if ev_name not in event:
			invalid_ev.append(ev_name)

	if not invalid_ev.is_empty():
		var err_str := "invalid event name (exclude):\n"
		err_str += ", ".join(invalid_ev)
		warnings.append(err_str)
	if not event.is_empty():
		_check_event_typo(warnings, event, exclude_ev)
		_check_unused_events(warnings, event, exclude_ev)

	warnings.append_array(super())
	return warnings


# ------------- [Private Static Method] -------------
static func is_instance_of_entry(ent: EntBase, target: Script) -> bool:
	if not is_instance_valid(ent):
		return false
	var s := (ent as Object).get_script() as Script
	while s != null:
		if s == target:
			return true
		s = s.get_base_script()
	return false


static func _init_and_get_entries(
	source: Script, entry_target: Script
) -> Dictionary[String, EntBase]:
	var target_type_name: String = entry_target.ENT_TYPE
	if _entries_cache.has(source):
		if _entries_cache[source].has(target_type_name):
			return _entries_cache[source][target_type_name]
	else:
		_entries_cache[source] = {}

	var ret: Dictionary[String, EntBase] = {}
	var current_script := source

	while true:
		var constants := current_script.get_script_constant_map()
		for c_name in constants:
			var val = constants[c_name]
			if val is EntBase and is_instance_of_entry(val, entry_target):
				val.name = c_name
				ret[c_name] = val

		for m in current_script.get_property_list():
			if m.name in ["script", "Built-in Script", "RefCounted", "Resource"]:
				continue
			var val = current_script.get(m.name)
			if val is EntBase:
				if is_instance_of_entry(val, entry_target):
					val.name = m.name
					ret[m.name] = val

		current_script = current_script.get_base_script()
		if current_script == null or SCInfoBase.is_infobase(current_script):
			break

	_entries_cache[source][target_type_name] = ret
	return ret


static func gather_params_id(source: Script) -> Dictionary[String, int]:
	var params_m: Dictionary[String, int] = {}
	var params := _init_and_get_entries(source, ParamEnt)
	for key in params:
		params_m[key] = (params[key] as ParamEnt).type_id
	return params_m


static func _check_parameter_type(
	param_name: String, expect_type_id: int, actual_value: Variant, context: Object
) -> void:
	if expect_type_id == TYPE_NIL:
		return
	var typeid := typeof(actual_value)
	if typeid != expect_type_id:
		DLogger.error(
			"Incompatible parameter type ({2}):\nExpected: {0}, Actual: {1}",
			[type_string(expect_type_id), type_string(typeid), param_name],
			CAT,
			context
		)


# ------------- [Private Method] -------------
@abstract func get_sc_info() -> SCInfo


func _make_zero(type: int) -> Variant:
	return type_convert(null, type)


func _get_best_context_state() -> StateChartState:
	if not _context_state_stack.is_empty():
		var last: StateChartState = _context_state_stack.back()
		if is_instance_valid(last) and last.active:
			var deeper := _find_deepest_active_state(last)
			if deeper:
				return deeper
			return last
	return _find_deepest_active_state(_state)


func _find_deepest_active_state(node: Node) -> StateChartState:
	if not node is StateChartState or not node.active:
		return null

	var deepest: StateChartState = node
	for child in node.get_children():
		if child is StateChartState and child.active:
			var d := _find_deepest_active_state(child)
			if d:
				deepest = d
				break
	return deepest


func _connect_state_signals_early(node: Node) -> void:
	for child in node.get_children():
		if child is StateChartState:
			if not _is_method_connected(child.state_entered, _on_state_entered_context):
				child.state_entered.connect(_on_state_entered_context.bind(child))

			# Connect onentry dispatcher
			if not _is_method_connected(child.state_entered, _on_state_entered_actions):
				child.state_entered.connect(_on_state_entered_actions.bind(child))

		_connect_state_signals_early(child)


func _connect_state_signals_late(node: Node) -> void:
	for child in node.get_children():
		if child is StateChartState:
			if not _is_method_connected(child.state_exited, _on_state_exited_cleanup):
				child.state_exited.connect(_on_state_exited_cleanup.bind(child))

			# Connect onexit dispatcher
			if not _is_method_connected(child.state_exited, _on_state_exited_actions):
				child.state_exited.connect(_on_state_exited_actions.bind(child))

		_connect_state_signals_late(child)


func _is_method_connected(sig: Signal, method: Callable) -> bool:
	for conn in sig.get_connections():
		var c: Callable = conn["callable"]
		if c.get_object() == self and c.get_method() == method.get_method():
			return true
	return false


func _update_debug_log_connections(node: Node) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	for child in node.get_children():
		if child is StateChartState:
			_update_state_signal(child, child.state_entered, _on_state_entered)
			_update_state_signal(child, child.state_exited, _on_state_exited)
		_update_debug_log_connections(child)


func _update_state_signal(state: Node, sig: Signal, method: Callable) -> void:
	var found_conn: Callable
	for conn in sig.get_connections():
		var c: Callable = conn["callable"]
		if c.get_object() == self and c.get_method() == method.get_method():
			found_conn = c
			break

	if debug_log:
		if found_conn.is_null():
			sig.connect(method.bind(state))
	else:
		if not found_conn.is_null():
			sig.disconnect(found_conn)


func _update_debug_event_connection() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var is_con := event_received.is_connected(_on_event_received)
	if debug_event:
		if not is_con:
			event_received.connect(_on_event_received)
	else:
		if is_con:
			event_received.disconnect(_on_event_received)


func _check_unused_events(
	warnings: PackedStringArray, event: Dictionary[String, EntBase], exclude_ev: PackedStringArray
) -> void:
	var using_event := _collect_using_event()
	var unused_event := event.keys()
	for ev_name in using_event:
		unused_event.erase(ev_name)
	for ev_name in exclude_ev:
		unused_event.erase(ev_name)
	if unused_event.size() > 0:
		warnings.append("unused event(s):\n" + ", ".join(unused_event))


func _collect_using_event() -> PackedStringArray:
	var using_set: Dictionary[String, bool] = {}
	_collect_using_event_internal(using_set, self)
	var using_ev_str: PackedStringArray = []
	for event_name in using_set:
		using_ev_str.append(event_name)
	return using_ev_str


func _collect_using_event_internal(dst: Dictionary[String, bool], node: Node) -> void:
	for c in node.get_children():
		if c is Transition and not c.event.is_empty():
			dst[c.event] = true
		else:
			_collect_using_event_internal(dst, c)


func _check_param(dst: PackedStringArray, param_def: Dictionary[String, int]) -> void:
	_check_param_internal(dst, self, "", param_def)


func _check_param_internal(
	dst: PackedStringArray, node: Node, path: String, param_def: Dictionary[String, int]
) -> void:
	for c in node.get_children():
		var child_path := path + PATH_SEPARATOR + c.name
		if c is Transition:
			var g_a := _find_expression_guard(dst, child_path, c.guard)
			for g in g_a:
				_check_expression(dst, child_path, g.expression, param_def)
		else:
			_check_param_internal(dst, c, child_path, param_def)


func _check_expression(
	dst: PackedStringArray, path: String, exp_str: String, param_def: Dictionary[String, int]
) -> void:
	var params: PackedStringArray = []
	for k in param_def.keys():
		params.append(k)

	var expr := Expression.new()
	if expr.parse(exp_str, params) != OK:
		dst.append("Expression parse error: {1}\n at [{0}]".format([path, expr.get_error_text()]))
		return

	var inputs: Array = []
	for k in param_def.keys():
		inputs.append(_make_zero(param_def[k]))

	expr.execute(inputs, self)
	if expr.has_execute_failed():
		dst.append(
			"Expression execution error: {1}\n at [{0}]".format([path, expr.get_error_text()])
		)


func _check_event_typo(
	err_msg: PackedStringArray, events: Dictionary[String, EntBase], exclude_ev: PackedStringArray
) -> void:
	_check_event_typo_internal(err_msg, self, "", events, exclude_ev)


func _check_event_typo_internal(
	err_msg: PackedStringArray,
	node: Node,
	path: String,
	events: Dictionary[String, EntBase],
	exclude_ev: PackedStringArray
) -> void:
	for c in node.get_children():
		var child_path := path + PATH_SEPARATOR + c.name
		if c is Transition:
			if not c.event.is_empty() and c.event not in events and c.event not in exclude_ev:
				err_msg.append("Unknown event: {1}\n at [{0}]".format([child_path, c.event]))
		else:
			_check_event_typo_internal(err_msg, c, child_path, events, exclude_ev)


func _find_expression_guard(
	warnings: PackedStringArray, path: String, g: Guard
) -> Array[ExpressionGuard]:
	if g is ExpressionGuard:
		return [g]
	if g is NotGuard:
		return _find_expression_guard(warnings, path, g.guard)
	if g is AllOfGuard or g is AnyOfGuard:
		if g.guards.is_empty():
			warnings.append("no guards inside\nat:{0}".format([path]))
		else:
			var ret: Array[ExpressionGuard] = []
			for gc in g.guards:
				ret.append_array(_find_expression_guard(warnings, path, gc))
			return ret
	return []


func _update_exclusion_list(list: Array[StringName], ev_name: StringName, enabled: bool) -> void:
	if enabled:
		if ev_name not in list:
			list.append(ev_name)
	else:
		list.erase(ev_name)


func _update_all_warnings(node: Node) -> void:
	if node.has_method("update_configuration_warnings"):
		node.update_configuration_warnings()
	for child in node.get_children():
		_update_all_warnings(child)


func _collect_nodes_recursive(node: Node, list: Array[Node]) -> void:
	list.append(node)
	for child in node.get_children():
		_collect_nodes_recursive(child, list)


# ------------- [Public Method] -------------
## Re-establishes internal signal connections for the entire state machine.
## Useful after importing SCXML or manually modifying the node tree.
func connect_internal_signals() -> void:
	_connect_state_signals_early(self)
	_connect_state_signals_late(self)
	_update_debug_log_connections(self)
	_update_debug_event_connection()


## Resets the internal state of the state chart.
## Useful before re-importing SCXML or when completely restarting the state machine.
func reset_internal_state() -> void:
	_any_state_entered = false
	_context_state_stack.clear()
	_state_local_params.clear()


## Re-imports the SCXML from the path stored in metadata.
func reimport_scxml() -> void:
	if not Engine.is_editor_hint():
		return
	var path := str(get_meta(SCXML_PATH_META_KEY, ""))
	if path.is_empty():
		DLogger.warn("No SCXML path stored in metadata.", [], CAT, self)
		return
	var importer := StateChartScxmlImporter.new()
	importer.import_scxml(path, self)


## Manually check for configuration warnings.
func check_errors() -> void:
	if Engine.is_editor_hint():
		DLogger.info("Checking configuration warnings...", [], CAT, self)
	_entries_cache.clear()
	_update_all_warnings(self)
	notify_property_list_changed()


## Clears all metadata from this node and all of its descendants.
## Supports undo/redo if called within the Godot editor.
func clear_all_metadata() -> void:
	var nodes: Array[Node] = []
	_collect_nodes_recursive(self, nodes)

	var cleared_count := 0
	if Engine.is_editor_hint():
		var ei: Object = Engine.get_singleton("EditorInterface")
		if ei:
			var ur: Object = ei.get_editor_undo_redo()
			if ur:
				ur.create_action("Clear All StateChartExt Metadata")
				for node in nodes:
					for meta_key in node.get_meta_list():
						var val = node.get_meta(meta_key)
						ur.add_do_method(node, "remove_meta", meta_key)
						ur.add_undo_method(node, "set_meta", meta_key, val)
						cleared_count += 1
				ur.commit_action()

				if cleared_count > 0:
					DLogger.info(
						"Cleared {0} metadata entries across {1} nodes.",
						[cleared_count, nodes.size()],
						CAT,
						self
					)
				else:
					DLogger.info("No metadata entries found to clear.", [], CAT, self)
				return

	# Fallback for runtime execution or when editor undo/redo is not available
	for node in nodes:
		for meta_key in node.get_meta_list():
			node.remove_meta(meta_key)
			cleared_count += 1

	if cleared_count > 0:
		DLogger.info(
			"Cleared {0} metadata entries across {1} nodes.",
			[cleared_count, nodes.size()],
			CAT,
			self
		)
	else:
		DLogger.info("No metadata entries found to clear.", [], CAT, self)


## Function to use instead of set_expression_property when setting parameters.
func set_expression_property_ext(
	param_ent: ParamEnt, value: Variant, suppress_notify := false
) -> void:
	var param_name := param_ent.name
	_check_parameter_type(param_ent.name, param_ent.type_id, value, self)
	var prev: Variant = get_expression_property_ext(param_ent, _s_none_value)

	if debug_log:
		var prev_str := "None" if prev is NoneValue else str(prev)
		DLogger.debug("Param '{0}' changed: {1} -> {2}", [param_name, prev_str, value], CAT, self)

	var can_call_base := is_instance_valid(_state)

	if not suppress_notify:
		if can_call_base:
			super.set_expression_property(param_ent.name, value)
		else:
			_expression_properties[param_ent.name] = value

		var ntf_ar := param_ent.notify
		for ntf in ntf_ar:
			var should_call: bool = (prev is NoneValue) or ntf.checker.call(prev, value)
			if should_call:
				send_event_ext(ntf.event)
	else:
		if can_call_base:
			super.set_expression_property(param_name, value)
		else:
			_expression_properties[param_name] = value


## Sets a parameter that is automatically removed when leaving the specified state.
func set_expression_property_local(
	param_ent: ParamEnt, value: Variant, state: StateChartState = null, suppress_notify := false
) -> void:
	var target_state := state
	if target_state == null:
		target_state = _get_best_context_state()

	if target_state == null:
		if Engine.is_editor_hint():
			# In editor, just set it as normal property if no state context
			set_expression_property_ext(param_ent, value, suppress_notify)
			return

		DLogger.error(
			"set_expression_property_local: No active state context. {0}",
			[param_ent.name],
			CAT,
			self
		)
		return

	if not _state_local_params.has(target_state):
		_state_local_params[target_state] = []
	if param_ent not in _state_local_params[target_state]:
		_state_local_params[target_state].append(param_ent)

	set_expression_property_ext(param_ent, value, suppress_notify)


## Get a proxy for operating local parameters tied to a specific state.
func local(state: StateChartState = null) -> StateChartLocalProxy:
	var target_state := state
	if target_state == null:
		target_state = _get_best_context_state()
	return StateChartLocalProxy.new(self, target_state)


## Function to use instead of get_expression_property when getting parameters.
func get_expression_property_ext(param_ent: ParamEnt, default_val: Variant = null) -> Variant:
	return super.get_expression_property(param_ent.name, default_val)


## Function to use instead of send_event when dispatching events.
func send_event_ext(event_ent: EventEnt) -> void:
	if not _any_state_entered:
		DLogger.warn(
			"Event '{0}' sent before any state was entered. This event will likely be lost",
			[event_ent.name],
			CAT,
			self
		)
	if is_instance_valid(_state):
		super.send_event(event_ent.name)


func set_expression_property(value_name: StringName, value: Variant) -> void:
	assert(
		false,
		"set_expression_property({0}, {1}) called. Use the _ext version instead.".format(
			[value_name, value]
		)
	)


func get_expression_property(value_name: StringName, default_val: Variant = null) -> Variant:
	assert(
		false,
		"get_expression_property({0}, {1}) called. Use the _ext version instead.".format(
			[value_name, default_val]
		)
	)
	return null


func send_event(event: StringName) -> void:
	assert(false, "send_event({0}) called. Use the _ext version instead.".format([event]))
