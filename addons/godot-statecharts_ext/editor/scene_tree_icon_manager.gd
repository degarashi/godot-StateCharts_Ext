@tool
extends RefCounted

const BUTTON_ID_BASE := 999600
const BUTTON_ID_EVENT := BUTTON_ID_BASE + 1
const BUTTON_ID_ENTERED := BUTTON_ID_BASE + 2
const BUTTON_ID_EXITED := BUTTON_ID_BASE + 3
const BUTTON_ID_PROCESSING := BUTTON_ID_BASE + 4
const BUTTON_ID_PHYSICS := BUTTON_ID_BASE + 5

var _plugin: EditorPlugin
var _tree: Tree
var _icons: Dictionary = {}
var _refresh_timer: SceneTreeTimer
var _last_best_score := -1
var _is_cleaning_up := false


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin

	_icons[BUTTON_ID_EVENT] = preload(
		"res://addons/godot-statecharts_ext/icons/icon_on_event_received.svg"
	)
	_icons[BUTTON_ID_ENTERED] = preload(
		"res://addons/godot-statecharts_ext/icons/icon_on_state_entered.svg"
	)
	_icons[BUTTON_ID_EXITED] = preload(
		"res://addons/godot-statecharts_ext/icons/icon_on_state_exited.svg"
	)
	_icons[BUTTON_ID_PROCESSING] = preload(
		"res://addons/godot-statecharts_ext/icons/icon_on_state_processing.svg"
	)
	_icons[BUTTON_ID_PHYSICS] = preload(
		"res://addons/godot-statecharts_ext/icons/icon_on_physics_state_processing.svg"
	)

	DLogger.debug("SceneTreeIconManager initialized.", [], "st_icon")
	_find_tree()

	_plugin.scene_changed.connect(func(_root): update_icons())
	_plugin.scene_closed.connect(func(_path): update_icons())
	_plugin.main_screen_changed.connect(func(_screen): update_icons())
	EditorInterface.get_selection().selection_changed.connect(update_icons)

	_start_periodic_refresh()


func _start_periodic_refresh() -> void:
	if _is_cleaning_up or _refresh_timer:
		return
	_refresh_timer = _plugin.get_tree().create_timer(2.0)
	_refresh_timer.timeout.connect(_on_refresh_timeout)


func _on_refresh_timeout() -> void:
	_refresh_timer = null
	update_icons()
	_start_periodic_refresh()


func _find_tree() -> void:
	var base := EditorInterface.get_base_control()
	if not base:
		return

	var all_trees: Array[Tree] = []
	_gather_all_trees(base, all_trees)

	var best_cand: Tree = null
	var best_score := -1

	for t in all_trees:
		if not is_instance_valid(t):
			continue
		var p = t.get_parent()
		if not p or p.get_class() != "SceneTreeEditor":
			continue

		var score := 0
		var path := _get_node_path_simple(t)
		if t.get_root() != null:
			score += 100
		if "/Scene/" in path:
			score += 50
		if "Animation" in path or "Dialog" in path:
			score -= 80

		if score > best_score:
			best_score = score
			best_cand = t

	if best_cand:
		if _tree != best_cand or best_score > _last_best_score:
			_tree = best_cand
			_last_best_score = best_score
			DLogger.info(
				"Tree identified: {0} (Score: {1}, Root: {2})",
				[_get_node_path_simple(_tree), best_score, _tree.get_root() != null],
				"st_icon"
			)

			if not _tree.is_connected("gui_input", _on_tree_gui_input):
				_tree.gui_input.connect(_on_tree_gui_input)

			if not _tree.is_connected("button_clicked", _on_tree_button_clicked):
				_tree.button_clicked.connect(_on_tree_button_clicked)
	else:
		_tree = null
		_last_best_score = -1


func _gather_all_trees(node: Node, list: Array[Tree]) -> void:
	if node is Tree:
		list.append(node)
	for child in node.get_children():
		_gather_all_trees(child, list)


func _get_node_path_simple(node: Node) -> String:
	var p := node.name
	var parent := node.get_parent()
	while parent and parent != EditorInterface.get_base_control():
		p = parent.name + "/" + p
		parent = parent.get_parent()
	return p


func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		update_icons()


func _on_tree_button_clicked(
	item: TreeItem, _column: int, id: int, _mouse_button_index: int
) -> void:
	if id < BUTTON_ID_BASE or id > BUTTON_ID_PHYSICS:
		return

	var node := _get_node_from_item(item)
	if not node:
		return

	var signal_name := ""
	match id:
		BUTTON_ID_EVENT:
			signal_name = "event_received"
		BUTTON_ID_ENTERED:
			signal_name = "state_entered"
		BUTTON_ID_EXITED:
			signal_name = "state_exited"
		BUTTON_ID_PROCESSING:
			signal_name = "state_processing"
		BUTTON_ID_PHYSICS:
			signal_name = "state_physics_processing"

	if signal_name == "":
		return

	var conns := _get_user_connections(node, signal_name)
	if conns.is_empty():
		return

	# Jump to the first connection target
	var conn := conns[0]
	var callable: Callable = conn["callable"]
	var target: Object = callable.get_object()
	var method: StringName = callable.get_method()

	if target is Node:
		var script: Script = target.get_script()
		if script:
			var line := _find_method_line(script, method)
			EditorInterface.edit_script(script, line)


func _get_node_from_item(item: TreeItem) -> Node:
	for i in range(2):
		var m = item.get_metadata(i)
		if m == null:
			continue
		if m is Node:
			return m
		if m is int:
			return instance_from_id(m) as Node
		if m is String or m is NodePath:
			var scene_root = EditorInterface.get_edited_scene_root()
			if scene_root:
				var n = scene_root.get_node_or_null(m)
				if n:
					return n
	return null


