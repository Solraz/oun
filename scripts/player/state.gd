extends State
class_name PlayerState

# Typed reference to the player node.
var player: Player
var stats: PlayerStats

func _ready() -> void:
	var _owner = get_parent().get_parent()

	await owner.ready

	player = _owner as Player
	stats = player.stats

	assert(player != null)
