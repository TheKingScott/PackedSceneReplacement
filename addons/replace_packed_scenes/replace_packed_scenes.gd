@tool
extends EditorPlugin

var editor_interface: EditorInterface
var scene_tree: Tree

const CONTEXT_MENU_REPLACE_SCENE_ID = 100

func _enter_tree():
	print("Plugin entering tree...")
	editor_interface = get_editor_interface()
	
	# Find SceneTreeDock and SceneTree
	var scene_tree_dock = find_scene_tree_dock(editor_interface.get_base_control())
	if not scene_tree_dock:
		print("Error: Could not find SceneTreeDock.")
		debug_print_hierarchy(editor_interface.get_base_control())
		return
		
	scene_tree = find_tree_node(scene_tree_dock)
	if not scene_tree:
		print("Error: Could not find Tree node.")
		debug_print_hierarchy(scene_tree_dock)
		return
	
	print("Found scene tree: ", scene_tree.name)
	
	# Connect signals for right-click detection
	if not scene_tree.gui_input.is_connected(_on_tree_gui_input):
		scene_tree.gui_input.connect(_on_tree_gui_input)
	
	print("Scene tree signals connected.")

func _exit_tree():
	# Clean up when plugin is disabled
	if scene_tree and is_instance_valid(scene_tree):
		if scene_tree.gui_input.is_connected(_on_tree_gui_input):
			scene_tree.gui_input.disconnect(_on_tree_gui_input)

func find_scene_tree_dock(node: Node) -> Control:
	if node is Control and node.get_class() == "SceneTreeDock":
		return node
	for child in node.get_children():
		var result = find_scene_tree_dock(child)
		if result:
			return result
	return null

func find_tree_node(node: Node) -> Tree:
	if node is Tree:
		return node
	for child in node.get_children():
		var result = find_tree_node(child)
		if result:
			return result
	return null

func debug_print_hierarchy(node: Node, depth: int = 0):
	var indent = "  ".repeat(depth)
	print(indent + "- " + node.name + " (" + node.get_class() + ")")
	for child in node.get_children():
		debug_print_hierarchy(child, depth + 1)

func _on_tree_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var mouse_pos = get_viewport().get_mouse_position()
		#print("Right-click detected at: ", mouse_pos)
		
		# Check if there's a selection
		var selected = editor_interface.get_selection().get_selected_nodes()
		if selected.size() == 0:
			return
			
		# Create a new PopupMenu each time (more reliable in editor)
		var popup = PopupMenu.new()
		popup.add_item("Replace Packed Scene", CONTEXT_MENU_REPLACE_SCENE_ID)
		
		# Add to editor interface
		editor_interface.get_base_control().add_child(popup)
		
		# Connect signal and show popup
		popup.id_pressed.connect(_on_popup_id_pressed.bind(popup))
		popup.close_requested.connect(_on_popup_closed.bind(popup))
		
		# Use popup_centered_ratio to ensure proper placement and visibility
		popup.popup(Rect2(mouse_pos, Vector2(1, 1)))
		
		# Accept event to prevent other handlers
		get_viewport().set_input_as_handled()

func _on_popup_id_pressed(id: int, popup: PopupMenu):
	if id == CONTEXT_MENU_REPLACE_SCENE_ID:
		print("Replace Packed Scene selected.")
		# Get the currently selected node in the scene tree
		var selected = editor_interface.get_selection().get_selected_nodes()
		if selected.size() > 0:
			print("Selected node: ", selected[0].name)
			_show_file_dialog()
	
	# Clean up popup
	popup.queue_free()

func _on_popup_closed(popup: PopupMenu):
	# Clean up popup when closed
	popup.queue_free()

func _show_file_dialog():
	# Create a file dialog to select a scene
	var file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.add_filter("*.tscn", "Scene")
	file_dialog.add_filter("*.scn", "Scene")
	
	# Add dialog to editor
	editor_interface.get_base_control().add_child(file_dialog)
	
	# Connect signal and show dialog
	file_dialog.file_selected.connect(_on_scene_selected.bind(file_dialog))
	file_dialog.canceled.connect(_on_dialog_canceled.bind(file_dialog))
	
	file_dialog.popup_centered_ratio(0.6)

