# [StateChartExt] Generated boilerplate. Do not edit manually.
@tool
class_name TestPlayerSC extends StateChartExt

var e: GEventProxy
var p: GParamProxy

class Event:
	extends StateChartExt.Event
	static var jump := e()
	static var land := e()
	static var attack := e()
	static var reload_done := e()
	static var stun := e()
	static var stun_end := e()
	static var die := e()
	static var respawn := e()
	static var health_changed := e()

class Param:
	extends StateChartExt.Param
	static var health := p(TYPE_FLOAT, {TestPlayerSC.Event.health_changed: true}, 100.0, &"")
	static var ammo := p(TYPE_INT, {}, 10, &"")
	static var is_invincible := p(TYPE_BOOL, {}, false, &"")
	static var speed := p(TYPE_FLOAT, {}, 5.0, &"")

class GEventProxy extends StateChartExt.EventProxy:
	func has(name: String) -> bool: return name in ["jump", "land", "attack", "reload_done", "stun", "stun_end", "die", "respawn", "health_changed"]
	func jump() -> void: _sc.send_event_ext(TestPlayerSC.Event.jump)
	func land() -> void: _sc.send_event_ext(TestPlayerSC.Event.land)
	func attack() -> void: _sc.send_event_ext(TestPlayerSC.Event.attack)
	func reload_done() -> void: _sc.send_event_ext(TestPlayerSC.Event.reload_done)
	func stun() -> void: _sc.send_event_ext(TestPlayerSC.Event.stun)
	func stun_end() -> void: _sc.send_event_ext(TestPlayerSC.Event.stun_end)
	func die() -> void: _sc.send_event_ext(TestPlayerSC.Event.die)
	func respawn() -> void: _sc.send_event_ext(TestPlayerSC.Event.respawn)
	func health_changed() -> void: _sc.send_event_ext(TestPlayerSC.Event.health_changed)

class GParamProxy extends StateChartExt.ParamProxy:
	func has(name: String) -> bool:
		if not name in ["health", "ammo", "is_invincible", "speed"]: return false
		return _sc._expression_properties.has(name)

	var health: float:
		get: return _sc.get_expression_property_ext(TestPlayerSC.Param.health, _sc._make_zero(TYPE_FLOAT))
		set(v): _sc.set_expression_property_ext(TestPlayerSC.Param.health, v)
	var ammo: int:
		get: return _sc.get_expression_property_ext(TestPlayerSC.Param.ammo, _sc._make_zero(TYPE_INT))
		set(v): _sc.set_expression_property_ext(TestPlayerSC.Param.ammo, v)
	var is_invincible: bool:
		get: return _sc.get_expression_property_ext(TestPlayerSC.Param.is_invincible, _sc._make_zero(TYPE_BOOL))
		set(v): _sc.set_expression_property_ext(TestPlayerSC.Param.is_invincible, v)
	var speed: float:
		get: return _sc.get_expression_property_ext(TestPlayerSC.Param.speed, _sc._make_zero(TYPE_FLOAT))
		set(v): _sc.set_expression_property_ext(TestPlayerSC.Param.speed, v)

func _init() -> void:
	e = GEventProxy.new(self)
	p = GParamProxy.new(self)

# [Override]
func get_sc_info() -> SCInfo:
	return SCInfo.new(Param, Event)