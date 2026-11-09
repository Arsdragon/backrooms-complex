extends Node
## Ход игры: меню → заставка → парк → провал → Комплекс → выход (концовка) или смерть.

const WorldGenS := preload("res://src/world/worldgen.gd")
const ComplexS := preload("res://src/world/complex.gd")
const ParkS := preload("res://src/scenes/park.gd")
const EndingS := preload("res://src/scenes/endings.gd")
const MenuS := preload("res://src/ui/menus.gd")
const NoteView := preload("res://src/ui/note_view.gd")
const CardS := preload("res://src/ui/card.gd")
const LifeformS := preload("res://src/world/lifeform.gd")
const StalkerS := preload("res://src/world/stalker.gd")

var main: Node = null
var state := "boot"
var seed := 0
var layers: Array = []
var _gen_task := -1
var _gen_result: Array = []
var _gen_mutex := Mutex.new()
var menus: Control = null
var note_view: Control = null
var complex: Node = null
var paused := false
var run_time := 0.0
var _menu_layers: Array = []
var _menu_tmp: Array = []
var mode := "base"             # мир текущей игры: base | adventure | survival | polygon
var _poly_layers: Array = []   # мир полигона (один и тот же сид, строится один раз)
var _poly_tmp: Array = []
const POLY_SEED := 1990


# ------------------------------------------------------------ правила мира

## Есть ли монстры (в «Приключении» — нет)
func monsters() -> bool:
	return mode != "adventure" and not Cfg.has_arg("no_monsters")


## Выносливость: только «Выживание» (и флажок полигона)
func stamina_on() -> bool:
	return mode == "survival" or Cfg.has_arg("stamina")


## Множитель скорости героя: «Приключение» — в полтора раза быстрее
func speed_mode() -> float:
	return 1.5 if (mode == "adventure" or Cfg.has_arg("fast")) else 1.0


## Свободная камера по G
func freecam_ok() -> bool:
	return mode == "adventure" or mode == "polygon" or Cfg.has_arg("freecam")


func survival() -> bool:
	return mode == "survival"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.global_shader_parameter_set("g_time", 0.0)


func boot() -> void:
	menus = MenuS.new()
	main.ui.add_child(menus)
	note_view = NoteView.new()
	main.ui.add_child(note_view)
	if Cfg.has_arg("world"):
		mode = Cfg.arg("world")
	var sc := Cfg.arg("scene", "")
	if sc == "complex" or sc == "lower":
		seed = int(Cfg.arg("seed", "1990"))
		_gen_result = WorldGenS.generate(seed)
		layers = _gen_result
		start_complex(sc == "lower")
	elif sc == "park":
		seed = int(Cfg.arg("seed", "1990"))
		_start_gen()
		start_park()
	elif sc == "gallery":
		if mode == "polygon":
			state = "gallery"
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		main.set_scene(load("res://src/scenes/gallery.gd").new())
	elif sc == "ending":
		seed = 1
		start_ending(Cfg.arg("kind", "ocean"))
	else:
		go_menu()


# ------------------------------------------------------------ генерация в фоне

func _start_gen() -> void:
	_gen_result = []
	_gen_task = WorkerThreadPool.add_task(_gen_job.bind(seed))


func _gen_job(s: int) -> void:
	var r := WorldGenS.generate(s)
	_gen_mutex.lock()
	_gen_result = r
	_gen_mutex.unlock()


func gen_ready() -> bool:
	_gen_mutex.lock()
	var ok := not _gen_result.is_empty()
	_gen_mutex.unlock()
	return ok


func _wait_gen() -> void:
	if _gen_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
	layers = _gen_result


# ------------------------------------------------------------ меню

func go_menu() -> void:
	state = "menu"
	ComplexS.Props.park_mode = false
	set_paused(false)
	Snd.stop_all(0.5)
	Snd.muffle(0.0)
	main.stopfx = 0.0
	main.bw = 0.0
	main.desat = 0.0
	main.hurt = 0.0
	main.hurt_flash = 0.0
	RenderingServer.global_shader_parameter_set("g_power", 1.0)
	main.interference = 0.0
	main.set_fade(Color(0, 0, 0, 1))
	main.osd.shown = false
	main.osd.cam_label = ""
	main.subs.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _menu_layers.is_empty():
		# фон меню строится в потоке, меню доступно сразу
		if mode == "polygon":
			menus.show_polygon()
		else:
			menus.show_main()
		var task := WorkerThreadPool.add_task(func() -> void: _menu_tmp = [WorldGenS.layer0(4242)])
		while not WorkerThreadPool.is_task_completed(task):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		_menu_layers = _menu_tmp
		if state != "menu":
			return
	var cx := ComplexS.new()
	main.set_scene(cx)
	complex = null
	var L: LayerData = _menu_layers[0]
	cx.setup(_menu_layers, 0, L.places["spawn"] + Vector3(0, 0, 0), 0.6, true)
	if mode == "polygon":
		menus.show_polygon()
	else:
		menus.show_main()
	main.fade_to(Color(0, 0, 0, 0), 1.5)
	_debug_menu()
	Snd.loop("menu_hum", "hum_fluor", 0.5, 2.0)


