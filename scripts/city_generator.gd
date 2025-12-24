# CityGenerator.gd
@tool
class_name CityGenerator
extends Node3D

enum ZoneType { RESIDENTIAL, COMMERCIAL, INDUSTRIAL, PARK, DOWNTOWN }

@export_group("City Size & Grid")
@export var city_size_x: float = 1024.0
@export var city_size_z: float = 1024.0
@export var block_size_x: float = 16.0
@export var block_size_z: float = 16.0
@export var road_width: float = 6.0
@export var sidewalk_width: float = 2.0
@export var random_seed: int = 12345

@export_group("Road Network")
@export var main_road_spacing_x: int = 8
@export var main_road_spacing_z: int = 8
@export var secondary_road_spacing_x: int = 4
@export var secondary_road_spacing_z: int = 4
@export_range(0.0, 1.0, 0.01) var main_road_noise_influence: float = 0.25
@export_range(0.0, 1.0, 0.01) var secondary_road_noise_influence: float = 0.5
@export var diagonal_roads: bool = true
@export_range(0.0, 1.0, 0.01) var diagonal_probability: float = 0.15

@export_group("Zoning / Districts")
@export var zone_noise_scale: float = 0.002
@export var downtown_radius: float = 200.0
@export var downtown_intensity: float = 1.5
@export_range(0.0, 2.0, 0.01) var residential_bias: float = 1.0
@export_range(0.0, 2.0, 0.01) var commercial_bias: float = 1.0
@export_range(0.0, 2.0, 0.01) var industrial_bias: float = 1.0
@export_range(0.0, 2.0, 0.01) var park_bias: float = 1.0

@export_group("Density / Height")
@export var density_noise_scale: float = 0.004
@export var base_height_residential: float = 3.0
@export var base_height_commercial: float = 6.0
@export var base_height_industrial: float = 5.0
@export var base_height_downtown: float = 10.0
@export var base_height_random_variation: float = 3.0
@export var snap_height_to_floor: float = 3.0

@export_group("Assets - Residential")
@export var residential_assets: Array[CityAsset] = []

@export_group("Assets - Commercial")
@export var commercial_assets: Array[CityAsset] = []

@export_group("Assets - Industrial")
@export var industrial_assets: Array[CityAsset] = []

@export_group("Assets - Park")
@export var park_assets: Array[CityAsset] = []

@export_group("Assets - Downtown Overlays")
@export var downtown_assets: Array[CityAsset] = []

@export_group("Assets - Roads & Sidewalks")
@export var road_segment_scene: PackedScene
@export var intersection_scene: PackedScene
@export var sidewalk_segment_scene: PackedScene
@export var plaza_scene: PackedScene

@export_group("Generation")
@export var clear_on_generate: bool = true
@export var generate_on_ready: bool = false
@export var preview_in_editor: bool = true

var _zone_noise: FastNoiseLite
var _density_noise: FastNoiseLite
var _road_noise: FastNoiseLite
var _rng: RandomNumberGenerator

var _grid_size_x: int
var _grid_size_z: int


func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	if generate_on_ready:
		generate_city()


func generate_city() -> void:
	_init_generators()
	if clear_on_generate:
		_clear_city()

	_grid_size_x = max(1, int(city_size_x / block_size_x))
	_grid_size_z = max(1, int(city_size_z / block_size_z))

	var road_grid := _generate_road_grid()
	var zone_grid := _generate_zones()
	var density_grid := _generate_density()

	_spawn_roads(road_grid)
	_spawn_buildings(road_grid, zone_grid, density_grid)
	_spawn_plazas(zone_grid, density_grid)


