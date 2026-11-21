@tool
extends EditorPlugin

const Package := preload("package.gd")
const Importer := preload("importer.gd")
const Exporter := preload("exporter.gd")
const Catalog := preload("catalog.gd")
const Definition := preload("definition.gd")
const Validation := preload("validation.gd")
const Presets := preload("preset_fixes.gd")
const Inspector := preload("package_inspector.gd")
const Context := preload("context_menu.gd")
const LIBRARY_DIR := "res://libraries"
const ACTION := "Pack GDScript Library…"
const COMMAND := "gdlib/pack"
const MOUNTER := "GDLibraryMounts"
const MOUNT_SCRIPT := "res://addons/gdlibrary/mounts.gd"

var source_lookup := preload("source_lookup.gd").new()
var importer := Importer.new()
var exporter := Exporter.new()
var catalog := Catalog.new()
var input_dialog: EditorFileDialog
var output_dialog: EditorFileDialog
var message_dialog: AcceptDialog
var after_error := Callable()
var bundle_dialog := ConfirmationDialog.new()
var source_list := ItemList.new()
var id_edit := LineEdit.new()
var id_hint := Label.new()
var overlapping_packages := PackedStringArray()
var deps_edit := LineEdit.new()
var installed_menu := MenuButton.new()
var report_dialog := AcceptDialog.new()
var report_text := TextEdit.new()
var package_inspector := Inspector.new()
var context_menu := Context.new()
var namespace_option := CheckBox.new()
var extra_assets := PackedStringArray()
var extra_list := ItemList.new()
var extra_button := Button.new()
var extra_dialog := AcceptDialog.new()
var embed_option := CheckBox.new()
var api_dialog := ConfirmationDialog.new()
var api_text := TextEdit.new()
var pending_save := Callable()
var version_edit := LineEdit.new()
var recipe_path := ""
var prior_output := ""
var hidden_sources := PackedStringArray()
var asset_dialog := ConfirmationDialog.new()
var asset_list := TextEdit.new()
var asset_continue := Callable()
var clean_picker: EditorFileDialog
var clean_thread := Thread.new()
var clean_timer := Timer.new()
var validation_dialog := ConfirmationDialog.new()
var pending_suggestions := PackedStringArray()
var after_validation := Callable()
var preset_dialog := AcceptDialog.new()
var preset_rows := VBoxContainer.new()
var picking_more := false
var selected_sources := PackedStringArray()
var library_dir_created := false
var refresh_queued := false
var attempted_imports := {}
var last_issues := PackedStringArray()

