extends Control
## Главное меню, пауза, настройки, заставка. Стиль — экранное меню видеомагнитофона: белые «блочные» заглавные
## буквы с чёрной окантовкой (как у надписей камеры), выбранный пункт — сплошная светлая полоса с тёмным текстом,
## значения — в < > и [X]. Всё живёт внутри кадра (frame): при 4:3 меню не уезжает в чёрные поля по бокам;
## раскладка пересчитывается при смене окна, формата и разрешения. Внутри frame — «проектные» пиксели
## при высоте кадра 720 (ширина 960 для 4:3 и 1280 для 16:9).

const DESIGN_H := 720.0
const TXT := Color(0.95, 0.95, 0.92)
const TXT_DIM := Color(0.82, 0.82, 0.78)
const HEAD := Color(0.97, 0.92, 0.62)
const BAR := Color(0.93, 0.93, 0.88)
const BAR_TXT := Color(0.05, 0.05, 0.06)
const EDGE := Color(0, 0, 0, 0.92)

var font: SystemFont
var font_b: SystemFont
var frame: Control             # область кадра на экране
var main_box: VBoxContainer
var pause_box: VBoxContainer
var settings_box: VBoxContainer
var title_box: VBoxContainer
var intro: Label
var controls: Label
var credit: Label
var _settings_from := "main"
var _rows := []
var world_box: Control
var world_desc: Label
var poly_box: Control
var rooms_box: Control
var poly_state := {"god": true, "nomon": false, "lfnow": false, "chase": false, "fast": false, "stamina": false}
var _dim: ColorRect
var _world_title: Label
var _world_col: VBoxContainer
var _poly_title: Label
var _poly_hint: Label
var _poly_flow: HFlowContainer
var _poly_first: Button
var _poly_back: Button
var _poly_font := 0
var _rooms_title: Label
var _rooms_row: HBoxContainer
var _rooms_cols: Array = []
var _room_btns: Array = []
var _rooms_key := ""
var _rooms_back: Button

const WORLD_KEYS := {"base": "ui.w_base", "adventure": "ui.w_adv", "survival": "ui.w_surv", "polygon": "ui.w_poly"}
## Странные комнаты: список занимает высоту от заголовка до «Назад»
const ROOMS_TOP := 96.0
const ROOMS_BOTTOM := 630.0
const ROOMS_GAP := 22.0         # между колонками
const ROOMS_MAX_COLS := 8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	font_b = SystemFont.new()
	font_b.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	font_b.font_weight = 700
	_build()
	Cfg.changed.connect(_relabel)
	Cfg.changed.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout()
	hide_all()


## Подпись пункта меню: заглавными, с полями для полосы выделения
func _cap(key: String) -> String:
	return " " + Loc.t(key).to_upper() + " "