func _init_generators() -> void:
	if _zone_noise == null:
		_zone_noise = FastNoiseLite.new()
	if _density_noise == null:
		_density_noise = FastNoiseLite.new()
	if _road_noise == null:
		_road_noise = FastNoiseLite.new()
	if _rng == null:
		_rng = RandomNumberGenerator.new()

	_rng.seed = random_seed

	_zone_noise.seed = random_seed * 31 + 1
	_zone_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_zone_noise.frequency = zone_noise_scale

	_density_noise.seed = random_seed * 61 + 7
	_density_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_density_noise.frequency = density_noise_scale

	_road_noise.seed = random_seed * 97 + 13
	_road_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_road_noise.frequency = 1.0 / 64.0


func _clear_city() -> void:
	for c in get_children():
		c.queue_free()


func _generate_road_grid() -> Array:
	var grid := []
	grid.resize(_grid_size_x * _grid_size_z)

	for z in range(_grid_size_z):
		for x in range(_grid_size_x):
			grid[z * _grid_size_x + x] = {
				"h": false,
				"v": false,
				"d": false
			}

	for z in range(_grid_size_z):
		for x in range(_grid_size_x):
			var idx := z * _grid_size_x + x

			var world_x : float = (float(x) / max(_grid_size_x - 1, 1) - 0.5) * city_size_x
			var world_z : float = (float(z) / max(_grid_size_z - 1, 1) - 0.5) * city_size_z

			var main_x := (x % main_road_spacing_x) == 0
			var main_z := (z % main_road_spacing_z) == 0
			var sec_x := (x % secondary_road_spacing_x) == 0
			var sec_z := (z % secondary_road_spacing_z) == 0

			var nx := _road_noise.get_noise_2d(world_x * 0.01, world_z * 0.01)
			var nz := _road_noise.get_noise_2d(world_z * 0.01, world_x * 0.01)

			var main_x_noise : float = abs(nx) < main_road_noise_influence
			var main_z_noise : float = abs(nz) < main_road_noise_influence
			var sec_x_noise : float = abs(nx) < secondary_road_noise_influence
			var sec_z_noise : float = abs(nz) < secondary_road_noise_influence

			var h := (main_x or main_x_noise) or (sec_x or sec_x_noise)
			var v := (main_z or main_z_noise) or (sec_z or sec_z_noise)

			var d := false
			if diagonal_roads:
				if _rng.randf() < diagonal_probability and (main_x or main_z):
					d = true

			grid[idx]["h"] = h
			grid[idx]["v"] = v
			grid[idx]["d"] = d

	return grid


func _generate_zones() -> Array:
	var zones := []
	zones.resize(_grid_size_x * _grid_size_z)

	# var center := Vector2(0.0, 0.0)

	for z in range(_grid_size_z):
		for x in range(_grid_size_x):
			var idx := z * _grid_size_x + x

			var world_x : float = (float(x) / max(_grid_size_x - 1, 1) - 0.5) * city_size_x
			var world_z : float = (float(z) / max(_grid_size_z - 1, 1) - 0.5) * city_size_z

			var p := Vector2(world_x, world_z)
			var dist := p.length()
			var dist_norm : float = clamp(dist / max(downtown_radius, 1.0), 0.0, 1.0)
			var downtown_factor := pow(1.0 - dist_norm, 2.0) * downtown_intensity

			var zn := _zone_noise.get_noise_2d(world_x, world_z)
			zn = (zn + 1.0) * 0.5

			var r_score := residential_bias * (1.0 - zn) * (1.0 - downtown_factor * 0.5)
			var c_score := commercial_bias * (zn * 0.5 + downtown_factor * 0.7)
			var i_score := industrial_bias * ((1.0 - zn) * 0.3 + zn * 0.2)
			var p_score : float = park_bias * (0.2 + (1.0 - abs(zn - 0.5)) * 0.4) * (1.0 - downtown_factor * 0.7)

			var d_score := downtown_factor

			var sum := r_score + c_score + i_score + p_score + d_score + 0.0001
			r_score /= sum
			c_score /= sum
			i_score /= sum
			p_score /= sum
			d_score /= sum

			var r := _rng.randf()
			var zone := ZoneType.RESIDENTIAL

			if r < r_score:
				zone = ZoneType.RESIDENTIAL
			elif r < r_score + c_score:
				zone = ZoneType.COMMERCIAL
			elif r < r_score + c_score + i_score:
				zone = ZoneType.INDUSTRIAL
			elif r < r_score + c_score + i_score + p_score:
				zone = ZoneType.PARK
			else:
				zone = ZoneType.DOWNTOWN

			zones[idx] = zone

	return zones


