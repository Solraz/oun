extends CanvasLayer
class_name DebugHud

# Player Character Reference Variables
@export var player : Player

# Label References Variables
@onready var current_state: Label = %CurrentStateLabelText

# Speed Reference Variables
@onready var wish_vector: Label = %DesiredMoveSpeedLabelText
@onready var speed_vector : Label = %VelocityVectorLabelText
@onready var velocity: Label = %VelocityLabelText

# @onready var is_on_floor_label_text: Label = %IsOnFloorLabelText
# @onready var ceiling_check_label_text: Label = %CeilingCheckLabelText
# @onready var jump_buffer_label_text: Label = %JumpBufferLabelText
# @onready var coyote_time_label_text: Label = %CoyoteTimeLabelText
# @onready var nb_jumps_in_air_allowed_label_text: Label = %NbJumpsInAirAllowedLabelText
# @onready var jump_cooldown_label_text: Label = %JumpCooldownLabelText
# @onready var slide_time_label_text: Label = %SlideTimeLabelText
# @onready var slide_cooldown_label_text: Label = %SlideCooldownLabelText
# @onready var nb_dashs_allowed_label_text: Label = %NbDashsAllowedLabelText
# @onready var dash_cooldown_label_text: Label = %DashCooldownLabelText
# @onready var camera_rotation_label_text: Label = %CameraRotationLabelText
# @onready var current_fov_label_text: Label = %CurrentFOVLabelText
# @onready var camera_bob_vertical_offset_label_text: Label = %CameraBobVerticalOffsetLabelText

# @onready var speed_lines_container: ColorRect = %SpeedLinesContainer
@onready var frames_per_second_label_text: Label = %FramesPerSecondLabelText

func _process(_delta : float) -> void:
	if (player):
		# display_current_FPS()
		display_properties()

	
func display_properties() -> void:
	# Player Character Properties
	current_state.text = player.state_machine.state.name

	wish_vector.text = str(
		"[ ", 
		snapped(player.stats.wish_vector.x, 0.01),
		" ", 
		snapped(player.stats.wish_vector.y, 0.01),
		" ", 
		snapped(player.stats.wish_vector.z, 0.01), 
		" ]"
	)
	
	speed_vector.text = str(
		"[ ", 
		snapped(player.velocity.x, 0.01)
		," ", 
		snapped(player.velocity.y, 0.01),
		" ", 
		snapped(player.velocity.z, 0.01), 
		" ]"
	)

	velocity.text = str(
		snapped(player.velocity.length(), 0.01)
	)

	# is_on_floor_label_text.set_text(str(player.is_on_floor()))
	# ceiling_check_label_text.set_text(str(player.ceiling_check.is_colliding()))
	# jump_buffer_label_text.set_text(str(player.jump_buff_on))
	# coyote_time_label_text.set_text(str(round_to_3_decimals(player.coyote_jump_cooldown)))
	# nb_jumps_in_air_allowed_label_text.set_text(str(player.nb_jumps_in_air_allowed))
	# jump_cooldown_label_text.set_text(str(round_to_3_decimals(player.jump_cooldown)))
	# slide_time_label_text.set_text(str(round_to_3_decimals(player.slide_time)))
	# slide_cooldown_label_text.set_text(str(round_to_3_decimals(player.time_bef_can_slide_again)))
	# nb_dashs_allowed_label_text.set_text(str(player.nb_dashs_allowed))
	# dash_cooldown_label_text.set_text(str(round_to_3_decimals(player.time_bef_can_dash_again)))
	
	# Camera Properties
	# camera_rotation_label_text.set_text(str("[ ", round_to_3_decimals(player.cam.rotation.x)," ", round_to_3_decimals(player.cam.rotation.y)," ", round_to_3_decimals(player.cam.rotation.z), " ]"))
	# current_fov_label_text.set_text(str(player.cam.fov))
	# camera_bob_vertical_offset_label_text.set_text(str(round_to_3_decimals(player.cam.v_offset)))
	
func display_current_FPS() -> void:
	frames_per_second_label_text.set_text(
		str(
			Engine.get_frames_per_second()
		)
	)
	
# func display_speed_lines(value : bool) -> void:
# 	speed_lines_container.visible = value
	
	
	
	
	
	
