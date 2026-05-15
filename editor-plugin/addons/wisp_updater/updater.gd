@tool
extends EditorPlugin
## The Wisp updater editor plugin.
## 
## Looks for updates when the button is pressed.

# Assets
var icon: Texture2D = load("uid://bye648xq1hcd6")

# Nodes for the Update Button in the toolbar.
var update_button: Button
var button_tween: Tween

# Popup nodes.
var dialog: ConfirmationDialog # TODO: This is temp, should be scene.
var vbox: VBoxContainer # TODO: This is temp, should be cleaned up.

# Keeps track of the checkboxes for updates.
var update_checkboxes: Dictionary = {}

# The CLI instance we'll be interacting with.
var cli: CLI = CLI.new()

## Ran when the plugin is enabled.
func _enter_tree() -> void:
	_init_button()
	_init_dialog()

	# Check whether wisp is installed, and if not disable the button.

	cli.wisp_exists() # This is on startup so no need to check for existence.
	var result: Array = await cli.command_finished

	# We only need the exit code.
	var exit_code: int = result[0]
	if exit_code != OK:
		push_warning("Wisp was not found on your machine. You can install it and reload the addon to use the editor plugin.")
		update_button.disabled = true
		update_button.tooltip_text = "Wisp CLI not found! Please install Wisp and restart Godot to use this feature."


## Ran when the plugin is disabled. Cleanup goes here.
func _exit_tree() -> void:
	update_button.queue_free()
	dialog.queue_free()
	cli.join()


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
	update_button.icon = icon
	update_button.visible = true
	update_button.text = ""
	update_button.toggle_mode = false
	update_button.tooltip_text = "Check for addon updates."
	update_button.shortcut = null
	update_button.expand_icon = true
	update_button.custom_minimum_size = Vector2(28, 28)
	update_button.focus_mode = Control.FOCUS_NONE
	update_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	
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
	dialog.canceled.connect(_on_dialog_cancelled)

	# VBox
	vbox = VBoxContainer.new()
	dialog.add_child(vbox)

	get_editor_interface().get_base_control().add_child(dialog)


## Called when the wisp button is pressed in the top right.
## Will start the loading animation and the check command.
func _on_wisp_button_pressed() -> void:
	_start_loading_animation()
	var free := cli.wisp_check()
	if !free: # Means the thread was already working.
		return

	var result: Array = await cli.command_finished

	var exit_code: int = result[0]
	var output: Array = result[1]

	# Proceed to processing
	_on_wisp_check_finished(exit_code, output)


## Called by the worker to signal the "wisp check" command finished.
func _on_wisp_check_finished(exit_code: int, output: Array) -> void:
	# Join the thread
	cli.join()

	if exit_code != OK or output.is_empty():
		printerr("Wisp failed to check for updates.")
		_stop_loading_animation()
		return
	
	# Parse JSON
	var json_string: String = "".join(output)
	var json: JSON = JSON.new()
	var error := json.parse(json_string)

	# Will always return at least an empty list.
	var outdated_addons = json.data

	# Clear the checkboxes
	for child in vbox.get_children():
		child.queue_free()
	update_checkboxes.clear()

	# Build UI based on JSON.
	if outdated_addons.is_empty():
		var label := Label.new()
		label.text = "All tracked addons are up to date!"
		vbox.add_child(label)
	else:
		for addon in outdated_addons:
			var cb := CheckBox.new()

			cb.text = "%s (%s -> %s)" % [addon["repo"], addon["current_version"], addon["latest_version"]]
			cb.button_pressed = true

			vbox.add_child(cb)
			update_checkboxes[addon["repo"]] = cb

	# Show the popup in the middle of the screen
	dialog.popup_centered(Vector2(350, 150))


## Called when the CANCEL button is pressed in the Dialogue box.
func _on_dialog_cancelled() -> void:
	_stop_loading_animation()


## Called when the Dialogue CONFIRM button is pressed.
## Will perform the wisp update command with all of the checked addons.
func _on_dialog_confirmed() -> void:
	var repos_to_update: Array[String] = []
	for repo in update_checkboxes:
		if update_checkboxes[repo].button_pressed:
			repos_to_update.append(repo)

	if repos_to_update.is_empty():
		_stop_loading_animation()
		return # Do nothing when everything is deselected

	# Run the update command
	var free := cli.wisp_update(repos_to_update)
	if !free: # Means the thread was already occupied.
		return

	var result: Array = await cli.command_finished
	
	var exit_code: int = result[0]
	var output: Array = result[1]

	_on_wisp_update_finished(exit_code, output)


## Called by the worker to signal the "wisp update" command finished.
func _on_wisp_update_finished(exit_code: int, output: Array) -> void:
	# Join the thread
	cli.join()

	_stop_loading_animation()
	if exit_code == OK:
		get_editor_interface().get_resource_filesystem().scan()
	else:
		printerr("Wisp failed to update some addons.")


## Starts the loading animation of the button in the editor and disables it.
func _start_loading_animation() -> void:
	_stop_loading_animation()

	# Set the pivot offset and disable the button.
	update_button.disabled = true
	update_button.pivot_offset = update_button.size / 2.0

	button_tween = update_button.create_tween().bind_node(update_button)

	# Set looping and trans
	button_tween.set_loops()
	button_tween.set_trans(Tween.TRANS_SINE)

	# Rotation
	button_tween.tween_property(update_button, "rotation", TAU, 1.0).as_relative()


## Stops the loading animation of the button in the editor and enables it.
func _stop_loading_animation() -> void:
	if button_tween and button_tween.is_valid():
		button_tween.kill()
	
	update_button.disabled = false
	update_button.rotation = 0