func new_game(world := "base") -> void:
	mode = world
	Cfg.flags = {}
	state = "intro"
	menus.hide_all()
	seed = randi() % 1000000
	_start_gen()
	Snd.stop_loop("menu_hum", 0.6)
	var tw: Tween = main.fade_to(Color(0, 0, 0, 1), 0.8)
	await tw.finished
	main.set_scene(null)
	menus.show_intro(Loc.t("ui.intro"))
	Snd.play("tape_insert", -4.0)
	await get_tree().create_timer(3.6).timeout
	menus.hide_all()
	start_park()


# ------------------------------------------------------------ парк

func start_park() -> void:
	state = "park"
	run_time = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var p := ParkS.new()
	main.set_scene(p)
	main.osd.shown = true
	main.osd.rec = true
	main.osd.date_reset = false
	main.osd.date_key = "osd.date_park"
	main.osd.clock = 16.0 * 3600.0 + 12.0 * 60.0
	main.osd.battery = 1.0
	main.gain = 1.0
	main.interference = 0.0
	Snd.play("rec_beep", -6.0)
	main.fade_to(Color(0, 0, 0, 0), 1.2)
	menus.flash_controls()


## Вызывается парком, когда герой проваливается сквозь землю
func fall_from_park() -> void:
	if state != "park":
		return
	state = "falling"
	# ждём мир (обычно давно готов)
	while not gen_ready():
		await get_tree().process_frame
	_wait_gen()
	start_complex(false, true)


# ------------------------------------------------------------ Комплекс

func start_complex(lower := false, from_fall := false) -> void:
	state = "complex"
	main.hurt = 0.0
	ComplexS.Props.park_mode = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var cx := ComplexS.new()
	main.set_scene(cx)
	complex = cx
	var L: LayerData = layers[0]
	var sp: Vector3 = L.places["spawn"]
	var start_layer := 0
	if lower:
		start_layer = 1
		var L1: LayerData = layers[1]
		var dc: Vector2i = L1.places["drop_center"]
		sp = Vector3((dc.x + 0.5) * LayerData.C, L1.floor_y, (dc.y + 0.5) * LayerData.C)
	if Cfg.has_arg("place"):
		var Lp: LayerData = layers[start_layer]
		var pv: Variant = Lp.places.get(Cfg.arg("place"))
		if pv is Array and not (pv as Array).is_empty():
			pv = (pv as Array)[0]
		if pv is Vector3:
			sp = pv
		elif pv is Vector2i:
			sp = Vector3(((pv as Vector2i).x + 0.5) * LayerData.C, Lp.floor_y, ((pv as Vector2i).y + 0.5) * LayerData.C)
		sp += Vector3(float(Cfg.arg("dx", "0")), 0, float(Cfg.arg("dz", "0")))
	if Cfg.has_arg("pos"):
		var pp := Cfg.arg("pos").split(",")
		sp = Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
	var yaw := float(Cfg.arg("yaw", "0.0"))
	cx.setup(layers, start_layer, sp + Vector3(0, 1.6 if from_fall else 0.05, 0), yaw)
	if Cfg.has_arg("pitch"):
		cx.player.set_look(yaw, float(Cfg.arg("pitch")))
	if Cfg.has_arg("vhs"):
		Cfg.vhs = float(Cfg.arg("vhs"))
	if Cfg.has_arg("tour"):
		cx._tour(Cfg.arg("tour"))
	main.osd.shown = true
	main.osd.date_key = "osd.date_park"
	main.osd.date_reset = true
	# монстры: в «Приключении» их нет, в «Выживании» на нижнем слое две плачущие копии
	if monsters():
		var lf := LifeformS.new()
		cx.add_child(lf)
		lf.setup(cx)
		cx.entities.append(lf)
		cx.listeners.append(lf)
		if layers.size() > 1:
			for k in (2 if survival() else 1):
				var st := StalkerS.new()
				st.extra = k > 0
				cx.add_child(st)
				st.setup(cx)
				cx.entities.append(st)
				cx.listeners.append(st)
	if from_fall:
		cx.landing_intro()
	else:
		main.fade_to(Color(0, 0, 0, 0), 0.6)
	if Cfg.has_arg("fc_test"):
		_fc_test()
	if Cfg.has_arg("walk"):
		_walk_test(float(Cfg.arg("walk")))
	if Cfg.has_arg("hurt"):
		cx.hurt = float(Cfg.arg("hurt"))
		cx._hurt_cd = 9999.0


