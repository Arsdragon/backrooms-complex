extends Control
## Карточка концовки: чёрный экран, заголовок, текст «из архива».

signal closed

var _can_close := false
var _title: Label
var _body: Label
var _press: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	f.font_weight = 700
	var f2 := SystemFont.new()
	f2.font_names = PackedStringArray(["Courier New", "Consolas", "monospace"])
	_title = Label.new()
	_title.add_theme_font_override("font", f)
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.7))
	_title.anchor_left = 0.12
	_title.anchor_right = 0.88
	_title.anchor_top = 0.16
	_title.anchor_bottom = 0.26
	add_child(_title)
	_body = Label.new()
	_body.add_theme_font_override("font", f2)
	_body.add_theme_font_size_override("font_size", 24)
	_body.add_theme_color_override("font_color", Color(0.88, 0.88, 0.84))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.anchor_left = 0.12
	_body.anchor_right = 0.88
	_body.anchor_top = 0.3
	_body.anchor_bottom = 0.85
	_body.visible_ratio = 0.0
	add_child(_body)
	_press = Label.new()
	_press.add_theme_font_override("font", f)
	_press.add_theme_font_size_override("font_size", 18)
	_press.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	_press.anchor_left = 0.12
	_press.anchor_right = 0.88
	_press.anchor_top = 0.9
	_press.anchor_bottom = 0.95
	_press.modulate.a = 0.0
	add_child(_press)


func open(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_press.text = Loc.t("ui.press")
	Snd.play("card_hum", -10.0)
	var tw := create_tween()
	tw.tween_property(_body, "visible_ratio", 1.0, maxf(2.5, body.length() * 0.028))
	tw.tween_property(_press, "modulate:a", 1.0, 0.8)
	tw.tween_callback(func() -> void: _can_close = true)


func _input(e: InputEvent) -> void:
	if not _can_close:
		return
	if (e is InputEventKey and e.is_pressed()) or (e is InputEventMouseButton and e.is_pressed()):
		_can_close = false
		get_viewport().set_input_as_handled()
		closed.emit()
