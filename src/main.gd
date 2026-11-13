extends Node
## Корень. 3D-мир рендерится в маленький SubViewport (кадр 480/600/720 строк), дальше — «видеокамера» и «плёнка».
## Каждая ступень — свой SubViewport; сёстры рисуются в порядке добавления (сверху вниз), поэтому вся цепочка
## укладывается в один кадр без задержки:
##   World (3D, MSAA 4x) → Lag (инерция матрицы: хвосты ламп) → Copy (прошлый кадр для Lag)
##   → Glow1 (яркое, 1/4) → Glow2 (размытое, 1/8) → Glow3 (1/16) → Glow4 (1/32, широкая дымка)
##   → Meter (экспонометр 16×12) → Osd (впечатанные в запись дата и время, прозрачный)
##   → Cam (объектив, ирис, AGC, клип, ореол, смаз, баланс белого, ранение, OSD)
##   → Tape (VHS: полоса, шумы, сбои, затемнение) → экран (Catmull-Rom под размер окна)
##   → надписи видоискателя (REC, батарея, SP — на плёнку не пишутся, osd.vf).
## Сверху — чёткий интерфейс (меню, субтитры, записки).

const VHS_SHADER := preload("res://src/shaders/vhs.gdshader")
const CAM_SHADER := preload("res://src/shaders/camera.gdshader")
const LAG_SHADER := preload("res://src/shaders/cam_lag.gdshader")
const GLOW_SHADER := preload("res://src/shaders/cam_glow.gdshader")
const METER_SHADER := preload("res://src/shaders/cam_meter.gdshader")
const OUT_SHADER := preload("res://src/shaders/vhs_out.gdshader")
const Osd := preload("res://src/render/osd.gd")
const Subs := preload("res://src/ui/subs.gd")
const METER := Vector2i(16, 12)
const DISTORT := 0.03           # бочка объектива (camera.gdshader distort; нужна и здесь — где солнце в кадре)
## Автоусиление (AGC) по экспонометру: средняя яркость кадра ниже AGC_REF — усиление растёт (до AGC_MAX)
const AGC_REF := 0.26
const AGC_MAX := 2.4
const WB_DRIFT := 0.012         # медленное «гуляние» автобаланса белого (доля R/B)

signal frame_changed            # прямоугольник кадра на экране изменился (окно, формат, разрешение)

var vp: SubViewport             # 3D-мир
var osd_vp: SubViewport         # надписи камеры (прозрачный, размер кадра)
var screen: TextureRect
var vhs_mat: ShaderMaterial     # плёнка (vhs.gdshader)
var cam_mat: ShaderMaterial     # объектив и матрица (camera.gdshader)
var back: ColorRect
var ui: CanvasLayer
var fade: ColorRect             # затемнение поверх интерфейса — только для переходов самого UI (ui_fade_to)
var osd: Osd
var subs: Subs
var scene: Node = null

# параметры камеры и плёнки, которые задают сцены
var gain := 1.0                 # усиление, которое задаёт сцена (Комплекс, концовки): ярче и шумнее в темноте, 1..3.5
var auto_gain := true           # камера сама поднимает усиление в темноте по экспонометру (во всех сценах)
var agc := 1.0                  # усиление по экспонометру (плавное), 1..AGC_MAX
var gain_eff := 1.0             # итоговое усиление камеры: max(gain сцены, agc)
var exposure := 1.0             # ирис: линейный множитель света (1 — норма, 0.5 — на ступень темнее); × автоирис
var auto_iris := true           # камера сама прикрывает ирис по экспонометру (лампы в кадре, яркий день)
## Баланс белого (линейные множители RGB) под люминесцентные лампы: тёпло-нейтральный (R ≥ G) — обои масляно-жёлтые,
## потолок тёпло-белый, без оливковой зелени. В парке камера сама подстраивается под дневной свет (WB_DAY);
## переход плавный, как автобаланс бытовой камеры (пара секунд), и баланс чуть «гуляет» (WB_DRIFT).
var white_balance := Vector3(1.01, 1.0, 0.94)
const WB_DAY := Vector3(1.0, 1.0, 1.0)
var defocus := 0.0              # поиск автофокуса 0..1 (задаёт герой; сам затухает)
var fade_col := Color(0, 0, 0, 0)   # затемнение «на плёнке» (fade_to / set_fade)
var interference := 0.0
var tracking := 0.0
var _tracking_burst := 0.0
var stopfx := 0.0
var bw := 0.0
var desat := 0.0
var hurt := 0.0                # ранение 0..1 (красный кадр)
var hurt_flash := 0.0
# экспонометр (читается с видеокарты асинхронно, с задержкой в пару кадров)
var meter_avg := 0.45           # средняя яркость кадра с весом к центру, 0..1 (до ириса)
var meter_hot := 0.0            # доля пересвеченного (лампы), 0..1
var iris := 1.0                 # текущее положение автоириса (множитель света)

