extends Control
## Субтитры (мысли героя, радио, голос из динамика) и подсказки взаимодействия.

var _lbl: Label
var _hint: Label
var _queue: Array = []
var _cur_t := 0.0
var _alpha := 0.0
var _hint_text := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl = Label.new()
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl.anchor_left = 0.15
	_lbl.anchor_right = 0.85
	_lbl.anchor_top = 0.6
	_lbl.anchor_bottom = 0.8
	_lbl.add_theme_font_size_override("font_size", 24)
	_lbl.add_theme_color_override("font_color", Color(0.96, 0.95, 0.88))
	_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_lbl.add_theme_constant_override("shadow_offset_x", 2)
	_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_lbl.add_theme_constant_override("outline_size", 6)
	_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	add_child(_lbl)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.3
	_hint.anchor_right = 0.7
	_hint.anchor_top = 0.56
	_hint.anchor_bottom = 0.62
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85, 0.85))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override("outline_size", 5)
	add_child(_hint)


## Показать строку. who — подпись («РАДИО», «ДИНАМИК»), dur — сек (0 = по длине текста)
func say(text: String, dur := 0.0, who := "") -> void:
	var d := dur if dur > 0.0 else clampf(1.6 + text.length() * 0.06, 2.0, 9.0)
	var s := text if who == "" else "%s: %s" % [who, text]
	_queue.append([s, d])
	if _queue.size() == 1:
		_cur_t = 0.0


func clear() -> void:
	_queue.clear()
	_lbl.text = ""


func hint(text: String) -> void:
	_hint_text = text


func _process(dt: float) -> void:
	_hint.text = _hint_text
	if _queue.is_empty():
		_alpha = move_toward(_alpha, 0.0, dt * 3.0)
	else:
		var cur: Array = _queue[0]
		_lbl.text = String(cur[0])
		_cur_t += dt
		_alpha = move_toward(_alpha, 1.0, dt * 4.0)
		if _cur_t >= float(cur[1]):
			_queue.pop_front()
			_cur_t = 0.0
			if not _queue.is_empty():
				_alpha = 0.3
	_lbl.modulate.a = _alpha if Cfg.subtitles else 0.0