func _enter_tree() -> void:
	set_process(false)
	if not DirAccess.dir_exists_absolute(LIBRARY_DIR):
		var error := DirAccess.make_dir_absolute(ProjectSettings.globalize_path(LIBRARY_DIR))
		library_dir_created = error == OK
		if not library_dir_created and not DirAccess.dir_exists_absolute(LIBRARY_DIR):
			push_warning("GDLibrary could not create %s: %s" % [LIBRARY_DIR, error_string(error)])
	if not FileAccess.file_exists(Package.INDEX):
		catalog.bootstrap()
	add_import_plugin(importer)
	exporter.catalog = catalog
	add_export_plugin(exporter)
	if not ProjectSettings.has_setting("autoload/" + MOUNTER):
		add_autoload_singleton(MOUNTER, MOUNT_SCRIPT)
		var mount_key := "autoload/" + MOUNTER
		var earliest := ProjectSettings.get_order(mount_key)
		for setting: Dictionary in ProjectSettings.get_property_list():
			var key := String(setting.name)
			if key.begins_with("autoload/") and key != mount_key:
				earliest = mini(earliest, ProjectSettings.get_order(key) - 1)
		ProjectSettings.set_order(mount_key, earliest)
		ProjectSettings.save()
	elif not owns_mounter():
		push_error("GDLibrary requires the autoload name " + MOUNTER + ". Another script already uses it.")
	input_dialog = make_dialog("Choose library scripts", EditorFileDialog.FILE_MODE_OPEN_FILES, EditorFileDialog.ACCESS_RESOURCES, "*.gd", "GDScript")
	output_dialog = make_dialog("Save GDScript library", EditorFileDialog.FILE_MODE_SAVE_FILE, EditorFileDialog.ACCESS_FILESYSTEM, "*.gdlib", "GDScript library")
	input_dialog.files_selected.connect(select_sources)
	input_dialog.canceled.connect(func() -> void:
		if picking_more:
			reopen_form()
	)
	output_dialog.canceled.connect(reopen_form)
	output_dialog.file_selected.connect(save_library)
	message_dialog = AcceptDialog.new()
	message_dialog.confirmed.connect(resume_after_error)
	message_dialog.canceled.connect(resume_after_error)
	add_child(message_dialog)
	package_inspector.host = self
	add_inspector_plugin(package_inspector)
	EditorInterface.get_file_system_dock().selection_changed.connect(inspect_selection)
	context_menu.host = self
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, context_menu)
	validation_dialog.title = "Confirm library dependencies"
	validation_dialog.get_ok_button().text = "Add Requirements"
	validation_dialog.confirmed.connect(accept_suggestions)
	validation_dialog.canceled.connect(reopen_form)
	add_child(validation_dialog)
	preset_dialog.title = "GDLibrary Export Presets"
	preset_rows.custom_minimum_size.x = 440
	preset_dialog.add_child(preset_rows)
	add_child(preset_dialog)
	add_tool_menu_item("GDLibrary Export Presets…", show_presets)
	setup_bundle_dialog()
	add_child(source_lookup)
	add_tool_menu_item("Go to GDLibrary Source…", source_lookup.popup_centered)
	api_dialog.title = "Review public API changes"
	api_dialog.get_ok_button().text = "Pack This Version"
	api_text.editable = false
	api_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	api_text.custom_minimum_size = Vector2(600, 260)
	api_dialog.add_child(api_text)
	add_child(api_dialog)
	api_dialog.confirmed.connect(func() -> void:
		var action := pending_save
		pending_save = Callable()
		if action.is_valid():
			action.call()
	)
	api_dialog.canceled.connect(func() -> void:
		pending_save = Callable()
		reopen_form()
	)
	asset_dialog.title = "Required assets to ship beside this library"
	asset_dialog.get_ok_button().text = "Continue"
	asset_list.editable = false
	asset_list.custom_minimum_size = Vector2(580, 200)
	asset_dialog.add_child(asset_list)
	asset_dialog.confirmed.connect(func() -> void: asset_continue.call_deferred())
	asset_dialog.canceled.connect(reopen_form)
	add_child(asset_dialog)
	clean_picker = make_dialog("Test packaged library in a clean project", EditorFileDialog.FILE_MODE_OPEN_FILE, EditorFileDialog.ACCESS_FILESYSTEM, "*.gdlib", "GDScript library")
	clean_picker.file_selected.connect(test_clean)
	add_tool_menu_item("Test GDLibrary in Clean Project…", func() -> void: clean_picker.popup_centered_ratio(0.65))
	clean_timer.wait_time = 0.25
	clean_timer.timeout.connect(poll_clean_test)
	add_child(clean_timer)
	report_dialog.title = "GDLibrary Dependencies"
	report_text.editable = false
	report_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	report_text.custom_minimum_size = Vector2(520, 260)
	report_dialog.add_child(report_text)
	add_child(report_dialog)
	add_tool_menu_item("GDLibrary Dependencies…", show_report)
	add_tool_menu_item(ACTION, choose_source)
	EditorInterface.get_command_palette().add_command(ACTION, COMMAND, choose_source)
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.filesystem_changed.connect(queue_refresh)
	filesystem.resources_reimported.connect(on_reimported)
	queue_refresh()