var _lag_vp: SubViewport
var _copy_vp: SubViewport
var _glow1_vp: SubViewport
var _glow2_vp: SubViewport
var _glow3_vp: SubViewport
var _glow4_vp: SubViewport
var _meter_vp: SubViewport
var _cam_vp: SubViewport
var _tape_vp: SubViewport
var _lag_mat: ShaderMaterial
var _glow1_mat: ShaderMaterial
var _glow2_mat: ShaderMaterial
var _glow3_mat: ShaderMaterial
var _glow4_mat: ShaderMaterial
var _iris_v := 0.0
var _meter_busy := false
var _meter_ok := true
var _meter_wait := 0
var _meter_busy_frames := 0
var _glitch := 0.0
var _glitch_t := 0.0
var _frame_rect := Rect2()
var _fade_id := 0
var _wb := Vector3(1.035, 1.0, 0.87)
var _wb_t := 0.0
var _sun_light: DirectionalLight3D = null
var _sun_scene_id := 0
var _sun_look := 0.0
var _still: ImageTexture = null     # последний кадр перед смертью (след в красном кадре)
var _still_amt := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	back = ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := CanvasLayer.new()
	bl.layer = -10
	add_child(bl)
	bl.add_child(back)

	vp = SubViewport.new()
	vp.name = "World"
	vp.audio_listener_enable_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_debanding = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.positional_shadow_atlas_size = 1024
	vp.handle_input_locally = false
	add_child(vp)

	# ступени камеры и плёнки (порядок добавления = порядок отрисовки)
	_lag_vp = _stage("Lag")
	_copy_vp = _stage("Copy")
	_glow1_vp = _stage("Glow1")
	_glow2_vp = _stage("Glow2")
	_glow3_vp = _stage("Glow3")
	_glow4_vp = _stage("Glow4")
	# ореол хранит «энергию» ламп (больше 1) — плавающая точка, без ступенек в слабых хвостах
	for g in [_glow1_vp, _glow2_vp, _glow3_vp, _glow4_vp]:
		(g as SubViewport).use_hdr_2d = true
	_meter_vp = _stage("Meter")
	osd_vp = _stage("Osd")
	osd_vp.transparent_bg = true
	_cam_vp = _stage("Cam")
	_tape_vp = _stage("Tape")

	_lag_mat = _pass(_lag_vp, LAG_SHADER)
	_lag_mat.set_shader_parameter("cur_tex", vp.get_texture())
	_lag_mat.set_shader_parameter("prev_tex", _copy_vp.get_texture())
	var cp := TextureRect.new()
	cp.texture = _lag_vp.get_texture()
	cp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cp.stretch_mode = TextureRect.STRETCH_SCALE
	cp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cp.set_anchors_preset(Control.PRESET_FULL_RECT)
	_copy_vp.add_child(cp)
	_glow1_mat = _pass(_glow1_vp, GLOW_SHADER)
	_glow1_mat.set_shader_parameter("src", _lag_vp.get_texture())
	_glow1_mat.set_shader_parameter("mode", 0)
	_glow2_mat = _pass(_glow2_vp, GLOW_SHADER)
	_glow2_mat.set_shader_parameter("src", _glow1_vp.get_texture())
	_glow2_mat.set_shader_parameter("mode", 1)
	_glow3_mat = _pass(_glow3_vp, GLOW_SHADER)
	_glow3_mat.set_shader_parameter("src", _glow2_vp.get_texture())
	_glow3_mat.set_shader_parameter("mode", 1)
	_glow4_mat = _pass(_glow4_vp, GLOW_SHADER)
	_glow4_mat.set_shader_parameter("src", _glow3_vp.get_texture())
	_glow4_mat.set_shader_parameter("mode", 1)
	var mm := _pass(_meter_vp, METER_SHADER)
	mm.set_shader_parameter("src", _lag_vp.get_texture())
	mm.set_shader_parameter("cells", Vector2(METER))
	osd = Osd.new()
	osd.process_mode = Node.PROCESS_MODE_ALWAYS
	osd_vp.add_child(osd)
	cam_mat = _pass(_cam_vp, CAM_SHADER)
	cam_mat.set_shader_parameter("src", _lag_vp.get_texture())
	cam_mat.set_shader_parameter("glow_a", _glow1_vp.get_texture())
	cam_mat.set_shader_parameter("glow_b", _glow2_vp.get_texture())
	cam_mat.set_shader_parameter("glow_c", _glow3_vp.get_texture())
	cam_mat.set_shader_parameter("glow_d", _glow4_vp.get_texture())
	cam_mat.set_shader_parameter("distort", DISTORT)
	cam_mat.set_shader_parameter("osd_tex", osd_vp.get_texture())
	vhs_mat = _pass(_tape_vp, VHS_SHADER)
	vhs_mat.set_shader_parameter("cam_tex", _cam_vp.get_texture())

	var sl := CanvasLayer.new()
	sl.layer = 0
	add_child(sl)
	screen = TextureRect.new()
	screen.texture = _tape_vp.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var om := ShaderMaterial.new()
	om.shader = OUT_SHADER
	screen.material = om
	sl.add_child(screen)
	# надписи видоискателя (REC, батарея, SP) — поверх записанной картинки, на плёнку не попадают (osd.gd)
	var vl := CanvasLayer.new()
	vl.layer = 1
	add_child(vl)
	vl.add_child(osd.vf)

	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	subs = Subs.new()
	ui.add_child(subs)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fl := CanvasLayer.new()
	fl.layer = 20
	add_child(fl)
	fl.add_child(fade)

	_glitch_t = randf_range(50.0, 150.0)
	if Cfg.has_arg("glitch"):
		_glitch_t = float(Cfg.arg("glitch"))
	if Cfg.has_arg("iris"):
		exposure = float(Cfg.arg("iris"))
	if Cfg.has_arg("no_auto_iris"):
		auto_iris = false
	Cfg.changed.connect(_apply_cfg)
	get_viewport().size_changed.connect(_apply_cfg)
	_apply_cfg()
	Game.main = self
	Game.boot.call_deferred()
	if Cfg.has_arg("shot"):
		_auto_shot.call_deferred()


