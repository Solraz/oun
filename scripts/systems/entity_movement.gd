extends CharacterBody3D
class_name MovementSystem

#region References
@export var stats : Stats
@export var entity : Entity
@export var player : Player
@export var state_machine : StateMachine
#endregion

#region Features Settings 
@export_group("Feature Settings")

@export_subgroup("Jumping and Air")
@export var jumping_enabled : bool = true
@export var jump_feedback_animation : bool = true
@export var hold_to_jump : bool = true
@export var can_accel_air : bool = true
@export var gravity_enablesd : bool = true

@export_subgroup("Sprint")
@export var can_sprint : bool = true
@export var dynamic_sprint_fov : bool = true
@export_enum("Hold to Sprint", "Toggle Sprint") var sprint_mode : int = 0

@export_subgroup("Crouching")
@export var crouch_enabled : bool = true
@export var dynamic_crouch_fov : bool = true
@export_enum("Hold to Crouch", "Toggle Crouch") var crouch_mode : int = 0

@export_subgroup("Camera")
@export var view_bobbing : bool = true
@export var pausing_enabled : bool = true
@export var dynamic_state_shader : bool = false

@export_subgroup("Miscellaneous")
@export var movement_smoothing : bool = true
@export var has_dynamic_gravity : bool = true
#endregion

var idle_timer: Timer
var jump_timer : Timer
var coyote_timer: Timer

func _ready() -> void:
	pass


func _physics_process(_delta: float) -> void:
	pass

func _process(_delta: float) -> void:
	pass


func handle_input(event: InputEvent) -> void:
	if (entity is not Player):
		pass

	if event is InputEventKey:
		var input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var direction := (entity.transform.basis * Vector3(input_direction.x, stats.wish_vector.y, input_direction.y)).normalized()

		stats.wish_vector = direction

		if (event.is_action("jump")):
			jump()


func physics_update(delta: float) -> void:
	var accel := stats.acceleration
	var speed := stats.speed
	var lerp_mult := stats.lerp_mult
	var friction := stats.friction

	if (entity.state_machine.state.name == "air"):
		accel = stats.air_acceleration
		speed = stats.air_speed
		lerp_mult = stats.air_lerp_mult
		friction = stats.air_friction
		stats.speed_vector.y = lerp(delta * friction, speed + stats.gravity * stats.gravity_mult * stats.wish_vector.y, lerp_mult)

	if (stats.wish_vector != Vector3.ZERO):
		stats.speed_vector.z = lerp(delta * accel, speed * stats.wish_vector.z, lerp_mult)
		stats.speed_vector.x = lerp(delta * accel, speed * stats.wish_vector.x, lerp_mult)
	else:
		stats.speed_vector.z = lerp(delta * friction, 0.0, lerp_mult)
		stats.speed_vector.x = lerp(delta * friction, 0.0, lerp_mult)

	move_and_slide()


func jump():
	jump_timer = Timer.new()
	player.add_child(jump_timer)
	jump_timer.start(stats.suspend_gravity_timer)
	
	stats.wish_vector.y = 1.0
	stats.gravity_mult = 0.0

	await jump_timer.timeout

	jump_timer = Timer.new()
	player.add_child(jump_timer)
	jump_timer.start(stats.increase_gravity_timer)

	stats.wish_vector.y = -1.0
	stats.gravity_mult = 2.0

	await jump_timer.timeout


func add_gravity() -> void:
	if (jump_timer):
		return

	coyote_timer = Timer.new()
	player.add_child(coyote_timer)
	coyote_timer.start(stats.coyote_timer)

	await coyote_timer.timeout

	stats.wish_vector.y = -1.0
	stats.can_jump = false
