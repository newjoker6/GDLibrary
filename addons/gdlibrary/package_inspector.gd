@tool
extends EditorInspectorPlugin

const Definition := preload("definition.gd")
const Versions := preload("versions.gd")
var host: EditorPlugin

func _can_handle(object: Object) -> bool:
	return object is Resource and (object.has_meta("gdlib") or object.get_script() == Definition)

func _parse_begin(object: Object) -> void:
	var asset := object as Resource
	var box := VBoxContainer.new()
	add_custom_control(box)
	if asset.get_script() == Definition:
		button(box, "Repack Library", func() -> void: host.call("repack_definition", asset.resource_path))
		button(box, "Edit Library Definition…", func() -> void: host.call("open_definition", asset.resource_path))
		return
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var update := func() -> void:
		var catalog: RefCounted = host.get("catalog")
		var info: Dictionary = catalog.cache.get(asset.resource_path, asset.get_meta("gdlib"))
		var classes := PackedStringArray()
		var deps := PackedStringArray()
		for member: Dictionary in info.members:
			if not member.get("private", false):
				classes.append((String(info.id) + "." if info.get("scoped", false) else "") + String(member.name))
		for dep: String in info.requires:
			deps.append(Versions.describe(dep, info.get("rules", {}).get(dep, "")))
		var version := String(info.get("version", ""))
		label.text = "Package ID: %s\nVersion: %s\nStatus: %s\nPublic classes: %s\nRequires: %s" % [info.id, version if not version.is_empty() else "Unversioned", catalog.package_states.get(info.id, "Pending"), ", ".join(classes), ", ".join(deps) if not deps.is_empty() else "None"]
		var embedded := PackedStringArray(info.get("embedded", {}).keys()) if info.has("embedded") else PackedStringArray(info.get("embedded_paths", []))
		if not embedded.is_empty():
			label.text += "\nEmbedded resources:\n" + "\n".join(embedded)
		if not info.get("assets", []).is_empty():
			label.text += "\nRequired assets:\n" + "\n".join(info.assets)
	update.call()
	var catalog: RefCounted = host.get("catalog")
	catalog.connect("catalog_changed", update)
	box.tree_exiting.connect(func() -> void:
		if catalog.is_connected("catalog_changed", update):
			catalog.disconnect("catalog_changed", update)
	, CONNECT_ONE_SHOT)
	button(box, "Test in Clean Project", func() -> void: host.call("test_clean", asset.resource_path))
	button(box, "Copy Package ID", func() -> void: DisplayServer.clipboard_set(String(asset.get_meta("gdlib").id)))

func button(box: VBoxContainer, caption: String, action: Callable) -> void:
	var control := Button.new()
	control.text = caption
	control.pressed.connect(action)
	box.add_child(control)
