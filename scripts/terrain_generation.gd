@tool
class_name TerrainChunk
extends MeshInstance3D

signal terrain_ready

@export_group("Chunk Grid")
@export var chunk_coord: Vector2i = Vector2i(0, 0) : set = _set_chunk_coord

@export_group("Terrain Size")
@export var map_size_x: float = 256.0
@export var map_size_z: float = 256.0

@export_group("Base Resolution / LOD")
@export var resolution_x: int = 128
@export var resolution_z: int = 128
@export_range(0, 4, 1) var lod_level: int = 0
@export var sample_step: float = 2.0

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

enum Backends { CPU_SINGLE, CPU_MULTI, GPU }
@export_group("Backends")
@export var use_multithread_cpu: bool = true
@export var cpu_jobs: int = 4
@export var use_gpu_height_erosion: bool = false
@export var gpu_erosion_scene: PackedScene

@export_group("Erosion Backend")
@export var enable_erosion: bool = true
@export var erosion_backend: Backends = Backends.CPU_SINGLE
@export var erosion_iterations: int = 16
@export_range(0.0, 1.0, 0.01) var erosion_strength: float = 0.12

@export_group("Erosion - Thermal")
@export var enable_thermal: bool = true
@export var talus_angle: float = 2.0
@export_range(0.0, 1.0, 0.01) var thermal_strength: float = 0.5

@export_group("Erosion - Hydraulic")
@export var enable_hydraulic: bool = true
@export var rain_amount: float = 0.5
@export_range(0.0, 1.0, 0.01) var hydraulic_strength: float = 0.7
@export_range(0.0, 1.0, 0.01) var evaporation: float = 0.5
@export var sediment_capacity: float = 1.0

@export_group("Erosion - Wind")
@export var enable_wind: bool = true
@export var wind_direction: Vector2 = Vector2(1.0, 0.3)
@export_range(0.0, 1.0, 0.01) var wind_strength: float = 0.4

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
var _gpu_erosion: GPUErosion

var _heights: PackedFloat32Array
var _pending_jobs: int = 0
var _job_lock := Mutex.new()

var _half_x: float
var _half_z: float
var _step_x: float
var _step_z: float

var _cpu_threads: Array[Thread] = []
var _cpu_jobs_done := 0
var _cpu_job_lock := Mutex.new()
var _cpu_job_sem := Semaphore.new()

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
		generate_async()

func _set_chunk_coord(v: Vector2i) -> void:
	chunk_coord = v
	_update_transform_from_coord()
	if auto_generate and Engine.is_editor_hint():
		generate()

func _update_transform_from_coord() -> void:
	var samples_x := resolution_x - 1
	var samples_z := resolution_z - 1
	# var world_size_x : float = float(samples_x) * sample_step
	# var world_size_z : float = float(samples_z) * sample_step
	var ox : float = float(chunk_coord.x * samples_x)
	var oz : float = float(chunk_coord.y * samples_z)
	global_transform.origin = Vector3(ox, global_transform.origin.y, oz)
	# keep local mesh in 0..world_size, origin at chunk corner

func generate_async() -> void:
	_init_noise()
	_clear_old_collision_and_vegetation()

	_half_x = map_size_x * 0.5
	_half_z = map_size_z * 0.5
	_step_x = map_size_x / float(max(resolution_x - 1, 1))
	_step_z = map_size_z / float(max(resolution_z - 1, 1))

	_heights = PackedFloat32Array()
	_heights.resize(resolution_x * resolution_z)

	if use_multithread_cpu:
		_start_multithread_generation()
	else:
		_generate_singlethread()
		_post_heightmap_process()

func _start_multithread_generation() -> void:
	var jobs : int = max(1, min(cpu_jobs, resolution_z))
	var rows_per_job : int = max(1, resolution_z / jobs)

	_pending_jobs = 0

	for j in range(jobs):
		var start_z := j * rows_per_job
		var end_z := (j + 1) * rows_per_job
		if j == jobs - 1:
			end_z = resolution_z

		if start_z >= resolution_z:
			continue

		_pending_jobs += 1
		var job_data := {
			"start_z": start_z,
			"end_z": end_z,
			"res_x": resolution_x,
			"res_z": resolution_z,
			"half_x": _half_x,
			"half_z": _half_z,
			"step_x": _step_x,
			"step_z": _step_z,
			"origin": global_transform.origin,
			"noise_scale": noise_scale,
			"height_scale": height_scale,
			"mountain_noise_scale": mountain_noise_scale,
			"mountain_height": mountain_height,
			"mountain_ridge_power": mountain_ridge_power,
			"mountain_threshold": mountain_threshold,
			"mountain_blend": mountain_blend
		}
		WorkerThreadPool.add_task(
			Callable(self, "_worker_generate_slice").bind(job_data)
		)

