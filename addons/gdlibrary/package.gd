@tool
extends RefCounted

const TOKENS: String = "(?s)\"\"\"(?:\\\\.|(?!\"\"\").)*\"\"\"|'''(?:\\\\.|(?!''').)*'''|\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|#[^\\n]*|\\bclass_name[ \\t]+([A-Za-z_][A-Za-z0-9_]*)\\b"
const MAGIC: String = "GDL2"
const VERSION: int = 6
const Embedded = preload("embedded.gd")
const Surface = preload("api_surface.gd")
const Versions = preload("versions.gd")
const PRIVATE_ROOT: String = "res://.godot/gdlib/_bundle_private_/"
const BUNDLE_LIMIT: int = 128 * 1024 * 1024
const MANIFEST_LIMIT: int = 2 * 1024 * 1024
const BUNDLE_HEADER: int = 48
const MAX_SOURCE: int = 16 * 1024 * 1024
const MAX_PACKAGE: int = MAX_SOURCE + 128 * 1024
const HEADER_SIZE: int = 47
const ROOT: String = "res://.godot/gdlib/"
const INDEX: String = ROOT + "mounts.json"
const TOOL: int = 1
const ABSTRACT: int = 2

static func body_path(info: Dictionary) -> String:
	if info.has("source_path"):
		return info.source_path
	if info.get("private", false) or info.get("scoped", false):
		return ROOT + "private/%s/%s.gd" % [info.scope, info.name]
	return ROOT + "code/%s/%s.gd" % [info.name, info.digest]

static func archive_path(info: Dictionary) -> String:
	if info.has("source_path") or info.get("private", false) or info.get("scoped", false):
		return ROOT + "packs/%s-%s.zip" % [info.scope, info.name]
	return ROOT + "packs/%s.zip" % info.digest

static func checksum(name_bytes: PackedByteArray, flags: int, body: PackedByteArray) -> PackedByteArray:
	var hash_context: HashingContext = HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(PackedByteArray([flags]))
	hash_context.update(name_bytes)
	hash_context.update(PackedByteArray([0]))
	hash_context.update(body)
	return hash_context.finish()

static func pack(script_path: String, destination: String) -> Error:
	var script: GDScript = load(script_path) as GDScript
	if script == null:
		return ERR_PARSE_ERROR
	return pack_files(PackedStringArray([script_path]), destination, public_name(script_path, script), PackedStringArray())

static func pack_definition(recipe: Resource, target: String) -> Error:
	return pack_files(recipe.sources, target, recipe.package_id, recipe.requirements, recipe.version, recipe.private_sources, recipe.namespace_enabled, recipe.embed_resources, recipe.asset_inputs)

static func api_changes(id: String, previous: String, candidate: String) -> PackedStringArray:
	var old: Dictionary = read_package(previous)
	if old.is_empty() or old.get("id") != id:
		return PackedStringArray(["The existing file is unreadable or belongs to a different package."])
	if old.get("api", {}).is_empty():
		return PackedStringArray(["The previous package has no API snapshot. Packing this version establishes the baseline."])
	var current: Dictionary = read_package(candidate)
	return Surface.compare(old.api, current.api)

static func public_name(path: String, script: GDScript) -> String:
	var declared: String = String(script.get_global_name())
	return path.get_file().get_basename().to_pascal_case() if declared.is_empty() else declared

static func valid_id(value: String) -> bool:
	return value.is_valid_ascii_identifier() and value.length() <= 255

