extends Control
## Главное меню, пауза, настройки, заставка. Стиль — экранное меню видеомагнитофона.

var font: SystemFont
var font_b: SystemFont
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

const WORLD_KEYS := {"base": "ui.w_base", "adventure": "ui.w_adv", "survival": "ui.w_surv", "polygon": "ui.w_poly"}


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
	hide_all()


func _lbl(text: String, size: int, col := Color(0.93, 0.93, 0.88), bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_b if bold else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


func _btn(key: String, cb: Callable, size := 30) -> Button:
	var b := Button.new()
	b.set_meta("key", key)
	b.text = "  " + Loc.t(key)
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", font_b)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	b.add_theme_color_override("font_hover_color", Color(0.55, 0.95, 1.0))
	b.add_theme_color_override("font_focus_color", Color(0.55, 0.95, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, empty)
	b.pressed.connect(func() -> void:
		Snd.play("ui_click", -6.0)
		cb.call())
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	b.focus_entered.connect(func() -> void:
		b.text = "▶ " + Loc.t(String(b.get_meta("key")))
		Snd.play("ui_move", -14.0))
	b.focus_exited.connect(func() -> void: b.text = "  " + Loc.t(String(b.get_meta("key"))))
	return b


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	title_box = VBoxContainer.new()
	title_box.position = Vector2(110, 120)
	add_child(title_box)
	var t1 := _lbl(Loc.t("ui.title"), 86, Color(0.95, 0.92, 0.7), true)
	t1.set_meta("key", "ui.title")
	title_box.add_child(t1)
	var t2 := _lbl(Loc.t("ui.subtitle"), 30, Color(0.85, 0.82, 0.62))
	t2.set_meta("key", "ui.subtitle")
	title_box.add_child(t2)
	main_box = VBoxContainer.new()
	main_box.position = Vector2(100, 380)
	main_box.add_theme_constant_override("separation", 6)
	add_child(main_box)
	main_box.add_child(_btn("ui.play", func() -> void: show_worlds()))
	main_box.add_child(_btn("ui.settings", func() -> void: show_settings("main")))
	main_box.add_child(_btn("ui.quit", func() -> void: get_tree().quit()))
	pause_box = VBoxContainer.new()
	pause_box.position = Vector2(100, 260)
	pause_box.add_theme_constant_override("separation", 6)
	add_child(pause_box)
	var pt := _lbl(Loc.t("ui.pause"), 44, Color(0.95, 0.92, 0.7), true)
	pt.set_meta("key", "ui.pause")
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
	intro = _lbl("", 34, Color(0.92, 0.92, 0.88))
	intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(intro)
	controls = _lbl(Loc.t("ui.controls"), 18, Color(0.9, 0.9, 0.85, 0.85))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(controls)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -34
	controls.offset_bottom = -6
	credit = _lbl("Fan game based on the Backrooms universe of Kane Parsons (Kane Pixels). Not affiliated.", 13, Color(0.7, 0.7, 0.65, 0.6))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(credit)
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	credit.offset_top = -26
	credit.offset_bottom = -6
	credit.offset_right = -16


# ------------------------------------------------------------ выбор мира

func _build_worlds() -> void:
	world_box = Control.new()
	world_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world_box)
	var t := _lbl(Loc.t("ui.world"), 44, Color(0.95, 0.92, 0.7), true)
	t.set_meta("key", "ui.world")
	t.position = Vector2(100, 130)
	world_box.add_child(t)
	var col := VBoxContainer.new()
	col.position = Vector2(100, 230)
	col.add_theme_constant_override("separation", 8)
	world_box.add_child(col)
	world_desc = _lbl("", 23, Color(0.9, 0.9, 0.84))
	world_desc.position = Vector2(560, 246)
	world_desc.size = Vector2(620, 300)
	world_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_box.add_child(world_desc)
	for w in Cfg.WORLDS:
		var wk: String = w
		var b := _btn(WORLD_KEYS[wk], func() -> void: _pick_world(wk))
		b.set_meta("world", wk)
		b.focus_entered.connect(func() -> void: world_desc.text = Loc.t(String(WORLD_KEYS[wk]) + "_d"))
		col.add_child(b)
	var back := _btn("ui.back", func() -> void: show_main())
	col.add_child(back)


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
	(get_node("Dim") as ColorRect).visible = true
	(get_node("Dim") as ColorRect).color = Color(0, 0, 0, 0.6)
	_relabel()
	var col := world_box.get_child(1) as VBoxContainer
	for b in col.get_children():
		if b.has_meta("world") and String(b.get_meta("world")) == Cfg.world:
			(b as Button).grab_focus()
	world_desc.text = Loc.t(String(WORLD_KEYS[Cfg.world]) + "_d")


# ------------------------------------------------------------ полигон

func _poly_col(parent: Control, x: float, head: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(x, 128)
	v.add_theme_constant_override("separation", 1)
	parent.add_child(v)
	var h := _lbl(Loc.t(head), 22, Color(0.95, 0.85, 0.45), true)
	h.set_meta("key", head)
	v.add_child(h)
	return v


func _pbtn(v: VBoxContainer, key: String, cb: Callable) -> void:
	v.add_child(_btn(key, cb, 20))


func _ptoggle(v: VBoxContainer, key: String, id: String) -> void:
	var b := _vbtn("")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 20)
	var upd := func() -> void:
		b.text = "[" + ("X" if bool(poly_state[id]) else " ") + "] " + Loc.t(key)
	b.pressed.connect(func() -> void:
		poly_state[id] = not bool(poly_state[id])
		Snd.play("ui_click", -6.0)
		upd.call())
	b.focus_entered.connect(func() -> void: Snd.play("ui_move", -14.0))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	_rows.append(upd)
	upd.call()
	v.add_child(b)


func _build_polygon() -> void:
	poly_box = Control.new()
	poly_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(poly_box)
	var t := _lbl(Loc.t("poly.title"), 44, Color(0.95, 0.92, 0.7), true)
	t.set_meta("key", "poly.title")
	t.position = Vector2(60, 26)
	poly_box.add_child(t)
	var hint := _lbl(Loc.t("poly.hint"), 17, Color(0.8, 0.85, 0.85))
	hint.set_meta("key", "poly.hint")
	hint.position = Vector2(62, 84)
	poly_box.add_child(hint)
	var c1 := _poly_col(poly_box, 50, "poly.c_start")
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
	var c2 := _poly_col(poly_box, 425, "poly.c_ends")
	for k in ["ocean", "sky", "highway", "wall", "space", "async"]:
		var kk: String = k
		_pbtn(c2, "poly.e_" + kk, func() -> void: Game.poly_ending(kk))
	_pbtn(c2, "poly.e_death", func() -> void: Game.poly_death())
	var c3 := _poly_col(poly_box, 685, "poly.c_beings")
	for g in ["copies", "copies2", "anim", "lifeform", "finds", "objects", "async", "tv", "models"]:
		var gg: String = g
		_pbtn(c3, "poly.g_" + gg, func() -> void: Game.poly_gallery(gg))
	var c4 := _poly_col(poly_box, 995, "poly.c_funcs")
	_ptoggle(c4, "poly.f_god", "god")
	_ptoggle(c4, "poly.f_nomon", "nomon")
	_ptoggle(c4, "poly.f_lfnow", "lfnow")
	_ptoggle(c4, "poly.f_chase", "chase")
	_ptoggle(c4, "poly.f_fast", "fast")
	_ptoggle(c4, "poly.f_stamina", "stamina")
	var back := _btn("ui.back", func() -> void: Game.leave_polygon(), 24)
	back.position = Vector2(56, 640)
	poly_box.add_child(back)


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
	(get_node("Dim") as ColorRect).visible = true
	(get_node("Dim") as ColorRect).color = Color(0, 0, 0, 0.7)
	_relabel()
	var first := (poly_box.get_child(2) as VBoxContainer).get_child(1) as Button
	first.grab_focus()


func _build_rooms() -> void:
	rooms_box = Control.new()
	rooms_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rooms_box)
	var t := _lbl(Loc.t("poly.rooms_t"), 40, Color(0.95, 0.92, 0.7), true)
	t.set_meta("key", "poly.rooms_t")
	t.position = Vector2(60, 30)
	rooms_box.add_child(t)
	var cols := []
	for c in 6:
		var v := VBoxContainer.new()
		v.position = Vector2(26 + c * 208, 100)
		v.add_theme_constant_override("separation", 1)
		rooms_box.add_child(v)
		cols.append(v)
	var plan: Array = load("res://src/world/worldgen_rooms.gd").PLAN
	var i := 0
	for e in plan:
		var row: Array = e
		var typ: String = row[0]
		var lower: bool = int(row[1]) == 1
		var b := _btn("room." + typ, func() -> void: Game.poly_complex(lower, "room_%s_0" % typ), 15)
		(cols[mini(i / 11, 5)] as VBoxContainer).add_child(b)
		i += 1
	var back := _btn("ui.back", func() -> void: show_polygon(), 24)
	back.position = Vector2(56, 640)
	rooms_box.add_child(back)


