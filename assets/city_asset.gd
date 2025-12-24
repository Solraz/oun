class_name CityAsset
extends Resource

@export var scene: PackedScene
@export var weight: float = 1.0
@export var min_scale: float = 1.0
@export var max_scale: float = 1.0
@export_range(0.0, 1.0, 0.01) var density_factor: float = 1.0