func inspect_selection() -> void:
	var paths := EditorInterface.get_selected_paths()
	if paths.size() == 1 and paths[0].get_extension().to_lower() == "gdlib" and ResourceLoader.exists(paths[0]):
		var asset := ResourceLoader.load(paths[0])
		if asset != null and asset.has_meta("gdlib") and EditorInterface.get_inspector().get_edited_object() != asset:
			EditorInterface.edit_resource(asset)

func owns_mounter() -> bool:
	var path := String(ProjectSettings.get_setting("autoload/" + MOUNTER, "")).trim_prefix("*")
	if path.begins_with("uid://"):
		path = ResourceUID.get_id_path(ResourceUID.text_to_id(path))
	return path == MOUNT_SCRIPT

func _disable_plugin() -> void:
	if owns_mounter():
		remove_autoload_singleton(MOUNTER)

func _exit_tree() -> void:
	remove_tool_menu_item("Go to GDLibrary Source…")
	remove_tool_menu_item("Test GDLibrary in Clean Project…")
	if clean_thread.is_started():
		clean_thread.wait_to_finish()
	if DisplayServer.get_name() == "headless":
		var error := preload("cold_import.gd").finish(catalog)
		if error != OK:
			push_error("GDLibrary could not finalize the script class index: " + error_string(error))
	var filesystem := EditorInterface.get_resource_filesystem()
	filesystem.filesystem_changed.disconnect(queue_refresh)
	filesystem.resources_reimported.disconnect(on_reimported)
	remove_tool_menu_item("GDLibrary Dependencies…")
	EditorInterface.get_file_system_dock().selection_changed.disconnect(inspect_selection)
	remove_context_menu_plugin(context_menu)
	remove_inspector_plugin(package_inspector)
	remove_tool_menu_item("GDLibrary Export Presets…")
	remove_tool_menu_item(ACTION)
	EditorInterface.get_command_palette().remove_command(COMMAND)
	remove_import_plugin(importer)
	remove_export_plugin(exporter)

func make_dialog(title_text: String, mode: EditorFileDialog.FileMode, access: EditorFileDialog.Access, pattern: String, description: String) -> EditorFileDialog:
	var dialog := EditorFileDialog.new()
	dialog.title = title_text
	dialog.access = access
	dialog.file_mode = mode
	if not pattern.is_empty():
		dialog.add_filter(pattern, description)
	if access == EditorFileDialog.ACCESS_FILESYSTEM:
		dialog.use_native_dialog = true
	add_child(dialog)
	return dialog

func setup_bundle_dialog() -> void:
	bundle_dialog.title = "Pack GDScript Library"
	bundle_dialog.get_ok_button().text = "Choose Destination…"
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	bundle_dialog.add_child(scroll)
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(layout)
	add_field(layout, "Package ID", id_edit)
	id_edit.placeholder_text = "Jumanji"
	id_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_hint.add_theme_color_override("font_color", EditorInterface.get_editor_theme().get_color("error_color", "Editor"))
	id_hint.hide()
	layout.add_child(id_hint)
	id_edit.text_changed.connect(update_id_hint)
	add_field(layout, "Version", version_edit)
	namespace_option.text = "Use package ID as a namespace"
	namespace_option.tooltip_text = "Access public classes as PackageID.ClassName."
	layout.add_child(namespace_option)
	embed_option.text = "Embed referenced resources"
	embed_option.tooltip_text = "Include supported resources and their dependencies in this file."
	layout.add_child(embed_option)
	setup_asset_inputs()
	layout.add_child(extra_button)
	add_field(layout, "Included scripts", source_list)
	source_list.custom_minimum_size.y = 145
	source_list.select_mode = ItemList.SELECT_MULTI
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	var add := Button.new()
	add.text = "Add scripts…"
	add.pressed.connect(pick_more)
	actions.add_child(add)
	var remove := Button.new()
	remove.text = "Remove selected"
	remove.pressed.connect(remove_sources)
	actions.add_child(remove)
	var toggle := Button.new()
	toggle.text = "Toggle public/private"
	toggle.pressed.connect(toggle_visibility)
	actions.add_child(toggle)
	add_field(layout, "Requirements (ID, ID@1.2.3 or ID@^1.2.3)", deps_edit)
	deps_edit.placeholder_text = "GatorMath"
	installed_menu.text = "Add installed dependency"
	layout.add_child(installed_menu)
	installed_menu.get_popup().id_pressed.connect(add_installed_dependency)
	var check := bundle_dialog.add_button("Validate", true)
	check.pressed.connect(func() -> void: validate_for(validation_passed))
	bundle_dialog.confirmed.connect(choose_destination)
	add_child(bundle_dialog)

