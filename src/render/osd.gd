extends CanvasLayer
## Экранные надписи бытовой видеокамеры. Генератор символов как у камер конца 80-х: точечный шрифт 5×7,
## белые «кирпичики» с чёрной окантовкой (не тень). Работает и на паузе: мигание не замирает, вместо REC — STBY.
##
## Что попадает на плёнку, а что — нет (как у настоящих камер 1990 года):
##  • ДАТА и ВРЕМЯ — функция DATE/TIME камеры впечатывает их в запись: рисуются в прозрачном SubViewport размером
##    с кадр (main.osd_vp), camera.gdshader кладёт их поверх картинки, и дальше они идут на «плёнку» вместе с
##    кадром (размытие цвета, шум, дрожание строк, срывы трекинга). Так же — подписи камеры наблюдения (CAM 04).
##  • REC / STBY, батарея, SP, «BATTERY LOW» — только в видоискателе, на кассету они не пишутся. Рисуются отдельным
##    слоем поверх уже записанной картинки (vf, его ставит main.gd): чуть прозрачнее, без плёночных искажений —
##    так и видно, что это видоискатель, а не запись. Затемнение «на плёнке» (fade_col) гасит и их.

var shown := false
var rec := true
var clock := 16.0 * 3600.0 + 12.0 * 60.0   # 4:12 PM
var date_key := "osd.date_park"
var date_reset := false      # после падения часы камеры сбились — мигает 12:00 и JAN. 1 1980
var battery := 1.0
var message := ""            # крупная надпись по центру (NO SIGNAL, BATTERY LOW…)
var message_blink := true
var cam_label := ""          # режим камеры наблюдения Async: «CAM 04»
var _t := 0.0
var _c: Control              # запись (в main.osd_vp, кадр в пикселях кадра)
var vf: Control              # видоискатель (экран, поверх плёнки; родителя ставит main.gd)
var _cv: Control             # куда рисуем сейчас
var font: Font               # запасной шрифт для символов, которых нет в генераторе

const INK := Color(0.96, 0.96, 0.93)
const EDGE := Color(0.02, 0.02, 0.025)
const RED := Color(0.92, 0.1, 0.06)
const VF_ALPHA := 0.82       # надписи видоискателя чуть прозрачнее впечатанных в запись

## Точечный шрифт 5×7: строки сверху вниз, «1» — точка горит
const GLYPH_SRC := {
	"0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
	"2": "01110 10001 00001 00010 00100 01000 11111", "3": "11111 00010 00100 00010 00001 10001 01110",
	"4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
	"6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
	"8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
	"A": "01110 10001 10001 10001 11111 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
	"C": "01110 10001 10000 10000 10000 10001 01110", "D": "11100 10010 10001 10001 10001 10010 11100",
	"E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
	"G": "01110 10001 10000 10111 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
	"I": "01110 00100 00100 00100 00100 00100 01110", "J": "00111 00010 00010 00010 00010 10010 01100",
	"K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
	"M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 10001 11001 10101 10011 10001 10001",
	"O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
	"Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
	"S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
	"U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
	"W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
	"Y": "10001 10001 10001 01010 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
	".": "00000 00000 00000 00000 00000 01100 01100", ",": "00000 00000 00000 00000 01100 00100 01000",
	":": "00000 01100 01100 00000 01100 01100 00000", "-": "00000 00000 00000 11111 00000 00000 00000",
	"/": "00000 00001 00010 00100 01000 10000 00000", "!": "00100 00100 00100 00100 00100 00000 00100",
	"?": "01110 10001 00001 00010 00100 00000 00100", "'": "01100 00100 01000 00000 00000 00000 00000",
	"(": "00010 00100 01000 01000 01000 00100 00010", ")": "01000 00100 00010 00010 00010 00100 01000",
	"+": "00000 00100 00100 11111 00100 00100 00000", "▶": "01000 01100 01110 01111 01110 01100 01000",
	"Б": "11111 10000 10000 11110 10001 10001 11110", "Г": "11111 10000 10000 10000 10000 10000 10000",
	"Д": "00110 01010 01010 01010 01010 11111 10001", "Ж": "10101 10101 10101 01110 10101 10101 10101",
	"З": "01110 10001 00001 00110 00001 10001 01110", "И": "10001 10001 10011 10101 11001 10001 10001",
	"Й": "01010 00100 10001 10011 10101 11001 10001", "Л": "00111 01001 01001 01001 01001 01001 10001",
	"П": "11111 10001 10001 10001 10001 10001 10001", "У": "10001 10001 10001 01111 00001 10001 01110",
	"Ф": "00100 01110 10101 10101 10101 01110 00100", "Ц": "10010 10010 10010 10010 10010 11111 00001",
	"Ч": "10001 10001 10001 01111 00001 00001 00001", "Ш": "10101 10101 10101 10101 10101 10101 11111",
	"Щ": "10101 10101 10101 10101 10101 11111 00001", "Ъ": "11000 01000 01000 01110 01001 01001 01110",
	"Ы": "10001 10001 10001 11101 10011 10011 11101", "Ь": "10000 10000 10000 11110 10001 10001 11110",
	"Э": "01110 10001 00001 00111 00001 10001 01110", "Ю": "10010 10101 10101 11101 10101 10101 10010",
	"Я": "01111 10001 10001 01111 00101 01001 10001",
}
## Кириллица, совпадающая с латиницей по начертанию
const ALIAS := {"А": "A", "В": "B", "Е": "E", "Ё": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P",
	"С": "C", "Т": "T", "Х": "X"}

