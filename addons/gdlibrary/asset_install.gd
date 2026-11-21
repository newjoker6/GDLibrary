@tool
extends RefCounted

const Package := preload("package.gd")
const ROOT := Package.Embedded.ROOT
const LEDGER := ROOT + ".gdlib-owned.json"

var owned := {}
var wanted := {}
var changed := false
var dirty := false
var ledger_ok := true
var issues := PackedStringArray()

func _init() -> void:
	if DirAccess.open("res://").is_link("gdlib_assets"):
		ledger_ok = false
		issues.append("Cannot install into a linked gdlib_assets directory.")
	elif FileAccess.file_exists(LEDGER):
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEDGER))
		if stored is Dictionary:
			owned = stored
		else:
			ledger_ok = false
			issues.append("Cannot read asset ownership file " + LEDGER)

func safe(path: String) -> bool:
	if not path.begins_with(ROOT) or not Package.valid_asset_path(path):
		return false
	var current := "res://"
	for part in path.trim_prefix("res://").split("/"):
		var dir := DirAccess.open(current)
		if dir != null and dir.is_link(part):
			return false
		current = current.path_join(part)
	return true

func install(info: Dictionary) -> bool:
	if not ledger_ok and not info.get("embedded", {}).is_empty():
		return false
	var writes := {}
	var imports := {}
	var import_keys := {}
	for source: String in info.get("embedded", {}):
		var path := Package.Embedded.destination(info.id, source)
		wanted[path] = true
		if info.get("imports", {}).has(source):
			wanted[path + ".import"] = true
	for source: String in info.get("embedded", {}):
		var path := Package.Embedded.destination(info.id, source)
		var meta: Dictionary = info.embedded[source]
		if not safe(path) or not safe(path + ".import"):
			issues.append("Cannot install embedded asset at " + path)
			return false
		if info.get("imports", {}).has(source):
			var settings: Dictionary = info.imports[source]
			var key := path + ".import"
			var digest := (String(meta.hash) + JSON.stringify(settings)).sha256_text()
			if owned.get(key, "") != digest or not preload("asset_import.gd").ready(path):
				imports[path] = settings
				import_keys[key] = digest
		if FileAccess.file_exists(path):
			var existing := FileAccess.get_sha256(path)
			if existing == meta.hash:
				continue
			if existing != owned.get(path, ""):
				issues.append("Embedded asset conflicts with a local file at " + path)
				return false
		writes[path] = meta
	for path: String in writes:
		var meta: Dictionary = writes[path]
		if Package.write_bytes(path, FileAccess.get_file_as_bytes(meta.cache)) != OK:
			issues.append("Cannot write embedded asset " + path)
			return false
		owned[path] = meta.hash
		changed = true
		dirty = true
	var error := preload("asset_import.gd").compile(imports)
	if error != OK:
		issues.append("%s could not prepare its embedded resources. %s" % [info.id, error_string(error)])
		return false
	if not imports.is_empty():
		owned.merge(import_keys, true)
		dirty = true
		changed = true
	return true

func finish() -> void:
	for path: String in owned.keys():
		if wanted.has(path) or not safe(path):
			continue
		if FileAccess.file_exists(path) and FileAccess.get_sha256(path) == owned[path]:
			if DirAccess.remove_absolute(path) != OK:
				issues.append("Cannot remove obsolete embedded asset " + path)
				continue
			for suffix in [".import", ".uid"]:
				if FileAccess.file_exists(path + suffix) and safe(path + suffix):
					DirAccess.remove_absolute(path + suffix)
			changed = true
		owned.erase(path)
		dirty = true
	if dirty and (not safe(ROOT + "ledger") or DirAccess.open(ROOT).is_link(LEDGER.get_file()) or Package.write_bytes(LEDGER, JSON.stringify(owned).to_utf8_buffer()) != OK):
		issues.append("Cannot save asset ownership file " + LEDGER)