static func pack_files(paths: PackedStringArray, destination: String, package_id: String, requires: PackedStringArray, version: String = "1.0.0", private_paths: PackedStringArray = PackedStringArray(), scoped: bool = false, embed: bool = false, asset_inputs: PackedStringArray = PackedStringArray()) -> Error:
	if paths.is_empty() or destination.get_extension().to_lower() != "gdlib" or not valid_id(package_id):
		return ERR_INVALID_PARAMETER
	var parsed: Dictionary = Versions.requirements(requires, package_id)
	if parsed.has("error") or not Versions.valid(version):
		return ERR_INVALID_PARAMETER
	for private_path: String in private_paths:
		if not paths.has(private_path):
			return ERR_INVALID_PARAMETER
	if paths.size() == private_paths.size():
		return ERR_INVALID_PARAMETER
	var rules: Dictionary = parsed.rules
	var dependencies: PackedStringArray = PackedStringArray(rules.keys())
	dependencies.sort()
	var scripts: Dictionary = {}
	var names: Dictionary = {}
	var seen: Dictionary = {}
	var sorted_paths: PackedStringArray = paths.duplicate()
	sorted_paths.sort()
	for path: String in sorted_paths:
		if path.get_extension().to_lower() != "gd":
			return ERR_INVALID_PARAMETER
		var script: GDScript = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or script.reload() != OK:
			return ERR_PARSE_ERROR
		var member_name: String = public_name(path, script)
		if not valid_id(member_name) or seen.has(member_name.to_lower()):
			return ERR_ALREADY_EXISTS
		seen[member_name.to_lower()] = true
		scripts[path] = script
		names[path] = member_name
	var targets: Dictionary = {}
	var private_types: Dictionary = {}
	for path: String in names:
		var member_name: String = names[path]
		if not valid_origin(path):
			return ERR_INVALID_PARAMETER
		targets[path] = PRIVATE_ROOT + path.trim_prefix("res://") if scoped or private_paths.has(path) else "res://gdlib_api/" + member_name + ".gd"
		if (scoped or private_paths.has(path)) and scripts[path].get_global_name() != &"":
			private_types[member_name] = targets[path]
	var entries: Array[Dictionary] = []
	var payload: PackedByteArray = PackedByteArray()
	var assets: Dictionary = {}
	var api: Dictionary = {}
	var selection_error: String = collect_inputs(asset_inputs, assets, embed)
	if not selection_error.is_empty():
		push_error(selection_error)
		return ERR_INVALID_DATA
	for path: String in sorted_paths:
		for ref: Dictionary in source_refs(scripts[path].source_code, path):
			if String(ref.path).begins_with("uid://"):
				return ERR_FILE_NOT_FOUND
			if is_asset(ref.path):
				var asset_error: Error = collect_asset(ref.path, assets)
				if asset_error != OK:
					return asset_error
	var asset_paths: PackedStringArray = PackedStringArray(assets.keys())
	asset_paths.sort()
	var bundled: Dictionary = {}
	var imports: Dictionary = {}
	if embed:
		var packed: Dictionary = Embedded.collect(asset_paths, targets, package_id, BUNDLE_LIMIT)
		if packed.has("error"):
			return packed.error
		bundled = packed.files
		imports = packed.imports
		for path: String in bundled:
			targets[path] = Embedded.destination(package_id, path)
		asset_paths.clear()
	for path: String in sorted_paths:
		var script: GDScript = scripts[path]
		var member_name: String = names[path]
		var source: String = script.source_code if script.get_global_name() == &"" else strip_global_name(script.source_code, member_name)
		var flags: int = (TOOL if script.is_tool() else 0) | (ABSTRACT if script.is_abstract() else 0)
		var author_digest: String = checksum(member_name.to_ascii_buffer(), flags, source.to_utf8_buffer()).hex_encode()
		var linked: String = link_members(source, path, targets)
		var body: PackedByteArray = link_private_types(linked, private_types).to_utf8_buffer()
		if body.is_empty() or body.size() > MAX_SOURCE or payload.size() + body.size() > BUNDLE_LIMIT:
			return ERR_PARAMETER_RANGE_ERROR
		var parent: Script = script.get_base_script()
		var base: String = String(script.get_instance_base_type())
		while parent != null:
			if names.has(parent.resource_path) and not private_paths.has(parent.resource_path):
				base = names[parent.resource_path]
				break
			if not names.has(parent.resource_path) and parent.get_global_name() != &"":
				base = parent.get_global_name()
				break
			parent = parent.get_base_script()
		entries.append({"origin": path, "base": String(base), "name": member_name, "flags": flags, "size": body.size(), "author_digest": author_digest, "private": private_paths.has(path)})
		payload.append_array(body)
		if not private_paths.has(path):
			var api_name: String = package_id + "." + member_name if scoped else member_name
			api[api_name] = Surface.record(script, base, bool(flags & ABSTRACT))
	var files: Array[Dictionary] = []
	for path: String in bundled:
		var data: PackedByteArray = bundled[path]
		if data.size() > BUNDLE_LIMIT - payload.size():
			return ERR_PARAMETER_RANGE_ERROR
		files.append({"path": path, "size": data.size(), "import": imports.get(path, {})})
		payload.append_array(data)
	var signature: PackedByteArray = JSON.stringify(api).to_utf8_buffer()
	if signature.size() > BUNDLE_LIMIT - payload.size():
		return ERR_PARAMETER_RANGE_ERROR
	payload.append_array(signature)
	var manifest: PackedByteArray = JSON.stringify({"assets": asset_paths, "embedded": files, "api_size": signature.size(), "scoped": scoped, "id": package_id, "version": version, "rules": rules, "requires": dependencies, "members": entries}).to_utf8_buffer()
	if manifest.size() > MANIFEST_LIMIT:
		return ERR_PARAMETER_RANGE_ERROR
	var packet: PackedByteArray = MAGIC.to_ascii_buffer()
	packet.resize(BUNDLE_HEADER)
	packet.encode_u32(4, VERSION)
	packet.encode_u32(8, manifest.size())
	packet.encode_u32(12, payload.size())
	var digest: PackedByteArray = checksum(manifest, VERSION, payload)
	for index: int in digest.size():
		packet[16 + index] = digest[index]
	packet.append_array(manifest)
	packet.append_array(payload.compress(FileAccess.COMPRESSION_GZIP))
	return write_bytes(destination, packet)