func _on_scene_selected(path: String, dialog: EditorFileDialog):
	print("Selected scene: ", path)
	var selected = editor_interface.get_selection().get_selected_nodes()
	if selected.size() > 0:
		var selected_node = selected[0]
		
		print("Replacing ", selected_node.name, " with scene from ", path)
		
		# Get the instance owner for proper scene tree updates
		var owner = selected_node.owner
		
		# Store position/transform and other important properties
		var original_position
		var is_3d = false
		
		# For 2D nodes
		if selected_node is Node2D:
			original_position = selected_node.position
		# For UI nodes
		elif selected_node is Control:
			original_position = selected_node.position
		# For 3D nodes  
		elif selected_node is Node3D:
			original_position = selected_node.position
			is_3d = true
			
		var original_name = selected_node.name
		var original_parent = selected_node.get_parent()
		
		# Get original node's position in parent's children
		var original_pos = -1
		if original_parent:
			original_pos = original_parent.get_children().find(selected_node)
		
		# Store the children of the original node
		var original_children = []
		for child in selected_node.get_children():
			original_children.append(child)
		
		# Load and instantiate the new scene
		var packed_scene = load(path)
		if not packed_scene:
			print("Error: Failed to load scene from path: ", path)
			dialog.queue_free()
			return
			
		# Instantiate the packed scene
		var new_instance = packed_scene.instantiate()
		if not new_instance:
			print("Error: Failed to instantiate scene")
			dialog.queue_free()
			return
		
		# Remove all children from the new instance
		for child in new_instance.get_children():
			new_instance.remove_child(child)
			child.queue_free()  # Free the child node
		
		# Give the new node the same name as the original
		new_instance.name = original_name
		
		# Temporarily remove the old node to avoid name conflicts
		if original_parent:
			original_parent.remove_child(selected_node)
		
		# Add the new node to the same parent
		if original_parent:
			# If we stored the position, insert at the same index
			if original_pos >= 0 and original_pos < original_parent.get_child_count():
				original_parent.add_child(new_instance)
				original_parent.move_child(new_instance, original_pos)
			else:
				original_parent.add_child(new_instance)
		
		# Add the original children back to the new node
		for child in original_children:
			# Remove the child from its current parent (original node)
			selected_node.remove_child(child)
			# Add the child to the new node #Scott test
			#new_instance.add_child(child)
			# Set the owner for proper scene saving #Scott test
			#child.owner = owner
		
		# Set the owner for proper scene saving
		if owner and owner != new_instance:
			new_instance.owner = owner
		
		# Apply stored position to the new node based on its type
		if original_position != null:
			if is_3d and new_instance is Node3D:
				new_instance.position = original_position
			elif new_instance is Node2D:
				new_instance.position = original_position
			elif new_instance is Control:
				new_instance.position = original_position
		
		# Remove the script from the new node (if it has one)
		if new_instance.get_script():
			print("Removing script from new node: ", new_instance.name)
			new_instance.set_script(null)  # This removes the script
		
		# Ensure the new node has a valid scene_file_path for editable children
		new_instance.scene_file_path = path
		
		# Select the new node in the editor
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(new_instance)
		
		# Free the old node (only after children have been reparented)
		selected_node.queue_free()
		
		# Mark the scene as modified
		editor_interface.get_resource_filesystem().scan()
		
		print("Replacement complete: ", new_instance.name)
	
	dialog.queue_free()

func _on_dialog_canceled(dialog: EditorFileDialog):
	dialog.queue_free()

# Helper function to recursively set the owner of a node and its children
func _recursively_set_owner(node: Node, owner: Node):
	node.owner = owner
	for child in node.get_children():
		_recursively_set_owner(child, owner)
