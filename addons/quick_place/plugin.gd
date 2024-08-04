@tool
extends EditorPlugin

var dock

var setting_scene: PackedScene
var setting_rotation: int
var setting_active: bool

var start_stop_button: Button

func _enter_tree():
	dock = create_settings_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock)

func _exit_tree():
	remove_control_from_docks(dock)
	dock.free()
	
func _handles(object):
	return object is Node3D

func _forward_3d_gui_input(viewport_camera, event):
	if setting_active and setting_scene != null:
		if event is InputEventMouseButton:
			if(event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
				# Mouse Position in Viewport to World Raycast
				var position_in_node = event.position
				var ray_space_state = viewport_camera.get_world_3d().direct_space_state
				var ray_origin = viewport_camera.project_ray_origin(position_in_node)
				var ray_end = ray_origin + viewport_camera.project_ray_normal(position_in_node) * 5000.0
				var ray_query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
				ray_query.collide_with_areas = false
				var ray_result = ray_space_state.intersect_ray(ray_query)
				
				# Instantiate
				if ray_result.has("position"):
					var selections = get_editor_interface().get_selection().get_selected_nodes()
					var scene = viewport_camera.get_tree().get_edited_scene_root()
					var new_scene : Node3D = setting_scene.instantiate()
					new_scene.name = str(new_scene.name, " #", selections[0].get_child_count())
					selections[0].add_child(new_scene)
					new_scene.global_position = ray_result.position
					new_scene.set_owner(scene)
					
					if (setting_rotation == 2 or setting_rotation == 3) and ray_result.normal != null:
						# Align To Face
						new_scene.global_transform.basis = align_up(new_scene.global_transform.basis, ray_result.normal.normalized())
						
						# Random Aligned To Face
						if(setting_rotation == 3):
							var random_rotation = randf_range(0.0, 360.0)
							new_scene.global_transform = new_scene.global_transform.rotated_local(Vector3.UP, random_rotation)
							pass
					if (setting_rotation == 1):
						# Rotate Random
						var random_rotation_x = randf_range(0, TAU)
						var random_rotation_y = randf_range(0, TAU)
						var random_rotation_z = randf_range(0, TAU)
						new_scene.rotation = Vector3(random_rotation_x, random_rotation_y, random_rotation_z)
					
					return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func create_settings_dock():
	var root = PanelContainer.new()
	root.name = "QuickPlace Settings"
	
	var settings_list = VBoxContainer.new()
	settings_list.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(settings_list)
	
	# SCENE
	var scene_picker = EditorResourcePicker.new()
	scene_picker.base_type = "PackedScene"
	var settings_item_scene = create_settings_item("Scene", scene_picker)
	settings_list.add_child(settings_item_scene)
	scene_picker.connect("resource_changed", _on_scene_changed)
	
	# ROTATION
	var rotation_select = OptionButton.new()
	rotation_select.add_item("Original", 0)
	rotation_select.add_item("Random", 1)
	rotation_select.add_item("Aligned to Face", 2)
	rotation_select.add_item("Random Aligned to Face", 3)
	rotation_select.connect("item_selected", _on_rotation_select_item_selected)
	var settings_item_rotation_select = create_settings_item("Rotation", rotation_select)
	settings_list.add_child(settings_item_rotation_select)
	
	# START/STOP BUTTON
	start_stop_button = Button.new()
	start_stop_button.disabled = true
	start_stop_button.text = "Start/Stop"
	start_stop_button.toggle_mode = true
	settings_list.add_child(start_stop_button)
	start_stop_button.connect("toggled", _on_active_toggled)
	
	return root

func create_settings_item(label, control):
	var new_item_panel = PanelContainer.new()
	
	var new_item = HBoxContainer.new()
	new_item.set_anchors_preset(Control.PRESET_VCENTER_WIDE)
	new_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_item_panel.add_child(new_item)
	
	var new_label = Label.new()
	new_label.text = label
	new_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_item.add_child(new_label)
	
	control.set_anchors_preset(Control.PRESET_VCENTER_WIDE)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_item.add_child(control)
	
	return new_item_panel

func _on_scene_changed(new_resource: PackedScene) -> void:
	setting_scene = new_resource
	start_stop_button.disabled = new_resource == null

func _on_rotation_select_item_selected(index: int) -> void:
	setting_rotation = index
	
func _on_active_toggled(is_active: bool) -> void:
	setting_active = is_active
	
# https://www.reddit.com/r/godot/comments/f2fowu/comment/fhdkxz5/
# Adjusted to support 90deg side angles
func align_up(node_basis, normal):
	var result = Basis()
	var scale = node_basis.get_scale()

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