## Ступень цепочки: 2D-вьюпорт без 3D и без ввода, рисуется каждый кадр
func _stage(n: String) -> SubViewport:
	var v := SubViewport.new()
	v.name = n
	v.disable_3d = true
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	v.handle_input_locally = false
	v.gui_disable_input = true
	add_child(v)
	return v


## Прямоугольник на весь вьюпорт со своим шейдером
func _pass(v: SubViewport, sh: Shader) -> ShaderMaterial:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	v.add_child(r)
	return m


func _auto_shot() -> void:
	var w := float(Cfg.arg("wait", "3"))
	await get_tree().create_timer(w).timeout
	# отладка: --pause — снять кадр с открытой паузой
	if Cfg.has_arg("pause") and Game.state in ["park", "complex", "ending", "gallery"]:
		Game.set_paused(true)
		await get_tree().create_timer(0.8).timeout
	var paths := Cfg.arg("shot").split(";")
	for i in paths.size():
		if i > 0:
			await get_tree().create_timer(float(Cfg.arg("every", "1.0"))).timeout
		await RenderingServer.frame_post_draw
		screenshot(paths[i])
		# отладка: --raw — ещё и кадр 3D-мира до камеры и плёнки (<имя>_raw.png)
		if Cfg.has_arg("raw"):
			vp.get_texture().get_image().save_png(paths[i].get_basename() + "_raw.png")
		print("SHOT ", paths[i], " fps=", Engine.get_frames_per_second(), " iris=%.2f avg=%.2f hot=%.3f gain=%.2f agc=%.2f" % [iris, meter_avg, meter_hot, gain_eff, agc])
	get_tree().quit()


