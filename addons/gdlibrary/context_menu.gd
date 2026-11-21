@tool
extends EditorContextMenuPlugin

var host: EditorPlugin
const Definition = preload("definition.gd")

func _popup_menu(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	if paths.size() == 1 and paths[0].get_extension() == "tres":
		var asset: Resource = load(paths[0])
		if asset != null and asset.get_script() == Definition:
			add_context_menu_item("Repack Library", func(_selected: Variant) -> void: host.call("repack_definition", paths[0]))
			add_context_menu_item("Edit Library Definition…", func(_selected: Variant) -> void: host.call("open_definition", paths[0]))
			return
	for path: String in paths:
		if path.get_extension() != "gd":
			return
	add_context_menu_item("Pack as Library…", func(_selected: Variant) -> void: host.call("start_pack", paths))
