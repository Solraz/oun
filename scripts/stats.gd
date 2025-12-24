extends Node
class_name Stats

#region Movement Vectors
@export_group("Movement Vectors")
@export var wish_vector: Vector3 = Vector3.ZERO
@export var speed_vector: Vector3 = Vector3.ZERO
@export var max_speed_vector: Vector3 = Vector3(speed, speed, speed)
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
#endregion

#region Movement Stats
@export_group("Movement Stats")
@export var speed: float = 50.0
@export var crouch_speed: float = 35.0
@export var air_speed: float = 25.0
##
@export var acceleration: float = 20.0
@export var air_acceleration: float = 5.0
@export var friction: float = 9.0
@export var air_friction: float = 6.0
##
@export var idle_timer: float = 0.01
@export var coyote_timer: float = 0.33
@export var gravity_mult: float = 1.0
##
@export var max_velocity: float = 300.0
@export var max_air_velocity: float = 600.0
##
@export var jump_force: float = 150.0
@export var suspend_gravity_timer: float = 0.11
@export var increase_gravity_timer: float = 0.22
##
@export var lerp_mult: float = 0.85
@export var air_lerp_mult: float = 0.9
@export var inertia_lerp_mult: float = 0.6
@export var still_lerp_mult: float = 0.4
#endregion

#region State Variables
@export_group("States")
@export var state: String = "IDLE"
@export var can_jump = true
#endregion

#region Character Attributes
@export_group("Attributes")
@export var level: int = 1
@export var experience: int = 0
##
@export var strength: int = 10
@export var agility: int = 10
@export var endurance: int = 10
@export var dexterity: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
##
@export var luck: int = 5
@export var spirit: int = 2
#endregion

#region Character Variables
@export_group("Stats")
@export var health: float = 100.0
@export var health_regen: float = 0.0
@export var health_regen_delay: float = 0.0
##
@export var poise: float = 0.0
@export var shield: float = 0.0
@export var defense: float = 0.0
##
@export var stamina: float = 100.0
@export var stamina_regen: float = 10.0
@export var stamina_regen_delay: float = 0.25
##
@export var mana: float = 10.0
@export var mana_regen: float = 0.0
@export var mana_regen_delay: float = 0.25
#endregion