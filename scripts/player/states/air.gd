extends PlayerState

var jump_timer: Timer = Timer.new()

func enter(msg := {}) -> void:
  if (msg.has("jump")):
    player.add_child(jump_timer)
    jump_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
    jump()

func exit() -> void:
  player.remove_child(jump_timer)
  jump_timer.free()

func physics_update(_delta: float) -> void:
  # stats.speed_vector.x = stats.speed_vector.x.lerp(0.0, delta * stats.air_friction)
  # stats.speed_vector.z = stats.speed_vector.z.lerp(0.0, delta * stats.air_friction)
  # stats.speed_vector.y = stats.speed_vector.y.lerp(stats.wish_vector.y, delta * stats.air_friction)

  if (player.is_on_floor()):
    stats.wish_vector.y = 0.0
    player.can_jump = true

func jump():
  # var suspension = player.create_timer(stats.suspend_gravity_timer, false, true, false)
  jump_timer.start(stats.suspend_gravity_timer)
  stats.gravity_mult = 0.0
  stats.wish_vector.y = stats.jump_force + (9.8 * stats.gravity_mult)

  # await suspension.timeout
  await jump_timer.timeout

  # var quickening = player.create_timer(stats.increase_gravity_timer, false, true, false)
  jump_timer.start(stats.increase_gravity_timer)
  stats.gravity_mult = 3.0
  stats.wish_vector.y = 9.8 * stats.gravity_mult

  # await quickening.timeout
  await jump_timer.timeout
  stats.gravity_mult = 1.0
  stats.wish_vector.y = 0.0
