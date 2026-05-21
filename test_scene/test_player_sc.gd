# [StateChartExt] Generated boilerplate. Do not edit manually.
@tool
class_name TestPlayerSC extends StateChartExt

class Event:
	extends StateChartExt.Event
	static var move := e()
	static var stop := e()
	static var health_changed := e()

class Param:
	extends StateChartExt.Param
	static var health := p(TYPE_FLOAT, {TestPlayerSC.Event.health_changed: true})
	static var speed := p(TYPE_FLOAT)

# [Override]
func get_sc_info() -> SCInfo:
	return SCInfo.new(Param, Event)