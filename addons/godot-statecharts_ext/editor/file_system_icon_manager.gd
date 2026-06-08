@tool
extends RefCounted

const ICON_TEX := preload("uid://wutp82auwys2")
const BUTTON_ID := 999543  # Unique ID

var _plugin: EditorPlugin
var _trees: Array[Tree] = []


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_find_trees()

	var fs := EditorInterface.get_resource_filesystem()
	fs.filesystem_changed.connect(update_icons)

	# Also connect to the dock's visibility or selection changes to trigger updates
	var dock := EditorInterface.get_file_system_dock()
	dock.visibility_changed.connect(update_icons)


func _find_trees() -> void:
	_trees.clear()
	var dock := EditorInterface.get_file_system_dock()
	_find_trees_recursive(dock)


func _find_trees_recursive(node: Node) -> void:
	if node is Tree:
		_trees.append(node)
		if not node.draw.is_connected(update_icons):
			node.draw.connect(update_icons)
		if not node.item_activated.is_connected(_on_item_activated.bind(node)):
			node.item_activated.connect(_on_item_activated.bind(node))

	for child in node.get_children():
		_find_trees_recursive(child)


func _on_item_activated(_tree: Tree) -> void:
	# Activation is handled by _edit() in godot-statecharts_ext.gd to avoid conflicts.
	pass


func update_icons() -> void:
	for tree in _trees:
		if not is_instance_valid(tree) or not tree.is_visible_in_tree():
			continue

		var root := tree.get_root()
		if not root:
			continue

		_process_item_recursive(root)


func _process_item_recursive(item: TreeItem) -> void:
	var metadata = item.get_metadata(0)
	if typeof(metadata) == TYPE_STRING:
		var path: String = metadata
		if path.ends_with(".scdef") or path.ends_with(".scxml"):
			item.set_icon(0, ICON_TEX)
			# Check if button already exists
			var has_button := false
			for i in range(item.get_button_count(0)):
				if item.get_button_id(0, i) == BUTTON_ID:
					has_button = true
					break

			if not has_button:
				# Add the badge icon
				item.add_button(0, ICON_TEX, BUTTON_ID, true, "StateChart Extension")

	var child := item.get_first_child()
	while child:
		_process_item_recursive(child)
		child = child.get_next()


func cleanup() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs.filesystem_changed.is_connected(update_icons):
		fs.filesystem_changed.disconnect(update_icons)

	var dock := EditorInterface.get_file_system_dock()
	if dock.visibility_changed.is_connected(update_icons):
		dock.visibility_changed.disconnect(update_icons)

	for tree in _trees:
		if is_instance_valid(tree):
			if tree.draw.is_connected(update_icons):
				tree.draw.disconnect(update_icons)
			if tree.item_activated.is_connected(_on_item_activated):
				tree.item_activated.disconnect(_on_item_activated)
			# Optionally remove buttons
			_remove_buttons_recursive(tree.get_root())

	_trees.clear()


func _remove_buttons_recursive(item: TreeItem) -> void:
	if not item:
		return

	for i in range(item.get_button_count(0) - 1, -1, -1):
		if item.get_button_id(0, i) == BUTTON_ID:
			item.erase_button(0, i)

	var child := item.get_first_child()
	while child:
		_remove_buttons_recursive(child)
		child = child.get_next()
