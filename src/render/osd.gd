extends CanvasLayer
## Экранные надписи бытовой видеокамеры (рисуются внутри 3D-кадра, поэтому тоже «плывут» на плёнке).

var shown := false
var rec := true
var clock := 16.0 * 3600.0 + 12.0 * 60.0   # 4:12 PM
var date_key := "osd.date_park"
var date_reset := false      # после падения часы камеры сбились — мигает 12:00
var battery := 1.0
var message := ""            # крупная надпись по центру (NO SIGNAL, BATTERY LOW…)
var message_blink := true
var cam_label := ""          # режим камеры наблюдения Async: «CAM 04»
var _t := 0.0
var _c: Control
var font: Font


func _ready() -> void:
	layer = 5
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	sf.hinting = TextServer.HINTING_NORMAL
	sf.font_weight = 700
	font = sf
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw_osd)
	add_child(_c)


func _process(dt: float) -> void:
	_t += dt
	if not get_tree().paused:
		clock += dt
	_c.queue_redraw()


func _txt(pos: Vector2, s: String, size: int, col := Color(0.95, 0.95, 0.92)) -> void:
	_c.draw_string(font, pos + Vector2(2, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
	_c.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _txt_r(pos: Vector2, s: String, size: int, col := Color(0.95, 0.95, 0.92)) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_txt(pos - Vector2(w, 0), s, size, col)


func time_text() -> String:
	if date_reset:
		return "12:00 AM"
	var s := int(clock) % 86400
	var h := s / 3600
	var m := (s / 60) % 60
	var sec := s % 60
	var ap := "PM" if h >= 12 else "AM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d:%02d %s" % [h12, m, sec, ap]


func _draw_osd() -> void:
	if not shown or not Cfg.osd:
		return
	var sz := _c.size
	var fs := int(round(sz.y / 22.0))
	var m := Vector2(sz.y * 0.07, sz.y * 0.09)
	if cam_label != "":
		_txt(m, cam_label, fs)
		_txt_r(Vector2(sz.x - m.x, m.y), "ASYNC", fs)
		_txt_r(Vector2(sz.x - m.x, sz.y - m.y * 0.6), Loc.t(date_key) + "  " + time_text(), fs)
		return
	if rec:
		if fmod(_t, 1.0) < 0.6:
			_c.draw_circle(m + Vector2(fs * 0.35, -fs * 0.33), fs * 0.32, Color(0.9, 0.08, 0.05))
		_txt(m + Vector2(fs * 0.9, 0), "REC", fs)
	else:
		_txt(m, "PLAY ▶", fs)
	# батарея
	var bx := sz.x - m.x - fs * 2.2
	var by := m.y - fs * 0.75
	var bw := fs * 1.9
	var bh := fs * 0.8
	var low := battery < 0.2
	if not low or fmod(_t, 0.8) < 0.5:
		_c.draw_rect(Rect2(bx + 2, by + 2, bw, bh), Color(0, 0, 0, 0.7), false, 2.0)
		_c.draw_rect(Rect2(bx, by, bw, bh), Color(0.95, 0.95, 0.92), false, 2.0)
		_c.draw_rect(Rect2(bx + bw, by + bh * 0.3, fs * 0.15, bh * 0.4), Color(0.95, 0.95, 0.92))
		var segs := int(ceil(battery * 4.0))
		for i in segs:
			_c.draw_rect(Rect2(bx + 3 + i * (bw - 6) / 4.0, by + 3, (bw - 6) / 4.0 - 2, bh - 6), Color(0.95, 0.95, 0.92))
	_txt(Vector2(m.x, sz.y - m.y * 0.6), "SP", fs)
	var blink_off := date_reset and fmod(_t, 1.0) > 0.55
	if not blink_off:
		_txt_r(Vector2(sz.x - m.x, sz.y - m.y * 0.6 - fs * 1.15), time_text(), fs)
		_txt_r(Vector2(sz.x - m.x, sz.y - m.y * 0.6), Loc.t("osd.date_reset") if date_reset else Loc.t(date_key), fs)
	if message != "" and (not message_blink or fmod(_t, 1.0) < 0.65):
		var w := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_txt(Vector2((sz.x - w) * 0.5, sz.y * 0.5), message, fs)