static func source_refs(source: String, script_path: String) -> Array[Dictionary]:
	var strings_and_comments: String = TOKENS.get_slice("|\\bclass_name", 0)
	var pattern: String = "(?s)(?<![.\\w])(preload|load|ResourceLoader\\s*\\.\\s*load)\\s*\\(\\s*([\"'])([^\"'\\n]+)\\2(?=\\s*[,\\)])|\\b(extends)\\s+([\"'])([^\"'\\n]+)\\5"
	var regex: RegEx = RegEx.create_from_string(pattern + "|" + strings_and_comments.trim_prefix("(?s)"))
	var refs: Array[Dictionary] = []
	for token: RegExMatch in regex.search_all(source):
		var group: int = 3 if not token.get_string(1).is_empty() else 6
		var ref_path: String = token.get_string(group)
		if ref_path.is_empty():
			continue
		if ref_path.begins_with("uid://"):
			var uid: int = ResourceUID.text_to_id(ref_path)
			if ResourceUID.has_id(uid):
				ref_path = ResourceUID.get_id_path(uid)
		elif ref_path.is_relative_path():
			ref_path = script_path.get_base_dir().path_join(ref_path).simplify_path()
		refs.append({"path": ref_path.simplify_path(), "start": token.get_start(group), "end": token.get_end(group)})
	return refs

static func is_asset(path: String) -> bool:
	return path.begins_with("res://") and path.get_extension().to_lower() != "gd"

static func valid_asset_path(path: String) -> bool:
	if not path.begins_with("res://") or path != path.simplify_path() or path.contains("\\"):
		return false
	var relative: String = path.trim_prefix("res://")
	return not relative.is_empty() and not relative.contains(":") and not relative.begins_with(".") and not relative.contains("/.") and relative != "project.godot"

static func source_location(path: String) -> Dictionary:
	var prefix: String = ROOT + "source/"
	if not path.begins_with(prefix):
		return {}
	var parts: PackedStringArray = path.trim_prefix(prefix).split("/", true, 2)
	if parts.size() != 3 or parts[0].length() != 64 or not parts[0].is_valid_hex_number():
		return {}
	var release: PackedStringArray = parts[1].split("@")
	var origin: String = "res://" + parts[2]
	if release.size() != 2 or not valid_id(release[0]) or not Versions.valid(release[1]) or not valid_origin(origin):
		return {}
	return {"release": parts[1], "path": origin}