func _apply_cfg() -> void:
	var fs := Cfg.frame_size()
	var q := Vector2i(ceili(fs.x / 4.0), ceili(fs.y / 4.0))
	var e := Vector2i(ceili(fs.x / 8.0), ceili(fs.y / 8.0))
	var e3 := Vector2i(ceili(fs.x / 16.0), ceili(fs.y / 16.0))
	var e4 := Vector2i(ceili(fs.x / 32.0), ceili(fs.y / 32.0))
	vp.size = fs
	for v in [_lag_vp, _copy_vp, osd_vp, _cam_vp, _tape_vp]:
		(v as SubViewport).size = fs
	_glow1_vp.size = q
	_glow2_vp.size = e
	_glow3_vp.size = e3
	_glow4_vp.size = e4
	_meter_vp.size = METER
	var fsv := Vector2(fs)
	_glow1_mat.set_shader_parameter("src_px", Vector2.ONE / fsv)
	_glow2_mat.set_shader_parameter("src_px", Vector2.ONE / Vector2(q))
	_glow3_mat.set_shader_parameter("src_px", Vector2.ONE / Vector2(e))
	_glow4_mat.set_shader_parameter("src_px", Vector2.ONE / Vector2(e3))
	cam_mat.set_shader_parameter("src_size", fsv)
	cam_mat.set_shader_parameter("glow_a_size", Vector2(q))
	cam_mat.set_shader_parameter("glow_b_size", Vector2(e))
	cam_mat.set_shader_parameter("glow_c_size", Vector2(e3))
	cam_mat.set_shader_parameter("glow_d_size", Vector2(e4))
	vhs_mat.set_shader_parameter("src_size", fsv)
	var fr := frame_rect()
	if fr != _frame_rect:
		_frame_rect = fr
		frame_changed.emit()


## Где кадр на экране (координаты интерфейса): меню и подписи ставятся внутрь, а не в чёрные поля по бокам
func frame_rect() -> Rect2:
	return Cfg.frame_rect(get_viewport().get_visible_rect())


func set_scene(n: Node) -> void:
	if scene != null and is_instance_valid(scene):
		vp.remove_child(scene)
		scene.queue_free()
	scene = n
	if n != null:
		vp.add_child(n)
		vp.move_child(n, 0)


func burst(amount := 1.0) -> void:
	_tracking_burst = maxf(_tracking_burst, amount)


## Затемнение кадра «на плёнке»: под шумом ленты, поверх OSD. Интерфейс (меню, карточки) остаётся виден.
## Побеждает последний запрос: прежний переход доигрывает (его finished придёт вовремя), но кадр уже не трогает —
## иначе медленное «проявление» из меню перебивало бы, например, красный экран смерти.
func fade_to(c: Color, time: float) -> Tween:
	_fade_id += 1
	var id := _fade_id
	var step := func(v: Color) -> void:
		if id == _fade_id:
			fade_col = v
	var tw := create_tween()
	tw.tween_method(step, fade_col, c, maxf(time, 0.001))
	return tw


func set_fade(c: Color) -> void:
	_fade_id += 1
	fade_col = c


## Затемнение поверх всего, включая интерфейс (старый слой 20) — для переходов самого UI
func ui_fade_to(c: Color, time: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade, "color", c, time)
	return tw


func set_ui_fade(c: Color) -> void:
	fade.color = c


func _process(dt: float) -> void:
	var fr := frame_rect()
	if fr != _frame_rect:
		_frame_rect = fr
		frame_changed.emit()
	_tracking_burst = move_toward(_tracking_burst, 0.0, dt * 1.6)
	hurt_flash = move_toward(hurt_flash, 0.0, dt * 2.2)
	defocus = move_toward(defocus, 0.0, dt * 1.2)
	_update_glitch(dt)
	_update_iris(minf(dt, 0.05))
	_update_agc(minf(dt, 0.05))
	_update_sun(dt)
	_update_still(dt)
	# инерция матрицы: доли заданы для 60 к/с, шейдер пересчитывает их на длину кадра
	_lag_mat.set_shader_parameter("frames", clampf(dt * 60.0, 0.1, 6.0))
	cam_mat.set_shader_parameter("exposure", exposure * iris)
	cam_mat.set_shader_parameter("agc", gain_eff)
	cam_mat.set_shader_parameter("defocus", defocus)
	# баланс белого: цель (лампы / день) и медленное «гуляние» автобаланса в тёплую и холодную сторону
	_wb_t += dt
	var dr := (sin(_wb_t * 0.071) * 0.6 + sin(_wb_t * 0.029 + 1.9) * 0.4) * WB_DRIFT
	var wb_target := (WB_DAY if Game.state == "park" else white_balance) * Vector3(1.0 + dr, 1.0, 1.0 - dr)
	_wb = _wb.lerp(wb_target, minf(1.0, dt * 0.7))
	if fade_col.a > 0.95 or Engine.get_process_frames() < 3:
		_wb = wb_target                 # пока кадр затемнён — сразу (подстройку никто не увидит)
	cam_mat.set_shader_parameter("white_bal", _wb)
	# ранение — сбой камеры до генератора символов (OSD остаётся белым); удар — ещё и срыв трекинга
	cam_mat.set_shader_parameter("hurt", hurt)
	cam_mat.set_shader_parameter("hurt_flash", hurt_flash)
	vhs_mat.set_shader_parameter("intensity", Cfg.vhs)
	vhs_mat.set_shader_parameter("gain", gain_eff)
	vhs_mat.set_shader_parameter("interference", interference)
	vhs_mat.set_shader_parameter("tracking", maxf(maxf(tracking, _tracking_burst), hurt_flash * 0.3))
	vhs_mat.set_shader_parameter("glitch", _glitch)
	vhs_mat.set_shader_parameter("stopfx", stopfx)
	vhs_mat.set_shader_parameter("bw", bw)
	vhs_mat.set_shader_parameter("desat", desat)
	vhs_mat.set_shader_parameter("hurt", hurt)
	vhs_mat.set_shader_parameter("hurt_flash", hurt_flash)
	vhs_mat.set_shader_parameter("fade_col", fade_col)


