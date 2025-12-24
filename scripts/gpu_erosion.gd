# GPUErosion.gd (SubViewport GPU backend)
@tool
class_name GPUErosion
extends Node

@export var erosion_shader: Shader

var _material: ShaderMaterial
var _viewport: SubViewport
var _rect: ColorRect


func _ready() -> void:
	if erosion_shader == null:
		erosion_shader = load("res://shaders/erosion_height_gpu.gdshader")

	_material = ShaderMaterial.new()
	_material.shader = erosion_shader

	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	_rect = ColorRect.new()
	_rect.material = _material
	_rect.color = Color.BLACK
	_viewport.add_child(_rect)


func apply_heightmap(
	heights: PackedFloat32Array,
	width: int,
	height: int,
	iterations: int,
	erosion_strength: float,
	enable_thermal: bool,
	talus_angle: float,
	thermal_strength: float,
	enable_hydraulic: bool,
	rain_amount: float,
	hydraulic_strength: float,
	evaporation: float,
	sediment_capacity: float,
	enable_wind: bool,
	wind_direction: Vector2,
	wind_strength: float
) -> PackedFloat32Array:
	if heights.size() != width * height:
		return heights

	var img := Image.create(width, height, false, Image.FORMAT_RF)
	for z in range(height):
		for x in range(width):
			var h := heights[z * width + x]
			img.set_pixel(x, z, Color(h, 0.0, 0.0, 1.0))

	var tex := ImageTexture.create_from_image(img)

	_viewport.size = Vector2i(width, height)
	_rect.size = Vector2(width, height)

	_material.set_shader_parameter("height_tex", tex)
	_material.set_shader_parameter("map_size", Vector2(width, height))
	_material.set_shader_parameter("erosion_iterations", iterations)
	_material.set_shader_parameter("erosion_strength", erosion_strength)

	_material.set_shader_parameter("enable_thermal", int(enable_thermal))
	_material.set_shader_parameter("talus_angle", talus_angle)
	_material.set_shader_parameter("thermal_strength", thermal_strength)

	_material.set_shader_parameter("enable_hydraulic", int(enable_hydraulic))
	_material.set_shader_parameter("rain_amount", rain_amount)
	_material.set_shader_parameter("hydraulic_strength", hydraulic_strength)
	_material.set_shader_parameter("evaporation", evaporation)
	_material.set_shader_parameter("sediment_capacity", sediment_capacity)

	_material.set_shader_parameter("enable_wind", int(enable_wind))
	_material.set_shader_parameter("wind_direction", wind_direction)
	_material.set_shader_parameter("wind_strength", wind_strength)

	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame

	var out_tex := _viewport.get_texture()
	if out_tex == null:
		return heights

	var out_img := out_tex.get_image()
	out_img.convert(Image.FORMAT_RF)

	var out_heights := PackedFloat32Array()
	out_heights.resize(width * height)

	for z in range(height):
		for x in range(width):
			out_heights[z * width + x] = out_img.get_pixel(x, z).r

	return out_heights
