@tool
extends RefCounted

const _ZH_CN_MESSAGES := {
	"TileMap Baker": "TileMap 烘焙",
	"TileMapLayer Baker": "TileMapLayer 烘焙器",
	"Select one or more static TileMapLayer nodes, then bake them into PNG + Sprite2D.": "选中一个或多个静态 TileMapLayer 后，一键烘焙成 PNG + Sprite2D。",
	"Output Directory": "输出目录",
	"File Prefix (leave empty to use scene name)": "文件前缀（留空使用场景名）",
	"Combine by z_index": "按 z_index 分组合并",
	"Hide source TileMapLayers after baking": "烘焙后隐藏源 TileMapLayer",
	"Include hidden layers (for rebaking)": "包含隐藏图层（便于重新烘焙）",
	"Overwrite matching PNG / Baked Sprite": "覆盖同名 PNG / Baked Sprite",
	"Bake Selected TileMapLayer(s)": "烘焙选中 TileMapLayer",
	"Waiting for TileMapLayer selection.": "等待选择 TileMapLayer。",
	"EditorInterface is unavailable.": "EditorInterface 不可用。",
	"Select one or more TileMapLayer nodes in the scene tree first.": "请先在场景树中选择一个或多个 TileMapLayer。",
	"Baking %d TileMapLayer(s)...": "正在烘焙 %d 个 TileMapLayer...",
	"Bake failed": "烘焙失败",
	"Bake finished: %d PNG(s), %d Sprite2D node(s).": "烘焙完成：%d 张 PNG，%d 个 Sprite2D。",
	"Source TileMapLayer nodes were kept and hidden according to the option; inspect the scene before saving.": "源 TileMapLayer 已保留，只是按选项隐藏；请检查画面后保存场景。",
	"No TileMapLayer can be baked.": "没有可烘焙的 TileMapLayer。",
	"Cannot find the current scene root.": "无法找到当前场景根节点。",
	"Output directory must start with res://.": "输出目录必须是 res:// 开头。",
	"Cannot create output directory: %s": "无法创建输出目录：%s",
	"Failed": "失败",
	"Failed to save %s: %s": "保存失败 %s：%s",
	"No PNG was generated. %s": "没有生成 PNG。%s",
	"Selected layers have no drawable tiles.": "选中图层没有可绘制图块。",
	"Invalid bake size.": "烘焙尺寸无效。",
	"Bake size %dx%d exceeds the safety limit %d. Split the layer first.": "烘焙尺寸 %dx%d 超过安全上限 %d。请拆分图层。",
}

static var _translations: Array = []
static var _editor_locale := ""

static func register_translations(editor_interface = null) -> void:
	update_editor_locale(editor_interface)
	if not _translations.is_empty():
		return
	for locale in ["zh_CN", "zh_Hans", "zh"]:
		var translation := Translation.new()
		translation.set_locale(locale)
		for source in _ZH_CN_MESSAGES:
			translation.add_message(source, _ZH_CN_MESSAGES[source])
		TranslationServer.add_translation(translation)
		_translations.append(translation)

static func unregister_translations() -> void:
	for translation in _translations:
		TranslationServer.remove_translation(translation)
	_translations.clear()
	_editor_locale = ""

static func update_editor_locale(editor_interface = null) -> bool:
	var locale := _read_editor_locale(editor_interface)
	if locale == _editor_locale:
		return false
	_editor_locale = locale
	return true

static func t(message: String) -> String:
	if _is_chinese_locale(_editor_locale) and _ZH_CN_MESSAGES.has(message):
		return _ZH_CN_MESSAGES[message]
	return TranslationServer.translate(message)

static func _read_editor_locale(editor_interface = null) -> String:
	if editor_interface != null and editor_interface.has_method("get_editor_settings"):
		var editor_settings = editor_interface.get_editor_settings()
		if editor_settings != null and editor_settings.has_setting("interface/editor/editor_language"):
			var editor_locale := String(editor_settings.get_setting("interface/editor/editor_language"))
			if not _is_auto_locale(editor_locale):
				return editor_locale
	return _read_resolved_locale()

static func _read_resolved_locale() -> String:
	var server_locale := TranslationServer.get_locale()
	if not _is_auto_locale(server_locale):
		return server_locale
	if TranslationServer.has_method("get_tool_locale"):
		var tool_locale := String(TranslationServer.call("get_tool_locale"))
		if not _is_auto_locale(tool_locale):
			return tool_locale
	return OS.get_locale()

static func _is_auto_locale(locale: String) -> bool:
	var normalized := locale.strip_edges().to_lower()
	return normalized.is_empty() or normalized == "auto"

static func _is_chinese_locale(locale: String) -> bool:
	var normalized := locale.replace("-", "_").to_lower()
	return normalized == "zh" or normalized.begins_with("zh_")
