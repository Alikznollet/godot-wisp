extends Resource
class_name CLI

## Emitted when a command finished.
signal command_finished(exit_code: int, output: Array)

## This thread handles the execution of wisp commands so the main thread isn't blocked.
var wisp_thread: Thread

## Cleans up the thread if it's still open.
func join() -> void:
	if wisp_thread and wisp_thread.is_started():
		wisp_thread.wait_to_finish()


func wisp_check() -> bool:
	# If already pressed just skip
	if wisp_thread and wisp_thread.is_alive(): return false

	# Clean up the old thread
	if wisp_thread and wisp_thread.is_started():
		wisp_thread.wait_to_finish()

	wisp_thread = Thread.new()
	wisp_thread.start(_wisp_check_worker)
	return true


## Worker used to run the "wisp check" command on a separate thread.
## The multithreading itself is engaged outside of this method. The method itself just does the work.
func _wisp_check_worker() -> void:
	var output = []
	var exit_code: int = OS.execute("wisp", ["check", "--json"], output, true, false)

	# Hand the output back to the main thread.
	command_finished.emit.call_deferred(exit_code, output)


## Will run the "wisp update" command on a separate thread.
## Handles the joining of the thread.
func wisp_update(repos_to_update: Array) -> bool:
	# If already pressed just skip
	if wisp_thread and wisp_thread.is_alive(): return false

	# Clean up the old thread
	if wisp_thread and wisp_thread.is_started():
		wisp_thread.wait_to_finish()

	wisp_thread = Thread.new()
	wisp_thread.start(_wisp_update_worker.bind(repos_to_update))
	return true


## Worker used to run the "wisp update" command on a separate thread.
## The multithreading itself is engaged outside of this method. The method itself just does the work.
func _wisp_update_worker(repos_to_update: Array) -> void:
	# Pass all repos to update.
	var args = ["update"]
	args.append_array(repos_to_update)
	args.append("--yes") # Bypass confirmation

	var output = []
	var exit_code := OS.execute("wisp", args, output, true, false)

	# Hand the exit code back to the main thread.
	command_finished.emit.call_deferred(exit_code, output)
