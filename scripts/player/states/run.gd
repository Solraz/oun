extends PlayerState

var movements: Dictionary = {
  "left": false,
  "right": false,
  "up": false,
  "down": false
}
var idle_timer: Timer = Timer.new()

func enter(_msg := {}) -> void:
  player.add_child(idle_timer)
  print(idle_timer)
  idle_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
  idle_timer.one_shot = true

func exit() -> void:
  player.remove_child(idle_timer)
  # idle_timer.free()

func handle_input(event: InputEvent) -> void:
  if event is InputEventKey:
    if (event.is_action_pressed("move_left")):
      stats.wish_vector.x = -1.0
      movements.left = true
    if (event.is_action_pressed("move_right")):
      stats.wish_vector.x = 1.0
      movements.right = true
    if (event.is_action_pressed("move_up")):
      stats.wish_vector.z = -1.0
      movements.up = true
    if (event.is_action_pressed("move_down")):
      stats.wish_vector.z = 1.0
      movements.down = true
    if (event.is_action("jump")):
      if (stats.can_jump):
        state_machine.transition_to("air", {jump = 1})

  if (event.is_action_released("move_left")):
    movements.left = false
  if (event.is_action_released("move_right")):
    movements.right = false
  if (event.is_action_released("move_up")):
    movements.up = false
  if (event.is_action_released("move_down")):
    movements.down = false

func physics_update(_delta: float) -> void:
  if (stats.wish_vector != Vector3.ZERO):
    stats.speed_vector = stats.wish_vector * stats.speed
    check_for_stop()

  if (stats.speed_vector == Vector3.ZERO):
    state_machine.transition_to("idle")

func check_for_stop() -> void:
  if (idle_timer.is_stopped()):
    idle_timer.start(stats.idle_timer)
    await idle_timer.timeout
    if (!movements.left && !movements.right && !movements.up && !movements.down):
      stats.wish_vector = Vector3.ZERO