static func valid_origin(path: String) -> bool:
	if not valid_asset_path(path) or path.get_extension().to_lower() != "gd":
		return false
	for part: String in path.trim_prefix("res://").split("/"):
		if not part.is_valid_filename():
			return false
	return true

static func collect_inputs(inputs: PackedStringArray, assets: Dictionary, embed: bool) -> String:
	if not inputs.is_empty() and not embed:
		return "Enable Embed referenced resources to pack the selected asset files and folders."
	var pending: PackedStringArray = inputs.duplicate()
	var visited: Dictionary = {}
	while not pending.is_empty():
		var path: String = pending[pending.size() - 1]
		pending.resize(pending.size() - 1)
		if visited.has(path):
			continue
		visited[path] = true
		if not valid_asset_path(path) or path.begins_with(Embedded.ROOT) or path == Embedded.ROOT.trim_suffix("/"):
			return "Choose an asset file or folder inside the author project: " + path
		var current: String = "res://"
		for part: String in path.trim_prefix("res://").split("/"):
			var parent: DirAccess = DirAccess.open(current)
			if parent == null or parent.is_link(part):
				return "Missing or linked asset input: " + path
			current = current.path_join(part)
		if DirAccess.dir_exists_absolute(path):
			var dir: DirAccess = DirAccess.open(path)
			if dir == null or dir.file_exists(".gdignore") or dir.file_exists("project.godot"):
				return "Cannot pack this folder: " + path
			for name_: String in dir.get_directories():
				if not name_.begins_with("."):
					pending.append(path.path_join(name_))
			for name_: String in dir.get_files():
				if not name_.begins_with(".") and name_.get_extension().to_lower() not in ["gd", "import", "uid"]:
					pending.append(path.path_join(name_))
		elif not FileAccess.file_exists(path):
			return "Missing asset input: " + path
		elif path.get_extension().to_lower() == "gd":
			return "Use Add scripts… in the pack dialog to include GDScript: " + path
		elif not Embedded.supported(path):
			return "Unsupported embedded asset: " + path
		elif collect_asset(path, assets) != OK:
			return "Cannot read asset or dependency: " + path
	return ""

static func collect_asset(path: String, assets: Dictionary) -> Error:
	if assets.has(path):
		return OK
	if not valid_asset_path(path) or not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	assets[path] = true
	for entry: String in ResourceLoader.get_dependencies(path):
		var parts: PackedStringArray = entry.split("::")
		var child: String = parts[0]
		if child.begins_with("uid://"):
			var uid: int = ResourceUID.text_to_id(child)
			if ResourceUID.has_id(uid):
				child = ResourceUID.get_id_path(uid)
			elif parts.size() >= 3:
				child = parts[-1]
			else:
				return ERR_FILE_NOT_FOUND
		var error: Error = collect_asset(child, assets)
		if error != OK:
			return error
	return OK

static func link_members(source: String, script_path: String, targets: Dictionary) -> String:
	var cursor: int = 0
	var result: String = ""
	for ref: Dictionary in source_refs(source, script_path):
		if targets.has(ref.path) or is_asset(ref.path):
			result += source.substr(cursor, ref.start - cursor) + String(targets.get(ref.path, ref.path))
			cursor = ref.end
	return result + source.substr(cursor)

static func identifiers(source: String) -> Dictionary:
	var masked: String = mask_literals(source)
	var regex: RegEx = RegEx.create_from_string("(?<![.\\w])[A-Za-z_][A-Za-z_0-9]*")
	var result: Dictionary = {}
	for token: RegExMatch in regex.search_all(masked):
		result[token.get_string()] = true
	var declarations: RegEx = RegEx.create_from_string("\\b(?:const|var|func|class|class_name|signal|enum)\\s+([A-Za-z_][A-Za-z_0-9]*)")
	for token: RegExMatch in declarations.search_all(masked):
		result.erase(token.get_string(1))
	return result

static func mask_literals(source: String) -> String:
	var regex: RegEx = RegEx.create_from_string(TOKENS.get_slice("|\\bclass_name", 0))
	var result: String = ""
	var cursor: int = 0
	for token: RegExMatch in regex.search_all(source):
		result += source.substr(cursor, token.get_start() - cursor) + " ".repeat(token.get_end() - token.get_start())
		cursor = token.get_end()
	return result + source.substr(cursor)

