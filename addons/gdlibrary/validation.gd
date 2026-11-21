@tool
extends RefCounted

const Package = preload("package.gd")

static func package_id_error(value: String) -> String:
	if value.contains(" ") or value.contains("\t") or value.contains("\n") or value.contains("\r"):
		return "Package IDs cannot contain spaces or other whitespace. Use GatorPack or gator_pack."
	if not Package.valid_id(value):
		return "Enter a package ID using letters, digits or underscores. Start with a letter or underscore (maximum 255 characters)."
	return ""

static func imported_destination(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	var folder: String = path.get_base_dir()
	while folder != "res://":
		if folder.get_file().begins_with(".") or FileAccess.file_exists(folder.path_join(".gdignore")) or FileAccess.file_exists(folder.path_join("project.godot")):
			return false
		folder = folder.get_base_dir()
	return true

static func destination_error(id: String, path: String, catalog: RefCounted, result: Dictionary) -> String:
	if not imported_destination(path):
		return ""
	var installed: Dictionary = catalog.package_infos.get(id, {})
	var reason: String = ""
	if not result.overlaps.is_empty():
		reason = "Installed packages expose the same public classes: " + ", ".join(result.overlaps)
	elif not installed.is_empty() and installed.path != path:
		reason = "This project already has package ID '%s' at %s." % [id, installed.path]
	return reason + "\nChoose a location outside this project or in a .gdignore folder." if not reason.is_empty() else ""

static func review(recipe: Resource, catalog: RefCounted, dirty: PackedStringArray = PackedStringArray()) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var suggestions: Dictionary = {}
	var id_error: String = package_id_error(recipe.package_id)
	var overlaps: PackedStringArray = PackedStringArray()
	if not id_error.is_empty():
		errors.append(id_error)
	if not Package.Versions.valid(recipe.version):
		errors.append("Enter a version with three numbers, such as 1.2.0.")
	var parsed: Dictionary = Package.Versions.requirements(recipe.requirements, recipe.package_id)
	if parsed.has("error"):
		errors.append(parsed.error)
	var rules: Dictionary = parsed.get("rules", {})
	var required: Dictionary = rules.duplicate()
	var pending: Array = rules.keys()
	while not pending.is_empty():
		var dependency: String = pending.pop_back()
		for child: String in catalog.package_infos.get(dependency, {}).get("requires", []):
			if not required.has(child):
				required[child] = true
				pending.append(child)
	var globals: Dictionary = {}
	for info: Dictionary in ProjectSettings.get_global_class_list():
		globals[String(info.class)] = String(info.path)
	var names: Dictionary = {}
	var public_bindings: Dictionary = {}
	var selected: Dictionary = {}
	var sources: Dictionary = {}
	var assets: Dictionary = {}
	var asset_problem: String = Package.collect_inputs(recipe.asset_inputs, assets, recipe.embed_resources)
	if not asset_problem.is_empty():
		errors.append(asset_problem)
	for path: String in recipe.sources:
		if not path.begins_with("res://") or path.get_extension() != "gd" or not FileAccess.file_exists(path):
			errors.append("Missing GDScript: " + path)
			continue
		if dirty.has(path):
			errors.append("Save the script before packing: " + path)
		var source: String = FileAccess.get_file_as_string(path)
		sources[path] = source
		var declaration: RegExMatch = Package.global_declaration(source)
		var public_name: String = declaration.get_string(1) if declaration != null else path.get_file().get_basename().to_pascal_case()
		var key: String = public_name.to_lower()
		if not Package.valid_id(public_name):
			errors.append("Invalid class name '%s' in %s." % [public_name, path])
		if names.has(key):
			errors.append("Class '%s' occurs in both %s and %s." % [public_name, names[key], path])
		names[key] = path
		selected[path] = true
		if not recipe.private_sources.has(path) and not recipe.namespace_enabled:
			public_bindings[catalog.API_DIR.path_join(public_name + ".gd")] = true
			var other_path: String = globals.get(public_name, "")
			if not other_path.is_empty() and other_path != path and not recipe.sources.has(other_path):
				var generated: bool = other_path.get_base_dir() == catalog.API_DIR and catalog.is_binding(other_path)
				if not generated:
					errors.append("Public class '%s' from %s conflicts with %s." % [public_name, path, other_path])
			if ClassDB.class_exists(public_name) or ProjectSettings.has_setting("autoload/" + public_name):
				errors.append("%s conflicts with the engine or autoload name '%s'." % [path, public_name])
	var exports: Dictionary = {}
	if recipe.namespace_enabled:
		exports[recipe.package_id.to_lower()] = recipe.package_id
		var namespace_path: String = globals.get(recipe.package_id, "")
		if (not namespace_path.is_empty() and not (namespace_path.get_base_dir() == catalog.API_DIR and catalog.is_binding(namespace_path))) or ClassDB.class_exists(recipe.package_id) or ProjectSettings.has_setting("autoload/" + recipe.package_id):
			errors.append("Namespace '%s' is already a project or engine class." % recipe.package_id)
	else:
		for key: String in names:
			if not recipe.private_sources.has(names[key]):
				exports[key] = true
	for owner: String in catalog.package_infos:
		if owner == recipe.package_id:
			continue
		for member: Dictionary in catalog.exported_globals(catalog.package_infos[owner]):
			if member.get("private", false) or not exports.has(String(member.name).to_lower()):
				continue
			if required.has(owner):
				errors.append("%s and its required package %s both expose '%s'." % [recipe.package_id, owner, member.name])
			elif not overlaps.has(owner):
				overlaps.append(owner)
	for path: String in recipe.private_sources:
		if not selected.has(path):
			errors.append("Private helper is missing from the script list: " + path)
	if recipe.sources.is_empty() or recipe.private_sources.size() >= recipe.sources.size():
		errors.append("Include at least one public script.")
	for path: String in sources:
		var source: String = sources[path]
		for ref: Dictionary in Package.source_refs(source, path):
			if String(ref.path).begins_with("uid://"):
				errors.append("%s references unknown resource %s." % [path, ref.path])
			if Package.is_asset(ref.path) and Package.collect_asset(ref.path, assets) != OK:
				errors.append("%s needs %s or one of its dependencies, which could not be found." % [path, ref.path])
			if ref.path == "res://addons/gdlibrary/assets.gd" or selected.has(ref.path) or public_bindings.has(ref.path) or String(ref.path).get_extension() != "gd":
				continue
			var id: String = catalog.providers.get(String(ref.path).get_file().get_basename(), "") if String(ref.path).get_base_dir() == "res://gdlib_api" else ""
			if id.is_empty():
				errors.append("%s references %s. Include that script or use a library's public class." % [path, ref.path])
			elif not rules.has(id):
				suggestions[id] = path
		for symbol: String in Package.identifiers(source):
			if names.has(symbol.to_lower()) or globals.get(symbol, "") == "res://addons/gdlibrary/assets.gd":
				continue
			var owner: String = catalog.providers.get(symbol, "")
			if not owner.is_empty():
				if owner != recipe.package_id and not rules.has(owner):
					suggestions[owner] = path
			elif globals.has(symbol) and not selected.has(globals[symbol]):
				errors.append("%s uses local class %s from %s. Include its script." % [path, symbol, globals[symbol]])
	if recipe.embed_resources:
		for path: String in assets:
			if path.get_extension() == "gd" and not selected.has(path):
				errors.append("Include the scene's script in the library: " + path)
			elif not selected.has(path) and not Package.Embedded.supported(path):
				errors.append("Cannot embed %s. Use external assets for this format." % path)
			elif path.get_extension() in ["res", "scn"] and not ResourceLoader.get_dependencies(path).is_empty():
				errors.append("Save %s in text format (.tres or .tscn) so its references can be relocated." % path)
	for id: String in rules:
		var info: Dictionary = catalog.package_infos.get(id, {})
		if info.is_empty() or catalog.package_states.get(id, "") != "Ready":
			errors.append("Required package %s is missing or blocked." % id)
		elif not Package.Versions.accepts(info.get("version", ""), rules[id]):
			errors.append("Requires %s. Installed version: %s." % [Package.Versions.describe(id, rules[id]), info.get("version", "unversioned") if info.get("version", "") != "" else "unversioned"])
	if errors.is_empty():
		for path: String in sources:
			var script: GDScript = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
			if script == null or script.reload() != OK:
				errors.append("Godot could not compile " + path)
	return {"assets": PackedStringArray(assets.keys()), "errors": errors, "suggestions": suggestions, "overlaps": overlaps}
