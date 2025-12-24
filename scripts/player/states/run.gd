extends PlayerState
@onready var movement : MovementSystem = %movement_system

func enter(_msg := {}) -> void:
	movement.idle_timer = Timer.new()
	entity.add_child(movement.idle_timer)
	movement.idle_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	movement.idle_timer.one_shot = true

	stats.max_speed_vector = Vector3(stats.speed, stats.gravity * stats.gravity_mult, stats.speed)


func exit() -> void:
	entity.remove_child(movement.idle_timer)


func handle_input(event: InputEvent) -> void:
	movement.handle_input(event)


func physics_update(delta: float) -> void:
	movement.physics_update(delta)
	check_for_stop()


func check_for_stop() -> void:
	if (movement.idle_timer.is_stopped()):
		movement.idle_timer.start(stats.idle_timer)

		await movement.idle_timer.timeout

		if (!movement.movements.left && !movement.movements.right && !movement.movements.up && !movement.movements.down):
			# stats.wish_vector = Vector3.ZERO
			pass
