# [StateChartExt] Generated boilerplate. Do not edit manually.
@tool
class_name TestPlayerSC extends StateChartExt

class Event:
	extends StateChartExt.Event
	## Start moving the player.
	## This triggers a transition to the Move state.
	static var move := e()
	## Stop moving
	static var stop := e()
	## Health has been updated
	static var health_changed := e()

class Param:
	extends StateChartExt.Param
	## Current health points
	static var health := p(TYPE_FLOAT, {TestPlayerSC.Event.health_changed: true})
	## Movement speed in pixels per second.
	## Default is usually 0.0.
	static var speed := p(TYPE_FLOAT)

# [Override]
func get_sc_info() -> SCInfo:
	return SCInfo.new(Param, Event)