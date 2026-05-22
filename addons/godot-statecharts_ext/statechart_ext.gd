@icon("statechart_ext.svg")
@tool
## [StateChartExt]
## Extends StateChart to provide statically typed parameter management,
## event dispatching, and editor-side validation.
@abstract class_name StateChartExt
extends StateChart

# ==============================================================================
# [Proxy Classes Explanation and Usage Examples]
#
# This script uses "proxy objects" to supplement Godot's dynamic typing nature,
# making StateChart parameter operations and event dispatching safer and more comfortable.
#
# EventProxy (variable e)
#    - Proxy for event dispatching. You can dispatch events (send_event_ext)
#      intuitively as if calling a function with the defined event name.
#      [Example]:
#          _st.e.jump()            # Sends the 'jump' event
#          _st.e.crouch()          # Sends the 'crouch' event
#
# ParamProxy (variable p)
#    - Proxy for global parameter operations. Accessing properties directly
#      transparently executes parameter operations (_ext functions) with
#      internal type checks and automatic event notifications.
#      [Example]:
#          _st.p.health = 100.0    # Automatically triggers 'health_changed' event
#          if _st.p.ammo <= 0:     # Intuitively get and compare parameter values
#              _st.e.reload()
# ==============================================================================

# ------------- [Constants] -------------
const CAT := "state_chart"


class NoneValue:
	pass


# ------------- [Static Variable] -------------
static var _s_none_value := NoneValue.new()


## Class enumerating EntBase (Base class)
class SCInfoBase:
	const SCINFO_BASE = 0

	## Check if the script inherits from SCInfoBase
	static func is_infobase(s: Script) -> bool:
		return "SCINFO_BASE" in s.get_script_constant_map()


## Inherit this when users define Parameters
class Param:
	extends SCInfoBase

	## Helper to simplify Parameter definition
	static func p(
		typ: int,
		notify_map: Dictionary = {},
		init_val: Variant = StateChartExt._s_none_value,
		loc_state: StringName = &""
	) -> ParamEnt:
		return ParamEnt.new(typ, notify_map, init_val, loc_state)


## Inherit this when users define Events
class Event:
	extends SCInfoBase

	## Helper to simplify Event definition
	static func e() -> EventEnt:
		return EventEnt.new()


## Base class for a single entry of Event or Param
class EntBase:
	var name: StringName


## A single Event entry
class EventEnt:
	extends EntBase
	const ENT_TYPE = "EVENT"


## A single Param entry
class ParamEnt:
	extends EntBase
	const ENT_TYPE = "PARAM"
	var type_id: int
	var notify: Array[NotifyEnt]
	var initial_value: Variant
	var local_state: StringName

	func _init(
		typ: int,
		notify_map: Dictionary = {},
		init_val: Variant = StateChartExt._s_none_value,
		loc_state: StringName = &""
	):
		type_id = typ
		initial_value = init_val
		local_state = loc_state

		notify = []
		# [EventEnt] -> (bool | Callable)
		for ev_ent in notify_map:
			notify.append(NotifyEnt.new(ev_ent, notify_map[ev_ent]))


## For describing Param Notify items
class NotifyEnt:
	extends EntBase
	const ENT_TYPE = "NOTIFY"
	## Event to monitor
	var event: EventEnt
	## Notification determination function
	## (func(prev,current) -> bool)
	var checker: Callable

	## (checker_a = Callable[[prev, current], bool] | bool)
	func _init(event_a: EventEnt, checker_a: Variant):
		assert(is_instance_valid(event_a), "event_a must be a valid instance")
		event = event_a
		# Default: always send event
		checker = func(_prev: Variant, _current: Variant) -> bool: return true
		if checker_a is bool:
			if checker_a:
				# Send event only when value changes
				checker = func(prev: Variant, current: Variant) -> bool: return prev != current
		else:
			# Custom check function
			checker = checker_a


## Enumeration of StateChart's Parameters + Events
class SCInfo:
	var param: Script  # (class Param)
	var event: Script  # (class Event)

	func _init(param_a: Script, event_a: Script):
		param = param_a
		event = event_a


# ------------- [Static Variable] -------------
## Cache for entries (ParamEnt/EventEnt) per Script
## [Script] -> [EntryTypeName] -> Dictionary[String, EntBase]
static var _entries_cache: Dictionary = {}

# ------------- [Exports] -------------
## Whether to output state transition logs
@export var debug_log: bool = false:
	set(value):
		debug_log = value
		_update_debug_log_connections(self)