## Редкие случайные сбои ленты (раз в 1–3 минуты, пока идёт запись): короткий срыв трекинга
func _update_glitch(dt: float) -> void:
	_glitch = move_toward(_glitch, 0.0, dt * 1.3)
	if osd == null or not osd.shown or get_tree().paused:
		return
	_glitch_t -= dt
	if _glitch_t <= 0.0:
		_glitch_t = randf_range(60.0, 180.0)
		_glitch = randf_range(0.4, 0.85)


## Автоирис: по экспонометру быстро прикрывается на ярком (лампы в кадре), медленно открывается, чуть перелетает
func _update_iris(dt: float) -> void:
	_meter_request()
	var target := 1.0
	if auto_iris and _meter_ok:
		# норма — средняя яркость около 0.5; пересвет (лампы) прикрывает сильнее
		target = clampf(minf(1.0, 0.52 / maxf(meter_avg, 0.05)) / (1.0 + 2.4 * meter_hot), 0.4, 1.0)
	var closing := target < iris
	var w := 7.5 if closing else 1.6
	var z := 0.55 if closing else 0.75
	_iris_v += (w * w * (target - iris) - 2.0 * z * w * _iris_v) * dt
	iris = clampf(iris + _iris_v * dt, 0.3, 1.1)


## Автоусиление (AGC) во всех сценах: когда кадр темнее нормы и ирис уже открыт, усиление растёт — картинка
## светлеет и шумит. Сцены могут требовать больше (Комплекс, фары грузовика): итог — max(gain сцены, agc).
## Экспонометр стоит до ириса и усиления, поэтому петли нет: AGC не раскачивается.
func _update_agc(dt: float) -> void:
	if fade_col.a < 0.9:                # в затемнении держим (не «качать» на чёрном кадре перехода)
		var target := 1.0
		if auto_gain and _meter_ok and scene != null:
			# лампы в кадре прикрывают усиление (камера держит яркое)
			var m := maxf(meter_avg + meter_hot * 0.8, 0.02)
			target = clampf(AGC_REF / m, 1.0, AGC_MAX)
		# бытовая AGC медленная: поднимается за пару секунд, падает быстрее (вошли в свет — не пересвечивать)
		var rate := 0.8 if target > agc else 2.4
		agc = lerpf(agc, target, minf(1.0, dt * rate))
	gain_eff = maxf(gain, agc)


