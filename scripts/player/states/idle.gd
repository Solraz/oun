extends PlayerState

func enter(_msg := {}) -> void:
  pass

func handle_input(event: InputEvent) -> void:
  if event is InputEventKey:
    if event.is_action("move_left") or event.is_action("move_right") or event.is_action("move_up") or event.is_action("move_down"):
      state_machine.transition_to("run")
    if event.is_action("jump"):
      if (stats.can_jump):
        state_machine.transition_to("air", {jump = 1})

func physics_update(delta: float) -> void:
  stats.speed_vector = stats.speed_vector.lerp(Vector3.ZERO, delta * stats.friction)
