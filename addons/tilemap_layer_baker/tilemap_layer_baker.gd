@tool
extends RefCounted

const BAKER_META := "tilemap_layer_baker"
const BAKER_GROUP_META := "tilemap_layer_baker_group"
const MAX_TEXTURE_SIZE := 8192
const DEFAULT_NODE_NAME_TEMPLATE := "BakedZ{z}"
const _ALLOWED_NODE_NAME_PLACEHOLDERS := ["z", "layer", "scene", "index"]
const I18N := preload("res://addons/tilemap_layer_baker/tilemap_layer_baker_i18n.gd")

static func prepare_bake_plan(layers: Array, options: Dictionary) -> Dictionary:
	var valid_layers := _filter_layers(layers, options.get("include_hidden", true))
	if valid_layers.is_empty():
		return {"ok": false, "error": I18N.t("No TileMapLayer can be baked.")}

	var scene_root := _find_scene_root(valid_layers[0])
	if scene_root == null:
		return {"ok": false, "error": I18N.t("Cannot find the current scene root.")}

	var output_dir := String(options.get("output_dir", "res://assets/baked")).strip_edges()
	if output_dir.is_empty():
		output_dir = "res://assets/baked"
	if not output_dir.begins_with("res://"):
		return {"ok": false, "error": I18N.t("Output directory must start with res://.")}

	var prefix := String(options.get("prefix", "")).strip_edges()
	if prefix.is_empty():
		prefix = _scene_prefix(scene_root)
	prefix = _safe_file_name(prefix)

	var template := String(options.get("node_name_template", "")).strip_edges()
	if template.is_empty():
		template = DEFAULT_NODE_NAME_TEMPLATE

	var placeholder_error := _validate_node_name_template(template)
	if not placeholder_error.is_empty():
		return {"ok": false, "error": placeholder_error}

	var groups := _make_groups(valid_layers, options.get("combine_by_z", true))
	var outputs: Array[Dictionary] = []
	var conflicts: Array[Dictionary] = []
	var node_names_by_parent := {}
	var scene_name := _scene_display_name(scene_root)
	var overwrite := options.get("overwrite", true)
	var index := 1

	for group_key in groups.keys():
		var group_layers: Array = groups[group_key]
		_sort_layers_for_draw(group_layers)
		var parent: Node = _common_parent(group_layers)
		if parent == null:
			parent = valid_layers[0].get_parent()
		var z_index := _group_z_index(group_layers)
		var layer_name := _template_layer_name(group_layers, parent, scene_name)
		var node_name_result := _make_node_name(template, z_index, layer_name, scene_name, index)
		if not node_name_result.get("ok", false):
			return node_name_result

		var file_name := "%s_%s.png" % [prefix, _safe_file_name(String(group_key))]
		var original_png_path := output_dir.path_join(file_name)
		var png_path := original_png_path
		if not overwrite:
			png_path = _deduplicate_path(png_path)

		var output := {
			"group_key": group_key,
			"layers": group_layers,
			"parent": parent,
			"node_name": node_name_result["node_name"],
			"z_index": z_index,
			"png_path": png_path,
			"original_png_path": original_png_path,
		}
		outputs.append(output)

		var parent_key := str(parent.get_instance_id())
		var node_key := "%s/%s" % [parent_key, output["node_name"]]
		if node_names_by_parent.has(node_key):
			return {
				"ok": false,
				"error": I18N.t("Node name template creates duplicate output node: %s. Add {z}, {layer}, or {index}.") % output["node_name"],
			}
		node_names_by_parent[node_key] = true

		var existing_node := parent.get_node_or_null(output["node_name"])
		if existing_node != null:
			if not overwrite:
				return {
					"ok": false,
					"error": I18N.t("Target node already exists: %s. Change Node Name Template or enable overwrite.") % _scene_node_path(existing_node, scene_root),
				}
			output["replace_node_path"] = str(existing_node.get_path())
			conflicts.append({
				"type": "node",
				"path": _scene_node_path(existing_node, scene_root),
				"is_baked": existing_node.get_meta(BAKER_META, false),
			})

		if overwrite and (ResourceLoader.exists(original_png_path) or FileAccess.file_exists(original_png_path)):
			conflicts.append({
				"type": "file",
				"path": original_png_path,
				"is_baked": true,
			})

		index += 1

	return {
		"ok": true,
		"valid_layers": valid_layers,
		"scene_root": scene_root,
		"output_dir": output_dir,
		"prefix": prefix,
		"outputs": outputs,
		"conflicts": conflicts,
	}