func setup_asset_inputs() -> void:
	extra_dialog.title = "Additional package assets"
	extra_dialog.get_ok_button().text = "Done"
	var layout := VBoxContainer.new()
	extra_dialog.add_child(layout)
	var hint := Label.new()
	hint.text = "Folders skip .gd files. Use Add scripts… to include a class."
	layout.add_child(hint)
	extra_list.custom_minimum_size = Vector2(450, 130)
	extra_list.select_mode = ItemList.SELECT_MULTI
	layout.add_child(extra_list)
	var row := HBoxContainer.new()
	layout.add_child(row)
	var files := make_dialog("Select asset files", EditorFileDialog.FILE_MODE_OPEN_FILES, EditorFileDialog.ACCESS_RESOURCES, "", "")
	var folder := make_dialog("Select an asset folder", EditorFileDialog.FILE_MODE_OPEN_DIR, EditorFileDialog.ACCESS_RESOURCES, "", "")
	files.files_selected.connect(add_asset_inputs)
	folder.dir_selected.connect(func(path: String) -> void: add_asset_inputs(PackedStringArray([path])))
	for picker: EditorFileDialog in [files, folder]:
		var button := Button.new()
		button.text = "Add files…" if picker == files else "Add folder…"
		button.pressed.connect(pick_extra_assets.bind(picker))
		picker.canceled.connect(func() -> void: extra_dialog.popup_centered.call_deferred())
		row.add_child(button)
	var remove := Button.new()
	remove.text = "Remove selected"
	remove.pressed.connect(remove_asset_inputs)
	row.add_child(remove)
	extra_button.pressed.connect(func() -> void:
		bundle_dialog.hide()
		extra_dialog.popup_centered()
	)
	extra_dialog.confirmed.connect(reopen_form)
	extra_dialog.canceled.connect(reopen_form)
	add_child(extra_dialog)
	refresh_asset_inputs()

func pick_extra_assets(picker: EditorFileDialog) -> void:
	extra_dialog.hide()
	picker.popup_centered_ratio(0.65)

func add_asset_inputs(paths: PackedStringArray) -> void:
	for path in paths:
		var normalized := path.trim_suffix("/") if path != "res://" else path
		if not extra_assets.has(normalized):
			extra_assets.append(normalized)
	embed_option.button_pressed = true
	refresh_asset_inputs()
	extra_dialog.popup_centered.call_deferred()

func remove_asset_inputs() -> void:
	var indexes := extra_list.get_selected_items()
	indexes.reverse()
	for index in indexes:
		extra_assets.remove_at(index)
	refresh_asset_inputs()

func refresh_asset_inputs() -> void:
	extra_list.clear()
	for path in extra_assets:
		extra_list.add_item(path + ("/" if DirAccess.dir_exists_absolute(path) else ""))
	extra_button.text = "Additional asset files and folders… (%d)" % extra_assets.size()

func update_id_hint(value: String) -> void:
	id_hint.text = Validation.package_id_error(value)
	id_hint.visible = not id_hint.text.is_empty()

func add_field(layout: VBoxContainer, caption: String, control: Control) -> void:
	var label := Label.new()
	label.text = caption
	layout.add_child(label)
	layout.add_child(control)

func choose_source() -> void:
	var paths := PackedStringArray()
	for path in EditorInterface.get_selected_paths():
		if path.get_extension().to_lower() == "gd":
			paths.append(path)
	start_pack(paths)