func _worker_generate_slice(job_data: Dictionary) -> void:
	var start_z: int = job_data["start_z"]
	var end_z: int = job_data["end_z"]
	var res_x: int = job_data["res_x"]
	var res_z: int = job_data["res_z"]
	var half_x: float = job_data["half_x"]
	var half_z: float = job_data["half_z"]
	var step_x: float = job_data["step_x"]
	var step_z: float = job_data["step_z"]
	var origin: Vector3 = job_data["origin"]
	var n_scale: float = job_data["noise_scale"]
	var h_scale: float = job_data["height_scale"]
	var m_scale: float = job_data["mountain_noise_scale"]
	var m_height: float = job_data["mountain_height"]
	var m_ridge_power: float = job_data["mountain_ridge_power"]
	var m_threshold: float = job_data["mountain_threshold"]
	var m_blend: float = job_data["mountain_blend"]

	var slice_height := PackedFloat32Array()
	var slice_rows := end_z - start_z
	slice_height.resize(slice_rows * res_x)

	for z in range(start_z, end_z):
		var local_z := z - start_z
		for x in range(res_x):
			var px := -half_x + float(x) * step_x
			var pz := -half_z + float(z) * step_z

			var world_x := origin.x + px
			var world_z := origin.z + pz

			var nx := world_x * n_scale
			var nz := world_z * n_scale
			var base_h := _noise_base.get_noise_2d(nx, nz) * h_scale

			var mnx := world_x * m_scale
			var mnz := world_z * m_scale
			var m := _noise_mountain.get_noise_2d(mnx, mnz)
			m = 1.0 - abs(m)
			m = clamp(m, 0.0, 1.0)
			m = pow(m, m_ridge_power)

			var mask := smoothstep(m_threshold, 1.0, m)
			mask *= m_blend

			var mountain_h := m * m_height
			var h := base_h + mountain_h * mask

			slice_height[local_z * res_x + x] = h

	Callable(self, "_on_worker_slice_ready").call_deferred(start_z, end_z, res_x, res_z, slice_height)


func _on_worker_slice_ready(start_z: int, end_z: int, res_x: int, res_z: int, slice: PackedFloat32Array) -> void:
	var slice_rows := end_z - start_z

	for local_z in range(slice_rows):
		var global_z := start_z + local_z
		if global_z >= res_z:
			break
		for x in range(res_x):
			var global_idx := global_z * res_x + x
			var local_idx := local_z * res_x + x
			_heights[global_idx] = slice[local_idx]

	_job_lock.lock()
	_pending_jobs -= 1
	var done := _pending_jobs <= 0
	_job_lock.unlock()

	if done:
		_post_heightmap_process()
		

func _generate_singlethread() -> void:
	for z in range(resolution_z):
		for x in range(resolution_x):
			var px: float = -_half_x + x * _step_x
			var pz: float = -_half_z + z * _step_z
			_heights[z * resolution_x + x] = _cpu_get_height(px, pz)
			

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
	return max(resolution_x >> lod_level, 8)

func _get_effective_resolution_z() -> int:
	return max(resolution_z >> lod_level, 8)


func _generate_terrain() -> void:
	# resolution_x = _get_effective_resolution_x()
	# resolution_z = _get_effective_resolution_z()

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
			var h := _cpu_get_height(px, pz)
			heights[z * resolution_x + x] = h

	if enable_erosion and erosion_iterations > 0:
		heights = await _apply_erosion(heights, resolution_x, resolution_z)

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

func _cpu_get_height(local_x: float, local_z: float) -> float:
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

func _post_heightmap_process() -> void:
	if enable_erosion and erosion_iterations > 0:
		if use_gpu_height_erosion and gpu_erosion_scene != null:
			if _gpu_erosion == null:
				var inst := gpu_erosion_scene.instantiate()
				if inst is GPUErosion:
					_gpu_erosion = inst
					add_child(_gpu_erosion)
			if _gpu_erosion != null:
				_heights = await _gpu_erosion.apply_heightmap(
					_heights,
					resolution_x,
					resolution_z,
					erosion_iterations,
					erosion_strength,
					enable_thermal,
					talus_angle,
					thermal_strength,
					enable_hydraulic,
					rain_amount,
					hydraulic_strength,
					evaporation,
					sediment_capacity,
					enable_wind,
					wind_direction,
					wind_strength
				)
		else:
			_apply_erosion_cpu(_heights, resolution_x, resolution_z)

	_build_mesh_from_heights()
	emit_signal("terrain_ready")

