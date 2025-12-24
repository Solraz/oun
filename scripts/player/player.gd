extends Entity
class_name Player

func _ready() -> void:
	pass

func _input(event: InputEvent) -> void:
	state_machine.state.handle_input(event)

func _physics_process(_delta: float) -> void:	
	pass