## Whether to output event reception logs
@export var debug_event: bool = false:
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

@export_tool_button("Check errors", "Callable") var check_errors_btn: Callable = check_errors

# ------------- [Public Variable] -------------
# Proxies (e, p) are handled via _get/_set to allow subclass shadowing for static types.

# ------------- [Private Variable] -------------
## Whether at least one state has been entered
var _any_state_entered: bool = false
## Currently active states (supports nesting)
var _context_state_stack: Array[StateChartState] = []
## Local parameters managed per state
## [StateChartState] -> Array[ParamEnt]
var _state_local_params: Dictionary = {}

## Internal storage for dynamic proxies (when not shadowed by subclass)
var _e_dyn: EventProxy
var _p_dyn: ParamProxy


# ------------- [Callbacks] -------------
func _get(property: StringName) -> Variant:
	if property == &"e":
		return _e_dyn
	if property == &"p":
		return _p_dyn
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"e":
		_e_dyn = value
		return true
	if property == &"p":
		_p_dyn = value
		return true
	return false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return

	# Connect state_entered as early as possible in _enter_tree
	_connect_state_signals_early(self)


func _ready() -> void:
	super()

	if Engine.is_editor_hint():
		return

	# Generate proxies safely only during game execution
	var sc_info := get_sc_info()
	if sc_info != null:
		# Always initialize entries to ensure internal name resolution works
		var params := _init_and_get_entries(sc_info.param, ParamEnt)
		_init_and_get_entries(sc_info.event, EventEnt)

		# Set initial values for non-local parameters
		for p_name in params:
			var ent := params[p_name] as ParamEnt
			if ent.local_state.is_empty() and not ent.initial_value is NoneValue:
				set_expression_property_ext(ent, ent.initial_value, true)

		# Only create dynamic proxies if they haven't been set by a subclass (via member or _init)
		if get(&"e") == null:
			set(&"e", DynamicEventProxy.new(self, sc_info.event))
		if get(&"p") == null:
			set(&"p", DynamicParamProxy.new(self, sc_info.param))

	# Connect state_exited as late as possible in _ready
	_connect_state_signals_late(self)

	_update_debug_log_connections(self)
	_update_debug_event_connection()

	if debug_log:
		DLogger.debug("Initialized", [], CAT, self)

	if OS.is_debug_build():
		_valid_event_names.append_array(exclude_warn_unknown_events)


func _connect_state_signals_early(node: Node) -> void:
	for child in node.get_children():
		if child is StateChartState:
			if not _is_method_connected(child.state_entered, _on_state_entered_context):
				child.state_entered.connect(_on_state_entered_context.bind(child))

		_connect_state_signals_early(child)


func _connect_state_signals_late(node: Node) -> void:
	for child in node.get_children():
		if child is StateChartState:
			if not _is_method_connected(child.state_exited, _on_state_exited_cleanup):
				child.state_exited.connect(_on_state_exited_cleanup.bind(child))

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
	# Find existing connection (including bound ones)
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


func _on_state_entered(state: Node) -> void:
	DLogger.debug("State entered (Post): {0}", [state.name], CAT, self)


func _on_state_exited(state: Node) -> void:
	DLogger.debug("State exited (Post): {0}", [state.name], CAT, self)


func _on_state_entered_context(state: StateChartState) -> void:
	_any_state_entered = true
	if state not in _context_state_stack:
		_context_state_stack.append(state)

	# Check for automatic local parameters
	var sc_info := get_sc_info()
	if sc_info != null:
		var params := _init_and_get_entries(sc_info.param, ParamEnt)
		for p_name in params:
			var ent := params[p_name] as ParamEnt
			if ent.local_state == state.name:
				var init_val = ent.initial_value
				if init_val is NoneValue:
					init_val = _make_zero(ent.type_id)
				set_expression_property_local(ent, init_val, state, true)


func _on_state_exited_cleanup(state: StateChartState) -> void:
	_context_state_stack.erase(state)
	# Cleanup local parameters
	if state in _state_local_params:
		var params: Array = _state_local_params[state]
		for param_ent in params:
			# Directly manipulate and remove (or reset to initial value) variables inside StateChart
			if _expression_properties.has(param_ent.name):
				if initial_expression_properties.has(param_ent.name):
					_expression_properties[param_ent.name] = initial_expression_properties[
						param_ent.name
					]
				else:
					_expression_properties.erase(param_ent.name)
				_property_change_pending = true

		# Unregister
		_state_local_params.erase(state)

		# Apply property changes if any
		if _property_change_pending and not _locked_down:
			_run_changes()