func start_pack(paths: PackedStringArray) -> void:
	selected_sources.clear()
	source_list.clear()
	id_edit.clear()
	namespace_option.button_pressed = false
	embed_option.button_pressed = false
	extra_assets.clear()
	refresh_asset_inputs()
	deps_edit.clear()
	version_edit.text = "1.0.0"
	recipe_path = ""
	prior_output = ""
	hidden_sources.clear()
	picking_more = false
	if paths.is_empty():
		input_dialog.popup_centered_ratio(0.65)
	else:
		select_sources(paths)

func pick_more() -> void:
	picking_more = true
	bundle_dialog.hide()
	input_dialog.popup_centered_ratio(0.65)

func remove_sources() -> void:
	var selected := source_list.get_selected_items()
	selected.reverse()
	for index in selected:
		hidden_sources.erase(selected_sources[index])
		selected_sources.remove_at(index)
		source_list.remove_item(index)

func select_sources(paths: PackedStringArray) -> void:
	input_dialog.hide()
	for path in paths:
		if not selected_sources.has(path):
			selected_sources.append(path)
			source_list.add_item(path.trim_prefix("res://") + ("  [private]" if hidden_sources.has(path) else ""))
	if id_edit.text.is_empty() and not selected_sources.is_empty():
		var first := selected_sources[0]
		if selected_sources.size() == 1:
			var declaration := Package.global_declaration(FileAccess.get_file_as_string(first))
			id_edit.text = declaration.get_string(1) if declaration != null else first.get_file().get_basename().to_pascal_case()
	var popup := installed_menu.get_popup()
	popup.clear()
	for id in catalog.package_ids:
		popup.add_item(id)
	installed_menu.disabled = popup.item_count == 0
	picking_more = false
	update_id_hint(id_edit.text)
	show_pack_form()

func add_installed_dependency(index: int) -> void:
	var id := installed_menu.get_popup().get_item_text(index)
	var ids := dependency_ids()
	if not ids.has(id):
		ids.append(id)
	deps_edit.text = ", ".join(ids)

func dependency_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for entry in deps_edit.text.split(",", false):
		var id := entry.strip_edges()
		if not id.is_empty() and not result.has(id):
			result.append(id)
	return result

func resume_after_error() -> void:
	var action := after_error
	after_error = Callable()
	if action.is_valid():
		action.call_deferred()

func show_error(details: String, next := Callable()) -> void:
	after_error = next
	message_dialog.title = "Library packing"
	message_dialog.dialog_text = details
	message_dialog.popup_centered()

func toggle_visibility() -> void:
	for index in source_list.get_selected_items():
		var path := selected_sources[index]
		if hidden_sources.has(path):
			hidden_sources.erase(path)
		else:
			hidden_sources.append(path)
		source_list.set_item_text(index, path.trim_prefix("res://") + ("  [private]" if hidden_sources.has(path) else ""))

func form_recipe() -> Resource:
	var recipe := Definition.new()
	recipe.namespace_enabled = namespace_option.button_pressed
	recipe.embed_resources = embed_option.button_pressed
	recipe.asset_inputs = extra_assets.duplicate()
	recipe.package_id = id_edit.text
	recipe.version = version_edit.text.strip_edges()
	recipe.requirements = dependency_ids()
	recipe.sources = selected_sources.duplicate()
	recipe.private_sources = hidden_sources.duplicate()
	recipe.output_path = prior_output
	return recipe

func fill_form(path: String) -> bool:
	var recipe := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Definition
	if recipe == null:
		show_error("Unable to open library definition " + path)
		return false
	recipe_path = path
	prior_output = recipe.output_path
	namespace_option.button_pressed = recipe.namespace_enabled
	embed_option.button_pressed = recipe.embed_resources
	extra_assets = recipe.asset_inputs.duplicate()
	refresh_asset_inputs()
	id_edit.text = recipe.package_id
	version_edit.text = recipe.version
	deps_edit.text = ", ".join(recipe.requirements)
	hidden_sources = recipe.private_sources.duplicate()
	selected_sources.clear()
	source_list.clear()
	select_sources(recipe.sources)
	return true