static func bake_layers(layers: Array, options: Dictionary, editor_interface = null) -> Dictionary:
	var plan: Dictionary = options.get("bake_plan", {})
	if plan.is_empty():
		plan = prepare_bake_plan(layers, options)
	if not plan.get("ok", false):
		return plan

	var valid_layers: Array = plan.get("valid_layers", [])
	var output_dir := String(plan.get("output_dir", "res://assets/baked"))
	if not _ensure_dir(output_dir):
		return {"ok": false, "error": I18N.t("Cannot create output directory: %s") % output_dir}

	var created_files: Array[String] = []
	var created_sprites: Array[NodePath] = []
	var created_sprite_nodes: Array[Sprite2D] = []
	var errors: Array[String] = []

	for output in plan.get("outputs", []):
		var group_key = output["group_key"]
		var group_layers: Array = output["layers"]
		var bake := _compose_group(group_layers)
		if not bake.get("ok", false):
			errors.append("%s: %s" % [group_key, bake.get("error", I18N.t("Failed"))])
			continue

		var png_path := String(output["png_path"])
		var image: Image = bake["image"]
		var save_error := image.save_png(png_path)
		if save_error != OK:
			errors.append(I18N.t("Failed to save %s: %s") % [png_path, error_string(save_error)])
			continue

		var parent: Node = output["parent"]
		var sprite := _create_or_replace_sprite(parent, output["node_name"], output.get("replace_node_path", ""))
		if sprite == null:
			var existing_node := parent.get_node_or_null(output["node_name"])
			var existing_path := str(existing_node.get_path()) if existing_node != null else String(output["node_name"])
			errors.append(I18N.t("Target node already exists: %s. Change Node Name Template or enable overwrite.") % existing_path)
			continue
		_configure_sprite(sprite, png_path, bake, group_layers, parent, String(group_key))
		created_files.append(png_path)
		created_sprites.append(sprite.get_path())
		created_sprite_nodes.append(sprite)

	if options.get("hide_sources", true):
		for layer in valid_layers:
			layer.visible = false

	if editor_interface != null and editor_interface.has_method("mark_scene_as_unsaved"):
		editor_interface.mark_scene_as_unsaved()

	if created_files.is_empty():
		return {"ok": false, "error": I18N.t("No PNG was generated. %s") % "; ".join(errors)}
	return {"ok": true, "files": created_files, "sprites": created_sprites, "sprite_nodes": created_sprite_nodes, "errors": errors}

static func update_texture_import_for_vram(res_path: String) -> bool:
	var import_path := "%s.import" % res_path
	if not FileAccess.file_exists(import_path):
		return false
	var config := ConfigFile.new()
	var err := config.load(import_path)
	if err != OK:
		return false
	var metadata = config.get_value("remap", "metadata", {})
	if typeof(metadata) != TYPE_DICTIONARY:
		metadata = {}
	metadata["vram_texture"] = true
	if not metadata.has("imported_formats"):
		metadata["imported_formats"] = ["s3tc_bptc", "etc2_astc"]
	config.set_value("remap", "metadata", metadata)
	config.set_value("params", "compress/mode", 2)
	config.set_value("params", "compress/high_quality", false)
	config.set_value("params", "compress/lossy_quality", 0.7)
	config.set_value("params", "mipmaps/generate", false)
	config.set_value("params", "process/fix_alpha_border", true)
	return config.save(import_path) == OK

static func assign_imported_textures(sprites: Array, files: Array) -> void:
	for index in range(mini(sprites.size(), files.size())):
		var sprite := sprites[index] as Sprite2D
		if sprite == null:
			continue
		var texture := ResourceLoader.load(files[index], "Texture2D", ResourceLoader.CACHE_MODE_REPLACE)
		if texture != null:
			sprite.texture = texture

static func _filter_layers(layers: Array, include_hidden: bool) -> Array[TileMapLayer]:
	var result: Array[TileMapLayer] = []
	for item in layers:
		if item is TileMapLayer:
			var layer := item as TileMapLayer
			if layer.tile_set == null:
				continue
			if layer.get_used_cells().is_empty():
				continue
			if not include_hidden and not layer.visible:
				continue
			result.append(layer)
	return result

static func _make_groups(layers: Array[TileMapLayer], combine_by_z: bool) -> Dictionary:
	var groups := {}
	for layer in layers:
		var key := layer.name
		if combine_by_z:
			key = "z%s" % layer.z_index
		if not groups.has(key):
			groups[key] = []
		groups[key].append(layer)
	return groups

