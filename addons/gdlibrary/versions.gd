@tool
extends RefCounted

static func valid(value: String) -> bool:
	var parts: PackedStringArray = value.split(".")
	if parts.size() != 3:
		return false
	for part: String in parts:
		if part.is_empty() or part.length() > 9 or (part.length() > 1 and part.begins_with("0")):
			return false
		for ch: String in part:
			if ch < "0" or ch > "9":
				return false
	return true

static func requirements(entries: PackedStringArray, owner: String) -> Dictionary:
	var result: Dictionary = {}
	for entry: String in entries:
		var pair: PackedStringArray = entry.strip_edges().split("@")
		var id: String = pair[0].strip_edges()
		if pair.size() > 2 or not id.is_valid_ascii_identifier() or id.length() > 255 or id == owner or result.has(id):
			return {"error": "Invalid or repeated requirement '%s'." % entry}
		var rule: String = ""
		if pair.size() == 2:
			rule = pair[1].strip_edges()
			if not valid(rule.trim_prefix("^")):
				return {"error": "Use ID, ID@1.2.3 or ID@^1.2.3 for '%s'." % entry}
		result[id] = rule
	return {"rules": result}

static func accepts(installed: String, rule: String) -> bool:
	if rule.is_empty():
		return true
	if not valid(installed):
		return false
	if not rule.begins_with("^"):
		return installed == rule
	var actual: PackedStringArray = installed.split(".")
	var minimum: PackedStringArray = rule.substr(1).split(".")
	var first_difference: int = 0
	var locked: bool = true
	for i: int in 3:
		var a: int = actual[i].to_int()
		var b: int = minimum[i].to_int()
		if locked and a != b:
			return false
		if b != 0:
			locked = false
		if first_difference == 0:
			first_difference = signi(a - b)
	return first_difference >= 0

static func describe(id: String, rule: String) -> String:
	return id if rule.is_empty() else id + "@" + rule