func open_definition(path: String) -> void:
	fill_form(path)

func repack_definition(path: String) -> void:
	if fill_form(path):
		bundle_dialog.hide()
		if prior_output.is_empty():
			choose_destination()
		else:
			validate_for(save_library.bind(prior_output))

func notice(text: String) -> void:
	EditorInterface.get_editor_toaster().push_toast(text)

func validate_for(next: Callable) -> void:
	var result := Validation.review(form_recipe(), catalog, EditorInterface.get_script_editor().get_unsaved_files())
	overlapping_packages = result.overlaps
	if not result.errors.is_empty():
		bundle_dialog.hide()
		show_error("\n".join(result.errors), reopen_form)
		return
	if not result.suggestions.is_empty():
		bundle_dialog.hide()
		after_validation = next
		pending_suggestions = PackedStringArray(result.suggestions.keys())
		pending_suggestions.sort()
		var lines := PackedStringArray()
		for id in pending_suggestions:
			lines.append("%s uses a class from %s." % [result.suggestions[id], id])
		validation_dialog.dialog_text = "\n".join(lines)
		validation_dialog.popup_centered()
		return
	if not result.assets.is_empty():
		bundle_dialog.hide()
		asset_continue = next
		asset_dialog.title = "Embedded resources" if embed_option.button_pressed else "Required external assets"
		asset_list.text = ("These resources will be embedded:\n\n" if embed_option.button_pressed else "Supply these files at their listed project paths:\n\n") + "\n".join(result.assets)
		asset_dialog.popup_centered()
		return
	next.call()

func validation_passed() -> void:
	if not bundle_dialog.visible:
		reopen_form()
	if overlapping_packages.is_empty():
		notice("Validation passed.")
	else:
		notice("Ready to pack. Save outside this project or in a .gdignore folder. Installed packages share public classes: " + ", ".join(overlapping_packages))

func show_pack_form() -> void:
	var editor_size := EditorInterface.get_base_control().get_viewport_rect().size
	var preferred := Vector2(550, 620) * EditorInterface.get_editor_scale()
	bundle_dialog.min_size = Vector2i(preferred.min(editor_size * 0.9))
	bundle_dialog.popup_centered(bundle_dialog.min_size)

func reopen_form() -> void:
	show_pack_form.call_deferred()

func accept_suggestions() -> void:
	validation_dialog.hide()
	var deps := dependency_ids()
	deps.append_array(pending_suggestions)
	deps_edit.text = ", ".join(deps)
	pending_suggestions.clear()
	validate_for(after_validation)

func choose_destination() -> void:
	bundle_dialog.hide()
	validate_for(pick_destination)

func pick_destination() -> void:
	output_dialog.title = "Save GDScript library" if overlapping_packages.is_empty() else "Save distribution library outside the project or in a .gdignore folder"
	if prior_output.is_empty():
		output_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		output_dialog.current_file = id_edit.text.strip_edges() + ".gdlib"
	else:
		output_dialog.current_path = ProjectSettings.globalize_path(prior_output)
	output_dialog.popup_centered_ratio(0.65)