func _build_mesh_from_heights() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in range(resolution_z - 1):
		for x in range(resolution_x - 1):
			var i0 := z * resolution_x + x
			var i1 := z * resolution_x + x + 1
			var i2 := (z + 1) * resolution_x + x
			var i3 := (z + 1) * resolution_x + x + 1

			var p0 := Vector3(-_half_x + x * _step_x, _heights[i0], -_half_z + z * _step_z)
			var p1 := Vector3(-_half_x + (x + 1) * _step_x, _heights[i1], -_half_z + z * _step_z)
			var p2 := Vector3(-_half_x + x * _step_x, _heights[i2], -_half_z + (z + 1) * _step_z)
			var p3 := Vector3(-_half_x + (x + 1) * _step_x, _heights[i3], -_half_z + (z + 1) * _step_z)

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

	if material_override == null:
		var debug_mat := StandardMaterial3D.new()
		debug_mat.albedo_color = Color(0.3, 0.7, 0.4)
		material_override = debug_mat

func _compute_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	return ac.cross(ab).normalized()

func _apply_erosion(heights: PackedFloat32Array, res_x: int, res_z: int) -> PackedFloat32Array:
	match erosion_backend:
		Backends.CPU_SINGLE:
			_apply_erosion_cpu(heights, res_x, res_z)
			return heights
		Backends.CPU_MULTI:
			if enable_multithread_cpu:
				return _apply_erosion_cpu_multithread(heights, res_x, res_z)
			# _apply_erosion_cpu(heights, res_x, res_z)
			return heights
		Backends.GPU:
			if gpu_erosion_scene != null:
				if _gpu_erosion == null:
					var inst := gpu_erosion_scene.instantiate()
					if inst is GPUErosion:
						_gpu_erosion = inst
						add_child(_gpu_erosion)
				if _gpu_erosion != null:
					return await _gpu_erosion.apply_heightmap(
						heights,
						res_x,
						res_z,
						erosion_iterations,
						erosion_strength,
						enable_thermal,
						talus_angle,
						thermal_strength,
						enable_hydraulic,
						rain_amount,
						hydraulic_strength,
						evaporation,
						sediment_capacity,
						enable_wind,
						wind_direction,
						wind_strength
					)
			# _apply_erosion_cpu(heights, res_x, res_z)/
			return heights
		_:
			_apply_erosion_cpu(heights, res_x, res_z)
			return heights


func _apply_erosion_cpu(heights: PackedFloat32Array, res_x: int, res_z: int) -> void:
	for _i in range(erosion_iterations):
		if enable_thermal:
			_apply_thermal_erosion(heights, res_x, res_z)
		if enable_hydraulic:
			_apply_hydraulic_erosion(heights, res_x, res_z)
		if enable_wind:
			_apply_wind_erosion(heights, res_x, res_z)


func _apply_erosion_cpu_multithread(heights: PackedFloat32Array, res_x: int, res_z: int) -> PackedFloat32Array:
	var threads_to_use : int = clamp(max_threads, 1, OS.get_processor_count())
	var rows_per_job : int = max(1, res_z / threads_to_use)

	var shared_heights := heights
	_cpu_jobs_done = 0
	_cpu_threads.clear()

	for t in range(threads_to_use):
		var start_z := t * rows_per_job
		var end_z := (t + 1) * rows_per_job
		if t == threads_to_use - 1:
			end_z = res_z

		var job := CPUJob.new()
		job.start_z = start_z
		job.end_z = end_z
		job.res_x = res_x
		job.res_z = res_z
		job.iterations = erosion_iterations
		job.heights = shared_heights
		job.chunk_ref = weakref(self)

		var thread := Thread.new()
		_cpu_threads.append(thread)
		thread.start(Callable(job, "_erosion_thread_job"))
		# thread.start(Callable(self, "_erosion_thread_job"), job)

	for thread in _cpu_threads:
		if thread.is_started():
			thread.wait_to_finish()

	_cpu_threads.clear()
	return shared_heights


func _erosion_thread_job(job: CPUJob) -> void:
	var chunk: TerrainChunk = job.chunk_ref.get_ref()
	if chunk == null:
		return

	for _i in range(job.iterations):
		if enable_thermal:
			chunk._apply_thermal_erosion_range(job.heights, job.res_x, job.res_z, job.start_z, job.end_z)
		if enable_hydraulic:
			chunk._apply_hydraulic_erosion_range(job.heights, job.res_x, job.res_z, job.start_z, job.end_z)
		if enable_wind:
			chunk._apply_wind_erosion_range(job.heights, job.res_x, job.res_z, job.start_z, job.end_z)

	_cpu_job_lock.lock()
	_cpu_jobs_done += 1
	_cpu_job_lock.unlock()
	_cpu_job_sem.post()

func _apply_thermal_erosion(heights: PackedFloat32Array, res_x: int, res_z: int) -> void:
	_apply_thermal_erosion_range(heights, res_x, res_z, 1, res_z - 1)

