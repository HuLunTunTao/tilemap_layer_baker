@tool
extends EditorPlugin

const BakerDock := preload("res://addons/tilemap_layer_baker/tilemap_layer_baker_dock.gd")
const I18N := preload("res://addons/tilemap_layer_baker/tilemap_layer_baker_i18n.gd")

var _dock: Control
var _editor_settings

func _enter_tree() -> void:
	var editor_interface := get_editor_interface()
	I18N.configure(editor_interface)
	_editor_settings = editor_interface.get_editor_settings()
	if _editor_settings != null and not _editor_settings.settings_changed.is_connected(_on_editor_settings_changed):
		_editor_settings.settings_changed.connect(_on_editor_settings_changed)
	_create_dock(editor_interface)

func _exit_tree() -> void:
	if _editor_settings != null and _editor_settings.settings_changed.is_connected(_on_editor_settings_changed):
		_editor_settings.settings_changed.disconnect(_on_editor_settings_changed)
	_editor_settings = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	I18N.reset()

func _create_dock(editor_interface) -> void:
	_dock = BakerDock.new()
	_dock.setup(editor_interface)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

func _on_editor_settings_changed() -> void:
	var editor_interface := get_editor_interface()
	if not I18N.update_editor_locale(editor_interface):
		return
	if _dock != null and _dock.has_method("refresh_translations"):
		_dock.refresh_translations()
