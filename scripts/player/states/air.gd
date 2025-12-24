extends PlayerState
@onready var movement : MovementSystem = %movement_system

func enter(msg := {}) -> void:	
	if (msg.has("jump")):
		movement.jump_timer = Timer.new()
		entity.add_child(movement.jump_timer)
		movement.jump_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
		movement.jump()
	
	stats.max_speed_vector = Vector3(stats.air_speed, stats.gravity * stats.gravity_mult, stats.air_speed)

	movement.add_gravity()

func handle_input(event: InputEvent) -> void:
	movement.handle_input(event)

func physics_update(delta: float) -> void:
	movement.physics_update(delta)

func exit() -> void:
	if (movement.jump_timer):
		entity.remove_child(movement.jump_timer)
		movement.jump_timer.free()