func _on_event_received(event: StringName) -> void:
	DLogger.debug("Event received: {0}", [event], CAT, self)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	var sc_info := get_sc_info()

	# --- Param checks ---
	# Typo check
	var params_m := gather_params_id(sc_info.param)
	if not params_m.is_empty():
		_check_param(warnings, params_m)

	# --- Event checks ---
	var event := _init_and_get_entries(sc_info.event, EventEnt)
	# Check if event names exist
	var invalid_ev: PackedStringArray = []
	var exclude_ev: PackedStringArray = []
	# --- Check for unused event exceptions ---
	var chk_events_exist := func(src: Array[StringName]) -> void:
		for ev_name in src:
			if ev_name not in event:
				# Non-existent event name specified as an exception
				invalid_ev.append(ev_name)
			else:
				exclude_ev.append(ev_name)

	chk_events_exist.call(exclude_unused_event)
	chk_events_exist.call(exclude_warn_unknown_events)

	if not invalid_ev.is_empty():
		var err_str: String = "invalid event name (exclude):\n"
		err_str += ", ".join(invalid_ev)
		warnings.append(err_str)
	# ------
	if not event.is_empty():
		# Check for typos in events described in Transition event fields
		_check_event_typo(warnings, event)
		# Check for unused events
		_check_unused_events(warnings, event, exclude_ev)

	# Include parent's warnings
	warnings.append_array(super())
	return warnings


# ------------- [Private Static Method] -------------
static func is_instance_of_entry(ent: EntBase, target: Script) -> bool:
	if not is_instance_valid(ent):
		return false
	# We check if the script of the instance is exactly the target or a child of it
	var s := (ent as Object).get_script() as Script
	while s != null:
		if s == target:
			return true
		s = s.get_base_script()
	return false


## Collect entries (ParamEnt/EventEnt) within SCInfoBase, including parent classes.
## As a side effect, assigns the variable name to the name property of each entry.
## (source = User-defined Event/Param class)
## (entry_target = EventEnt/ParamEnt class)
static func _init_and_get_entries(
	source: Script, entry_target: Script
) -> Dictionary[String, EntBase]:
	var target_type_name: String = entry_target.ENT_TYPE
	# Check cache
	if _entries_cache.has(source):
		if _entries_cache[source].has(target_type_name):
			return _entries_cache[source][target_type_name]
	else:
		_entries_cache[source] = {}

	var ret: Dictionary[String, EntBase] = {}
	var current_script := source

	while true:
		# Check constants (sometimes e() / p() calls in static var result in constants or entries)
		var constants := current_script.get_script_constant_map()
		for c_name in constants:
			var val = constants[c_name]
			if val is EntBase and is_instance_of_entry(val, entry_target):
				val.name = c_name
				ret[c_name] = val

		# Check all properties (get_property_list on the script object itself)
		for m in current_script.get_property_list():
			# Skip obvious internal things
			if m.name in ["script", "Built-in Script", "RefCounted", "Resource"]:
				continue

			var val = current_script.get(m.name)
			if val is EntBase:
				if is_instance_of_entry(val, entry_target):
					val.name = m.name
					ret[m.name] = val

		# Check parent class
		current_script = current_script.get_base_script()
		if current_script == null or SCInfoBase.is_infobase(current_script):
			break

	_entries_cache[source][target_type_name] = ret
	return ret


# [param_name] -> param_type
static func gather_params_id(source: Script) -> Dictionary[String, int]:
	# Collect Param with _init_and_get_entries and keep only TypeId
	var params_m: Dictionary[String, int] = {}
	var params := _init_and_get_entries(source, ParamEnt)
	for key in params:
		params_m[key] = (params[key] as ParamEnt).type_id
	return params_m


static func _check_parameter_type(
	param_name: String, expect_type_id: int, actual_value: Variant, context: Object
) -> void:
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


## Create initial value according to Type ID
func _make_zero(type: int) -> Variant:
	return type_convert(null, type)


## Get the most suitable state as the current execution context
func _get_best_context_state() -> StateChartState:
	# Prioritize the last (latest) in stack if it's active
	if not _context_state_stack.is_empty():
		var last: StateChartState = _context_state_stack.back()
		if is_instance_valid(last) and last.active:
			# Look for a deeper active child state
			# (Measure against signal handlers not yet executed)
			var deeper := _find_deepest_active_state(last)
			if deeper:
				return deeper
			return last

	# Search from root if stack is empty or invalid
	return _find_deepest_active_state(_state)