func save_library(path: String) -> void:
	output_dialog.hide()
	if path.get_extension().is_empty():
		path += ".gdlib"
	var recipe := form_recipe()
	recipe.output_path = ProjectSettings.localize_path(path)
	if recipe.output_path.get_extension().to_lower() != "gdlib":
		show_error("Choose a .gdlib output file.")
		return
	var target := recipe_path
	if target.is_empty():
		target = "res://gdlib_definitions/" + String(recipe.package_id) + ".gdlib.tres"
		if FileAccess.file_exists(target):
			show_error("A definition already exists at %s. Open it and choose Edit Library Definition or Repack Library." % target)
			return
	var err := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if err != OK:
		show_error(error_string(err))
		return
	var result := Validation.review(recipe, catalog, EditorInterface.get_script_editor().get_unsaved_files())
	if not result.errors.is_empty() or not result.suggestions.is_empty():
		show_error("The inputs changed. Validate again.\n" + "\n".join(result.errors))
		return
	var problem := Validation.destination_error(recipe.package_id, recipe.output_path, catalog, result)
	if not problem.is_empty():
		show_error(problem, pick_destination)
		return
	var staging := DirAccess.create_temp("gdlib-candidate")
	if staging == null:
		show_error("Could not create a temporary package.")
		return
	var candidate := staging.get_current_dir().path_join("candidate.gdlib")
	err = Package.pack_definition(recipe, candidate)
	if err != OK:
		show_error("Could not pack %s. %s" % [recipe.package_id, error_string(err)], reopen_form)
		return
	var destination_hash := FileAccess.get_sha256(recipe.output_path) if FileAccess.file_exists(recipe.output_path) else ""
	var original := 0
	var inputs: PackedStringArray = recipe.sources.duplicate()
	if recipe.embed_resources:
		for asset: String in result.assets:
			if not inputs.has(asset):
				inputs.append(asset)
	for input in inputs:
		var source := FileAccess.open(input, FileAccess.READ)
		if source != null:
			original += source.get_length()
	var publish := publish_candidate.bind(recipe, target, staging, destination_hash, original)
	var baseline := String(recipe.output_path) if not destination_hash.is_empty() else prior_output
	if not baseline.is_empty() and FileAccess.file_exists(baseline):
		var changes := Package.api_changes(recipe.package_id, baseline, candidate)
		if not changes.is_empty():
			api_text.text = "\n".join(changes)
			pending_save = publish
			api_dialog.popup_centered()
			return
	publish.call()

func publish_candidate(recipe: Resource, target: String, staging: DirAccess, expected: String, original: int) -> void:
	var path := String(recipe.output_path)
	var current := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	if current != expected:
		show_error("The destination changed during the review. Repack to compare it again.", reopen_form)
		return
	var bytes := FileAccess.get_file_as_bytes(staging.get_current_dir().path_join("candidate.gdlib"))
	if bytes.is_empty():
		show_error("The temporary package could not be read.", reopen_form)
		return
	var err := Package.write_bytes(path, bytes)
	if err != OK:
		show_error("Could not save %s. %s" % [path, error_string(err)], reopen_form)
		return
	err = ResourceSaver.save(recipe, target)
	if err != OK:
		show_error("Packed %s, but could not save %s. %s" % [path, target, error_string(err)])
		return
	recipe_path = target
	prior_output = recipe.output_path
	var packed := bytes.size()
	notice("%s • %d scripts • %d → %d bytes (%+.1f%%)" % [recipe.package_id, recipe.sources.size(), original, packed, 100.0 * (packed - original) / maxi(original, 1)])
	EditorInterface.get_resource_filesystem().scan()

func show_presets() -> void:
	for child in preset_rows.get_children():
		preset_rows.remove_child(child)
		child.queue_free()
	var affected := Presets.missing()
	if affected.is_empty():
		var label := Label.new()
		label.text = "No selected-export presets need the GDLibrary include filter."
		preset_rows.add_child(label)
	for section: String in affected:
		var name_: String = affected[section]
		var row := Button.new()
		row.text = "Fix Export Preset — " + name_
		row.pressed.connect(fix_preset.bind(section, name_))
		preset_rows.add_child(row)
	preset_dialog.popup_centered()

func fix_preset(section: String, name_: String) -> void:
	var error := Presets.fix(section, name_)
	preset_dialog.hide()
	if error != OK:
		show_error("Unable to update %s: %s" % [name_, error_string(error)])
		return
	notice("Saved %s. Reopen the project before exporting from this editor session." % name_)

func show_report() -> void:
	refresh()
	update_report()
	report_dialog.popup_centered()

func update_report() -> void:
	var lines := catalog.status.duplicate()
	if lines.is_empty():
		lines.append("No libraries found.")
	var fixes := Presets.missing()
	if not fixes.is_empty():
		lines.append("Export presets needing a fix: " + ", ".join(fixes.values()) + ". Open Project → Tools → GDLibrary Export Presets…")
	if not catalog.issues.is_empty():
		lines.append("")
		lines.append_array(catalog.issues)
	report_text.text = "\n".join(lines)