var _glyphs := {}            # символ → массив из 7 строк (биты, старший — левая точка)
var _u := 3                  # размер точки, пикс кадра
var _e := 2                  # толщина окантовки, пикс


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	for ch in GLYPH_SRC.keys():
		var rows: Array = []
		for r in String(GLYPH_SRC[ch]).split(" "):
			rows.append(String(r).bin_to_int())
		_glyphs[ch] = rows
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
	vf = Control.new()
	vf.name = "Viewfinder"
	vf.set_anchors_preset(Control.PRESET_FULL_RECT)
	vf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vf.process_mode = Node.PROCESS_MODE_ALWAYS
	vf.draw.connect(_draw_vf)


func _process(dt: float) -> void:
	_t += dt
	if not get_tree().paused:
		clock += dt
	_c.queue_redraw()
	if vf.is_inside_tree():
		# затемнение «на плёнке» гасит и надписи видоискателя (переходы, смерть)
		var fa := 0.0
		if Game.main != null:
			fa = Game.main.fade_col.a
		vf.modulate.a = VF_ALPHA * (1.0 - fa)
		vf.queue_redraw()


func _exit_tree() -> void:
	if is_instance_valid(vf) and not vf.is_inside_tree():
		vf.free()


func _glyph(ch: String) -> Variant:
	var c := String(ALIAS.get(ch, ch))
	return _glyphs.get(c, null)


## Ширина строки в пикселях кадра (ячейка 6 точек: 5 + промежуток)
func text_w(s: String) -> float:
	return maxf(0.0, s.length() * 6.0 - 1.0) * _u