static func link_private_types(source: String, private_types: Dictionary) -> String:
	if private_types.is_empty():
		return source
	var used: Dictionary = identifiers(source)
	var regex: RegEx = RegEx.create_from_string("\\bextends[ \\t]+([A-Za-z_][A-Za-z_0-9]*)")
	var cursor: int = 0
	var result: String = ""
	for item: RegExMatch in regex.search_all(mask_literals(source)):
		var base: String = item.get_string(1)
		if used.has(base) and private_types.has(base):
			result += source.substr(cursor, item.get_start(1) - cursor) + JSON.stringify(private_types[base])
			cursor = item.get_end(1)
	result += source.substr(cursor)
	for name_: String in private_types:
		if used.has(name_):
			result += "\nconst %s = preload(%s)\n" % [name_, JSON.stringify(private_types[name_])]
	return result

static func global_declaration(source: String) -> RegExMatch:
	if not source.contains("class_name"):
		return null
	var tokens: RegEx = RegEx.create_from_string(TOKENS)
	for token: RegExMatch in tokens.search_all(source):
		if not token.get_string(1).is_empty():
			return token
	return null

static func strip_global_name(source: String, library_name: String) -> String:
	var token: RegExMatch = global_declaration(source)
	if token == null or token.get_string(1) != library_name:
		return ""
	var after: String = source.substr(token.get_end())
	if after.get_slice("\n", 0).strip_edges().begins_with("extends"):
		after = after.strip_edges(true, false)
	return source.left(token.get_start()) + after

