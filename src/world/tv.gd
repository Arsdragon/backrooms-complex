class_name TVHub
extends Node
## Телеканалы для редких телевизоров в Комплексе. Каждый канал — маленький SubViewport (192×144),
## 2D, перерисовка 12 раз в секунду — это дёшево. Экраны берут его текстуру.

const CHANNELS := ["async_ad", "news", "bars", "explorers", "weather", "home"]

static var _hub: TVHub = null
var vps := {}          # канал -> SubViewport


static func hub(scene_root: Node) -> TVHub:
	if _hub == null or not is_instance_valid(_hub) or not _hub.is_inside_tree():
		_hub = TVHub.new()
		_hub.name = "TVHub"
		scene_root.add_child(_hub)
	return _hub


func texture(ch: String) -> Texture2D:
	if not vps.has(ch):
		var vp := SubViewport.new()
		vp.size = Vector2i(192, 144)
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var c := Channel.new()
		c.kind = ch
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		vp.add_child(c)
		add_child(vp)
		vps[ch] = vp
	return (vps[ch] as SubViewport).get_texture()


class Channel extends Control:
	var kind := "bars"
	var t := 0.0
	var _font: SystemFont
	var _acc := 0.0

	func _ready() -> void:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Arial", "Bahnschrift", "sans-serif"])
		_font.font_weight = 700
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		t = randf() * 30.0

	func _process(dt: float) -> void:
		t += dt
		_acc += dt
		if _acc >= 1.0 / 12.0:
			_acc = 0.0
			queue_redraw()

	func _txt(p: Vector2, s: String, sz: int, c := Color.WHITE) -> void:
		draw_string(_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

	func _ctxt(y: float, s: String, sz: int, c := Color.WHITE) -> void:
		var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		_txt(Vector2((192.0 - w) * 0.5, y), s, sz, c)

	func _person(p: Vector2, h: float, c: Color, phase := 0.0) -> void:
		var step := sin(phase) * h * 0.08
		draw_circle(p + Vector2(0, -h * 0.88), h * 0.1, c)
		draw_rect(Rect2(p + Vector2(-h * 0.1, -h * 0.78), Vector2(h * 0.2, h * 0.38)), c)
		draw_line(p + Vector2(-h * 0.05, -h * 0.4), p + Vector2(-h * 0.06 - step, 0), c, 2.0)
		draw_line(p + Vector2(h * 0.05, -h * 0.4), p + Vector2(h * 0.06 + step, 0), c, 2.0)

	func _draw() -> void:
		match kind:
			"async_ad": _async_ad()
			"news": _news()
			"bars": _bars()
			"explorers": _explorers()
			"weather": _weather()
			"home": _home()

	## Реклама Async «A-SPACE»: люди живут в жёлтых комнатах
	func _async_ad() -> void:
		var ph := fmod(t, 24.0)
		draw_rect(Rect2(0, 0, 192, 144), Color(0.05, 0.08, 0.22))
		for i in 12:
			draw_rect(Rect2(0, i * 12, 192, 6), Color(0.07, 0.11, 0.28))
		if ph < 6.0:
			draw_texture_rect(Mats.tex("async_mark"), Rect2(76, 24, 40, 40), false, Color(0.9, 0.92, 1.0))
			_ctxt(88, "ASYNC", 20, Color(0.92, 0.94, 1.0))
			_ctxt(106, "RESEARCH INSTITUTE", 9, Color(0.7, 0.75, 0.9))
			_ctxt(126, Loc.t("tv.ad1"), 9, Color(0.95, 0.85, 0.4))
		elif ph < 16.0:
			# диорама: срез жёлтых комнат, в них ходят люди
			_ctxt(18, "A-SPACE", 16, Color(0.95, 0.85, 0.4))
			for r in 2:
				for k in 3:
					var x0 := 14.0 + k * 56.0
					var y0 := 30.0 + r * 52.0
					draw_rect(Rect2(x0, y0, 52, 48), Color(0.78, 0.7, 0.36))
					draw_rect(Rect2(x0 + 20, y0 + 2, 12, 3), Color(1, 1, 0.9))
					draw_rect(Rect2(x0, y0 + 44, 52, 4), Color(0.5, 0.42, 0.22))
					var px := x0 + 10.0 + fmod(t * (6.0 + k * 2.0) + r * 13.0 + k * 7.0, 32.0)
					_person(Vector2(px, y0 + 44), 22.0, Color(0.15, 0.13, 0.12), t * 6.0 + k)
					if (r + k) % 2 == 0:
						_person(Vector2(x0 + 40, y0 + 44), 16.0, Color(0.2, 0.15, 0.12), t * 5.0)
			_ctxt(138, Loc.t("tv.ad2"), 9, Color(0.9, 0.92, 1.0))
		else:
			_ctxt(40, Loc.t("tv.ad3"), 11, Color(0.95, 0.85, 0.4))
			_ctxt(62, Loc.t("tv.ad4"), 9, Color(0.85, 0.88, 1.0))
			_ctxt(78, Loc.t("tv.ad5"), 9, Color(0.85, 0.88, 1.0))
			_ctxt(120, "1-800-KV31-NOW", 12, Color(1, 1, 1))

	## Вечерние новости: пропавшие в районе залива
	func _news() -> void:
		draw_rect(Rect2(0, 0, 192, 144), Color(0.12, 0.14, 0.3))
		draw_rect(Rect2(110, 20, 72, 54), Color(0.35, 0.55, 0.3))
		for k in 4:
			draw_circle(Vector2(122 + k * 16, 42 + (k % 2) * 6), 8, Color(0.2, 0.38, 0.18))
		draw_rect(Rect2(110, 62, 72, 12), Color(0.6, 0.6, 0.55))
		# ведущий
		draw_circle(Vector2(56, 56), 14, Color(0.75, 0.6, 0.5))
		draw_rect(Rect2(34, 70, 44, 50), Color(0.18, 0.18, 0.22))
		draw_rect(Rect2(10, 104, 172, 20), Color(0.55, 0.08, 0.06))
		_txt(Vector2(14, 118), Loc.t("tv.news1"), 9, Color(1, 1, 1))
		var tick := Loc.t("tv.news2")
		var off := fmod(t * 30.0, 600.0)
		draw_rect(Rect2(0, 128, 192, 16), Color(0.05, 0.05, 0.08))
		_txt(Vector2(192 - off, 140), tick, 9, Color(0.95, 0.9, 0.5))
		_txt(Vector2(8, 14), "KNTV 11", 9, Color(1, 1, 1))

	## Настроечная таблица
	func _bars() -> void:
		var cols := [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0), Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
		for i in 7:
			draw_rect(Rect2(i * 192.0 / 7.0, 0, 192.0 / 7.0 + 1, 100), cols[i])
		draw_rect(Rect2(0, 100, 192, 44), Color(0.06, 0.06, 0.08))
		_ctxt(126, Loc.t("tv.bars"), 10, Color(1, 1, 1))

	## Архивная съёмка: исследователи Async в коридорах Комплекса
	func _explorers() -> void:
		draw_rect(Rect2(0, 0, 192, 144), Color(0.42, 0.37, 0.18))
		# коридор в перспективе
		var c := Vector2(96, 70)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(192, 0), c + Vector2(26, -18), c + Vector2(-26, -18)]), Color(0.62, 0.6, 0.52))
		draw_colored_polygon(PackedVector2Array([Vector2(0, 144), Vector2(192, 144), c + Vector2(26, 18), c + Vector2(-26, 18)]), Color(0.3, 0.25, 0.12))
		draw_rect(Rect2(c.x - 26, c.y - 18, 52, 36), Color(0.2, 0.17, 0.08))
		for k in 3:
			var y := 10.0 + k * 14.0
			draw_rect(Rect2(96 - 12 + k * 3, y, 24 - k * 6, 4), Color(1, 1, 0.9))
		var walk := fmod(t * 0.07, 1.0)
		for k in 2:
			var s := lerpf(1.0, 0.35, fmod(walk + k * 0.18, 1.0))
			var px := 96.0 + (k * 2 - 1) * 14.0 * s
			_person(Vector2(px, 70 + 60 * s), 70.0 * s, Color(0.75, 0.72, 0.6) * 0.8, t * 5.0 + k)
		_txt(Vector2(6, 12), "KV31  EXP. 04", 9, Color(1, 1, 1))
		_txt(Vector2(6, 138), Loc.t("tv.exp"), 9, Color(1, 1, 1))
		if fmod(t, 7.0) < 0.2:
			draw_rect(Rect2(0, 0, 192, 144), Color(1, 1, 1, 0.5))

	## Прогноз погоды
	func _weather() -> void:
		draw_rect(Rect2(0, 0, 192, 144), Color(0.1, 0.25, 0.5))
		draw_colored_polygon(PackedVector2Array([Vector2(20, 30), Vector2(90, 24), Vector2(120, 60), Vector2(100, 120), Vector2(40, 126), Vector2(16, 80)]), Color(0.3, 0.55, 0.25))
		draw_circle(Vector2(70, 70), 4, Color(1, 1, 1))
		_txt(Vector2(78, 74), "SAN JOSE", 9, Color(1, 1, 1))
		draw_circle(Vector2(150, 50), 14, Color(1, 0.85, 0.2))
		_txt(Vector2(134, 90), "74°F", 16, Color(1, 1, 1))
		_txt(Vector2(10, 14), Loc.t("tv.weather"), 9, Color(1, 1, 1))
		_txt(Vector2(10, 138), "JUL 14  " + Loc.t("tv.sunny"), 9, Color(0.95, 0.9, 0.5))

	## Домашнее видео: день рождения
	func _home() -> void:
		draw_rect(Rect2(0, 0, 192, 144), Color(0.32, 0.22, 0.14))
		draw_rect(Rect2(0, 92, 192, 52), Color(0.45, 0.32, 0.2))
		draw_rect(Rect2(60, 80, 72, 14), Color(0.9, 0.88, 0.82))
		draw_rect(Rect2(84, 66, 24, 14), Color(0.95, 0.85, 0.85))
		for k in 3:
			var fl := 1.0 + sin(t * 20.0 + k) * 0.3
			draw_circle(Vector2(90 + k * 6, 62 - fl), 1.6, Color(1, 0.8, 0.3))
		for k in 4:
			var px := 30.0 + k * 44.0
			_person(Vector2(px, 92 + (k % 2) * 4), 46.0 + (k % 2) * 8, Color(0.12, 0.1, 0.08), t * 0.5 + k)
		_txt(Vector2(120, 138), "DEC 25 1989", 9, Color(1, 1, 1))
		_txt(Vector2(8, 14), "PLAY >", 9, Color(1, 1, 1))