func _apply_thermal_erosion_range(
	heights: PackedFloat32Array,
	res_x: int,
	res_z: int,
	start_z: int,
	end_z: int
) -> void:
	var new_heights := heights.duplicate()
	for z in range(max(1, start_z), min(end_z, res_z - 1)):
		for x in range(1, res_x - 1):
			var idx := z * res_x + x
			var h: float = heights[idx]

			var max_diff := 0.0
			var move_idx := -1

			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					var nx := x + dx
					var nz := z + dz
					if nx < 0 or nx >= res_x or nz < 0 or nz >= res_z:
						continue
					var nidx := nz * res_x + nx
					var nh: float = heights[nidx]
					var diff := h - nh
					if diff > max_diff:
						max_diff = diff
						move_idx = nidx

			if max_diff > talus_angle and move_idx != -1:
				var move := max_diff * thermal_strength * erosion_strength
				new_heights[idx] = new_heights[idx] - move
				new_heights[move_idx] = new_heights[move_idx] + move

	for z in range(max(1, start_z), min(end_z, res_z - 1)):
		for x in range(1, res_x - 1):
			var idx := z * res_x + x
			heights[idx] = new_heights[idx]

func _apply_hydraulic_erosion(heights: PackedFloat32Array, res_x: int, res_z: int) -> void:
	_apply_hydraulic_erosion_range(heights, res_x, res_z, 1, res_z - 1)

func _apply_hydraulic_erosion_range(
	heights: PackedFloat32Array,
	res_x: int,
	res_z: int,
	start_z: int,
	end_z: int
) -> void:
	var water := PackedFloat32Array()
	var sediment := PackedFloat32Array()
	water.resize(heights.size())
	sediment.resize(heights.size())

	for i in range(heights.size()):
		water[i] = water[i] + rain_amount

	var new_heights := heights.duplicate()

	for z in range(max(1, start_z), min(end_z, res_z - 1)):
		for x in range(1, res_x - 1):
			var idx := z * res_x + x
			var h_total := heights[idx] + water[idx]
			var lowest_h := h_total
			var lowest_idx := -1

			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					var nx := x + dx
					var nz := z + dz
					if nx < 0 or nx >= res_x or nz < 0 or nz >= res_z:
						continue
					var nidx := nz * res_x + nx
					var nh_total := heights[nidx] + water[nidx]
					if nh_total < lowest_h:
						lowest_h = nh_total
						lowest_idx = nidx

			if lowest_idx != -1:
				var delta := h_total - lowest_h
				if delta > 0.0:
					var flow := delta * hydraulic_strength * erosion_strength
					flow = min(flow, water[idx])

					water[idx] -= flow
					water[lowest_idx] += flow

					var capacity := flow * sediment_capacity
					var cur_sediment := sediment[idx]
					var height_here := heights[idx]

					if cur_sediment < capacity:
						var amount : float = min((capacity - cur_sediment), height_here * erosion_strength)
						sediment[idx] += amount
						new_heights[idx] -= amount
					else:
						var deposit := (cur_sediment - capacity) * erosion_strength
						sediment[idx] -= deposit
						new_heights[idx] += deposit

	for i in range(heights.size()):
		water[i] *= (1.0 - evaporation)
		heights[i] = new_heights[i]

func _apply_wind_erosion(heights: PackedFloat32Array, res_x: int, res_z: int) -> void:
	_apply_wind_erosion_range(heights, res_x, res_z, 1, res_z - 1)

func _apply_wind_erosion_range(
	heights: PackedFloat32Array,
	res_x: int,
	res_z: int,
	start_z: int,
	end_z: int
) -> void:
	var new_heights := heights.duplicate()
	var dir := wind_direction.normalized()
	var dir_x := dir.x
	var dir_z := dir.y

	for z in range(max(1, start_z), min(end_z, res_z - 1)):
		for x in range(1, res_x - 1):
			var idx := z * res_x + x
			var h: float = heights[idx]

			var upwind_x : int = clamp(int(round(x - dir_x)), 0, res_x - 1)
			var upwind_z : int = clamp(int(round(z - dir_z)), 0, res_z - 1)
			var downwind_x : int = clamp(int(round(x + dir_x)), 0, res_x - 1)
			var downwind_z : int = clamp(int(round(z + dir_z)), 0, res_z - 1)

			var up_idx := upwind_z * res_x + upwind_x
			var down_idx := downwind_z * res_x + downwind_x

			var up_h := heights[up_idx]
			var slope := up_h - h

			if slope > 0.0:
				var move := slope * wind_strength * erosion_strength
				new_heights[up_idx] -= move
				new_heights[down_idx] += move

	for z in range(max(1, start_z), min(end_z, res_z - 1)):
		for x in range(1, res_x - 1):
			var idx := z * res_x + x
			heights[idx] = new_heights[idx]

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