func _lbl(text: String, size: int, col := TXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_b if bold else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	# окантовка, как у символов видеомагнитофона (не тень)
	l.add_theme_color_override("font_outline_color", EDGE)
	l.add_theme_constant_override("outline_size", clampi(size / 5, 4, 10))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Кнопка в стиле экранного меню VCR: обычная — белый текст с окантовкой, выбранная — сплошная полоса
func _vcr_style(b: Button, size: int) -> void:
	b.flat = false
	b.add_theme_font_override("font", font_b)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TXT)
	b.add_theme_color_override("font_disabled_color", TXT_DIM)
	for c in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, BAR_TXT)
	b.add_theme_color_override("font_outline_color", EDGE)
	var ol := clampi(size / 5, 3, 8)
	b.add_theme_constant_override("outline_size", ol)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 4
	empty.content_margin_right = 4
	empty.content_margin_top = 1
	empty.content_margin_bottom = 1
	var bar := StyleBoxFlat.new()
	bar.bg_color = BAR
	bar.content_margin_left = 4
	bar.content_margin_right = 4
	bar.content_margin_top = 1
	bar.content_margin_bottom = 1
	for s in ["normal", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	for s in ["hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(s, bar)
	# на светлой полосе окантовка не нужна — тёмный текст
	b.focus_entered.connect(func() -> void: b.add_theme_constant_override("outline_size", 0))
	b.focus_exited.connect(func() -> void: b.add_theme_constant_override("outline_size", ol))
	b.mouse_entered.connect(func() -> void: b.grab_focus())


func _btn(key: String, cb: Callable, size := 28) -> Button:
	var b := Button.new()
	b.set_meta("key", key)
	b.text = _cap(key)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_vcr_style(b, size)
	b.pressed.connect(func() -> void:
		Snd.play("ui_click", -6.0)
		cb.call())
	b.focus_entered.connect(func() -> void: Snd.play("ui_move", -14.0))
	return b


## Затемнение под меню: не ровная чёрная вуаль (выбитые лампы становились тусклыми серыми плитами), а кривая —
## тени и полутона темнеют на долю color.a, а выбитое (лампы, их ореол) почти не трогается: светильники
## по-прежнему горят за притемнённым кадром. Сила — в _dim.color.a, как раньше.
const DIM_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
void fragment() {
	vec3 s = texture(screen_tex, SCREEN_UV).rgb;
	float y = dot(s, vec3(0.299, 0.587, 0.114));
	float keep = smoothstep(0.62, 0.97, y);
	float a = COLOR.a;
	// светлое сохраняется тем меньше, чем гуще затемнение (на экране настроек текст важнее ламп)
	float k = mix(1.0 - a, 1.0, keep * keep * (1.0 - 0.35 * a));
	COLOR = vec4(s * k, 1.0);
}
"""


func _build() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsh := Shader.new()
	dsh.code = DIM_SHADER
	var dm := ShaderMaterial.new()
	dm.shader = dsh
	_dim.material = dm
	add_child(_dim)
	frame = Control.new()
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	frame.add_child(title_box)
	var t1 := _lbl(Loc.t("ui.title"), 86, HEAD, true)
	t1.set_meta("key", "ui.title")
	title_box.add_child(t1)
	var t2 := _lbl(Loc.t("ui.subtitle"), 30, Color(0.9, 0.87, 0.68), true)
	t2.set_meta("key", "ui.subtitle")
	t2.uppercase = true
	title_box.add_child(t2)
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 4)
	main_box.custom_minimum_size = Vector2(330, 0)
	frame.add_child(main_box)
	main_box.add_child(_btn("ui.play", func() -> void: show_worlds()))
	main_box.add_child(_btn("ui.settings", func() -> void: show_settings("main")))
	main_box.add_child(_btn("ui.quit", func() -> void: get_tree().quit()))
	pause_box = VBoxContainer.new()
	pause_box.add_theme_constant_override("separation", 4)
	pause_box.custom_minimum_size = Vector2(330, 0)
	frame.add_child(pause_box)
	var pt := _lbl(Loc.t("ui.pause"), 44, HEAD, true)
	pt.set_meta("key", "ui.pause")
	pt.uppercase = true
	pause_box.add_child(pt)
	pause_box.add_child(_btn("ui.resume", func() -> void: Game.set_paused(false)))
	pause_box.add_child(_btn("ui.settings", func() -> void: show_settings("pause")))
	pause_box.add_child(_btn("ui.to_menu", func() -> void:
		Game.set_paused(false)
		Game.go_menu()))
	_build_settings()
	_build_worlds()
	_build_polygon()
	_build_rooms()
	intro = _lbl("", 34, TXT, true)
	intro.uppercase = true
	intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(intro)
	controls = _lbl(Loc.t("ui.controls"), 17, Color(0.9, 0.9, 0.85, 0.9))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frame.add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_left = 24
	controls.offset_right = -24
	controls.offset_top = -64
	controls.offset_bottom = -16
	controls.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	credit = _lbl("Fan game based on the Backrooms universe of Kane Parsons (Kane Pixels). Not affiliated.", 12, Color(0.75, 0.75, 0.7, 0.7))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.add_theme_constant_override("outline_size", 3)
	frame.add_child(credit)
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	credit.offset_top = -30
	credit.offset_bottom = -10
	credit.offset_right = -18


## Раскладка внутри кадра: при 4:3 (ширина 960) колонки уже, полигон и странные комнаты переносятся в строки
func _layout() -> void:
	if frame == null:
		return
	var fr := Cfg.frame_rect(get_viewport_rect())
	var s := fr.size.y / DESIGN_H
	frame.position = fr.position
	frame.scale = Vector2(s, s)
	frame.size = Vector2(fr.size.x / s, DESIGN_H)
	var dw := frame.size.x
	var wide := dw > 1100.0
	var mx := 84.0 if wide else 56.0
	title_box.position = Vector2(mx, 96)
	main_box.position = Vector2(mx - 6, 372)
	pause_box.position = Vector2(mx - 6, 210)
	settings_box.position = Vector2(mx - 6, 40)
	# колонка подписей настроек: при 4:3 уже, чтобы длинные значения («Смешанный (…)») не выходили за кадр
	for row in settings_box.get_children():
		if row is HBoxContainer:
			((row as HBoxContainer).get_child(0) as Control).custom_minimum_size.x = 430.0 if wide else 300.0
	_world_title.position = Vector2(mx, 112)
	_world_col.position = Vector2(mx - 6, 196)
	world_desc.position = Vector2(dw * (0.43 if wide else 0.46), 206)
	world_desc.size = Vector2(dw - world_desc.position.x - mx, 380)
	_poly_title.position = Vector2(mx, 22)
	_poly_hint.position = Vector2(mx, 76)
	_poly_hint.size = Vector2(dw - mx * 2.0, 40)
	_set_poly_font(20 if wide else 17)
	_poly_flow.position = Vector2(mx - 6, 124 if wide else 132)
	_poly_flow.size = Vector2(dw - mx * 2.0 + 12, 500)
	_poly_back.position = Vector2(mx - 6, 646)
	_rooms_title.position = Vector2(mx, 26)
	_rooms_row.position = Vector2(mx - 6, ROOMS_TOP)
	_reflow_rooms(dw - mx * 2.0 + 12.0)
	_rooms_back.position = Vector2(mx - 6, 646)


# ------------------------------------------------------------ выбор мира

func _build_worlds() -> void:
	world_box = Control.new()
	world_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(world_box)
	_world_title = _lbl(Loc.t("ui.world"), 44, HEAD, true)
	_world_title.set_meta("key", "ui.world")
	_world_title.uppercase = true
	world_box.add_child(_world_title)
	_world_col = VBoxContainer.new()
	_world_col.add_theme_constant_override("separation", 6)
	_world_col.custom_minimum_size = Vector2(330, 0)
	world_box.add_child(_world_col)
	world_desc = _lbl("", 22, TXT_DIM)
	world_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_box.add_child(world_desc)
	for w in Cfg.WORLDS:
		var wk: String = w
		var b := _btn(WORLD_KEYS[wk], func() -> void: _pick_world(wk))
		b.set_meta("world", wk)
		b.focus_entered.connect(func() -> void: world_desc.text = Loc.t(String(WORLD_KEYS[wk]) + "_d"))
		_world_col.add_child(b)
	var back := _btn("ui.back", func() -> void: show_main())
	_world_col.add_child(back)


func _pick_world(w: String) -> void:
	Cfg.world = w
	Cfg.save_cfg()
	if w == "polygon":
		Game.mode = "polygon"
		show_polygon()
	else:
		Game.new_game(w)


func show_worlds() -> void:
	hide_all()
	visible = true
	world_box.visible = true
	credit.visible = true
	_dim.visible = true
	_dim.color = Color(0, 0, 0, 0.6)
	_relabel()
	for b in _world_col.get_children():
		if b.has_meta("world") and String(b.get_meta("world")) == Cfg.world:
			(b as Button).grab_focus()
	world_desc.text = Loc.t(String(WORLD_KEYS[Cfg.world]) + "_d")


# ------------------------------------------------------------ полигон

func _poly_col(parent: Control, head: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	parent.add_child(v)
	var h := _lbl(Loc.t(head), 22, HEAD, true)
	h.set_meta("key", head)
	h.uppercase = true
	v.add_child(h)
	return v


func _pbtn(v: VBoxContainer, key: String, cb: Callable) -> void:
	v.add_child(_btn(key, cb, 20))


func _ptoggle(v: VBoxContainer, key: String, id: String) -> void:
	var b := _vbtn("")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20)
	var upd := func() -> void:
		b.text = " [" + ("X" if bool(poly_state[id]) else " ") + "] " + Loc.t(key).to_upper() + " "
	b.pressed.connect(func() -> void:
		poly_state[id] = not bool(poly_state[id])
		Snd.play("ui_click", -6.0)
		upd.call())
	b.focus_entered.connect(func() -> void: Snd.play("ui_move", -14.0))
	_rows.append(upd)
	upd.call()
	v.add_child(b)


func _build_polygon() -> void:
	poly_box = Control.new()
	poly_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(poly_box)
	_poly_title = _lbl(Loc.t("poly.title"), 40, HEAD, true)
	_poly_title.set_meta("key", "poly.title")
	_poly_title.uppercase = true
	poly_box.add_child(_poly_title)
	_poly_hint = _lbl(Loc.t("poly.hint"), 16, Color(0.82, 0.86, 0.86))
	_poly_hint.set_meta("key", "poly.hint")
	_poly_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	poly_box.add_child(_poly_hint)
	_poly_flow = HFlowContainer.new()
	_poly_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poly_flow.add_theme_constant_override("h_separation", 26)
	_poly_flow.add_theme_constant_override("v_separation", 14)
	poly_box.add_child(_poly_flow)
	var c1 := _poly_col(_poly_flow, "poly.c_start")
	_pbtn(c1, "poly.park", func() -> void: Game.poly_park())
	_pbtn(c1, "poly.l0", func() -> void: Game.poly_complex(false))
	_pbtn(c1, "poly.l1", func() -> void: Game.poly_complex(true))
	_pbtn(c1, "poly.outpost", func() -> void: Game.poly_complex(false, "outpost", {"dz": "3.6"}))
	_pbtn(c1, "poly.camp", func() -> void: Game.poly_complex(false, "camp"))
	_pbtn(c1, "poly.null", func() -> void: Game.poly_complex(false, "null_0", {"dz": "2.2"}))
	_pbtn(c1, "poly.pit", func() -> void: Game.poly_complex(false, "pits"))
	_pbtn(c1, "poly.stretch", func() -> void: Game.poly_complex(false, "stretch"))
	_pbtn(c1, "poly.house", func() -> void: Game.poly_complex(true, "house"))
	_pbtn(c1, "poly.rooms", func() -> void: show_rooms())
	_poly_first = c1.get_child(1) as Button
	var c2 := _poly_col(_poly_flow, "poly.c_ends")
	for k in ["ocean", "sky", "highway", "wall", "space", "async"]:
		var kk: String = k
		_pbtn(c2, "poly.e_" + kk, func() -> void: Game.poly_ending(kk))
	_pbtn(c2, "poly.e_death", func() -> void: Game.poly_death())
	var c3 := _poly_col(_poly_flow, "poly.c_beings")
	for g in ["copies", "copies2", "anim", "lifeform", "finds", "objects", "async", "tv", "models"]:
		var gg: String = g
		_pbtn(c3, "poly.g_" + gg, func() -> void: Game.poly_gallery(gg))
	var c4 := _poly_col(_poly_flow, "poly.c_funcs")
	_ptoggle(c4, "poly.f_god", "god")
	_ptoggle(c4, "poly.f_nomon", "nomon")
	_ptoggle(c4, "poly.f_lfnow", "lfnow")
	_ptoggle(c4, "poly.f_chase", "chase")
	_ptoggle(c4, "poly.f_fast", "fast")
	_ptoggle(c4, "poly.f_stamina", "stamina")
	_poly_back = _btn("ui.back", func() -> void: Game.leave_polygon(), 24)
	poly_box.add_child(_poly_back)


## Размер шрифта колонок полигона (при 4:3 мельче — колонки переносятся в две строки)
func _set_poly_font(sz: int) -> void:
	if sz == _poly_font:
		return
	_poly_font = sz
	for col in _poly_flow.get_children():
		for n in (col as Node).get_children():
			var c := n as Control
			if c is Button:
				c.add_theme_font_size_override("font_size", sz)
			elif c is Label:
				c.add_theme_font_size_override("font_size", sz + 2)


## Флаги запуска из полигона (те же ключи, что у отладочных аргументов)
func poly_flags() -> Dictionary:
	var f := {}
	if poly_state.god:
		f["god"] = "1"
	if poly_state.nomon:
		f["no_monsters"] = "1"
	if poly_state.lfnow or poly_state.chase:
		f["lf_now"] = "1"
	if poly_state.chase:
		f["lf_chase"] = "1"
	if poly_state.fast:
		f["fast"] = "1"
	if poly_state.stamina:
		f["stamina"] = "1"
	return f


func show_polygon() -> void:
	hide_all()
	visible = true
	poly_box.visible = true
	_dim.visible = true
	_dim.color = Color(0, 0, 0, 0.7)
	_relabel()
	_poly_first.grab_focus()


func _build_rooms() -> void:
	rooms_box = Control.new()
	rooms_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(rooms_box)
	_rooms_title = _lbl(Loc.t("poly.rooms_t"), 40, HEAD, true)
	_rooms_title.set_meta("key", "poly.rooms_t")
	_rooms_title.uppercase = true
	rooms_box.add_child(_rooms_title)
	_rooms_row = HBoxContainer.new()
	_rooms_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rooms_row.add_theme_constant_override("separation", int(ROOMS_GAP))
	rooms_box.add_child(_rooms_row)
	for c in ROOMS_MAX_COLS:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		_rooms_row.add_child(v)
		_rooms_cols.append(v)
	var plan: Array = load("res://src/world/worldgen_rooms.gd").PLAN
	for e in plan:
		var row: Array = e
		var typ: String = row[0]
		var lower: bool = int(row[1]) == 1
		var b := _btn("room." + typ, func() -> void: Game.poly_complex(lower, "room_%s_0" % typ), 15)
		_room_btns.append(b)
	_rooms_back = _btn("ui.back", func() -> void: show_polygon(), 24)
	rooms_box.add_child(_rooms_back)


## Разложить кнопки странных комнат по колонкам сверху вниз: самый крупный шрифт, при котором колонки
## помещаются в ширину кадра (avail_w), а строки — в высоту от заголовка до «Назад» (при 4:3 колонок меньше)
func _reflow_rooms(avail_w: float) -> void:
	var n := _room_btns.size()
	if n == 0:
		return
	var key := "%d|%s" % [int(avail_w), Cfg.lang]
	if key == _rooms_key:
		return
	_rooms_key = key
	var avail_h := ROOMS_BOTTOM - ROOMS_TOP
	var pick_sz := 14
	var pick_cols := ROOMS_MAX_COLS
	for sz in range(26, 13, -1):
		var bh := font_b.get_height(sz) + 2.0          # полоса выделения: поля 1+1
		var rows := maxi(1, int((avail_h + 3.0) / (bh + 3.0)))
		var cols := ceili(n / float(rows))
		if cols > ROOMS_MAX_COLS:
			continue
		if _rooms_width(sz, cols) <= avail_w:
			pick_sz = sz
			pick_cols = cols
			break
	var per := ceili(n / float(pick_cols))
	for i in n:
		var b: Button = _room_btns[i]
		b.add_theme_font_size_override("font_size", pick_sz)
		var col: VBoxContainer = _rooms_cols[mini(i / per, pick_cols - 1)]
		if b.get_parent() != col:
			if b.get_parent() != null:
				b.get_parent().remove_child(b)
			col.add_child(b)
	# строки — равномерно по доступной высоте (не плотной кучей наверху)
	var bh2 := font_b.get_height(pick_sz) + 2.0
	var sep := clampi(int((avail_h - per * bh2) / maxf(per - 1.0, 1.0)), 2, 14)
	for i in _rooms_cols.size():
		var c := _rooms_cols[i] as VBoxContainer
		c.visible = i < pick_cols
		c.add_theme_constant_override("separation", sep)


## Ширина колонок странных комнат при шрифте sz и cols колонках (подписи — как на кнопках, с полями)
func _rooms_width(sz: int, cols: int) -> float:
	var n := _room_btns.size()
	var per := ceili(n / float(cols))
	var w := 0.0
	for c in cols:
		var cw := 0.0
		for i in range(c * per, mini(n, (c + 1) * per)):
			var t := (_room_btns[i] as Button).text
			cw = maxf(cw, font_b.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + 10.0)
		w += cw
	return w + (cols - 1) * ROOMS_GAP


func show_rooms() -> void:
	hide_all()
	visible = true
	rooms_box.visible = true
	_dim.visible = true
	_dim.color = Color(0, 0, 0, 0.7)
	_relabel()
	_rooms_key = ""
	_layout()
	(_room_btns[0] as Button).grab_focus()


# ------------------------------------------------------------ настройки

func _build_settings() -> void:
	settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 3)
	frame.add_child(settings_box)
	var st := _lbl(Loc.t("ui.settings"), 40, HEAD, true)
	st.set_meta("key", "ui.settings")
	st.uppercase = true
	settings_box.add_child(st)
	_choice("ui.lang", ["mixed", "ru", "en"], ["ui.lang_mixed", "ui.lang_ru", "ui.lang_en"], func() -> Variant: return Cfg.lang, func(v: Variant) -> void: Cfg.lang = String(v))
	_slider("ui.sens", 0.2, 3.0, func() -> float: return Cfg.sens, func(v: float) -> void: Cfg.sens = v)
	_toggle("ui.invert", func() -> bool: return Cfg.invert_y, func(v: bool) -> void: Cfg.invert_y = v)
	_slider("ui.fov", 55.0, 90.0, func() -> float: return Cfg.fov, func(v: float) -> void: Cfg.fov = v)
	_slider("ui.vol", 0.0, 1.0, func() -> float: return Cfg.vol_master, func(v: float) -> void: Cfg.vol_master = v)
	_slider("ui.vol_sfx", 0.0, 1.0, func() -> float: return Cfg.vol_sfx, func(v: float) -> void: Cfg.vol_sfx = v)
	_slider("ui.vol_amb", 0.0, 1.0, func() -> float: return Cfg.vol_amb, func(v: float) -> void: Cfg.vol_amb = v)
	_slider("ui.vhs", 0.0, 1.5, func() -> float: return Cfg.vhs, func(v: float) -> void: Cfg.vhs = v)
	_choice("ui.aspect", ["4:3", "16:9"], ["", ""], func() -> Variant: return Cfg.aspect, func(v: Variant) -> void: Cfg.aspect = String(v))
	_choice("ui.res", [480, 600, 720], ["", "", ""], func() -> Variant: return Cfg.res, func(v: Variant) -> void: Cfg.res = int(v))
	_toggle("ui.fullscreen", func() -> bool: return Cfg.fullscreen, func(v: bool) -> void: Cfg.fullscreen = v)
	_toggle("ui.bob", func() -> bool: return Cfg.head_bob, func(v: bool) -> void: Cfg.head_bob = v)
	_toggle("ui.osd", func() -> bool: return Cfg.osd, func(v: bool) -> void: Cfg.osd = v)
	_toggle("ui.subs", func() -> bool: return Cfg.subtitles, func(v: bool) -> void: Cfg.subtitles = v)
	var back_cb := func() -> void:
		Cfg.save_cfg()
		if _settings_from == "pause":
			show_pause()
		else:
			show_main()
	var back := _btn("ui.back", back_cb, 24)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	settings_box.add_child(back)


func _row(key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var l := _lbl(Loc.t(key), 20, TXT, true)
	l.custom_minimum_size = Vector2(430, 0)
	l.uppercase = true
	l.set_meta("key", key)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	settings_box.add_child(h)
	return h


func _vbtn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	_vcr_style(b, 20)
	return b


func _choice(key: String, values: Array, labels: Array, getter: Callable, setter: Callable) -> void:
	var h := _row(key)
	var b := _vbtn("")
	h.add_child(b)
	var upd := func() -> void:
		var v: Variant = getter.call()
		var i := values.find(v)
		if i < 0:
			i = 0
		var lk: String = labels[i]
		b.text = " < " + (Loc.t(lk) if lk != "" else str(values[i]) + ("P" if typeof(values[i]) == TYPE_INT else "")).to_upper() + " > "
	b.pressed.connect(func() -> void:
		var i := values.find(getter.call())
		setter.call(values[(i + 1) % values.size()])
		Snd.play("ui_click", -6.0)
		Cfg.apply()
		upd.call())
	_rows.append(upd)
	upd.call()


func _toggle(key: String, getter: Callable, setter: Callable) -> void:
	var h := _row(key)
	var b := _vbtn("")
	h.add_child(b)
	var upd := func() -> void:
		b.text = " [" + ("X" if bool(getter.call()) else " ") + "] " + Loc.t("ui.on" if bool(getter.call()) else "ui.off").to_upper() + " "
	b.pressed.connect(func() -> void:
		setter.call(not bool(getter.call()))
		Snd.play("ui_click", -6.0)
		Cfg.apply()
		upd.call())
	_rows.append(upd)
	upd.call()


## Ползунок — «шкала уровня» видеомагнитофона: белая рамка, заполнение, блок-бегунок
func _slider(key: String, lo: float, hi: float, getter: Callable, setter: Callable) -> void:
	var h := _row(key)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.custom_minimum_size = Vector2(260, 26)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value = float(getter.call())
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.6)
	track.border_color = TXT
	track.set_border_width_all(2)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.85, 0.8)
	fill.border_color = TXT
	fill.set_border_width_all(2)
	var fill_hl := fill.duplicate() as StyleBoxFlat
	fill_hl.bg_color = BAR
	var foc := StyleBoxFlat.new()
	foc.draw_center = false
	foc.border_color = HEAD
	foc.set_border_width_all(2)
	foc.expand_margin_left = 4
	foc.expand_margin_right = 4
	foc.expand_margin_top = 2
	foc.expand_margin_bottom = 2
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hl)
	s.add_theme_stylebox_override("focus", foc)
	var g := _grabber_tex()
	s.add_theme_icon_override("grabber", g)
	s.add_theme_icon_override("grabber_highlight", g)
	s.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		Cfg.apply())
	s.mouse_entered.connect(func() -> void: s.grab_focus())
	h.add_child(s)
	_rows.append(func() -> void: s.set_value_no_signal(float(getter.call())))


## Бегунок ползунка: белый блок с чёрной окантовкой
func _grabber_tex() -> Texture2D:
	var img := Image.create(10, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	img.fill_rect(Rect2i(2, 2, 6, 20), TXT)
	return ImageTexture.create_from_image(img)


func _relabel() -> void:
	for n in _all(self):
		var c := n as Control
		if c == null or not c.has_meta("key"):
			continue
		var k := String(c.get_meta("key"))
		if c is Button:
			(c as Button).text = _cap(k)
		elif c is Label:
			(c as Label).text = Loc.t(k)
	for r in _rows:
		(r as Callable).call()
	controls.text = Loc.t("ui.controls")


func _all(n: Node) -> Array:
	var out := [n]
	for ch in n.get_children():
		out.append_array(_all(ch))
	return out


func hide_all() -> void:
	world_box.visible = false
	poly_box.visible = false
	rooms_box.visible = false
	main_box.visible = false
	pause_box.visible = false
	settings_box.visible = false
	title_box.visible = false
	intro.visible = false
	controls.visible = false
	credit.visible = false
	_dim.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_main() -> void:
	# отладка: --menu=settings — сразу экран настроек
	if Cfg.arg("menu", "") == "settings" and int(get_meta("dbg_settings", 0)) < 2:
		set_meta("dbg_settings", int(get_meta("dbg_settings", 0)) + 1)
		show_settings("main")
		return
	hide_all()
	visible = true
	title_box.visible = true
	main_box.visible = true
	credit.visible = true
	_dim.visible = true
	_dim.color = Color(0, 0, 0, 0.35)
	(main_box.get_child(0) as Button).grab_focus()


func show_pause() -> void:
	hide_all()
	# в полигоне «В меню» ведёт обратно в полигон
	var to := pause_box.get_child(3) as Button
	to.set_meta("key", "ui.to_poly" if Game.mode == "polygon" else "ui.to_menu")
	to.text = _cap(String(to.get_meta("key")))
	pause_box.visible = true
	_dim.visible = true
	_dim.color = Color(0, 0, 0, 0.6)
	(pause_box.get_child(1) as Button).grab_focus()


func show_settings(from: String) -> void:
	_settings_from = from
	hide_all()
	settings_box.visible = true
	_dim.visible = true
	_dim.color = Color(0, 0, 0, 0.72)
	_relabel()
	# первый пункт настроек — сразу под клавиатурой
	var first := (settings_box.get_child(1) as HBoxContainer).get_child(1) as Control
	first.grab_focus()


func show_intro(text: String) -> void:
	hide_all()
	intro.text = text
	intro.visible = true
	intro.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(intro, "modulate:a", 1.0, 0.8)
	tw.tween_interval(1.8)
	tw.tween_property(intro, "modulate:a", 0.0, 0.8)


## Надпись по центру без исчезновения (загрузка)
func show_intro_static(text: String) -> void:
	hide_all()
	intro.text = text
	intro.visible = true
	intro.modulate.a = 1.0


func flash_controls() -> void:
	controls.text = Loc.t("ui.controls")
	if Game.freecam_ok():
		controls.text += "   " + Loc.t("ui.freecam")
	controls.visible = true
	controls.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(controls, "modulate:a", 1.0, 0.8)
	tw.tween_interval(7.0)
	tw.tween_property(controls, "modulate:a", 0.0, 1.2)
	tw.tween_callback(func() -> void: controls.visible = false)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause") and (world_box.visible or rooms_box.visible or poly_box.visible):
		if world_box.visible:
			show_main()
		elif rooms_box.visible:
			show_polygon()
		else:
			Game.leave_polygon()
		get_viewport().set_input_as_handled()
		return
	if settings_box.visible and e.is_action_pressed("pause"):
		Cfg.save_cfg()
		if _settings_from == "pause":
			show_pause()
		else:
			show_main()
		get_viewport().set_input_as_handled()
