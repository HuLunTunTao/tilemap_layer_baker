@tool
extends VBoxContainer

const TileMapLayerBaker := preload("res://addons/tilemap_layer_baker/tilemap_layer_baker.gd")

var _editor_interface
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
	name = "TileMap Baker"
	_build_ui()

func _build_ui() -> void:
	custom_minimum_size = Vector2(300, 0)

	var title := Label.new()
	title.text = "TileMapLayer Baker"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	var hint := Label.new()
	hint.text = "选中一个或多个静态 TileMapLayer 后，一键烘焙成 PNG + Sprite2D。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	add_child(_make_separator())

	add_child(_make_field_label("输出目录"))
	_output_dir_edit = LineEdit.new()
	_output_dir_edit.text = "res://assets/baked"
	_output_dir_edit.placeholder_text = "res://assets/baked"
	add_child(_output_dir_edit)

	add_child(_make_field_label("文件前缀（留空使用场景名）"))
	_prefix_edit = LineEdit.new()
	_prefix_edit.placeholder_text = "level1_4"
	add_child(_prefix_edit)

	_combine_by_z_check = CheckBox.new()
	_combine_by_z_check.text = "按 z_index 分组合并"
	_combine_by_z_check.button_pressed = true
	add_child(_combine_by_z_check)

	_hide_sources_check = CheckBox.new()
	_hide_sources_check.text = "烘焙后隐藏源 TileMapLayer"
	_hide_sources_check.button_pressed = true
	add_child(_hide_sources_check)

	_include_hidden_check = CheckBox.new()
	_include_hidden_check.text = "包含隐藏图层（便于重新烘焙）"
	_include_hidden_check.button_pressed = true
	add_child(_include_hidden_check)

	_overwrite_check = CheckBox.new()
	_overwrite_check.text = "覆盖同名 PNG / Baked Sprite"
	_overwrite_check.button_pressed = true
	add_child(_overwrite_check)

	_bake_button = Button.new()
	_bake_button.text = "烘焙选中 TileMapLayer"
	_bake_button.tooltip_text = "也可以从 Project > Tools > Bake Selected TileMapLayers 触发"
	_bake_button.pressed.connect(bake_selected)
	add_child(_bake_button)

	_status_label = RichTextLabel.new()
	_status_label.fit_content = true
	_status_label.bbcode_enabled = true
	_status_label.scroll_active = false
	_status_label.text = "[color=gray]等待选择 TileMapLayer。[/color]"
	add_child(_status_label)

func _make_field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _make_separator() -> HSeparator:
	return HSeparator.new()

func bake_selected() -> void:
	if _editor_interface == null:
		_set_status("[color=red]EditorInterface 不可用。[/color]")
		return

	var selected_layers := _get_selected_tilemap_layers()
	if selected_layers.is_empty():
		_set_status("[color=yellow]请先在场景树中选择一个或多个 TileMapLayer。[/color]")
		return

	_bake_button.disabled = true
	_set_status("[color=gray]正在烘焙 %d 个 TileMapLayer...[/color]" % selected_layers.size())

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
		_set_status("[color=red]%s[/color]" % result.get("error", "烘焙失败"))
		return

	await _import_as_vram_textures(result.get("files", []))
	TileMapLayerBaker.assign_imported_textures(result.get("sprite_nodes", []), result.get("files", []))
	_bake_button.disabled = false

	var lines: Array[String] = []
	lines.append("[color=green]烘焙完成：%d 张 PNG，%d 个 Sprite2D。[/color]" % [result.get("files", []).size(), result.get("sprites", []).size()])
	for file_path in result.get("files", []):
		lines.append("- %s" % file_path)
	lines.append("[color=gray]源 TileMapLayer 已保留，只是按选项隐藏；请检查画面后保存场景。[/color]")
	_set_status("\n".join(lines))

func _get_selected_tilemap_layers() -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	var selection = _editor_interface.get_selection()
	for node in selection.get_selected_nodes():
		if node is TileMapLayer:
			layers.append(node)
	return layers

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