## Search for the deepest active state under the specified node
func _find_deepest_active_state(node: Node) -> StateChartState:
	if not node is StateChartState or not node.active:
		return null

	var deepest: StateChartState = node
	for child in node.get_children():
		if child is StateChartState and child.active:
			var d := _find_deepest_active_state(child)
			if d:
				deepest = d
				# One is enough if it's a CompoundState
				break
	return deepest


func _check_unused_events(
	warnings: PackedStringArray, event: Dictionary[String, EntBase], exclude_ev: PackedStringArray
) -> void:
	var using_event := _collect_using_event()
	var unused_event := event.keys()
	# Remove actually used EventNames from the registered Event list
	for ev_name in using_event:
		unused_event.erase(ev_name)
	# Also remove events specified as exceptions
	for ev_name in exclude_ev:
		unused_event.erase(ev_name)

	if unused_event.size() > 0:
		warnings.append("unused event(s):\n" + ", ".join(unused_event))


func _collect_using_event() -> PackedStringArray:
	# bool value has no special meaning, used as a set
	var using_set: Dictionary[String, bool] = {}
	_collect_using_event_internal(using_set, self)
	# Format set -> PackedStringArray and return
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
	# Find Transition in child nodes, then find ExpressionGuard there
	_check_param_internal(dst, self, "", param_def)


func _check_param_internal(
	dst: PackedStringArray, node: Node, path: String, param_def: Dictionary[String, int]
):
	for c in node.get_children():
		var child_path := path + "/" + c.name
		if c is Transition:
			var g_a := _find_expression_guard(dst, child_path, c.guard)
			for g in g_a:
				_check_expression(dst, child_path, g.expression, param_def)
		else:
			_check_param_internal(dst, c, child_path, param_def)


func _check_expression(
	dst: PackedStringArray, path: String, exp_str: String, param_def: Dictionary[String, int]
) -> void:
	var params: Array[StringName] = []
	for k in param_def.keys():
		params.append(k)

	var expr := Expression.new()
	if expr.parse(exp_str, params) != OK:
		dst.append("Expression parse error: {1}\n at [{0}]".format([path, expr.get_error_text()]))

	# Prepare some appropriate value according to the type
	var dummy_arg: Array[Variant] = []
	for param_name in params:
		dummy_arg.append(_make_zero(param_def.get(param_name)))
	expr.execute(dummy_arg)
	if expr.has_execute_failed():
		dst.append(
			'Expression execution failed:\n"{1}"\n{2}\n at [{0}]'.format(
				[path, exp_str, expr.get_error_text()]
			)
		)


func _check_event_typo(err_msg: PackedStringArray, events: Dictionary[String, EntBase]) -> void:
	# Find Transition in child nodes and check if the described event matches the list
	_check_event_typo_internal(err_msg, self, "", events)


func _check_event_typo_internal(
	err_msg: PackedStringArray, node: Node, path: String, events: Dictionary[String, EntBase]
):
	for c in node.get_children():
		var child_path := path + "/" + c.name
		if c is Transition:
			if not c.event.is_empty() and c.event not in events:
				err_msg.append("Unknown event: {1}\n at [{0}]".format([child_path, c.event]))
		else:
			_check_event_typo_internal(err_msg, c, child_path, events)


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


# ------------- [Public Method] -------------
## Manually check for errors
func check_errors() -> void:
	if Engine.is_editor_hint():
		DLogger.info("Checking configuration warnings...", [], CAT, self)

	# Clear cache to reflect script changes
	_entries_cache.clear()

	# Update warnings for self and all descendant states/transitions
	_update_all_warnings(self)

	# Encourage updating of editor inspector and scene tree displays
	notify_property_list_changed()


func _update_all_warnings(node: Node) -> void:
	if node.has_method("update_configuration_warnings"):
		node.update_configuration_warnings()

	for child in node.get_children():
		_update_all_warnings(child)


