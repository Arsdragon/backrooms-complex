extends Control
## Карточка концовки — архивная заставка, записанная на ту же кассету: чёрное поле, заголовок и текст «из архива»
## одним машинописным шрифтом (Courier: заголовок — жирный, заглавными, с разрядкой; текст — тем же шрифтом).
## Заголовок и текст рисуются в прозрачном вьюпорте надписей камеры (main.osd_vp), поэтому идут через камеру и
## плёнку, как и весь кадр: приподнятый чёрный, шум, расплывшийся цвет, дрожание строк, при появлении — срыв
## трекинга (склейка записи). Подсказка «нажмите любую клавишу» — экранная надпись видеомагнитофона: чёткая,
## поверх плёнки, мигает. Сам узел живёт в интерфейсе (ввод), «запись» карточки — в osd_vp; уходя, он её убирает.

signal closed

const INK := Color(0.93, 0.91, 0.82)
const INK_BODY := Color(0.84, 0.83, 0.77)

var _can_close := false
var _box: Control            # «записанная» часть: в main.osd_vp (или здесь же, если цепочки камеры нет)
var _title: Label
var _body: Label
var _press: Label
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = Control.new()
	_box.name = "CardTape"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(bg)
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Courier New", "Courier", "Liberation Mono", "monospace"])
	base.font_weight = 700
	var ft := FontVariation.new()
	ft.base_font = base
	ft.spacing_glyph = 3
	var fb := SystemFont.new()
	fb.font_names = base.font_names
	fb.font_weight = 600
	_title = Label.new()
	_title.add_theme_font_override("font", ft)
	_title.add_theme_color_override("font_color", INK)
	_title.uppercase = true
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.anchor_left = 0.1
	_title.anchor_right = 0.9
	_title.anchor_top = 0.14
	_title.anchor_bottom = 0.27
	_title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_box.add_child(_title)
	_body = Label.new()
	_body.add_theme_font_override("font", fb)
	_body.add_theme_color_override("font_color", INK_BODY)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.anchor_left = 0.1
	_body.anchor_right = 0.9
	_body.anchor_top = 0.31
	_body.anchor_bottom = 0.86
	_body.visible_ratio = 0.0
	_box.add_child(_body)
	var tape: Node = null
	if Game.main != null and Game.main.osd_vp != null:
		tape = Game.main.osd_vp
	if tape != null:
		tape.add_child(_box)
	else:
		add_child(_box)
	# подсказка — надпись видеомагнитофона: блочные заглавные с окантовкой (как в меню)
	var fp := SystemFont.new()
	fp.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
	fp.font_weight = 700
	_press = Label.new()
	_press.add_theme_font_override("font", fp)
	_press.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	_press.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	_press.uppercase = true
	_press.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_press.modulate.a = 0.0
	_press.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_press)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _exit_tree() -> void:
	if is_instance_valid(_box) and _box.get_parent() != self:
		_box.queue_free()


## Запись — на весь кадр (в пикселях кадра); подсказка — внутри кадра на экране. Размер шрифта — от высоты кадра.
func _layout() -> void:
	var vs := Vector2(Cfg.frame_size())
	if _box.get_parent() == self:
		var fr0 := Cfg.frame_rect(get_viewport_rect())
		_box.position = fr0.position
		vs = fr0.size
	else:
		_box.position = Vector2.ZERO
	_box.size = vs
	var s := vs.y / 720.0
	_title.add_theme_font_size_override("font_size", int(round(38.0 * s)))
	_body.add_theme_font_size_override("font_size", int(round(25.0 * s)))
	var fr := Cfg.frame_rect(get_viewport_rect())
	var ps := fr.size.y / 720.0
	_press.add_theme_font_size_override("font_size", int(round(22.0 * ps)))
	_press.add_theme_constant_override("outline_size", maxi(3, int(round(5.0 * ps))))
	_press.position = fr.position + Vector2(fr.size.x * 0.1, fr.size.y * 0.9)
	_press.size = Vector2(fr.size.x * 0.8, fr.size.y * 0.06)


func open(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_press.text = Loc.t("ui.press")
	Snd.play("card_hum", -10.0)
	if Game.main != null:
		# карточка — сама запись: затемнение «на плёнке» снимаем (чёрное поле — её собственное),
		# а склейку отмечает короткий срыв трекинга
		Game.main.set_fade(Color(0, 0, 0, 0))
		Game.main.burst(0.55)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(_body, "visible_ratio", 1.0, maxf(2.5, body.length() * 0.028))
	tw.tween_property(_press, "modulate:a", 1.0, 0.8)
	tw.tween_callback(func() -> void: _can_close = true)


func _process(dt: float) -> void:
	# подсказка мигает, как надпись на экране видеомагнитофона
	if _can_close:
		_t += dt
		_press.modulate.a = 1.0 if fmod(_t, 1.3) < 0.85 else 0.25


func _input(e: InputEvent) -> void:
	if not _can_close:
		return
	if (e is InputEventKey and e.is_pressed()) or (e is InputEventMouseButton and e.is_pressed()):
		_can_close = false
		# подсказка — не запись: исчезает сразу, а сама карточка уходит в чёрное вместе с плёнкой (Game.show_card)
		_press.visible = false
		get_viewport().set_input_as_handled()
		closed.emit()
