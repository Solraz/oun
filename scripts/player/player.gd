extends CharacterBody3D
class_name Player

@export var stats: PlayerStats
@export var state_machine: StateMachine

func _ready() -> void:
  pass

func _input(event: InputEvent) -> void:
  state_machine.state.handle_input(event)

func _physics_process(delta: float) -> void:
  velocity = stats.speed_vector
  stats.speed_vector = stats.speed_vector.lerp(Vector3.ZERO, delta * stats.friction)

  move_and_slide()