func show_rooms() -> void:
	hide_all()
	visible = true
	rooms_box.visible = true
	(get_node("Dim") as ColorRect).visible = true
	(get_node("Dim") as ColorRect).color = Color(0, 0, 0, 0.7)
	_relabel()
	((rooms_box.get_child(1) as VBoxContainer).get_child(0) as Button).grab_focus()


# ------------------------------------------------------------ настройки

func _build_settings() -> void:
	settings_box = VBoxContainer.new()
	settings_box.position = Vector2(100, 70)
	settings_box.add_theme_constant_override("separation", 3)
	add_child(settings_box)
	var st := _lbl(Loc.t("ui.settings"), 40, Color(0.95, 0.92, 0.7), true)
	st.set_meta("key", "ui.settings")
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
	var back := _btn("ui.back", func() -> void:
		Cfg.save_cfg()
		if _settings_from == "pause":
			show_pause()
		else:
			show_main())
	settings_box.add_child(back)


func _row(key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var l := _lbl(Loc.t(key), 21)
	l.custom_minimum_size = Vector2(430, 0)
	l.set_meta("key", key)
	h.add_child(l)
	settings_box.add_child(h)
	return h


func _vbtn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_override("font", font_b)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, empty)
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
		b.text = "< " + (Loc.t(lk) if lk != "" else str(values[i]) + ("p" if typeof(values[i]) == TYPE_INT else "")) + " >"
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
		b.text = "[" + ("X" if bool(getter.call()) else " ") + "] " + Loc.t("ui.on" if bool(getter.call()) else "ui.off")
	b.pressed.connect(func() -> void:
		setter.call(not bool(getter.call()))
		Snd.play("ui_click", -6.0)
		Cfg.apply()
		upd.call())
	_rows.append(upd)
	upd.call()


