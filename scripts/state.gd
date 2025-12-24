extends Node
class_name State

# Typed reference to the player node.
var machine: StateMachine
var entity: Entity
var stats: Stats

func _ready() -> void:
	var _owner = get_parent().get_parent()

	await owner.ready

	machine = get_parent()
	entity = _owner as Entity
	stats = entity.stats

	assert(machine != null)
	assert(entity != null)
	assert(stats != null)

func handle_input(_event: InputEvent) -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func enter(_msg := {}) -> void:
	pass

func exit() -> void:
	pass
