@tool
extends RefCounted

const Catalog = preload("catalog.gd")
const Package = preload("package.gd")
const CACHE: String = "res://.godot/global_script_class_cache.cfg"

static func finish(catalog: RefCounted) -> Error:
	var config: ConfigFile = ConfigFile.new()
	if FileAccess.file_exists(CACHE):
		var error: Error = config.load(CACHE)
		if error != OK:
			return error
	var entries: Array = config.get_value("", "list", [])
	var known: Dictionary = {}
	for entry: Dictionary in entries:
		known[entry.path] = true
	var changed: bool = false
	for id: String in catalog.package_infos:
		if catalog.package_states.get(id) != "Ready":
			continue
		for member: Dictionary in Catalog.exported_globals(catalog.package_infos[id]):
			var path: String = Catalog.API_DIR.path_join(String(member.name) + ".gd")
			if member.get("private", false) or known.has(path) or not FileAccess.file_exists(path):
				continue
			var source: String = FileAccess.get_file_as_string(path)
			if not Catalog.is_binding(path) or Package.global_declaration(source) == null:
				continue
			var base: String = member.get("base", "")
			if base.is_empty():
				base = base_name(Package.body_path(member), {})
			entries.append({"class": StringName(member.name), "base": StringName(base), "language": &"GDScript", "path": path, "icon": "", "is_tool": bool(member.flags & Package.TOOL), "is_abstract": bool(member.flags & Package.ABSTRACT)})
			changed = true
	if changed:
		config.set_value("", "list", entries)
		return Package.write_bytes(CACHE, config.encode_to_text().to_utf8_buffer())
	return OK

static func base_name(path: String, seen: Dictionary) -> String:
	if seen.has(path) or not FileAccess.file_exists(path):
		return "RefCounted"
	seen[path] = true
	var source: String = FileAccess.get_file_as_string(path)
	var declaration: RegExMatch = Package.global_declaration(source)
	if declaration != null:
		return declaration.get_string(1)
	var match_: RegExMatch = RegEx.create_from_string("(?m)^extends[ \\t]+([A-Za-z_][A-Za-z_0-9]*)").search(Package.mask_literals(source))
	if match_ != null:
		return match_.get_string(1)
	for ref: Dictionary in Package.source_refs(source, path):
		if source.left(ref.start - 1).rsplit("\n", true, 1)[-1].strip_edges() == "extends":
			return base_name(ref.path, seen)
	return "RefCounted"