func _generate_density() -> PackedFloat32Array:
	var density := PackedFloat32Array()
	density.resize(_grid_size_x * _grid_size_z)

	for z in range(_grid_size_z):
		for x in range(_grid_size_x):
			var idx := z * _grid_size_x + x

			var world_x : float = (float(x) / max(_grid_size_x - 1, 1) - 0.5) * city_size_x
			var world_z : float = (float(z) / max(_grid_size_z - 1, 1) - 0.5) * city_size_z

			var dn := _density_noise.get_noise_2d(world_x, world_z)
			dn = (dn + 1.0) * 0.5

			var dist_center := Vector2(world_x, world_z).length()
			var center_factor := pow(1.0 - clamp(dist_center / max(downtown_radius * 1.5, 1.0), 0.0, 1.0), 2.0)

			var final_density : float = clamp(dn * 0.6 + center_factor * 0.7, 0.0, 1.0)
			density[idx] = final_density

	return density


func _spawn_roads(road_grid: Array) -> void:
	if road_segment_scene == null and intersection_scene == null:
		return

	for z in range(_grid_size_z):
		for x in range(_grid_size_x):
			var idx := z * _grid_size_x + x
			var cell : Object = road_grid[idx]

			var world_x : float = (float(x) / max(_grid_size_x - 1, 1) - 0.5) * city_size_x
			var world_z : float = (float(z) / max(_grid_size_z - 1, 1) - 0.5) * city_size_z
			var pos := Vector3(world_x, 0.0, world_z)

			var h: bool = cell["h"]
			var v: bool = cell["v"]
			var d: bool = cell["d"]

			if (h and v) or (h and d) or (v and d):
				if intersection_scene != null:
					var inter := intersection_scene.instantiate()
					add_child(inter)
					inter.global_transform.origin = pos
				continue

			if h and road_segment_scene != null:
				var road_h := road_segment_scene.instantiate()
				add_child(road_h)
				road_h.global_transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, 0.0), pos)

			if v and road_segment_scene != null:
				var road_v := road_segment_scene.instantiate()
				add_child(road_v)
				road_v.global_transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, PI * 0.5), pos)

			if d and road_segment_scene != null:
				var angle := PI * 0.25
				var road_d := road_segment_scene.instantiate()
				add_child(road_d)
				road_d.global_transform = Transform3D(Basis.IDENTITY.rotated(Vector3.UP, angle), pos)

			if sidewalk_segment_scene != null and (h or v or d):
				var side := sidewalk_segment_scene.instantiate()
				add_child(side)
				side.global_transform.origin = pos