## Отладка: --walk=<сек> — встать лицом к центру места (--place) и идти вперёд, печатая высоту и ранение
func _walk_test(sec: float) -> void:
	await get_tree().create_timer(float(Cfg.arg("walk_delay", "1.5"))).timeout
	var cx: Node = complex
	var pl: Player = cx.get("player")
	var L: LayerData = layers[cx.cur]
	var key := Cfg.arg("place", "")
	if L.places.has(key + "_c"):
		var c: Vector3 = cx.wrap_near(L.places[key + "_c"], pl.global_position)
		var v := c - pl.global_position
		pl.set_look(atan2(-v.x, -v.z), 0.0)
	if Cfg.has_arg("run"):
		Input.action_press("run")
	Input.action_press("move_f")
	var t := 0.0
	while t < sec:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if complex == null or not is_instance_valid(complex):
			print("WALK t=%.1f state=%s" % [t, state])
			break
		print("WALK t=%.1f pos=(%.1f, %.2f, %.1f) hurt=%.2f" % [t, pl.global_position.x, pl.global_position.y, pl.global_position.z, complex.hurt])
	Input.action_release("move_f")
	Input.action_release("run")


## Отладка: --fc_test — через 2 с нажать G и 2,5 с лететь вперёд и вверх (проверка свободной камеры)
func _fc_test() -> void:
	await get_tree().create_timer(2.0).timeout
	if complex != null and is_instance_valid(complex):
		var p0: Player = complex.get("player")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var mm := InputEventMouseMotion.new()
		mm.relative = Vector2(200, 0)
		Input.parse_input_event(mm)
		await get_tree().create_timer(0.3).timeout
		print("FC yaw after mouse = ", p0.yaw)
	var ev := InputEventAction.new()
	ev.action = "freecam"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.2).timeout
	Input.action_press("move_f")
	Input.action_press("fly_up")
	Input.action_press("run")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("move_f")
	Input.action_release("fly_up")
	Input.action_release("run")
	if complex != null and is_instance_valid(complex):
		var pl: Player = complex.get("player")
		print("FC body=", pl.global_position, " cam=", pl.view_pos(), " freecam=", pl.freecam != null)


func _process(dt: float) -> void:
	if state == "complex" and not paused:
		run_time += dt
	if main == null:
		return
	var p: Player = null
	if complex != null and is_instance_valid(complex):
		p = complex.get("player")
	elif main.scene != null and main.scene.get("player") != null:
		p = main.scene.get("player")
	if p != null and is_instance_valid(p) and not paused and note_view != null and not note_view.visible:
		main.subs.hint(p.interact_hint)
	else:
		main.subs.hint("")


func _exit_tree() -> void:
	if _gen_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1


func _unhandled_input(e: InputEvent) -> void:
	if main == null or note_view == null:
		return
	if e.is_action_pressed("pause"):
		if note_view.visible:
			note_view.close()
			get_viewport().set_input_as_handled()
			return
		if state in ["park", "complex"] or (mode == "polygon" and state in ["ending", "gallery"]):
			set_paused(not paused)
			get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("use") and not paused:
		if note_view.visible:
			note_view.close()
			get_viewport().set_input_as_handled()
			return
		var p: Player = null
		if main.scene != null:
			p = main.scene.get("player")
		if p != null and is_instance_valid(p) and not p.frozen:
			if p.try_interact():
				get_viewport().set_input_as_handled()


func set_paused(v: bool) -> void:
	paused = v
	get_tree().paused = v
	if main != null:
		main.vp.process_mode = Node.PROCESS_MODE_PAUSABLE
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		menus.show_pause()
		Snd.muffle(0.7)
	else:
		menus.hide_all()
		Snd.muffle(0.0)
		if state in ["park", "complex", "ending", "gallery"]:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------ тексты

func say(key: String, who := "") -> void:
	if main != null:
		main.subs.say(Loc.t(key), 0.0, who)


func subs_clear() -> void:
	if main != null:
		main.subs.clear()


func show_note(key: String) -> void:
	Snd.play("paper", -6.0)
	note_view.open(Loc.t(key), key.begins_with("note.a_") or key == "note.u01" or key == "note.u04")


# ------------------------------------------------------------ концовки и смерть

