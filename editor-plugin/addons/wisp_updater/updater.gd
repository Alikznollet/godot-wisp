@tool
extends EditorPlugin
## The Wisp updater editor plugin.
## 
## Looks for updates when the button is pressed.

var update_button: Button
var dialog: ConfirmationDialog # TODO: This is temp, should be scene.
var vbox: VBoxContainer # TODO: This is temp, should be cleaned up.

var update_checkboxes: Dictionary = {}

func _enter_tree() -> void:
	# TODO: Check whether Wisp is installed before enabling the addon.

	# Toolbar button
	update_button = Button.new()
	update_button.text = "Wisp Sync"
	update_button.tooltip_text = "Check for addon updates"
	update_button.pressed.connect(_on_wisp_button_pressed)

	# Inject the button into the toolbar
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, update_button)

	# Popup
	dialog = ConfirmationDialog.new()
	dialog.title = "Wisp Updates Available"
	dialog.confirmed.connect(_on_dialog_confirmed)

	# VBox
	vbox = VBoxContainer.new()
	dialog.add_child(vbox)

	get_editor_interface().get_base_control().add_child(dialog)

func _exit_tree() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, update_button)
	update_button.queue_free()
	dialog.queue_free()

func _on_wisp_button_pressed() -> void:
	# Clear out old checkboxes if there are any.
	for child in vbox.get_children():
		child.queue_free()
	update_checkboxes.clear()
	
	# TODO: Make the button move visually during check.

	var output = []

	# Check for updates.
	var exit_code: int = OS.execute("wisp", ["check", "--json"], output, true, true)

	if exit_code != 0 or output.is_empty():
		printerr("Wisp failed to check for updates.")
		return

	# Parse JSON
	var json_string: String = "".join(output)
	var json: JSON = JSON.new()
	var error := json.parse(json_string)

	if error != OK:
		printerr("Failed to parse Wisp JSON. Check the terminal output.")
		return

	var outdated_addons = json.data
	if not outdated_addons:
		printerr("Wisp is currently not tracking any addons in this project.")
		return

	# Build UI based on JSON.
	if outdated_addons.is_empty():
		var label := Label.new()
		label.text = "All tracked addons are up to date!"
		vbox.add_child(label)
		dialog.get_ok_button().disabled = true
	else:
		dialog.get_ok_button().disabled = false
		for addon in outdated_addons:
			var cb := CheckBox.new()

			cb.text = "%s (%s -> %s)" % [addon["repo"], addon["current_version"], addon["latest_version"]]
			cb.button_pressed = true

			vbox.add_child(cb)
			update_checkboxes[addon["repo"]] = cb

	# Show the popup in the middle of the screen
	dialog.popup_centered(Vector2(350, 150))

func _on_dialog_confirmed() -> void:
	var repos_to_update: Array[String] = []
	for repo in update_checkboxes:
		if update_checkboxes[repo].button_pressed:
			repos_to_update.append(repo)

	if repos_to_update.is_empty():
		return # Do nothing when everything is deselected

	print("Wisp is downloading updates...")

	# Pass all repos to update.
	var args = ["update"]
	args.append_array(repos_to_update)
	args.append("--yes") # Bypass confirmation

	var output = []
	var exit_code := OS.execute("wisp", args, output, true, true)

	for line in output:
		print(line)
	
	# Re scan folders.
	if exit_code == 0:
		get_editor_interface().get_resource_filesystem().scan()
