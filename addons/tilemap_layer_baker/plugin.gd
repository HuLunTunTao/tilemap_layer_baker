@tool
extends EditorPlugin

const BakerDock := preload("res://addons/tilemap_layer_baker/tilemap_layer_baker_dock.gd")

var _dock: Control

func _enter_tree() -> void:
	_dock = BakerDock.new()
	_dock.setup(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	add_tool_menu_item("Bake Selected TileMapLayers", Callable(_dock, "bake_selected"))

func _exit_tree() -> void:
	remove_tool_menu_item("Bake Selected TileMapLayers")
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