static func read_package(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8 or file.get_buffer(4).get_string_from_ascii() != MAGIC:
		return {}
	var format: int = file.get_32()
	match format:
		1:
			var member: Dictionary = read_legacy(file)
			if not member.is_empty():
				return {"id": member.name, "requires": PackedStringArray(), "members": [member]}
		2, 3, 4, 5, VERSION:
			return read_bundle(file, format)
	return {}

static func read_bundle(file: FileAccess, format: int) -> Dictionary:
	if file.get_length() <= BUNDLE_HEADER or file.get_length() > BUNDLE_HEADER + MANIFEST_LIMIT + BUNDLE_LIMIT + 1024 * 1024:
		return {}
	var manifest_size: int = file.get_32()
	var raw_size: int = file.get_32()
	if manifest_size < 1 or manifest_size > MANIFEST_LIMIT or raw_size < 1 or raw_size > BUNDLE_LIMIT or BUNDLE_HEADER + manifest_size >= file.get_length():
		return {}
	var expected: PackedByteArray = file.get_buffer(32)
	var manifest: PackedByteArray = file.get_buffer(manifest_size)
	var payload: PackedByteArray = read_compressed(file, raw_size)
	if payload.size() != raw_size or checksum(manifest, format, payload) != expected:
		return {}
	var meta: Variant = JSON.parse_string(manifest.get_string_from_utf8())
	if not meta is Dictionary or not meta.get("id") is String or not valid_id(meta.id) or not meta.get("requires") is Array or not meta.get("members") is Array or meta.members.is_empty():
		return {}
	var deps: PackedStringArray = PackedStringArray()
	for dep: Variant in meta.requires:
		if not dep is String or not valid_id(dep) or dep == meta.id or deps.has(dep):
			return {}
		deps.append(dep)
	var release: String = ""
	var rules: Dictionary = {}
	if format >= 3:
		if not meta.get("version") is String or not Versions.valid(meta.version) or not meta.get("rules") is Dictionary or meta.rules.size() != deps.size():
			return {}
		release = meta.version
		for dep: String in deps:
			var rule: Variant = meta.rules.get(dep)
			if not rule is String or (not rule.is_empty() and not Versions.valid(rule.trim_prefix("^"))):
				return {}
			rules[dep] = rule
	var assets: PackedStringArray = PackedStringArray()
	if format >= 4:
		if not meta.get("assets") is Array:
			return {}
		for asset: Variant in meta.assets:
			if not asset is String or not valid_asset_path(asset):
				return {}
			assets.append(asset)
	var scoped: bool = false
	if format >= 5:
		if not meta.get("scoped") is bool or not meta.get("embedded") is Array:
			return {}
		scoped = meta.scoped
	var scope: String = expected.hex_encode()
	var source_root: String = ROOT + "private/" + scope + "/"
	if format >= 6:
		source_root = ROOT + "source/" + scope + "/" + String(meta.id) + "@" + release + "/"
	var origins: Dictionary = {}
	var cursor: int = 0
	var seen: Dictionary = {}
	var members: Array[Dictionary] = []
	for item: Variant in meta.members:
		if not item is Dictionary or not item.get("name") is String or not valid_id(item.name) or seen.has(item.name.to_lower()):
			return {}
		if not item.get("author_digest") is String or item.author_digest.length() != 64 or not item.author_digest.is_valid_hex_number():
			return {}
		if typeof(item.get("flags")) not in [TYPE_INT, TYPE_FLOAT] or typeof(item.get("size")) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		var flags: int = int(item.flags)
		var size: int = int(item.size)
		if flags != item.flags or flags < 0 or flags > 3 or size != item.size or size <= 0 or size > MAX_SOURCE or size > raw_size - cursor:
			return {}
		var body: PackedByteArray = payload.slice(cursor, cursor + size)
		var hidden: bool = false
		if format >= 3:
			if not item.get("private") is bool:
				return {}
			hidden = item.private
			var code: String = body.get_string_from_utf8()
			if code.contains(PRIVATE_ROOT):
				body = code.replace(PRIVATE_ROOT, source_root).to_utf8_buffer()
		var digest: String = checksum(String(item.name).to_ascii_buffer(), flags, body).hex_encode()
		if format >= 4 and (not item.get("base") is String or not valid_id(item.base)):
			return {}
		members.append({"scoped": scoped, "base": item.get("base", ""), "name": item.name, "flags": flags, "digest": digest, "author_digest": item.author_digest, "body": body, "private": hidden, "scope": scope})
		if format >= 6:
			if not item.get("origin") is String or not valid_origin(item.origin) or origins.has(item.origin.to_lower()):
				return {}
			origins[item.origin.to_lower()] = true
			members.back()["source_path"] = source_root + String(item.origin).trim_prefix("res://")
		seen[item.name.to_lower()] = true
		cursor += size
	var api: Dictionary = {}
	var embedded: Dictionary = {}
	var imports: Dictionary = {}
	if format >= 5:
		for entry: Variant in meta.embedded:
			if not entry is Dictionary or not entry.get("path") is String or not valid_asset_path(entry.path) or not Embedded.supported(entry.path) or embedded.has(entry.path):
				return {}
			if typeof(entry.get("size")) not in [TYPE_FLOAT, TYPE_INT] or int(entry.size) != entry.size or entry.size < 0 or entry.size > raw_size - cursor:
				return {}
			if entry.has("import") and entry["import"] != {}:
				if not Embedded.valid_settings(entry["import"]):
					return {}
				imports[entry.path] = entry["import"]
			var length: int = int(entry.size)
			var data: PackedByteArray = payload.slice(cursor, cursor + length)
			if String(entry.path).get_extension() in ["tscn", "tres"]:
				data = data.get_string_from_utf8().replace(PRIVATE_ROOT, source_root).to_utf8_buffer()
			embedded[entry.path] = data
			cursor += length
		if typeof(meta.get("api_size")) not in [TYPE_FLOAT, TYPE_INT] or meta.api_size != raw_size - cursor:
			return {}
		var parsed_api: Variant = JSON.parse_string(payload.slice(cursor).get_string_from_utf8())
		if not Surface.valid(parsed_api):
			return {}
		api = parsed_api
		cursor = raw_size
	if cursor != raw_size:
		return {}
	return {"scoped": scoped, "api": api, "embedded": embedded, "imports": imports, "assets": assets, "id": meta.id, "version": release, "rules": rules, "requires": deps, "members": members}

static func read_legacy(file: FileAccess) -> Dictionary:
	if file.get_length() <= HEADER_SIZE or file.get_length() > MAX_PACKAGE:
		return {}
	var raw_size: int = file.get_32()
	var name_length: int = file.get_16()
	var flags: int = file.get_8()
	if raw_size < 1 or raw_size > MAX_SOURCE or name_length < 1 or name_length > 255 or flags > 3:
		return {}
	var expected: PackedByteArray = file.get_buffer(32)
	var name_bytes: PackedByteArray = file.get_buffer(name_length)
	var library_name: String = name_bytes.get_string_from_ascii()
	if not library_name.is_valid_ascii_identifier() or name_bytes != library_name.to_ascii_buffer():
		return {}
	var remaining: int = file.get_length() - file.get_position()
	if remaining <= 0:
		return {}
	var body: PackedByteArray = read_compressed(file, raw_size)
	if body.size() != raw_size or checksum(name_bytes, flags, body) != expected:
		return {}
	return {"name": library_name, "flags": flags, "digest": expected.hex_encode(), "body": body}

static func read_compressed(file: FileAccess, size: int) -> PackedByteArray:
	var stream: PackedByteArray = file.get_buffer(file.get_length() - file.get_position())
	if stream.size() < 18 or stream.decode_u32(stream.size() - 4) != size:
		return PackedByteArray()
	return stream.decompress(size, FileAccess.COMPRESSION_GZIP)

static func write_bytes(path: String, data: PackedByteArray) -> Error:
	path = ProjectSettings.globalize_path(path)
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var temp: String = path + ".tmp-" + ResourceUID.id_to_text(ResourceUID.create_id()).trim_prefix("uid://")
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored: bool = file.store_buffer(data)
	file.close()
	if stored:
		error = DirAccess.rename_absolute(temp, path)
	else:
		error = ERR_FILE_CANT_WRITE
	if error != OK:
		DirAccess.remove_absolute(temp)
	return error

static func cache(info: Dictionary) -> Error:
	var body: String = body_path(info)
	var archive: String = archive_path(info)
	var bytes: PackedByteArray = info.body
	var error: Error = write_bytes(body, bytes)
	if error != OK:
		return error
	error = DirAccess.make_dir_recursive_absolute(archive.get_base_dir())
	if error != OK:
		return error
	var temp: String = archive + ".tmp-" + ResourceUID.id_to_text(ResourceUID.create_id()).trim_prefix("uid://")
	var zip: ZIPPacker = ZIPPacker.new()
	error = zip.open(temp)
	if error != OK:
		return error
	error = zip.start_file(body.trim_prefix("res://"))
	if error == OK:
		error = zip.write_file(bytes)
	if error == OK:
		error = zip.close_file()
	var close_error: Error = zip.close()
	if error == OK:
		error = close_error
	if error == OK:
		error = DirAccess.rename_absolute(temp, archive)
	if error != OK:
		DirAccess.remove_absolute(temp)
	return error

static func is_cached(library: Dictionary) -> bool:
	for meta: Dictionary in library.get("embedded", {}).values():
		if not FileAccess.file_exists(meta.cache):
			return false
	for member: Dictionary in library.members:
		if not FileAccess.file_exists(body_path(member)) or not FileAccess.file_exists(archive_path(member)):
			return false
	return true

static func prepare(library: Dictionary) -> Error:
	for path: String in library.get("embedded", {}):
		var bytes: PackedByteArray = library.embedded[path]
		var hash_context: HashingContext = HashingContext.new()
		hash_context.start(HashingContext.HASH_SHA256)
		hash_context.update(bytes)
		var digest: String = hash_context.finish().hex_encode()
		var cache_path: String = ROOT + "embedded/" + digest
		if not FileAccess.file_exists(cache_path):
			var error: Error = write_bytes(cache_path, bytes)
			if error != OK:
				return error
		library.embedded[path] = {"hash": digest, "cache": cache_path}
	for member: Dictionary in library.members:
		if not FileAccess.file_exists(body_path(member)) or not FileAccess.file_exists(archive_path(member)):
			var error: Error = cache(member)
			if error != OK:
				return error
		member.erase("body")
	return OK