func _spawn_buildings(road_grid: Array, zones: Array, density: PackedFloat32Array) -> void:
	for z in range(_grid_size_z):
		for x in range(_grid_size_x):
			var idx := z * _grid_size_x + x
			var cell : Object = road_grid[idx]
			var zone: int = zones[idx]
			var dens: float = density[idx]

			if cell["h"] or cell["v"] or cell["d"]:
				continue

			var world_x : float = (float(x) / max(_grid_size_x - 1, 1) - 0.5) * city_size_x
			var world_z : float = (float(z) / max(_grid_size_z - 1, 1) - 0.5) * city_size_z
			var base_pos := Vector3(world_x, 0.0, world_z)

			var assets: Array[CityAsset] = []
			match zone:
				ZoneType.RESIDENTIAL:
					assets = residential_assets
				ZoneType.COMMERCIAL:
					assets = commercial_assets
				ZoneType.INDUSTRIAL:
					assets = industrial_assets
				ZoneType.PARK:
					assets = park_assets
				ZoneType.DOWNTOWN:
					assets =  downtown_assets if downtown_assets.size() > 0 else commercial_assets

			if assets.is_empty():
				continue

			var asset: CityAsset = _choose_weighted_asset(assets, dens)
			if asset == null or asset.scene == null:
				continue

			var instance := asset.scene.instantiate()
			add_child(instance)

			var rand_offset_x := (_rng.randf() - 0.5) * (block_size_x - road_width)
			var rand_offset_z := (_rng.randf() - 0.5) * (block_size_z - road_width)
			var pos := base_pos + Vector3(rand_offset_x, 0.0, rand_offset_z)

			var height_base := _compute_base_height(zone, dens)
			var height_variation := (_rng.randf() - 0.5) * 2.0 * base_height_random_variation
			var total_height := height_base + height_variation
			if snap_height_to_floor > 0.0:
				total_height = round(total_height / snap_height_to_floor) * snap_height_to_floor
			total_height = max(total_height, snap_height_to_floor)

			var scale_y : float = max(total_height / max(snap_height_to_floor, 0.001), 0.1)
			var uniform_scale := _rng.randf_range(asset.min_scale, asset.max_scale)

			basis = basis.rotated(Vector3.UP, _rng.randf_range(0.0, TAU))
			basis = basis.scaled(Vector3(uniform_scale, scale_y, uniform_scale))

			instance.global_transform = Transform3D(basis, pos)


func _spawn_plazas(zones: Array, density: PackedFloat32Array) -> void:
	if plaza_scene == null:
		return

	for z in range(1, _grid_size_z - 1):
		for x in range(1, _grid_size_x - 1):
			var idx := z * _grid_size_x + x
			var zone: int = zones[idx]
			var dens: float = density[idx]

			if zone != ZoneType.DOWNTOWN and zone != ZoneType.COMMERCIAL:
				continue
			if dens < 0.6:
				continue
			if _rng.randf() > 0.03:
				continue

			var world_x : float = (float(x) / max(_grid_size_x - 1, 1) - 0.5) * city_size_x
			var world_z : float = (float(z) / max(_grid_size_z - 1, 1) - 0.5) * city_size_z
			var pos := Vector3(world_x, 0.0, world_z)

			var plaza := plaza_scene.instantiate()
			add_child(plaza)
			plaza.global_transform.origin = pos


func _choose_weighted_asset(assets: Array[CityAsset], density: float) -> CityAsset:
	var total := 0.0
	for a in assets:
		if a == null:
			continue
		var w : float = max(a.weight * lerp(0.4, 1.6, a.density_factor * density), 0.0)
		total += w

	if total <= 0.0:
		return null

	var r := _rng.randf() * total
	var acc := 0.0
	for a in assets:
		if a == null:
			continue
		var w : float = max(a.weight * lerp(0.4, 1.6, a.density_factor * density), 0.0)
		acc += w
		if r <= acc:
			return a

	return assets[assets.size() - 1]


func _compute_base_height(zone: int, density: float) -> float:
	match zone:
		ZoneType.RESIDENTIAL:
			return base_height_residential * (0.6 + density * 0.8)
		ZoneType.COMMERCIAL:
			return base_height_commercial * (0.7 + density * 1.2)
		ZoneType.INDUSTRIAL:
			return base_height_industrial * (0.8 + density * 0.6)
		ZoneType.PARK:
			return 0.0
		ZoneType.DOWNTOWN:
			return base_height_downtown * (0.8 + density * 1.8)
		_:
			return base_height_residential


func _create_collision_from_mesh(_m: Mesh) -> void:
	pass # optional: add navmesh / collision for city if needed
