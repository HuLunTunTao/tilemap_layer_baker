# TileMapLayer Baker

Godot 4 editor plugin for baking large, static visual `TileMapLayer` nodes into PNG-backed `Sprite2D` backgrounds.

## Why

Static TileMap layers still cost draw/setup work at runtime. For low-end office laptops, large decorative/isometric layers can be cheaper as a few compressed background textures while the original TileMap data stays in the scene for editing or gameplay logic.

## Usage

1. Enable `TileMapLayer Baker` in **Project > Project Settings > Plugins**.
2. Open a level scene and select one or more non-interactive visual `TileMapLayer` nodes.
3. In the **TileMap Baker** dock, keep **按 z_index 分组合并** enabled if layers with the same `z_index` can be merged.
4. Click **烘焙选中 TileMapLayer**.
5. Check the result visually, then save the scene.

The plugin writes PNG files to `res://assets/baked` by default, adds `Sprite2D` nodes named `Baked...` under the original parent, and hides the source `TileMapLayer` nodes if that option is enabled.

## Notes

- Use this only for pure visual/static TileMap layers.
- Keep movement, obstacle, navigation, trigger, or y-sort logic TileMaps visible or handled separately.
- Re-baking is supported: select the hidden source layers again and keep **包含隐藏图层** + **覆盖同名 PNG / Baked Sprite** enabled.
- The baker uses image composition from TileSet atlas regions, not a viewport screenshot, so it can work without relying on runtime camera setup.
- Axis-aligned flips are supported; arbitrary rotated/scaled TileMap layers should be checked carefully after baking.
