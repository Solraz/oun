# res://addons/terrain_tools/terrain_erosion_editor.gd
@tool
extends EditorPlugin

var _dock: VBoxContainer


func _enter_tree() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Terrain Erosion"

	var btn_regen := Button.new()
	btn_regen.text = "Regenerate Selected Chunks"
	btn_regen.pressed.connect(_on_regen_pressed)
	_dock.add_child(btn_regen)

	var btn_cpu := Button.new()
	btn_cpu.text = "Set Erosion Backend: CPU Single"
	btn_cpu.pressed.connect(func(): _set_backend(TerrainChunk.Backends.CPU_SINGLE))
	_dock.add_child(btn_cpu)

	var btn_cpu_mt := Button.new()
	btn_cpu_mt.text = "Set Erosion Backend: CPU Multi"
	btn_cpu_mt.pressed.connect(func(): _set_backend(TerrainChunk.Backends.CPU_MULTI))
	_dock.add_child(btn_cpu_mt)

	var btn_gpu := Button.new()
	btn_gpu.text = "Set Erosion Backend: GPU SubViewport"
	btn_gpu.pressed.connect(func(): _set_backend(TerrainChunk.Backends.GPU))
	_dock.add_child(btn_gpu)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.free()


func _get_selected_chunks() -> Array:
	var selection := get_editor_interface().get_selection()
	var result: Array = []
	for node in selection.get_selected_nodes():
		if node is TerrainChunk:
			result.append(node)
	return result


func _on_regen_pressed() -> void:
	for chunk in _get_selected_chunks():
		chunk.generate()


func _set_backend(backend: int) -> void:
	for chunk in _get_selected_chunks():
		chunk.erosion_backend = backend