func on_reimported(paths: PackedStringArray) -> void:
	for path in paths:
		catalog.cache.erase(path)
	queue_refresh()

func queue_refresh() -> void:
	if not refresh_queued:
		refresh_queued = true
		refresh.call_deferred()

func _process(_delta: float) -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if not filesystem.is_scanning() and not filesystem.is_importing():
		set_process(false)
		queue_refresh()

func refresh() -> void:
	refresh_queued = false
	if not is_inside_tree():
		return
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem.is_scanning() or filesystem.is_importing():
		set_process(true)
		return
	var changed := catalog.refresh(filesystem)
	if report_dialog.visible:
		update_report()
	if last_issues != catalog.issues:
		if not catalog.issues.is_empty():
			EditorInterface.get_editor_toaster().push_toast(catalog.issues[0])
		for issue in catalog.issues:
			push_warning(issue)
		last_issues = catalog.issues.duplicate()
	if changed:
		for path in catalog.touched:
			if filesystem.get_filesystem_path(path.get_base_dir()) != null:
				filesystem.update_file(path)
	var bindings := filesystem.get_filesystem_path(Catalog.API_DIR)
	if DirAccess.dir_exists_absolute(Catalog.API_DIR):
		for filename in DirAccess.get_files_at(Catalog.API_DIR):
			if filename.get_extension() == "gd" and (bindings == null or bindings.find_file_index(filename) == -1):
				changed = true
				break
	if library_dir_created:
		library_dir_created = false
		if filesystem.get_filesystem_path(LIBRARY_DIR) == null:
			changed = true
	if changed:
		filesystem.scan()
		set_process(true)
	else:
		repair_failed_imports(filesystem)

func repair_failed_imports(filesystem: EditorFileSystem) -> void:
	var pending := PackedStringArray()
	var failed := {}
	for id: String in catalog.package_infos:
		if catalog.package_states.get(id) != "Ready":
			continue
		var info: Dictionary = catalog.package_infos[id]
		var path: String = info.path
		var directory := filesystem.get_filesystem_path(path.get_base_dir())
		if directory == null:
			continue
		var index := directory.find_file_index(path.get_file())
		if index < 0 or directory.get_file_import_is_valid(index):
			continue
		var member: Dictionary = info.members[0]
		var revision: String = member.get("scope", member.digest)
		failed[path] = revision
		if attempted_imports.get(path) != revision:
			pending.append(path)
	attempted_imports = failed
	if not pending.is_empty():
		filesystem.reimport_files(pending)
		queue_refresh()

func _build() -> bool:
	refresh()
	return catalog.issues.is_empty()

func test_clean(path: String) -> void:
	if clean_thread.is_started():
		notice("A clean-project test is already running.")
		return
	var local := ProjectSettings.localize_path(path)
	var assets_root := "res://" if Validation.imported_destination(local) else path.get_base_dir()
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://addons/gdlibrary/release.gd", "--", "test", ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(assets_root)])
	var error := clean_thread.start(run_clean_test.bind(OS.get_executable_path(), args))
	if error != OK:
		show_error(error_string(error))
		return
	notice("Testing the packed library in a clean project…")
	clean_timer.start()

static func run_clean_test(binary: String, args: PackedStringArray) -> String:
	var output := []
	if OS.execute(binary, args, output, true) != 0:
		var log_text := "\n".join(output)
		return "Clean-project test failed.\n" + (log_text if log_text.length() <= 3500 else log_text.left(1700) + "\n…\n" + log_text.right(1700))
	return ""

func poll_clean_test() -> void:
	if clean_thread.is_alive():
		return
	clean_timer.stop()
	var problem: String = clean_thread.wait_to_finish()
	if problem.is_empty():
		notice("Clean import and exported package passed.")
	else:
		show_error(problem)
