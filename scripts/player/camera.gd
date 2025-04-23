extends Camera3D
class_name PlayerCamera

@export var player: Player
@export var head: Node3D
@export var eyes: Node3D

func _ready() -> void:
  # Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
  pass

func _input(_event: InputEvent):
  # if event is InputEventMouseMotion:
  # 	player.rotate_y(-event.relative.x*0.0005)
  # 	eyes.rotate_x(-event.relative.y*0.0005)
  pass

func _process(_delta: float) -> void:
  head.global_position.x = player.global_position.x
  head.global_position.y = player.global_position.y + 15.0
  head.global_position.z = player.global_position.z + 5.0
  
  eyes.look_at(player.global_position)


func _physics_process(_delta: float) -> void:
  pass
