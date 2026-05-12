@tool
extends EditorPlugin
## The Wisp updater editor plugin.
## 
## Looks for updates when the button is pressed.

var complete_icon: Texture2D = load("uid://gvon8mvqv1db")
var in_progress_icon: Texture2D = load("uid://7tfmm0phd0n3")
var failed_icon: Texture2D = load("uid://qgs7d6jrj6pa")

var update_button: Button
var dialog: ConfirmationDialog # TODO: This is temp, should be scene.
var vbox: VBoxContainer # TODO: This is temp, should be cleaned up.

var update_checkboxes: Dictionary = {}

## This thread handles the execution of wisp commands so the main thread isn't blocked.
var wisp_thread: Thread

func _enter_tree() -> void:
	# TODO: Check whether Wisp is installed before enabling the addon.

	_init_button()
	_init_dialog()

func _exit_tree() -> void:
	update_button.queue_free()
	dialog.queue_free()


## Initializes the button for Wisp
func _init_button() -> void:
	# Use a dummy to get the right control
	var dummy = Control.new()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, dummy)
	var target_toolbar = dummy.get_parent()
	dummy.queue_free()

	var native_button: Button

	# Safely recursively hunt for the first native Button inside the RunBar
	for child in target_toolbar.get_children():
		if child.name.contains("EditorRunBar"):
			# Go into the first VBOX
			if child.get_child_count() > 0:
				child = child.get_child(0)
				# Go into the second VBOX???
				if child.get_child_count() > 1:
					child = child.get_child(1)
					native_button = _find_first_button(child)
					break

	if not native_button:
		printerr("Wisp could not find a base editor button to clone!")
		return

	# Duplicate the button (without copying signals and such)
	update_button = native_button.duplicate()
	
	# Scrub the button
	update_button.icon = complete_icon
	update_button.visible = true
	update_button.text = ""
	update_button.toggle_mode = false
	update_button.tooltip_text = "Check for addon updates"
	update_button.shortcut = null
	update_button.expand_icon = true
	update_button.custom_minimum_size = Vector2(28, 28)
	update_button.focus_mode = Control.FOCUS_NONE
	
	update_button.pressed.connect(_on_wisp_button_pressed)

	# Inject the button.
	native_button.get_parent().add_child(update_button)

## Recursive helper to safely dig down and find the first Button node
func _find_first_button(node: Node) -> Button:
	if node is Button:
		return node
	for child in node.get_children():
		var result = _find_first_button(child)
		if result:
			return result
	return null
 
## Initialize the dialog box used for the popup and it's contents.
func _init_dialog() -> void:
	# Popup
	dialog = ConfirmationDialog.new()
	dialog.title = "Wisp Updates Available"
	dialog.confirmed.connect(_on_dialog_confirmed)

	# VBox
	vbox = VBoxContainer.new()
	dialog.add_child(vbox)

	get_editor_interface().get_base_control().add_child(dialog)


func _on_wisp_button_pressed() -> void:
	# If already pressed just skip
	if wisp_thread and wisp_thread.is_alive(): return

	# Clean up the old thread
	if wisp_thread and wisp_thread.is_started():
		wisp_thread.wait_to_finish()

	# Clear out old checkboxes if there are any.
	for child in vbox.get_children():
		child.queue_free()
	update_checkboxes.clear()
	
	# TODO: Make the button move visually during check.
	# Disable the button visually while working
	update_button.disabled = true
	update_button.icon = in_progress_icon

	wisp_thread = Thread.new()
	wisp_thread.start(_run_wisp_check_background)


## Worker used to run the "wisp check" command on a separate thread.
## The multithreading itself is engaged outside of this method. The method itself just does the work.
func _run_wisp_check_background() -> void:
	var output = []
	var exit_code: int = OS.execute("wisp", ["check", "--json"], output, true, false)

	# Hand the output back to the main thread.
	call_deferred(&"_on_wisp_check_finished", exit_code, output)


## Called by the worker to signal the "wisp check" command finished.
func _on_wisp_check_finished(exit_code: int, output: Array) -> void:
	# Join the thread.
	if wisp_thread.is_started():
		wisp_thread.wait_to_finish()

	if exit_code != OK or output.is_empty():
		printerr("Wisp failed to check for updates.")
		return
	
	# Parse JSON
	var json_string: String = "".join(output)
	var json: JSON = JSON.new()
	var error := json.parse(json_string)

	# Will always return at least an empty list.
	var outdated_addons = json.data

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
	update_button.disabled = false
	update_button.icon = complete_icon

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
