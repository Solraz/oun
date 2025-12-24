extends CharacterBody3D
class_name Entity

#region References
@export var stats: Stats
@export var state_machine: StateMachine
#endregion

func _ready() -> void:		
	pass

func _input(event: InputEvent) -> void:
	state_machine.state.handle_input(event)

func _physics_process(_delta: float) -> void:
	if (stats.speed_vector):
		velocity.x = stats.speed_vector.x
		velocity.z = stats.speed_vector.z
		velocity.y = stats.speed_vector.y

	move_and_slide()
