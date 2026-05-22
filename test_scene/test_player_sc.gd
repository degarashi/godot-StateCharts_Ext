# [StateChartExt] Generated boilerplate. Do not edit manually.
@tool
class_name TestPlayerSC extends StateChartExt

var e: GEventProxy
var p: GParamProxy

class Event:
	extends StateChartExt.Event
	## Start moving the player.
	static var move := e()
	static var stop := e()
	static var health_changed := e()

class Param:
	extends StateChartExt.Param
	## Health with initial value.
	## Automatically triggers health_changed on change.
	static var health := p(TYPE_FLOAT, {TestPlayerSC.Event.health_changed: true}, 100.0, &"")
	## Movement speed, only exists in Move state.
	static var speed := p(TYPE_FLOAT, {}, 5.0, &"Move")

class GEventProxy extends StateChartExt.EventProxy:
	func has(name: String) -> bool: return name in ["move", "stop", "health_changed"]
	func move() -> void: _sc.send_event_ext(TestPlayerSC.Event.move)
	func stop() -> void: _sc.send_event_ext(TestPlayerSC.Event.stop)
	func health_changed() -> void: _sc.send_event_ext(TestPlayerSC.Event.health_changed)

class GParamProxy extends StateChartExt.ParamProxy:
	func has(name: String) -> bool:
		if not name in ["health", "speed"]: return false
		return _sc._expression_properties.has(name)

	var health: float:
		get: return _sc.get_expression_property_ext(TestPlayerSC.Param.health, _sc._make_zero(TYPE_FLOAT))
		set(v): _sc.set_expression_property_ext(TestPlayerSC.Param.health, v)
	var speed: float:
		get: return _sc.get_expression_property_ext(TestPlayerSC.Param.speed, _sc._make_zero(TYPE_FLOAT))
		set(v): _sc.set_expression_property_ext(TestPlayerSC.Param.speed, v)

func _init() -> void:
	e = GEventProxy.new(self)
	p = GParamProxy.new(self)

# [Override]
func get_sc_info() -> SCInfo:
	return SCInfo.new(Param, Event)