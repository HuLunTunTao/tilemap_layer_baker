# TileMapLayer Baker

TileMapLayer Baker is a Godot 4 editor plugin that bakes selected static visual `TileMapLayer` nodes into PNG-backed `Sprite2D` backgrounds.

It is designed for decorative or background tile layers that do not need runtime TileMap behavior. Baking large static visual layers can reduce runtime TileMap processing and draw/setup overhead by replacing many tile cells with one or more regular sprites. The original `TileMapLayer` nodes stay in the scene for editing, and can be hidden after baking.

The editor UI supports English and Simplified Chinese.

## Features

- Bake one or more selected `TileMapLayer` nodes into PNG textures.
- Create matching `Sprite2D` nodes in the edited scene.
- Combine layers by `z_index` when they can share one baked image.
- Re-bake hidden source layers.
- Overwrite matching baked sprites and PNG files.
- Register English and Simplified Chinese editor UI text.

## Why Bake

Use this when a `TileMapLayer` is useful while editing but unnecessary at runtime. Background decoration, dense floor details, and other visual-only static layers can often be shipped more cheaply as PNG-backed `Sprite2D` nodes.

## Installation

1. Copy `addons/tilemap_layer_baker` into your Godot project.
2. Open **Project > Project Settings > Plugins**.
3. Enable **TileMapLayer Baker**.
4. Open a 2D scene that contains static visual `TileMapLayer` nodes.

## Usage

1. Select one or more static visual `TileMapLayer` nodes in the scene tree.
2. Open the **TileMap Baker** dock.
3. Choose an output directory, or keep the default `res://assets/baked`.
4. Keep **Combine by z_index** enabled if layers with the same `z_index` can be merged.
5. Click **Bake Selected TileMapLayer(s)**.
6. Inspect the generated `Sprite2D` nodes and PNG files, then save the scene.

## Limitations

- Use this only for static visual layers.
- Do not bake layers that provide collision, navigation, triggers, gameplay logic, or dynamic content.
- Axis-aligned tile flips are supported.
- Arbitrary rotated or scaled `TileMapLayer` nodes should be checked visually after baking.
- Very large layers are guarded by an 8192 pixel texture size limit.

## License

MIT. See `LICENSE`.