func _find_method_line(script: Script, method_name: String) -> int:
	var code := script.get_source_code()
	var lines := code.split("\n")
	# Basic search for "func method_name"
	var pattern := "func " + method_name
	for i in range(lines.size()):
		var line_text := lines[i].strip_edges()
		if line_text.begins_with(pattern):
			# Double check it's not a substring of another function
			var after_pattern = line_text.substr(pattern.length()).strip_edges()
			if (
				after_pattern == ""
				or after_pattern.begins_with("(")
				or after_pattern.begins_with(":")
			):
				return i + 1
	return -1


func update_icons() -> void:
	# Keep trying to find a better tree or wait for root
	if not is_instance_valid(_tree) or _tree.get_root() == null:
		_find_tree()
		if not is_instance_valid(_tree) or _tree.get_root() == null:
			return

	if not _tree.is_visible_in_tree():
		return

	var root: TreeItem = _tree.get_root()
	if not root:
		return

	_process_item_recursive(root)


func _process_item_recursive(item: TreeItem) -> void:
	var node: Node = null

	# Try all indices and various retrieval methods
	for i in range(2):
		var m = item.get_metadata(i)
		if m == null:
			continue

		if m is Node:
			node = m
		elif m is int:
			node = instance_from_id(m) as Node
		elif m is String or m is NodePath:
			# Try to resolve path relative to edited scene root
			var scene_root = EditorInterface.get_edited_scene_root()
			if scene_root:
				node = scene_root.get_node_or_null(m)

		if node:
			break

	# If still no node, but we have text, it might be a SceneTree item we don't know how to decode yet
	# DLogger.debug("Item: {0}, NodeFound: {1}, Meta0: {2}", [item.get_text(0), (node != null),
	# type_string(typeof(item.get_metadata(0)))], "st_icon")
	if node:
		_update_item_icons(item, node)

	var child: TreeItem = item.get_first_child()
	while child:
		_process_item_recursive(child)
		child = child.get_next()


func _update_item_icons(item: TreeItem, node: Node) -> void:
	# Clear existing extension icons
	for i in range(item.get_button_count(0) - 1, -1, -1):
		var id := item.get_button_id(0, i)
		if id >= BUTTON_ID_BASE and id <= BUTTON_ID_PHYSICS:
			item.erase_button(0, i)

	var sig_config := {
		"event_received": [BUTTON_ID_EVENT, _icons[BUTTON_ID_EVENT]],
		"state_entered": [BUTTON_ID_ENTERED, _icons[BUTTON_ID_ENTERED]],
		"state_exited": [BUTTON_ID_EXITED, _icons[BUTTON_ID_EXITED]],
		"state_processing": [BUTTON_ID_PROCESSING, _icons[BUTTON_ID_PROCESSING]],
		"state_physics_processing": [BUTTON_ID_PHYSICS, _icons[BUTTON_ID_PHYSICS]]
	}

	for s: String in sig_config:
		if node.has_signal(s):
			var conns := _get_user_connections(node, s)
			if conns.size() > 0:
				var cfg: Array = sig_config[s]
				var tex = cfg[1]
				if tex is Texture2D:
					var method_name: String = conns[0]["callable"].get_method()
					var tooltip := "{0} is connected\nClick to jump to [ {1} ]".format([s, method_name])
					item.add_button(0, tex, cfg[0], false, tooltip)
				else:
					DLogger.warn("Icon for {0} is not a valid Texture2D", [s], "st_icon")


func _get_user_connections(node: Node, signal_name: String) -> Array[Dictionary]:
	var user_conns: Array[Dictionary] = []
	if not node.has_signal(signal_name):
		return user_conns

	var conns := node.get_signal_connection_list(signal_name)
	for conn: Dictionary in conns:
		var callable: Callable = conn["callable"]
		var target: Object = callable.get_object()
		var method: StringName = callable.get_method()

		var is_internal := false
		if target is StateChartExt:
			if method in [
				"_on_state_entered_context",
				"_on_state_entered_actions",
				"_on_state_exited_cleanup",
				"_on_state_exited_actions",
				"_on_state_entered",
				"_on_state_exited"
			]:
				is_internal = true

		if not is_internal:
			user_conns.append(conn)

	return user_conns


func cleanup() -> void:
	_is_cleaning_up = true
	if _refresh_timer and _refresh_timer.timeout.is_connected(_on_refresh_timeout):
		_refresh_timer.timeout.disconnect(_on_refresh_timeout)
	_refresh_timer = null

	if EditorInterface.get_selection().selection_changed.is_connected(update_icons):
		EditorInterface.get_selection().selection_changed.disconnect(update_icons)

	if is_instance_valid(_tree) and _tree.gui_input.is_connected(_on_tree_gui_input):
		_tree.gui_input.disconnect(_on_tree_gui_input)

	if is_instance_valid(_tree) and _tree.button_clicked.is_connected(_on_tree_button_clicked):
		_tree.button_clicked.disconnect(_on_tree_button_clicked)

	if is_instance_valid(_tree):
		_remove_buttons_recursive(_tree.get_root())


func _remove_buttons_recursive(item: TreeItem) -> void:
	if not item:
		return
	for i in range(item.get_button_count(0) - 1, -1, -1):
		var id: int = item.get_button_id(0, i)
		if id >= BUTTON_ID_BASE and id <= BUTTON_ID_PHYSICS:
			item.erase_button(0, i)
	var child: TreeItem = item.get_first_child()
	while child:
		_remove_buttons_recursive(child)
		child = child.get_next()
