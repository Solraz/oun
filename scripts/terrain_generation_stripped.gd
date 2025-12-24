@tool
class_name TerrainChunkStripped
extends MeshInstance3D

@export_group("Terrain Size")
@export var map_size_x: float = 256.0
@export var map_size_z: float = 256.0

@export_group("Base Resolution / LOD")
@export var base_resolution_x: int = 128
@export var base_resolution_z: int = 128
@export_range(0, 4, 1) var lod_level: int = 0

@export_group("Base Noise (Hills)")
@export var noise_scale: float = 0.04
@export var height_scale: float = 22.0
@export var noise_seed: int = 12345
@export var noise_octaves: int = 4
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.5

@export_group("Mountains")
@export var mountain_noise_scale: float = 0.012
@export var mountain_height: float = 90.0
@export var mountain_ridge_power: float = 2.8
@export_range(0.0, 1.0, 0.01) var mountain_threshold: float = 0.25
@export_range(0.0, 1.0, 0.01) var mountain_blend: float = 0.9

@export_group("Vegetation - Grass")
@export var enable_grass: bool = true
@export var grass_mesh: Mesh
@export var grass_instance_count: int = 2000
@export var grass_min_height: float = -10.0
@export var grass_max_height: float = 40.0
@export_range(0.0, 1.0, 0.01) var grass_max_slope: float = 0.55
@export var grass_min_scale: float = 0.6
@export var grass_max_scale: float = 1.4

@export_group("Vegetation - Trees")
@export var enable_trees: bool = true
@export var tree_mesh: Mesh
@export var tree_instance_count: int = 180
@export var tree_min_height: float = 3.0
@export var tree_max_height: float = 80.0
@export_range(0.0, 1.0, 0.01) var tree_max_slope: float = 0.8
@export var tree_min_scale: float = 0.8
@export var tree_max_scale: float = 2.8

@export_group("Vegetation - Seed")
@export var vegetation_seed: int = 1

@export_group("Multithreading")
@export var enable_multithread_cpu: bool = true
@export var max_threads: int = 4

@export_group("Generation")
@export var auto_generate: bool = true
@export var create_collision: bool = true

var _noise_base: FastNoiseLite
var _noise_mountain: FastNoiseLite

class CPUJob:
	var start_z: int
	var end_z: int
	var res_x: int
	var res_z: int
	var iterations: int
	var chunk_ref: WeakRef
	var heights: PackedFloat32Array

func _ready() -> void:
	_init_noise()
	if auto_generate:
		generate()


func generate() -> void:
	_init_noise()
	_clear_old_collision_and_vegetation()
	_generate_terrain()

	if material_override == null:
		var debug_mat := StandardMaterial3D.new()
		debug_mat.albedo_color = Color(0.2, 0.7, 0.3)
		material_override = debug_mat


func _init_noise() -> void:
	if _noise_base == null:
		_noise_base = FastNoiseLite.new()
	if _noise_mountain == null:
		_noise_mountain = FastNoiseLite.new()

	_noise_base.seed = noise_seed
	_noise_base.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise_base.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_base.fractal_octaves = noise_octaves
	_noise_base.fractal_lacunarity = noise_lacunarity
	_noise_base.fractal_gain = noise_gain

	_noise_mountain.seed = noise_seed + 98765
	_noise_mountain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_mountain.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_mountain.fractal_octaves = noise_octaves + 1
	_noise_mountain.fractal_lacunarity = noise_lacunarity * 1.3
	_noise_mountain.fractal_gain = noise_gain * 0.9


func _get_effective_resolution_x() -> int:
	return max(base_resolution_x >> lod_level, 8)


func _get_effective_resolution_z() -> int:
	return max(base_resolution_z >> lod_level, 8)

func _get_height(local_x: float, local_z: float) -> float:
	var origin := global_transform.origin
	var world_x := origin.x + local_x
	var world_z := origin.z + local_z

	var nx := world_x * noise_scale
	var nz := world_z * noise_scale
	var base_h := _noise_base.get_noise_2d(nx, nz) * height_scale

	var mnx := world_x * mountain_noise_scale
	var mnz := world_z * mountain_noise_scale
	var m := _noise_mountain.get_noise_2d(mnx, mnz)

	m = 1.0 - abs(m)
	m = clamp(m, 0.0, 1.0)
	m = pow(m, mountain_ridge_power)

	var mask := smoothstep(mountain_threshold, 1.0, m)
	mask *= mountain_blend

	var mountain_h := m * mountain_height
	return base_h + mountain_h * mask


func _compute_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	return ac.cross(ab).normalized()


