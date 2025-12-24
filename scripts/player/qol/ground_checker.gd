extends RayCast3D

@export var player: Player

func _ready() -> void:
	pass

func _physics_process(_delta: float) -> void:
	if (!self.is_colliding()):
		player.state_machine.transition_to("air")
	else:
		player.stats.wish_vector.y = 0.0
		player.stats.can_jump = true
		player.state_machine.transition_to("run")

func aerial() -> void:
	pass