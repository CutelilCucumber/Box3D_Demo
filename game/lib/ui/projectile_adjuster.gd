extends Control
class_name ProjectileAdjuster

## In-game projectile parameter adjuster. Toggle with 'P' key.
## Reads/writes a ProjectileConfig resource.

var _config: ProjectileConfig = null
var _panel: PanelContainer = null
var _visible_btn: Button = null
var _reset_btn: Button = null
var _controls: Dictionary = {}


func _ready() -> void:
	_build_root_ui()


func _build_root_ui() -> void:
	# Main container
	var main_vb := VBoxContainer.new()
	add_child(main_vb)
	main_vb.anchors_preset = Control.PRESET_FULL_RECT
	main_vb.offset_left = 10
	main_vb.offset_top = 10
	main_vb.offset_right = -10
	main_vb.offset_bottom = -10
	
	# Toggle button row at top-right
	var top_hb := HBoxContainer.new()
	top_hb.horizontal_alignment = HBoxContainer.ALIGNMENT_END
	main_vb.add_child(top_hb)
	
	_visible_btn = Button.new()
	_visible_btn.text = "Projectile Adjuster (P)"
	_visible_btn.toggle_mode = true
	_visible_btn.button_pressed = false
	_visible_btn.toggled.connect(_on_visibility_toggled)
	top_hb.add_child(_visible_btn)
	
	# Panel (hidden by default)
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(380, 0)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0.75)
	bg_style.set_border_width_all(2)
	bg_style.border_color = Color(0.3, 0.3, 0.35, 0.8)
	bg_style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", bg_style)
	main_vb.add_child(_panel)
	
	# Panel content
	var panel_vb := VBoxContainer.new()
	panel_vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_vb.offset_left = 10
	panel_vb.offset_top = 10
	panel_vb.offset_right = -10
	panel_vb.offset_bottom = -10
	_panel.add_child(panel_vb)
	
	# Reset button
	_reset_btn = Button.new()
	_reset_btn.text = "Reset to Defaults"
	_reset_btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reset_btn.pressed.connect(_on_reset_pressed)
	panel_vb.add_child(_reset_btn)
	
	# Scrollable content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_vb.add_child(scroll)
	
	var content_vb := VBoxContainer.new()
	content_vb.add_theme_constant_override("separation", 12)
	scroll.add_child(content_vb)
	_controls["content"] = content_vb


func set_config(config: ProjectileConfig) -> void:
	_config = config
	if _controls.has("content"):
		_build_ui()


func _build_ui() -> void:
	if _config == null or not _controls.has("content"):
		return
	var content: VBoxContainer = _controls["content"]
	
	# Clear existing
	for c in content.get_children():
		c.queue_free()
	_controls.clear()
	_controls["content"] = content
	
	# Light Plasma section
	_add_section(content, "Light Plasma", [
		{"name": "plasma_life", "label": "Life (s)", "min": 0.5, "max": 20.0, "step": 0.1},
		{"name": "plasma_sweep", "label": "Sweep Radius (m)", "min": 0.05, "max": 0.5, "step": 0.01},
		{"name": "plasma_range", "label": "Range (m)", "min": 5.0, "max": 100.0, "step": 1.0},
		{"name": "plasma_fire_interval", "label": "Fire Interval (s)", "min": 0.05, "max": 1.0, "step": 0.01},
	])
	
	# Cannon section
	_add_section(content, "Cannon / Tank Round", [
		{"name": "cannon_damage", "label": "Damage (hp)", "min": 1.0, "max": 50.0, "step": 0.5},
		{"name": "cannon_speed", "label": "Speed (m/s)", "min": 10.0, "max": 80.0, "step": 1.0},
		{"name": "cannon_blast_radius", "label": "Blast Radius (m)", "min": 1.0, "max": 15.0, "step": 0.5},
		{"name": "cannon_blast_impulse", "label": "Blast Impulse", "min": 1.0, "max": 15.0, "step": 0.5},
		{"name": "cannon_fire_interval", "label": "Fire Interval (s)", "min": 0.1, "max": 2.0, "step": 0.05},
		{"name": "cannon_range", "label": "Range (m)", "min": 20.0, "max": 200.0, "step": 5.0},
	])
	
	# Physics Toy section
	_add_section(content, "Physics Toy (Destruction)", [
		{"name": "ball_speed", "label": "Ball Speed (m/s)", "min": 10.0, "max": 80.0, "step": 1.0},
		{"name": "blast_radius", "label": "Blast Radius (m)", "min": 1.0, "max": 20.0, "step": 0.5},
		{"name": "blast_impulse", "label": "Blast Impulse", "min": 1.0, "max": 20.0, "step": 0.5},
	])


func _add_section(parent: VBoxContainer, title: String, fields: Array[Dictionary]) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_constant_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(lbl)
	
	for f in fields:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		parent.add_child(hb)
		
		var l := Label.new()
		l.text = f["label"]
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		l.custom_minimum_size = Vector2(150, 0)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
		hb.add_child(l)
		
		var slider := HSlider.new()
		slider.min_value = f["min"]
		slider.max_value = f["max"]
		slider.step = f["step"]
		slider.value = _config.get(f["name"])
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_slider_changed.bind(f["name"]))
		hb.add_child(slider)
		
		var spin := SpinBox.new()
		spin.min_value = f["min"]
		spin.max_value = f["max"]
		spin.step = f["step"]
		spin.value = _config.get(f["name"])
		spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		spin.custom_minimum_size = Vector2(80, 0)
		spin.value_changed.connect(_on_spin_changed.bind(f["name"], slider))
		hb.add_child(spin)
		
		# Store for potential future use
		_controls[f["name"]] = {"slider": slider, "spin": spin}


func _on_slider_changed(value: float, prop_name: String) -> void:
	if _config == null:
		return
	_config.set(prop_name, value)
	if _controls.has(prop_name):
		var spin: SpinBox = _controls[prop_name]["spin"]
		if spin != null and abs(spin.value - value) > 0.001:
			spin.value = value


func _on_spin_changed(value: float, prop_name: String, slider: HSlider) -> void:
	if _config == null:
		return
	_config.set(prop_name, value)
	if abs(slider.value - value) > 0.001:
		slider.value = value


func _on_visibility_toggled(pressed: bool) -> void:
	if _panel != null:
		_panel.visible = pressed


func _on_reset_pressed() -> void:
	if _config == null:
		return
	_config.reset_to_defaults()
	_build_ui()