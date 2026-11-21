@tool
extends RefCounted

static func type_name(info: Dictionary) -> String:
	if not String(info.get("class_name", "")).is_empty():
		return String(info.class_name)
	if not String(info.get("hint_string", "")).is_empty() and info.type in [TYPE_ARRAY, TYPE_DICTIONARY]:
		return type_string(info.type) + "[" + String(info.hint_string) + "]"
	if info.type == TYPE_NIL:
		return "Variant" if int(info.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT else "void"
	return type_string(info.type)

static func method_signature(method: Dictionary) -> Dictionary:
	var args := PackedStringArray()
	var names := PackedStringArray()
	for arg: Dictionary in method.args:
		args.append(type_name(arg))
		names.append(String(arg.name))
	var defaults := PackedStringArray()
	for value: Variant in method.default_args:
		defaults.append(var_to_str(value) if typeof(value) != TYPE_OBJECT else "Object")
	return {"names": names, "args": args, "defaults": defaults, "return": type_name(method.return), "flags": int(method.flags) & (METHOD_FLAG_STATIC | METHOD_FLAG_VARARG)}

static func record(script: GDScript, base: String, abstract_class: bool) -> Dictionary:
	var result := {"class": {"base": base, "abstract": abstract_class}}
	for method: Dictionary in script.get_script_method_list():
		var name_ := String(method.name)
		if name_ == "_init" or (not name_.begins_with("_") and not name_.contains("@")):
			result["func " + name_] = method_signature(method)
	for signal_: Dictionary in script.get_script_signal_list():
		if not String(signal_.name).begins_with("_"):
			var args := PackedStringArray()
			for arg: Dictionary in signal_.args:
				args.append(type_name(arg))
			result["signal " + String(signal_.name)] = args
	for property: Dictionary in script.get_script_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and not String(property.name).begins_with("_"):
			result["var " + String(property.name)] = type_name(property)
	var constants := script.get_script_constant_map()
	for key: StringName in constants:
		if String(key).begins_with("_"):
			continue
		var value: Variant = constants[key]
		if value is Script:
			result["const " + String(key)] = "Script"
		elif value is Object:
			result["const " + String(key)] = value.get_class() if value != null else "null"
		else:
			result["const " + String(key)] = var_to_str(value)
	return result

static func compare(old: Dictionary, current: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for name_: String in old:
		if not current.has(name_):
			lines.append("Removed public class " + name_)
			continue
		var before: Dictionary = old[name_]
		var after: Dictionary = current[name_]
		for key: String in before:
			var label := name_ + ("." + key.get_slice(" ", 1) if key != "class" else "")
			if not after.has(key):
				lines.append("Removed " + label)
			elif before[key] != after[key]:
				if key.begins_with("func "):
					var a: Dictionary = before[key]
					var b: Dictionary = after[key]
					var extra: int = b.args.size() - b.defaults.size() - (a.args.size() - a.defaults.size())
					if extra > 0:
						lines.append("%s() requires %d more argument(s)." % [label, extra])
					else:
						lines.append("Changed %s() from %s to %s" % [label, describe(a), describe(b)])
				else:
					lines.append("Changed " + label)
		for key: String in after:
			if not before.has(key):
				lines.append("Added %s %s" % [name_, key])
	for name_: String in current:
		if not old.has(name_):
			lines.append("Added public class " + name_)
	lines.sort()
	return lines

static func describe(method: Dictionary) -> String:
	var args := PackedStringArray(method.args)
	var first: int = args.size() - method.defaults.size()
	for i in args.size():
		args[i] = String(method.names[i]) + ": " + args[i]
	for i in method.defaults.size():
		args[first + i] += " = " + str(method.defaults[i])
	return ("static " if int(method.flags) & METHOD_FLAG_STATIC else "") + "(" + ", ".join(args) + ") -> " + String(method.return)

static func valid(snapshot: Variant) -> bool:
	if not snapshot is Dictionary or snapshot.is_empty():
		return false
	for name_: String in snapshot:
		var members: Variant = snapshot[name_]
		if not members is Dictionary or not members.get("class") is Dictionary:
			return false
		for key: String in members:
			if key.begins_with("func "):
				var method: Variant = members[key]
				if not method is Dictionary or not method.get("args") is Array or not method.get("defaults") is Array or not method.get("names") is Array:
					return false
				if method.names.size() != method.args.size() or method.defaults.size() > method.args.size() or not method.get("return") is String or typeof(method.get("flags")) not in [TYPE_INT, TYPE_FLOAT]:
					return false
				for list: Array in [method.names, method.args, method.defaults]:
					for value: Variant in list:
						if not value is String:
							return false
	return true