static func _compose_group(layers: Array) -> Dictionary:
	var items: Array[Dictionary] = []
	var bounds := Rect2()
	var has_bounds := false
	var texture_cache := {}

	for layer in layers:
		var layer_items: Array[Dictionary] = []
		for cell in layer.get_used_cells():
			var item := _make_draw_item(layer, cell, texture_cache)
			if item.is_empty():
				continue
			layer_items.append(item)
			var rect: Rect2 = item["rect"]
			if has_bounds:
				bounds = bounds.merge(rect)
			else:
				bounds = rect
				has_bounds = true
		_sort_items_for_draw(layer_items)
		items.append_array(layer_items)

	if items.is_empty() or not has_bounds:
		return {"ok": false, "error": I18N.t("Selected layers have no drawable tiles.")}

	var min_pos := Vector2(floorf(bounds.position.x), floorf(bounds.position.y))
	var max_pos := Vector2(ceilf(bounds.end.x), ceilf(bounds.end.y))
	var size := Vector2i(int(max_pos.x - min_pos.x), int(max_pos.y - min_pos.y))
	if size.x <= 0 or size.y <= 0:
		return {"ok": false, "error": I18N.t("Invalid bake size.")}
	if size.x > MAX_TEXTURE_SIZE or size.y > MAX_TEXTURE_SIZE:
		return {"ok": false, "error": I18N.t("Bake size %dx%d exceeds the safety limit %d. Split the layer first.") % [size.x, size.y, MAX_TEXTURE_SIZE]}

	var canvas := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	for item in items:
		var tile_image: Image = item["image"]
		var dest := Vector2i(roundi(item["rect"].position.x - min_pos.x), roundi(item["rect"].position.y - min_pos.y))
		canvas.blend_rect(tile_image, Rect2i(Vector2i.ZERO, tile_image.get_size()), dest)

	return {
		"ok": true,
		"image": canvas,
		"global_center": min_pos + Vector2(size) * 0.5,
		"global_bounds": Rect2(min_pos, Vector2(size)),
	}

static func _make_draw_item(layer: TileMapLayer, cell: Vector2i, texture_cache: Dictionary) -> Dictionary:
	var source_id := layer.get_cell_source_id(cell)
	if source_id < 0 or layer.tile_set == null:
		return {}
	var source := layer.tile_set.get_source(source_id)
	if not (source is TileSetAtlasSource):
		return {}
	var atlas_source := source as TileSetAtlasSource
	var texture := atlas_source.get_texture()
	if texture == null:
		return {}
	var texture_image := _get_texture_image(texture, texture_cache)
	if texture_image == null:
		return {}

	var atlas_coords := layer.get_cell_atlas_coords(cell)
	var region: Rect2i = atlas_source.get_tile_texture_region(atlas_coords, 0)
	if region.size.x <= 0 or region.size.y <= 0:
		return {}

	var tile_image := Image.create(region.size.x, region.size.y, false, Image.FORMAT_RGBA8)
	tile_image.blit_rect(texture_image, region, Vector2i.ZERO)

	var alternative := layer.get_cell_alternative_tile(cell)
	var tile_data := atlas_source.get_tile_data(atlas_coords, alternative)
	var texture_origin := Vector2.ZERO
	var modulate := layer.modulate * layer.self_modulate
	if tile_data != null:
		texture_origin = Vector2(tile_data.get_texture_origin())
		modulate *= tile_data.get_modulate()

	var flip_h := layer.is_cell_flipped_h(cell)
	var flip_v := layer.is_cell_flipped_v(cell)
	if _layer_flips_h(layer):
		flip_h = not flip_h
		texture_origin.x = -texture_origin.x
	if _layer_flips_v(layer):
		flip_v = not flip_v
		texture_origin.y = -texture_origin.y
	if layer.is_cell_transposed(cell):
		tile_image = _transpose_image(tile_image)
		var old_x := texture_origin.x
		texture_origin.x = texture_origin.y
		texture_origin.y = old_x
	if flip_h:
		tile_image.flip_x()
	if flip_v:
		tile_image.flip_y()
	_apply_modulate(tile_image, modulate)

	var center := layer.to_global(layer.map_to_local(cell))
	var top_left := center - Vector2(tile_image.get_size()) * 0.5 + texture_origin
	var rect := Rect2(top_left, Vector2(tile_image.get_size()))
	var local_position := layer.map_to_local(cell)
	var z_index := 0
	var y_sort_origin := 0
	if tile_data != null:
		z_index = tile_data.z_index
		y_sort_origin = tile_data.y_sort_origin
	return {
		"image": tile_image,
		"rect": rect,
		"cell": cell,
		"local_position": local_position,
		"z_index": z_index,
		"y_sort_origin": y_sort_origin,
	}