func _slider(key: String, lo: float, hi: float, getter: Callable, setter: Callable) -> void:
	var h := _row(key)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 100.0
	s.custom_minimum_size = Vector2(260, 24)
	s.value = float(getter.call())
	s.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		Cfg.apply())
	h.add_child(s)
	_rows.append(func() -> void: s.set_value_no_signal(float(getter.call())))


func _relabel() -> void:
	for n in _all(self):
		var c := n as Control
		if c == null or not c.has_meta("key"):
			continue
		var k := String(c.get_meta("key"))
		if c is Button:
			(c as Button).text = ("▶ " if (c as Button).has_focus() else "  ") + Loc.t(k)
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
	(get_node("Dim") as ColorRect).visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_main() -> void:
	hide_all()
	visible = true
	title_box.visible = true
	main_box.visible = true
	credit.visible = true
	(get_node("Dim") as ColorRect).visible = true
	(get_node("Dim") as ColorRect).color = Color(0, 0, 0, 0.35)
	(main_box.get_child(0) as Button).grab_focus()


func show_pause() -> void:
	hide_all()
	# в полигоне «В меню» ведёт обратно в полигон
	var to := pause_box.get_child(3) as Button
	to.set_meta("key", "ui.to_poly" if Game.mode == "polygon" else "ui.to_menu")
	to.text = "  " + Loc.t(String(to.get_meta("key")))
	pause_box.visible = true
	(get_node("Dim") as ColorRect).visible = true
	(get_node("Dim") as ColorRect).color = Color(0, 0, 0, 0.6)
	(pause_box.get_child(1) as Button).grab_focus()


func show_settings(from: String) -> void:
	_settings_from = from
	hide_all()
	settings_box.visible = true
	(get_node("Dim") as ColorRect).visible = true
	(get_node("Dim") as ColorRect).color = Color(0, 0, 0, 0.72)
	_relabel()


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
