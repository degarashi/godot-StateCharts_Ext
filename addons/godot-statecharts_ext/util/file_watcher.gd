@tool
extends RefCounted

# ------------- [Signal] -------------
signal files_changed(files: PackedStringArray)

# ------------- [Private Variable] -------------
var _tree: SceneTree
var _get_watch_files_fn: Callable
var _last_files: PackedStringArray = []
var _last_modified_times: Dictionary = {}
var _accumulated_changes: Dictionary = {}
var _is_syncing := false
var _is_exiting := false


# ------------- [Callbacks] -------------
## Callback called when the filesystem changes
## Checks modified times of watched files and defers sync if changes are detected
func _on_filesystem_changed(_unused: Variant = null) -> void:
	if _is_syncing or _is_exiting:
		return

	var current_files := _get_current_files()
	var changed_files := _get_changed_files(current_files)
	if not changed_files.is_empty():
		for path in changed_files:
			_accumulated_changes[path] = true
		_deferred_sync.call_deferred()


# ------------- [Private Method] -------------
## Gets the list of currently watched files
func _get_current_files() -> PackedStringArray:
	if _get_watch_files_fn.is_valid():
		var res: Variant = _get_watch_files_fn.call()
		if res is PackedStringArray:
			return res
		elif res is Array:
			return PackedStringArray(res)
	return _get_default_watch_files()


## Checks the list of watched files and their modified times, returning a list of changed files
func _get_changed_files(current_files: PackedStringArray) -> PackedStringArray:
	var changed_files := PackedStringArray()

	var current_set := {}
	for path in current_files:
		current_set[path] = true

	# Detect deleted files
	for path in _last_files:
		if not current_set.has(path):
			changed_files.append(path)

	# Detect new or modified files
	for path in current_files:
		var mtime := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
		if not _last_modified_times.has(path) or _last_modified_times[path] != mtime:
			changed_files.append(path)

	return changed_files


## Updates the internal state with the latest file list
func _update_state(current_files: PackedStringArray) -> void:
	_last_files = current_files
	_last_modified_times.clear()
	for path in current_files:
		_last_modified_times[path] = FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0


func _get_default_watch_files() -> PackedStringArray:
	var files := PackedStringArray()
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		var root := fs.get_filesystem()
		if root:
			_collect_files_recursive(root, files)
	return files


func _collect_files_recursive(dir: EditorFileSystemDirectory, files: PackedStringArray) -> void:
	for i in range(dir.get_file_count()):
		files.append(dir.get_file_path(i))
	for i in range(dir.get_subdir_count()):
		var subdir := dir.get_subdir(i)
		if subdir:
			_collect_files_recursive(subdir, files)


## Deferred execution method to sync file changes
## Used to aggregate consecutive change events and prevent redundant processing
func _deferred_sync() -> void:
	if _is_exiting or not is_instance_valid(_tree):
		return
	await _tree.process_frame

	if _is_exiting or not is_instance_valid(_tree):
		return
	await _tree.process_frame

	if _is_exiting:
		return

	var current_files := _get_current_files()
	var changed_files := _get_changed_files(current_files)
	for path in changed_files:
		_accumulated_changes[path] = true

	if not _accumulated_changes.is_empty():
		var emit_files := PackedStringArray(_accumulated_changes.keys())
		_accumulated_changes.clear()
		_update_state(current_files)
		files_changed.emit(emit_files)


# ------------- [Public Method] -------------
## Constructor. Initializes dependencies required for watching and connects filesystem signals
func _init(
	tree: SceneTree = null, get_watch_files_fn := Callable()
) -> void:
	_tree = tree if tree else (Engine.get_main_loop() as SceneTree)
	_get_watch_files_fn = get_watch_files_fn

	# Record initial state
	var current_files := _get_current_files()
	_update_state(current_files)

	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.filesystem_changed.connect(_on_filesystem_changed)
		if fs.has_signal("sources_changed"):
			fs.sources_changed.connect(_on_filesystem_changed)


## Destructor. Disconnects connected signals
func destroy() -> void:
	_is_exiting = true
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		if fs.filesystem_changed.is_connected(_on_filesystem_changed):
			fs.filesystem_changed.disconnect(_on_filesystem_changed)
		if fs.has_signal("sources_changed") and fs.sources_changed.is_connected(_on_filesystem_changed):
			fs.sources_changed.disconnect(_on_filesystem_changed)


## Updates the file watcher's cached states with the current state of files on disk.
## Use this after making local modifications to watched files to avoid triggering duplicate signals.
func update_watched_state() -> void:
	var current_files := _get_current_files()
	_update_state(current_files)


## Called when the editor gains focus. Forces a filesystem scan and checks for changes
func handle_focus_in() -> void:
	if _is_syncing or _is_exiting:
		return
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()
	_on_filesystem_changed()


## Forces a synchronization process
func force_sync() -> void:
	_last_modified_times.clear()
	_last_files.clear()
	_deferred_sync.call_deferred()


## Sets whether syncing is in progress. Used to ignore file change events during sync
func set_syncing(syncing: bool) -> void:
	_is_syncing = syncing

