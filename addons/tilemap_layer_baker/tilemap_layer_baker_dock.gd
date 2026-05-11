@tool
extends VBoxContainer

const TileMapLayerBaker := preload("res://addons/tilemap_layer_baker/tilemap_layer_baker.gd")
const I18N := preload("res://addons/tilemap_layer_baker/tilemap_layer_baker_i18n.gd")

var _editor_interface
var _title_label: Label
var _hint_label: Label
var _output_dir_label: Label
var _prefix_label: Label
var _output_dir_edit: LineEdit
var _prefix_edit: LineEdit
var _combine_by_z_check: CheckBox
var _hide_sources_check: CheckBox
var _include_hidden_check: CheckBox
var _overwrite_check: CheckBox
var _status_label: RichTextLabel
var _bake_button: Button

func setup(editor_interface) -> void:
	_editor_interface = editor_interface
	I18N.update_editor_locale(editor_interface)
	name = I18N.t("TileMap Baker")
	_build_ui()

func _build_ui() -> void:
	custom_minimum_size = Vector2(300, 0)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	add_child(_title_label)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)

	add_child(_make_separator())

	_output_dir_label = _make_field_label("")
	add_child(_output_dir_label)
	_output_dir_edit = LineEdit.new()
	_output_dir_edit.text = "res://assets/baked"
	_output_dir_edit.placeholder_text = "res://assets/baked"
	add_child(_output_dir_edit)

	_prefix_label = _make_field_label("")
	add_child(_prefix_label)
	_prefix_edit = LineEdit.new()
	_prefix_edit.placeholder_text = "level1_4"
	add_child(_prefix_edit)

	_combine_by_z_check = CheckBox.new()
	_combine_by_z_check.button_pressed = true
	add_child(_combine_by_z_check)

	_hide_sources_check = CheckBox.new()
	_hide_sources_check.button_pressed = true
	add_child(_hide_sources_check)

	_include_hidden_check = CheckBox.new()
	_include_hidden_check.button_pressed = true
	add_child(_include_hidden_check)

	_overwrite_check = CheckBox.new()
	_overwrite_check.button_pressed = true
	add_child(_overwrite_check)

	_bake_button = Button.new()
	_bake_button.pressed.connect(bake_selected)
	add_child(_bake_button)

	_status_label = RichTextLabel.new()
	_status_label.fit_content = true
	_status_label.bbcode_enabled = true
	_status_label.scroll_active = false
	add_child(_status_label)
	refresh_translations()

func refresh_translations() -> void:
	I18N.update_editor_locale(_editor_interface)
	name = I18N.t("TileMap Baker")
	if _title_label != null:
		_title_label.text = I18N.t("TileMapLayer Baker")
	if _hint_label != null:
		_hint_label.text = I18N.t("Select one or more static TileMapLayer nodes, then bake them into PNG + Sprite2D.")
	if _output_dir_label != null:
		_output_dir_label.text = I18N.t("Output Directory")
	if _prefix_label != null:
		_prefix_label.text = I18N.t("File Prefix (leave empty to use scene name)")
	if _combine_by_z_check != null:
		_combine_by_z_check.text = I18N.t("Combine by z_index")
	if _hide_sources_check != null:
		_hide_sources_check.text = I18N.t("Hide source TileMapLayers after baking")
	if _include_hidden_check != null:
		_include_hidden_check.text = I18N.t("Include hidden layers (for rebaking)")
	if _overwrite_check != null:
		_overwrite_check.text = I18N.t("Overwrite matching PNG / Baked Sprite")
	if _bake_button != null:
		_bake_button.text = I18N.t("Bake Selected TileMapLayer(s)")
	if _status_label != null and _status_label.text.is_empty():
		_status_label.text = "[color=gray]%s[/color]" % I18N.t("Waiting for TileMapLayer selection.")

func _make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _make_separator() -> HSeparator:
	return HSeparator.new()

func bake_selected() -> void:
	if _editor_interface == null:
		_set_status("[color=red]%s[/color]" % I18N.t("EditorInterface is unavailable."))
		return

	var selected_layers := _get_selected_tilemap_layers()
	if selected_layers.is_empty():
		_set_status("[color=yellow]%s[/color]" % I18N.t("Select one or more TileMapLayer nodes in the scene tree first."))
		return

	_bake_button.disabled = true
	_set_status("[color=gray]%s[/color]" % (I18N.t("Baking %d TileMapLayer(s)...") % selected_layers.size()))

	var options := {
		"output_dir": _output_dir_edit.text.strip_edges(),
		"prefix": _prefix_edit.text.strip_edges(),
		"combine_by_z": _combine_by_z_check.button_pressed,
		"hide_sources": _hide_sources_check.button_pressed,
		"include_hidden": _include_hidden_check.button_pressed,
		"overwrite": _overwrite_check.button_pressed,
	}
	var result := TileMapLayerBaker.bake_layers(selected_layers, options, _editor_interface)

	if not result.get("ok", false):
		_bake_button.disabled = false
		_set_status("[color=red]%s[/color]" % result.get("error", I18N.t("Bake failed")))
		return

	await _import_as_vram_textures(result.get("files", []))
	TileMapLayerBaker.assign_imported_textures(result.get("sprite_nodes", []), result.get("files", []))
	_bake_button.disabled = false

	var lines: Array[String] = []
	lines.append("[color=green]%s[/color]" % (I18N.t("Bake finished: %d PNG(s), %d Sprite2D node(s).") % [result.get("files", []).size(), result.get("sprites", []).size()]))
	for file_path in result.get("files", []):
		lines.append("- %s" % file_path)
	lines.append("[color=gray]%s[/color]" % I18N.t("Source TileMapLayer nodes were kept and hidden according to the option; inspect the scene before saving."))
	_set_status("\n".join(lines))

func _get_selected_tilemap_layers() -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	var selection = _editor_interface.get_selection()
	var seen := {}
	for node in selection.get_selected_nodes():
		_collect_tilemap_layers(node, layers, seen)
	return layers

func _collect_tilemap_layers(node: Node, layers: Array[TileMapLayer], seen: Dictionary) -> void:
	if node is TileMapLayer and not seen.has(node.get_instance_id()):
		seen[node.get_instance_id()] = true
		layers.append(node)
	for child in node.get_children():
		_collect_tilemap_layers(child, layers, seen)

func _import_as_vram_textures(files: Array) -> void:
	if files.is_empty() or _editor_interface == null:
		return
	var fs = _editor_interface.get_resource_filesystem()
	if fs != null:
		fs.scan()
	await get_tree().create_timer(0.25).timeout
	for file_path in files:
		TileMapLayerBaker.update_texture_import_for_vram(file_path)
	if fs != null:
		fs.reimport_files(PackedStringArray(files))
		fs.scan()

func _set_status(bbcode: String) -> void:
	_status_label.text = bbcode