## Строка генератором символов: сначала чёрная окантовка, потом белые точки (горизонтальные отрезки — одним прямоугольником)
func _txt(pos: Vector2, s: String, col := INK) -> void:
	var up := s.to_upper()
	var origin := Vector2(round(pos.x), round(pos.y))
	for pass_i in 2:
		var x := origin.x
		for i in up.length():
			var ch := up.substr(i, 1)
			var g: Variant = _glyph(ch)
			if g == null:
				if ch != " " and pass_i == 1:
					# символа нет в генераторе — системным шрифтом с окантовкой
					var fs := _u * 8
					var bp := Vector2(x, origin.y + _u * 7)
					_cv.draw_string_outline(font, bp, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _e * 2, EDGE)
					_cv.draw_string(font, bp, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			else:
				var rows: Array = g
				for r in 7:
					var bits: int = rows[r]
					var c0 := -1
					for cx in 6:
						var on := cx < 5 and (bits >> (4 - cx)) & 1 == 1
						if on and c0 < 0:
							c0 = cx
						elif not on and c0 >= 0:
							var rx := x + c0 * _u
							var ry := origin.y + r * _u
							var rw := (cx - c0) * _u
							if pass_i == 0:
								_cv.draw_rect(Rect2(rx - _e, ry - _e, rw + _e * 2, _u + _e * 2), EDGE)
							else:
								_cv.draw_rect(Rect2(rx, ry, rw, _u), col)
							c0 = -1
			x += 6 * _u


func _txt_r(pos: Vector2, s: String, col := INK) -> void:
	_txt(pos - Vector2(text_w(s), 0), s, col)


## Прямоугольная рамка из «точек» с окантовкой (батарея)
func _box(r: Rect2, th: float) -> void:
	for pass_i in 2:
		var g := float(_e) if pass_i == 0 else 0.0
		var cc := EDGE if pass_i == 0 else INK
		_cv.draw_rect(Rect2(r.position.x - g, r.position.y - g, r.size.x + g * 2, th + g * 2), cc)
		_cv.draw_rect(Rect2(r.position.x - g, r.end.y - th - g, r.size.x + g * 2, th + g * 2), cc)
		_cv.draw_rect(Rect2(r.position.x - g, r.position.y - g, th + g * 2, r.size.y + g * 2), cc)
		_cv.draw_rect(Rect2(r.end.x - th - g, r.position.y - g, th + g * 2, r.size.y + g * 2), cc)


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


## Размер точки и поля кадра — от высоты кадра в пикселях кадра (480/600/720 строк)
func _metrics(sz: Vector2) -> void:
	_u = maxi(2, int(round(sz.y / 170.0)))
	_e = maxi(1, int(round(_u * 0.5)))


## Впечатано в запись: дата и время (и подписи камеры наблюдения)
func _draw_osd() -> void:
	if not shown or not Cfg.osd:
		return
	_cv = _c
	var sz := _c.size
	_metrics(sz)
	var u := float(_u)
	var lh := 7.0 * u                       # высота строки
	var m := Vector2(round(sz.y * 0.075), round(sz.y * 0.07))
	var bottom := sz.y - m.y - lh
	if cam_label != "":
		_txt(m, cam_label)
		_txt_r(Vector2(sz.x - m.x, m.y), "ASYNC")
		_txt_r(Vector2(sz.x - m.x, bottom), Loc.t(date_key) + "  " + time_text())
		return
	# часы камеры сбились при падении: 12:00 AM и JAN. 1 1980 мигают
	var blink_off := date_reset and fmod(_t, 1.0) > 0.55
	if not blink_off:
		_txt_r(Vector2(sz.x - m.x, bottom - lh - 3.0 * u), time_text())
		_txt_r(Vector2(sz.x - m.x, bottom), Loc.t("osd.date_reset") if date_reset else Loc.t(date_key))


## Только в видоискателе (на кассету не пишется): REC / STBY, батарея, SP, крупное сообщение.
## Рисуется в тех же «пикселях кадра», что и запись (тот же размер точек и поля), растянутых на кадр на экране.
func _draw_vf() -> void:
	if not shown or not Cfg.osd or cam_label != "":
		return
	var fs := Vector2(Cfg.frame_size())
	var fr := Cfg.frame_rect(vf.get_viewport_rect())
	if fs.y < 1.0 or fr.size.y < 1.0:
		return
	var sc := fr.size.y / fs.y
	vf.draw_set_transform(fr.position, 0.0, Vector2(sc, sc))
	_cv = vf
	var sz := fs
	_metrics(sz)
	var u := float(_u)
	var lh := 7.0 * u                       # высота строки
	var m := Vector2(round(sz.y * 0.075), round(sz.y * 0.07))
	var bottom := sz.y - m.y - lh
	var paused := get_tree().paused
	# запись / пауза записи (на паузе игры камера в «STBY») / воспроизведение
	if paused:
		_txt(m, "STBY")
	elif rec:
		if fmod(_t, 1.0) < 0.6:
			var cc := m + Vector2(3.5 * u, 3.5 * u)
			vf.draw_circle(cc, 3.0 * u + _e, EDGE)
			vf.draw_circle(cc, 3.0 * u, RED)
		_txt(m + Vector2(9.0 * u, 0), "REC")
	else:
		_txt(m, "PLAY ▶")
	# батарея: рамка, контакт, деления заряда
	var bw := 12.0 * u
	var bh := lh
	var bx := sz.x - m.x - bw - 2.0 * u
	var by := m.y
	var low := battery < 0.2
	if not low or fmod(_t, 0.8) < 0.5:
		_box(Rect2(bx, by, bw, bh), u)
		var nub := Rect2(bx + bw, by + bh * 0.3, 2.0 * u, bh * 0.4)
		vf.draw_rect(nub.grow(_e), EDGE)
		vf.draw_rect(nub, INK)
		var segs := int(ceil(battery * 4.0))
		var sw := (bw - 4.0 * u) / 4.0
		for i in segs:
			var r := Rect2(bx + 2.0 * u + i * sw, by + 2.0 * u, sw - u, bh - 4.0 * u)
			vf.draw_rect(r.grow(_e), EDGE)
		for i in segs:
			vf.draw_rect(Rect2(bx + 2.0 * u + i * sw, by + 2.0 * u, sw - u, bh - 4.0 * u), INK)
	_txt(Vector2(m.x, bottom), "SP")
	if message != "" and (not message_blink or fmod(_t, 1.0) < 0.65):
		_txt(Vector2((sz.x - text_w(message)) * 0.5, (sz.y - lh) * 0.5), message)