static func _get_texture_image(texture: Texture2D, texture_cache: Dictionary) -> Image:
	var key := str(texture.get_rid())
	if texture_cache.has(key):
		return texture_cache[key]
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	texture_cache[key] = image
	return image

static func _transpose_image(source: Image) -> Image:
	var size := source.get_size()
	var result := Image.create(size.y, size.x, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			result.set_pixel(y, x, source.get_pixel(x, y))
	return result

static func _apply_modulate(image: Image, color: Color) -> void:
	if color.is_equal_approx(Color.WHITE):
		return
	var size := image.get_size()
	for y in range(size.y):
		for x in range(size.x):
			image.set_pixel(x, y, image.get_pixel(x, y) * color)

static func _layer_flips_h(layer: CanvasItem) -> bool:
	var x_axis: Vector2 = layer.global_transform.x.normalized()
	return absf(x_axis.x) >= absf(x_axis.y) and x_axis.x < 0.0

static func _layer_flips_v(layer: CanvasItem) -> bool:
	var y_axis: Vector2 = layer.global_transform.y.normalized()
	return absf(y_axis.y) >= absf(y_axis.x) and y_axis.y < 0.0

static func _configure_sprite(sprite: Sprite2D, texture_path: String, bake: Dictionary, layers: Array, parent: Node, group_key: String) -> void:
	var texture := load(texture_path)
	if texture != null:
		sprite.texture = texture
	elif bake.has("image"):
		sprite.texture = ImageTexture.create_from_image(bake["image"])
	else:
		sprite.set("texture", load(texture_path))
	sprite.centered = true
	sprite.position = parent.to_local(bake["global_center"])
	sprite.z_index = _group_z_index(layers)
	sprite.texture_filter = layers[0].texture_filter
	sprite.set_meta(BAKER_META, true)
	sprite.set_meta(BAKER_GROUP_META, group_key)
	_set_owner_recursive(sprite, _find_scene_root(parent))

static func _create_or_replace_sprite(parent: Node, node_name: String, replace_node_path: String) -> Sprite2D:
	var old := parent.get_node_or_null(node_name)
	if old != null:
		if replace_node_path == str(old.get_path()):
			parent.remove_child(old)
			old.free()
		else:
			return null
	var sprite := Sprite2D.new()
	sprite.name = node_name
	parent.add_child(sprite)
	return sprite

static func _common_parent(layers: Array) -> Node:
	if layers.is_empty():
		return null
	var parent: Node = layers[0].get_parent()
	for layer in layers:
		if layer.get_parent() != parent:
			return layers[0].get_parent()
	return parent

static func _group_z_index(layers: Array) -> int:
	if layers.is_empty():
		return 0
	return int(layers[0].z_index)

static func _sort_layers_for_draw(layers: Array) -> void:
	layers.sort_custom(func(a: Node, b: Node) -> bool:
		if a.z_index == b.z_index:
			return _is_before_in_tree(a, b)
		return a.z_index < b.z_index
	)

static func _sort_items_for_draw(items: Array[Dictionary]) -> void:
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["z_index"] != b["z_index"]:
			return a["z_index"] < b["z_index"]
		var a_pos: Vector2 = a["local_position"]
		var b_pos: Vector2 = b["local_position"]
		var a_y := a_pos.y + float(a["y_sort_origin"])
		var b_y := b_pos.y + float(b["y_sort_origin"])
		if not is_equal_approx(a_y, b_y):
			return a_y < b_y
		if not is_equal_approx(a_pos.x, b_pos.x):
			return a_pos.x < b_pos.x
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]
		if a_cell.y == b_cell.y:
			return a_cell.x < b_cell.x
		return a_cell.y < b_cell.y
	)

static func _is_before_in_tree(a: Node, b: Node) -> bool:
	var a_chain := _node_index_chain(a)
	var b_chain := _node_index_chain(b)
	var count := mini(a_chain.size(), b_chain.size())
	for index in range(count):
		if a_chain[index] != b_chain[index]:
			return a_chain[index] < b_chain[index]
	return a_chain.size() < b_chain.size()

static func _node_index_chain(node: Node) -> Array[int]:
	var chain: Array[int] = []
	var current := node
	while current != null:
		chain.push_front(current.get_index())
		current = current.get_parent()
	return chain

static func _find_scene_root(node: Node) -> Node:
	var current := node
	while current != null:
		if current.owner == null and current.scene_file_path != "":
			return current
		current = current.get_parent()
	return node.get_tree().edited_scene_root if node.get_tree() != null else null

