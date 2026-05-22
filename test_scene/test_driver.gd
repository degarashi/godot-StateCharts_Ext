extends Node2D

const CAT := "test"

@onready var sc: TestPlayerSC = %Player


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Wait a frame to ensure StateChart has initialized and entered the root state
	await get_tree().process_frame

	DLogger.info("--- Starting StateChartExt Comprehensive Test ---", [], CAT, self)

	# Check initial state
	DLogger.info("Initial health: {0}", [sc.p.health], CAT, self)
	DLogger.info("Initial ammo: {0}", [sc.p.ammo], CAT, self)

	sc.event_received.connect(
		func(ev_name): DLogger.info(">> Event received: {0}", [ev_name], CAT, self)
	)

	# Test Movement (OnGround -> Airborne -> OnGround)
	DLogger.info("Testing jump...", [], CAT, self)
	sc.e.jump.call()
	await get_tree().process_frame

	DLogger.info("Testing land...", [], CAT, self)
	sc.e.land.call()
	await get_tree().process_frame

	# Test Attack (Compound / Parallel / Guards)
	# Requirement: ammo > 0 && In('OnGround')
	DLogger.info("Testing attack (should succeed as ammo=10 and on ground)...", [], CAT, self)
	sc.e.attack.call()
	await get_tree().process_frame
	# Now in 'Reloading' (Weapon side) while 'OnGround' (Movement side)

	await get_tree().create_timer(1.1).timeout  # Wait for ReloadDone (1.0s delay)
	DLogger.info("Should be back to Ready now.", [], CAT, self)

	# Test Attack while Airborne (should fail due to guard)
	sc.e.jump.call()
	await get_tree().process_frame
	DLogger.info("Testing attack while jumping (should FAIL due to guard)...", [], CAT, self)
	sc.e.attack.call()
	await get_tree().process_frame
	sc.e.land.call()
	await get_tree().process_frame

	# Test Stun (Complex AllOfGuard: !is_invincible && health > 0)
	DLogger.info("Testing stun...", [], CAT, self)
	sc.e.stun.call()
	await get_tree().process_frame

	DLogger.info("Testing stun end...", [], CAT, self)
	sc.e.stun_end.call()
	await get_tree().process_frame

	# Test Die (NotGuard: !is_invincible)
	DLogger.info("Testing die...", [], CAT, self)
	sc.e.die.call()
	await get_tree().process_frame

	# Test Respawn
	DLogger.info("Testing respawn...", [], CAT, self)
	sc.e.respawn.call()
	await get_tree().process_frame

	DLogger.info("--- Comprehensive Test Finished ---", [], CAT, self)
	get_tree().quit()
