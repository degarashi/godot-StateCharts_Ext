extends Node2D

const CAT := "test"

@onready var sc: TestPlayerSC = %TestPlayerSC


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Wait a frame to ensure StateChart has initialized and entered the root state
	await get_tree().process_frame

	DLogger.info("--- Starting StateChartExt Test ---", [], CAT, self)

	# Test 0: Existence check before assignment
	DLogger.info("Health exists before set: {0}", [sc.p.has("health")], CAT, self)
	DLogger.info("Event 'health_changed' exists: {0}", [sc.e.has("health_changed")], CAT, self)

	# Test 1: Proxy Parameter Access
	sc.p.health = 100.0
	DLogger.info("Health exists after set: {0}", [sc.p.has("health")], CAT, self)
	DLogger.info("Initial health: {0}", [sc.p.health], CAT, self)

	# Test 2: Auto-event on parameter change
	sc.event_received.connect(
		func(ev_name): DLogger.info("Event received: {0}", [ev_name], CAT, self)
	)

	sc.p.health = 90.0  # Should trigger health_changed

	# Wait a bit for event processing
	await get_tree().process_frame

	# Test 3: Proxy Event Dispatch (Transition to Move)
	DLogger.info("Sending 'move' event via proxy...", [], CAT, self)
	sc.e.move.call()

	# Wait for transition
	await get_tree().process_frame

	# Test 4: Local parameters
	# (Now that we are in 'Move' state, we can test local params)
	DLogger.info("Local proxy test (Move state)...", [], CAT, self)
	sc.local().set_param(TestPlayerSC.Param.speed, 5.0)
	DLogger.info("Speed: {0}", [sc.p.speed], CAT, self)

	# Test 5: Transition back to Idle
	DLogger.info("Sending 'stop' event via proxy...", [], CAT, self)
	sc.e.stop.call()
	# Wait for transition
	await get_tree().process_frame
	DLogger.info("Back to Idle. Speed (local param) should be cleaned up.", [], CAT, self)

	# Note: In StateChartExt, local params are cleaned up on state exit.
	# Since speed is a local param in Move, it should be gone (or reset to default) now.
	if sc.p.has("speed"):
		print(sc)
		print(sc.p)
		print(sc.p.speed)
		DLogger.info("Current Speed: {0}", [sc.p.speed], CAT, self)
	else:
		DLogger.info("Current Speed: (not found)", [], CAT, self)

	DLogger.info("--- Test Finished ---", [], CAT, self)