static func _set_owner_recursive(node: Node, owner: Node) -> void:
	if owner == null:
		return
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)

static func _ensure_dir(res_dir: String) -> bool:
	var absolute := ProjectSettings.globalize_path(res_dir)
	return DirAccess.make_dir_recursive_absolute(absolute) == OK

static func _scene_prefix(scene_root: Node) -> String:
	var scene_path := scene_root.scene_file_path
	if scene_path.is_empty():
		return _safe_file_name(scene_root.name)
	return _safe_file_name(scene_path.get_file().get_basename())

static func _scene_display_name(scene_root: Node) -> String:
	var scene_path := scene_root.scene_file_path
	if scene_path.is_empty():
		return scene_root.name
	return scene_path.get_file().get_basename()

static func _scene_node_path(node: Node, scene_root: Node) -> String:
	if node == null:
		return ""
	if scene_root == null:
		return str(node.get_path())
	if node == scene_root:
		return scene_root.name
	if scene_root.is_ancestor_of(node):
		return "%s/%s" % [scene_root.name, scene_root.get_path_to(node)]
	return str(node.get_path())

static func _safe_file_name(value: String) -> String:
	var result := value.to_lower()
	for token in [" ", "/", "\\", ":", "*", "?", "\"", "<", ">", "|", "=", "."]:
		result = result.replace(token, "_")
	while "__" in result:
		result = result.replace("__", "_")
	result = result.strip_edges().trim_prefix("_").trim_suffix("_")
	return result if not result.is_empty() else "tilemap"

static func _pascal_name(value: String) -> String:
	var safe := _safe_file_name(value)
	var parts := safe.split("_", false)
	var output := ""
	for part in parts:
		output += part.capitalize().replace(" ", "")
	return output if not output.is_empty() else "Tilemap"

static func _validate_node_name_template(template: String) -> String:
	var offset := 0
	while offset < template.length():
		var open := template.find("{", offset)
		var close := template.find("}", offset)
		if close != -1 and (open == -1 or close < open):
			return I18N.t("Node name template has an unopened placeholder.")
		if open == -1:
			return ""
		close = template.find("}", open + 1)
		if close == -1:
			return I18N.t("Node name template has an unclosed placeholder.")
		var placeholder := template.substr(open + 1, close - open - 1)
		if not _ALLOWED_NODE_NAME_PLACEHOLDERS.has(placeholder):
			return I18N.t("Unknown node name placeholder: {%s}. Supported placeholders: {z}, {layer}, {scene}, {index}.") % placeholder
		offset = close + 1
	return ""

static func _make_node_name(template: String, z_index: int, layer_name: String, scene_name: String, index: int) -> Dictionary:
	var rendered := template
	rendered = rendered.replace("{z}", _format_template_z(z_index))
	rendered = rendered.replace("{layer}", layer_name)
	rendered = rendered.replace("{scene}", scene_name)
	rendered = rendered.replace("{index}", "%02d" % index)
	var node_name := _safe_node_name(rendered)
	if node_name.is_empty():
		return {"ok": false, "error": I18N.t("Node name template produced an empty node name.")}
	return {"ok": true, "node_name": node_name}

static func _format_template_z(z_index: int) -> String:
	if z_index < 0:
		return "Minus%d" % absi(z_index)
	return str(z_index)

static func _template_layer_name(layers: Array, parent: Node, scene_name: String) -> String:
	if layers.size() == 1:
		return String(layers[0].name)
	if parent != null:
		return parent.name
	return scene_name

static func _safe_node_name(value: String) -> String:
	var normalized := value.strip_edges()
	for token in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "=", ".", ",", ";", " ", "\t", "\n", "\r", "-", "(", ")", "[", "]"]:
		normalized = normalized.replace(token, "_")
	while "__" in normalized:
		normalized = normalized.replace("__", "_")
	normalized = normalized.trim_prefix("_").trim_suffix("_")
	if normalized.is_empty():
		return ""
	var parts := normalized.split("_", false)
	var output := ""
	for part in parts:
		if part.is_empty():
			continue
		output += part.substr(0, 1).to_upper() + part.substr(1)
	return output

static func _deduplicate_path(path: String) -> String:
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return path
	var dir := path.get_base_dir()
	var base := path.get_file().get_basename()
	var ext := path.get_extension()
	var index := 2
	while true:
		var candidate := dir.path_join("%s_%02d.%s" % [base, index, ext])
		if not ResourceLoader.exists(candidate) and not FileAccess.file_exists(candidate):
			return candidate
		index += 1
	return path