func die() -> void:
	if state != "complex":
		return
	state = "dead"
	print("DIE")
	Snd.stop_all(0.05)
	Snd.play("death_hit", 2.0)
	main.set_fade(Color(0.62, 0.0, 0.0, 1.0))
	main.subs.clear()
	main.osd.shown = false
	await get_tree().create_timer(0.35).timeout
	main.set_scene(null)
	complex = null
	Snd.loop("death_drone", "death_drone", 0.6, 0.5)
	await get_tree().create_timer(3.8).timeout
	Snd.stop_loop("death_drone", 1.0)
	main.fade_to(Color(0, 0, 0, 1), 1.0)
	await get_tree().create_timer(1.1).timeout
	go_menu()


## kind: "null" (случайный выход) или "async"
func ending(kind: String) -> void:
	if state != "complex":
		return
	state = "ending"
	var k := kind
	if kind == "null":
		# случайный выход всегда смертелен
		var r := randf()
		if r < 0.2:
			k = "ocean"
		elif r < 0.38:
			k = "sky"
		elif r < 0.55:
			k = "basement"
		elif r < 0.7:
			k = "highway"
		elif r < 0.84:
			k = "wall"
		else:
			k = "space"
		if Cfg.has_arg("force_end"):
			k = Cfg.arg("force_end")
	start_ending(k)


func start_ending(k: String) -> void:
	state = "ending"
	complex = null
	var e := EndingS.new()
	e.kind = k
	main.set_scene(e)
	e.begin()


func show_card(k: String) -> void:
	state = "card"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var c := CardS.new()
	main.ui.add_child(c)
	c.open(Loc.t("end.%s_t" % k), Loc.t("end." + k))
	await c.closed
	c.queue_free()
	main.fade_to(Color(0, 0, 0, 1), 0.6)
	await get_tree().create_timer(0.7).timeout
	go_menu()


# ------------------------------------------------------------ полигон

var _debug_done := false


## Отладка: --menu=worlds|polygon|rooms — открыть экран меню; --poly=<действие> — запуск из полигона:
## park | l0 | l1 | place:<ключ>[:1] | ending:<вид> | death | gallery:<набор>
func _debug_menu() -> void:
	if _debug_done:
		return
	_debug_done = true
	match Cfg.arg("menu", ""):
		"worlds":
			menus.show_worlds()
		"polygon":
			mode = "polygon"
			menus.show_polygon()
		"rooms":
			mode = "polygon"
			menus.show_rooms()
	if not Cfg.has_arg("poly"):
		return
	var a := Cfg.arg("poly").split(":")
	await get_tree().create_timer(0.5).timeout
	match a[0]:
		"park":
			poly_park()
		"l0":
			poly_complex(false)
		"l1":
			poly_complex(true)
		"place":
			poly_complex(a.size() > 2 and a[2] == "1", a[1])
		"ending":
			poly_ending(a[1])
		"death":
			poly_death()
		"gallery":
			poly_gallery(a[1])

## Мир полигона: строится в фоне один раз, потом переиспользуется
func _poly_world() -> void:
	if not _poly_layers.is_empty():
		return
	menus.show_intro_static(Loc.t("poly.loading"))
	var task := WorkerThreadPool.add_task(func() -> void: _poly_tmp = WorldGenS.generate(POLY_SEED))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_poly_layers = _poly_tmp


## Общая подготовка запуска из полигона: флаги-переключатели + свои параметры
func _poly_begin(extra: Dictionary) -> void:
	mode = "polygon"
	state = "poly_load"
	menus.hide_all()
	Snd.stop_loop("menu_hum", 0.4)
	Cfg.flags = menus.poly_flags()
	for k in extra.keys():
		Cfg.flags[k] = extra[k]
	var tw: Tween = main.fade_to(Color(0, 0, 0, 1), 0.4)
	await tw.finished
	main.set_scene(null)
	main.subs.clear()


func poly_complex(lower: bool, place := "", extra := {}) -> void:
	var ex := extra.duplicate()
	if place != "":
		ex["place"] = place
	await _poly_begin(ex)
	await _poly_world()
	menus.hide_all()
	seed = POLY_SEED
	layers = _poly_layers
	run_time = 0.0
	main.osd.battery = 1.0
	start_complex(lower)


func poly_park() -> void:
	await _poly_begin({})
	await _poly_world()
	menus.hide_all()
	seed = POLY_SEED
	_gen_task = -1
	_gen_result = _poly_layers
	start_park()


func poly_ending(k: String) -> void:
	await _poly_begin({})
	start_ending(k)


func poly_death() -> void:
	await _poly_begin({})
	state = "complex"
	die()


func poly_gallery(set_name: String) -> void:
	await _poly_begin({"set": set_name})
	state = "gallery"
	main.osd.shown = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	main.set_scene(load("res://src/scenes/gallery.gd").new())


## Выйти из полигона в главное меню
func leave_polygon() -> void:
	mode = "base"
	Cfg.flags = {}
	menus.show_main()