## Function to use instead of set_expression_property when setting parameters
func set_expression_property_ext(
	param_ent: ParamEnt, value: Variant, suppress_notify: bool = false
) -> void:
	var param_name := param_ent.name
	# Type check for parameter
	_check_parameter_type(param_ent.name, param_ent.type_id, value, self)

	var prev = get_expression_property_ext(param_ent, _s_none_value)

	if debug_log:
		var prev_str := "None" if prev is NoneValue else str(prev)
		DLogger.debug("Param '{0}' changed: {1} -> {2}", [param_name, prev_str, value], CAT, self)

	# Process to fire event simultaneously with parameter setting
	if not suppress_notify:
		super.set_expression_property(param_ent.name, value)

		# List of events that should be issued when this parameter is set
		var ntf_ar := param_ent.notify
		for ntf in ntf_ar:
			var should_call: bool = (prev is NoneValue) or ntf.checker.call(prev, value)
			if should_call:
				send_event_ext(ntf.event)
	else:
		super.set_expression_property(param_name, value)


## Sets a parameter that is automatically removed when leaving the specified state.
## If state is null, the current active context is used.
func set_expression_property_local(
	param_ent: ParamEnt,
	value: Variant,
	state: StateChartState = null,
	suppress_notify: bool = false
) -> void:
	var target_state := state
	if target_state == null:
		target_state = _get_best_context_state()

	if target_state == null:
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


## Get a proxy for operating local parameters tied to a specific state
func local(state: StateChartState = null) -> StateChartLocalProxy:
	var target_state := state
	if target_state == null:
		target_state = _get_best_context_state()
	return StateChartLocalProxy.new(self, target_state)


## Function to use instead of get_expression_property when getting parameters
func get_expression_property_ext(param_ent: ParamEnt, default_val: Variant = null) -> Variant:
	return super.get_expression_property(param_ent.name, default_val)


## Function to use instead of send_event when dispatching events
func send_event_ext(event_ent: EventEnt) -> void:
	if not _any_state_entered:
		DLogger.warn(
			"Event '{0}' sent before any state was entered. This event will likely be lost",
			[event_ent.name],
			CAT,
			self
		)
	super.send_event(event_ent.name)


# ------------- [Override] -------------
# Overridden to disable to prevent users from calling by mistake
func set_expression_property(value_name: StringName, value: Variant) -> void:
	assert(
		false,
		"set_expression_property({0}, {1}) called. Use the _ext version instead.".format(
			[value_name, value]
		)
	)


# Overridden to disable to prevent users from calling by mistake
func get_expression_property(value_name: StringName, default_val: Variant = null) -> Variant:
	assert(
		false,
		"get_expression_property({0}, {1}) called. Use the _ext version instead.".format(
			[value_name, default_val]
		)
	)
	return null


# Overridden to disable to prevent users from calling by mistake
func send_event(event: StringName) -> void:
	assert(false, "send_event({0}) called. Use the _ext version instead.".format([event]))


## Proxy for performing parameter operations scoped to a specific state
class StateChartLocalProxy:
	var _sc: StateChartExt
	var _state: StateChartState

	func _init(sc: StateChartExt, state: StateChartState) -> void:
		_sc = sc
		_state = state

	## Sets a local parameter
	func set_param(
		param_ent: ParamEnt, value: Variant, suppress_notify: bool = false
	) -> StateChartLocalProxy:
		_sc.set_expression_property_local(param_ent, value, _state, suppress_notify)
		return self

	## Dispatches an event
	func send_event(event_ent: EventEnt) -> StateChartLocalProxy:
		_sc.send_event_ext(event_ent)
		return self


## Base class for event dispatching
class EventProxy:
	var _sc: StateChartExt

	func _init(sc: StateChartExt) -> void:
		_sc = sc

	## Returns true if the event exists
	func has(_event_name: String) -> bool:
		return false


## Proxy for event dispatching (dynamic)
class DynamicEventProxy:
	extends EventProxy
	var _cache: Dictionary[String, EntBase]

	func _init(sc: StateChartExt, event_script: Script) -> void:
		super(sc)
		_cache = StateChartExt._init_and_get_entries(event_script, EventEnt)

	## Returns true if the event exists in the cache
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


## Base class for parameter operations
class ParamProxy:
	var _sc: StateChartExt

	func _init(sc: StateChartExt) -> void:
		_sc = sc

	## Returns true if the parameter exists
	func has(_param_name: String) -> bool:
		return false


## Proxy for parameter operations (dynamic)
class DynamicParamProxy:
	extends ParamProxy
	var _cache: Dictionary[String, EntBase]

	func _init(sc: StateChartExt, param_script: Script) -> void:
		super(sc)
		_cache = StateChartExt._init_and_get_entries(param_script, ParamEnt)

	## Returns true if the parameter exists in the cache AND in the StateChart instance
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