## Солнце в кадре — для вертикального смаза ПЗС (camera.gdshader sun): направленный свет сцены, достаточно
## сильный, чтобы быть солнцем (парк, дневные концовки). В Комплексе направленного света нет — смаза нет.
func _update_sun(dt: float) -> void:
	var sv := Vector3.ZERO
	# сцена сменилась — искать заново (по id: прежняя сцена уже может быть удалена)
	var sid := scene.get_instance_id() if scene != null else 0
	if sid != _sun_scene_id:
		_sun_scene_id = sid
		_sun_light = null
		_sun_look = 0.0
	if not is_instance_valid(_sun_light):
		_sun_light = null
	if _sun_light == null and scene != null and Game.state in ["park", "ending", "gallery"]:
		# сцены ставят свет в _ready/begin — ищем раз в секунду, пока не найдём
		_sun_look -= dt
		if _sun_look <= 0.0:
			_sun_look = 1.0
			for n in scene.find_children("*", "DirectionalLight3D", true, false):
				var l := n as DirectionalLight3D
				if l.light_energy >= 1.0:
					_sun_light = l
					break
	var src_sun := Vector3.ZERO         # то же солнце в кадре мира (UV до объектива) — для «горячего» в Glow1
	var c := vp.get_camera_3d()
	if _sun_light != null and c != null and _sun_light.is_visible_in_tree():
		# свет идёт вдоль -Z — солнце в стороне +Z
		var far_p := c.global_position + _sun_light.global_transform.basis.z.normalized() * 1000.0
		if not c.is_position_behind(far_p):
			var vs := Vector2(vp.size)
			var uv := c.unproject_position(far_p) / vs
			var a := vs.x / vs.y
			var qv := (uv - Vector2(0.5, 0.5)) * Vector2(a, 1.0)
			# обратная бочка: где солнце на выходе камеры (несколько итераций — бочка слабая)
			var rc2 := (a * a + 1.0) * 0.25
			var pp := qv
			for i in 4:
				pp = qv * (1.0 + DISTORT * rc2) / (1.0 + DISTORT * pp.length_squared())
			var edge := maxf(absf(uv.x - 0.5), absf(uv.y - 0.5))
			sv = Vector3(pp.x, pp.y, 1.0 - smoothstep(0.47, 0.5, edge))
			src_sun = Vector3(uv.x, uv.y, sv.z)
	cam_mat.set_shader_parameter("sun", sv)
	_glow1_mat.set_shader_parameter("sun_src", src_sun)


## Смерть (hurt = 1): красный кадр хранит след последнего кадра — матрица им «выжжена». Кадр снимается один раз,
## в первый же кадр смерти (картинка Lag ещё прежняя: красный экран и пустая сцена появятся позже), и медленно
## тает, но не до конца. Можно вызвать и раньше (Game.die — до красного экрана): повторно не снимает.
func freeze_still() -> void:
	if _still != null:
		return
	var img := _lag_vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	_still = ImageTexture.create_from_image(img)
	_still_amt = 0.8
	cam_mat.set_shader_parameter("still_tex", _still)


func _update_still(dt: float) -> void:
	if hurt >= 0.999:
		freeze_still()
		_still_amt = move_toward(_still_amt, 0.3, dt * 0.12)
	elif _still != null:
		_still = null
		_still_amt = 0.0
	cam_mat.set_shader_parameter("still_amt", _still_amt if _still != null else 0.0)


## Асинхронное чтение экспонометра (16×12) с видеокарты — без остановки конвейера
func _meter_request() -> void:
	if not _meter_ok:
		return
	if _meter_busy:
		# ответ потерялся (вьюпорт пересоздан и т. п.) — через секунду спросить заново
		_meter_busy_frames += 1
		if _meter_busy_frames < 60:
			return
	_meter_busy_frames = 0
	_meter_wait -= 1
	if _meter_wait > 0:
		return
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		_meter_ok = false
		return
	var rid := RenderingServer.texture_get_rd_texture(_meter_vp.get_texture().get_rid())
	if not rid.is_valid():
		return
	_meter_busy = true
	if rd.texture_get_data_async(rid, 0, _on_meter) != OK:
		_meter_busy = false
		_meter_ok = false


func _on_meter(data: PackedByteArray) -> void:
	_meter_busy = false
	_meter_busy_frames = 0
	_meter_wait = 2
	var n := METER.x * METER.y
	if data.size() < n * 4:
		return
	var sl := 0.0
	var sh := 0.0
	var sw := 0.0
	for y in METER.y:
		for x in METER.x:
			var i := (y * METER.x + x) * 4
			# центровзвешенный замер, как у бытовых камер
			var dx := (x + 0.5) / METER.x - 0.5
			var dy := (y + 0.5) / METER.y - 0.5
			var w := 1.0 / (1.0 + 7.0 * (dx * dx + dy * dy))
			sl += data[i] / 255.0 * w
			sh += data[i + 1] / 255.0 * w
			sw += w
	meter_avg = sl / sw
	meter_hot = sh / sw


func screenshot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)


## 3D-мир живёт в SubViewport без контейнера — сам он ввод не получает, передаём вручную
## (обзор мышью у героя, G — свободная камера). Меню и пауза (Game) получают событие как раньше.
func _unhandled_input(e: InputEvent) -> void:
	if vp != null:
		vp.push_input(e)
