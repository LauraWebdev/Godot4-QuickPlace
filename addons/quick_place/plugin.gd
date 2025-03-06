@tool
extends EditorPlugin

var dock:Control
var undo_redo:EditorUndoRedoManager = get_undo_redo()

var setting_scene:PackedScene
var setting_rotation:RotationType
var setting_active:bool

var start_stop_button:Button

enum RotationType {
	ORIGINAL,
	RANDOM,
	ALIGNED_TO_FACE,
	RANDOM_ALIGNED_TO_FACE,
}

func _enter_tree()->void:
	# Add dock
	dock = create_settings_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)

func _exit_tree()->void:
	# Remove dock
	remove_control_from_docks(dock)
	dock.free()

func _handles(object:Object)->bool:
	return object is Node3D

func _forward_3d_gui_input(viewport_camera:Camera3D, event:InputEvent)->int:
	if not (setting_active and setting_scene != null):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Raycast mouse
	var position_in_node:Vector2 = event.position
	var ray_space_state:PhysicsDirectSpaceState3D = viewport_camera.get_world_3d().direct_space_state
	var ray_origin:Vector3 = viewport_camera.project_ray_origin(position_in_node)
	var ray_end:Vector3 = ray_origin + viewport_camera.project_ray_normal(position_in_node) * 5000.0
	var ray_query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	ray_query.collide_with_areas = false
	var ray_result:Dictionary = ray_space_state.intersect_ray(ray_query)
	if not ray_result.has("position"):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Instantiate prefab
	var parent:Node = get_editor_interface().get_selection().get_selected_nodes()[0]
	var prefab:Node3D = setting_scene.instantiate()
	prefab.name = str(prefab.name, " #", parent.get_child_count())
	
	# Place / Unplace
	undo_redo.create_action(str("Place ", setting_scene.resource_path))
	undo_redo.add_do_method(self, &"place", prefab, parent, ray_result)
	undo_redo.add_undo_method(self, &"unplace", prefab, parent)
	undo_redo.add_do_reference(prefab)
	undo_redo.commit_action()
	
	return EditorPlugin.AFTER_GUI_INPUT_STOP

func create_settings_dock()->PanelContainer:
	var root := PanelContainer.new()
	root.name = "QuickPlace Settings"
	
	var settings_list := VBoxContainer.new()
	settings_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(settings_list)
	
	# SCENE
	var scene_picker := EditorResourcePicker.new()
	scene_picker.base_type = "PackedScene"
	var settings_item_scene:PanelContainer = create_settings_item("Scene", scene_picker)
	settings_list.add_child(settings_item_scene)
	scene_picker.connect("resource_changed", func(new_resource:PackedScene)->void:
		setting_scene = new_resource
		start_stop_button.disabled = new_resource == null)
	
	# ROTATION
	var rotation_select := OptionButton.new()
	for rotation_type in RotationType:
		rotation_select.add_item(rotation_type.capitalize(), RotationType.get(rotation_type))
	rotation_select.connect("item_selected", func(index:int)->void:
		setting_rotation = index)
	var settings_item_rotation_select:PanelContainer = create_settings_item("Rotation", rotation_select)
	settings_list.add_child(settings_item_rotation_select)
	
	# START/STOP BUTTON
	start_stop_button = Button.new()
	start_stop_button.disabled = true
	start_stop_button.text = "Start"
	start_stop_button.toggle_mode = true
	settings_list.add_child(start_stop_button)
	start_stop_button.connect("toggled", func(is_active:bool)->void:
		setting_active = is_active
		start_stop_button.text = "Stop" if is_active else "Start")
	
	return root

func create_settings_item(label:String, control:Control)->PanelContainer:
	var new_item_panel := PanelContainer.new()
	
	var new_item := HBoxContainer.new()
	new_item.set_anchors_preset(Control.PRESET_VCENTER_WIDE)
	new_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_item_panel.add_child(new_item)
	
	var new_label := Label.new()
	new_label.text = label
	new_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_item.add_child(new_label)
	
	control.set_anchors_preset(Control.PRESET_VCENTER_WIDE)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_item.add_child(control)
	
	return new_item_panel

# https://www.reddit.com/r/godot/comments/f2fowu/comment/fhdkxz5/
# Adjusted to support 90° side angles
func align_up(node_basis:Basis, normal:Vector3)->Basis:
	var result := Basis()
	var scale:Vector3 = node_basis.get_scale()
	
	# Check if normal is parallel to node_basis.z
	if abs(normal.dot(node_basis.z)) > 0.999:
		# Choose a different axis to avoid zero vector
		if abs(normal.dot(Vector3(1, 0, 0))) < 0.999:
			result.x = normal.cross(Vector3(1, 0, 0))
		else:
			result.x = normal.cross(Vector3(0, 1, 0))
	else:
		result.x = normal.cross(node_basis.z)
	
	result.y = normal
	result.z = result.x.cross(normal)
	
	result = result.orthonormalized()
	result.x *= scale.x
	result.y *= scale.y
	result.z *= scale.z
	
	return result

func place(prefab:Node3D, parent:Node, ray_result:Dictionary)->void:
	# Spawn
	parent.add_child(prefab)
	prefab.set_owner(parent.get_tree().edited_scene_root)
	prefab.global_position = ray_result.position
	
	# Rotate
	match setting_rotation:
		RotationType.ALIGNED_TO_FACE, RotationType.RANDOM_ALIGNED_TO_FACE when ray_result.normal != null:
			# Align To Face
			prefab.global_transform.basis = align_up(prefab.global_transform.basis, ray_result.normal.normalized())
			
			# Random Aligned To Face
			if setting_rotation == RotationType.RANDOM_ALIGNED_TO_FACE:
				var random_rotation:float = randf_range(0.0, 360.0)
				prefab.global_transform = prefab.global_transform.rotated_local(Vector3.UP, random_rotation)
		RotationType.RANDOM:
			# Random
			var random_rotation_x:float = randf_range(0, TAU)
			var random_rotation_y:float = randf_range(0, TAU)
			var random_rotation_z:float = randf_range(0, TAU)
			prefab.rotation = Vector3(random_rotation_x, random_rotation_y, random_rotation_z)

func unplace(prefab:Node3D, parent:Node)->void:
	parent.remove_child(prefab)