func _generate_terrain() -> void:
	var resolution_x := _get_effective_resolution_x()
	var resolution_z := _get_effective_resolution_z()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_x: float = map_size_x * 0.5
	var half_z: float = map_size_z * 0.5

	var step_x: float = map_size_x / float(max(resolution_x - 1, 1))
	var step_z: float = map_size_z / float(max(resolution_z - 1, 1))

	var heights := PackedFloat32Array()
	heights.resize(resolution_x * resolution_z)

	for z in range(resolution_z):
		for x in range(resolution_x):
			var px: float = -half_x + x * step_x
			var pz: float = -half_z + z * step_z
			var h := _get_height(px, pz)
			heights[z * resolution_x + x] = h

	for z in range(resolution_z - 1):
		for x in range(resolution_x - 1):
			var i0 := z * resolution_x + x
			var i1 := z * resolution_x + x + 1
			var i2 := (z + 1) * resolution_x + x
			var i3 := (z + 1) * resolution_x + x + 1

			var p0 := Vector3(-half_x + x * step_x, heights[i0], -half_z + z * step_z)
			var p1 := Vector3(-half_x + (x + 1) * step_x, heights[i1], -half_z + z * step_z)
			var p2 := Vector3(-half_x + x * step_x, heights[i2], -half_z + (z + 1) * step_z)
			var p3 := Vector3(-half_x + (x + 1) * step_x, heights[i3], -half_z + (z + 1) * step_z)

			var n0 := _compute_normal(p0, p2, p1)
			st.set_normal(n0)
			st.set_uv(Vector2(float(x) / float(resolution_x), float(z) / float(resolution_z)))
			st.add_vertex(p0)

			st.set_normal(n0)
			st.set_uv(Vector2(float(x) / float(resolution_x), float(z + 1) / float(resolution_z)))
			st.add_vertex(p2)

			st.set_normal(n0)
			st.set_uv(Vector2(float(x + 1) / float(resolution_x), float(z) / float(resolution_z)))
			st.add_vertex(p1)

			var n1 := _compute_normal(p1, p2, p3)
			st.set_normal(n1)
			st.set_uv(Vector2(float(x + 1) / float(resolution_x), float(z) / float(resolution_z)))
			st.add_vertex(p1)

			st.set_normal(n1)
			st.set_uv(Vector2(float(x) / float(resolution_x), float(z + 1) / float(resolution_z)))
			st.add_vertex(p2)

			st.set_normal(n1)
			st.set_uv(Vector2(float(x + 1) / float(resolution_x), float(z + 1) / float(resolution_z)))
			st.add_vertex(p3)

	var array_mesh := st.commit()
	mesh = array_mesh

	if create_collision and array_mesh != null:
		_create_collision_from_mesh(array_mesh)
	
	_generate_vegetation(heights, resolution_x, resolution_z, step_x, step_z, half_x, half_z)

func _estimate_slope(x: int, z: int, heights: Array, res_x: int, res_z: int, step_x: float, step_z: float) -> float:
	var idx := z * res_x + x
	var h: float = heights[idx]

	var x1 : int = clamp(x + 1, 0, res_x - 1)
	var z1 : int = clamp(z + 1, 0, res_z - 1)

	var h_x: float = heights[z * res_x + x1]
	var h_z: float = heights[z1 * res_x + x]

	var dhx := h_x - h
	var dhz := h_z - h

	var sx : float = dhx / max(step_x, 0.0001)
	var sz : float = dhz / max(step_z, 0.0001)

	return min(1.0, sqrt(sx * sx + sz * sz))


func _generate_vegetation(heights: Array, res_x: int, res_z: int, step_x: float, step_z: float, half_x: float, half_z: float) -> void:
	for c in get_children():
		if c is MultiMeshInstance3D:
			c.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = vegetation_seed + int(global_transform.origin.x) * 73856093 + int(global_transform.origin.z) * 19349663

	if enable_grass and grass_mesh != null and grass_instance_count > 0:
		_spawn_multimesh(
			grass_mesh,
			grass_instance_count,
			heights,
			res_x,
			res_z,
			step_x,
			step_z,
			half_x,
			half_z,
			grass_min_height,
			grass_max_height,
			grass_max_slope,
			grass_min_scale,
			grass_max_scale,
			rng
		)

	if enable_trees and tree_mesh != null and tree_instance_count > 0:
		_spawn_multimesh(
			tree_mesh,
			tree_instance_count,
			heights,
			res_x,
			res_z,
			step_x,
			step_z,
			half_x,
			half_z,
			tree_min_height,
			tree_max_height,
			tree_max_slope,
			tree_min_scale,
			tree_max_scale,
			rng
		)


func _spawn_multimesh(
	mesh_res: Mesh,
	count: int,
	heights: Array,
	res_x: int,
	res_z: int,
	step_x: float,
	step_z: float,
	half_x: float,
	half_z: float,
	min_h: float,
	max_h: float,
	max_slope: float,
	min_scale: float,
	max_scale: float,
	rng: RandomNumberGenerator
) -> void:
	if count <= 0:
		return

	var total := res_x * res_z
	if total <= 0:
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh_res
	mm.instance_count = count

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

	var placed := 0
	var attempts := 0
	var max_attempts := count * 20

	while placed < count and attempts < max_attempts:
		attempts += 1
		var idx := rng.randi_range(0, total - 1)
		var h: float = heights[idx]
		if h < min_h or h > max_h:
			continue

		var z := idx / res_x
		var x := idx % res_x

		var slope := _estimate_slope(x, z, heights, res_x, res_z, step_x, step_z)
		if slope > max_slope:
			continue

		var local_x := -half_x + float(x) * step_x
		var local_z := -half_z + float(z) * step_z
		var pos := Vector3(local_x, h, local_z)

		var scale_val := rng.randf_range(min_scale, max_scale)
		basis = basis.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3.ONE * scale_val)

		var xf := Transform3D(basis, pos)
		mm.set_instance_transform(placed, xf)
		placed += 1

	mm.instance_count = placed

func _create_collision_from_mesh(m: Mesh) -> void:
	if m.get_surface_count() == 0:
		return

	var static_body := StaticBody3D.new()
	add_child(static_body)
	static_body.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene

	var col_shape := CollisionShape3D.new()
	static_body.add_child(col_shape)
	col_shape.owner = static_body.owner

	var shape := ConcavePolygonShape3D.new()
	var arrays := m.surface_get_arrays(0)
	shape.data = arrays[Mesh.ARRAY_VERTEX]
	col_shape.shape = shape

func _clear_old_collision_and_vegetation() -> void:
	for c in get_children():
		if c is StaticBody3D or c is MultiMeshInstance3D:
			c.queue_free()