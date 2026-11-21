@tool
extends ConfirmationDialog

const Package = preload("package.gd")

var input: TextEdit = TextEdit.new()
var result: Label = Label.new()

func _ready() -> void:
	title = "Go to GDLibrary Source"
	get_ok_button().text = "Open Author Script"
	var layout: VBoxContainer = VBoxContainer.new()
	add_child(layout)
	input.placeholder_text = "Paste a stack frame from a package built with GDLibrary 2.5 or later."
	input.custom_minimum_size = Vector2(540, 90)
	layout.add_child(input)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(result)
	input.text_changed.connect(update_result)
	confirmed.connect(open_source)
	update_result()

static func locate(frame: String) -> Dictionary:
	var pattern: RegEx = RegEx.create_from_string("(res://\\.godot/gdlib/source/[^\\r\\n]+?\\.gd):([1-9][0-9]*)")
	for match_: RegExMatch in pattern.search_all(frame):
		var location: Dictionary = Package.source_location(match_.get_string(1))
		if not location.is_empty():
			location["line"] = match_.get_string(2).to_int()
			return location
	return {}

func update_result() -> void:
	var frame: Dictionary = locate(input.text)
	get_ok_button().disabled = true
	if frame.is_empty():
		result.text = "" if input.text.is_empty() else "No mapped GDLibrary frame found."
		return
	result.text = "%s  •  %s:%d" % [frame.release, frame.path, frame.line]
	if not FileAccess.file_exists(frame.path):
		result.text += "\nOpen this dialog in the matching author project to jump to the source."
		return
	if int(frame.line) > FileAccess.get_file_as_string(frame.path).count("\n") + 1:
		result.text += "\nThis line is outside the local source. Check the package version."
		return
	get_ok_button().disabled = false

func open_source() -> void:
	var frame: Dictionary = locate(input.text)
	if frame.is_empty() or get_ok_button().disabled:
		return
	var script: GDScript = ResourceLoader.load(frame.path, "GDScript") as GDScript
	if script != null:
		EditorInterface.edit_script(script, int(frame.line), 1)
