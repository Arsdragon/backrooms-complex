extends Node
## Настройки игрока (user://settings.cfg) и раскладка управления.

signal changed

const PATH := "user://settings.cfg"

var lang := "mixed"        # "ru" | "en" | "mixed" (интерфейс и записки по-русски, таблички и камера по-английски)
var sens := 1.0            # чувствительность мыши
var invert_y := false
var fov := 68.0
var vol_master := 0.85
var vol_sfx := 1.0
var vol_amb := 1.0
var vhs := 1.0             # сила VHS-эффекта 0..1.5
var aspect := "4:3"        # "4:3" | "16:9"
var res := 480             # высота кадра: 480 | 600 | 720
var fullscreen := true
var head_bob := true
var osd := true            # надписи видеокамеры (REC, дата)
var subtitles := true
var world := "base"        # выбор мира: "base" | "adventure" | "survival" | "polygon"

const WORLDS := ["base", "adventure", "survival", "polygon"]

## Отладочные аргументы командной строки после «--»: --key=value
var args := {}
## Флаги текущего запуска из полигона (те же ключи, что у аргументов: god, place, set, lf_now…)
var flags := {}
## Значения из файла для настроек, перекрытых аргументами (--aspect/--res/--vhs): в файл пишутся они, а не перекрытые
var _file := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			var kv := s.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_setup_input()
	load_cfg()
	_cli_overrides()
	apply()


## Отладка: --aspect=4:3|16:9, --res=480|600|720, --vhs=0..1.5 — только на этот запуск, в настройки не сохраняются
func _cli_overrides() -> void:
	if args.has("aspect") and String(args["aspect"]) in ["4:3", "16:9"]:
		_file["aspect"] = aspect
		aspect = String(args["aspect"])
	if args.has("res") and int(args["res"]) in [480, 600, 720]:
		_file["res"] = res
		res = int(args["res"])
	if args.has("vhs"):
		_file["vhs"] = vhs
		vhs = clampf(float(args["vhs"]), 0.0, 1.5)


func arg(key: String, def := "") -> String:
	return String(flags.get(key, args.get(key, def)))


func has_arg(key: String) -> bool:
	return flags.has(key) or args.has(key)


func testing() -> bool:
	return has_arg("shot") or has_arg("test") or has_arg("auto")


func load_cfg() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	lang = String(c.get_value("game", "lang", lang))
	sens = float(c.get_value("game", "sens", sens))
	invert_y = bool(c.get_value("game", "invert_y", invert_y))
	fov = float(c.get_value("game", "fov", fov))
	head_bob = bool(c.get_value("game", "head_bob", head_bob))
	subtitles = bool(c.get_value("game", "subtitles", subtitles))
	world = String(c.get_value("game", "world", world))
	vol_master = float(c.get_value("audio", "master", vol_master))
	vol_sfx = float(c.get_value("audio", "sfx", vol_sfx))
	vol_amb = float(c.get_value("audio", "amb", vol_amb))
	vhs = float(c.get_value("video", "vhs", vhs))
	aspect = String(c.get_value("video", "aspect", aspect))
	res = int(c.get_value("video", "res", res))
	fullscreen = bool(c.get_value("video", "fullscreen", fullscreen))
	osd = bool(c.get_value("video", "osd", osd))
	if not world in WORLDS:
		world = "base"
	if not lang in ["ru", "en", "mixed"]:
		lang = "mixed"
	if not res in [480, 600, 720]:
		res = 480


func save_cfg() -> void:
	if testing():
		return
	var c := ConfigFile.new()
	c.set_value("game", "lang", lang)
	c.set_value("game", "sens", sens)
	c.set_value("game", "invert_y", invert_y)
	c.set_value("game", "fov", fov)
	c.set_value("game", "head_bob", head_bob)
	c.set_value("game", "subtitles", subtitles)
	c.set_value("game", "world", world)
	c.set_value("audio", "master", vol_master)
	c.set_value("audio", "sfx", vol_sfx)
	c.set_value("audio", "amb", vol_amb)
	c.set_value("video", "vhs", _file.get("vhs", vhs))
	c.set_value("video", "aspect", _file.get("aspect", aspect))
	c.set_value("video", "res", _file.get("res", res))
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("video", "osd", osd)
	c.save(PATH)


func apply() -> void:
	if not testing():
		if fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	changed.emit()


func frame_size() -> Vector2i:
	var h := res
	var w := int(round(h * (4.0 / 3.0 if aspect == "4:3" else 16.0 / 9.0)))
	w += w % 2
	return Vector2i(w, h)


## Где кадр на экране: прямоугольник формата кадра, вписанный по центру в видимую область view
## (так же его ставит TextureRect в main.gd). Меню и подписи размещаются внутри него, а не в чёрных полях.
func frame_rect(view: Rect2) -> Rect2:
	var fs := Vector2(frame_size())
	var k := minf(view.size.x / fs.x, view.size.y / fs.y)
	var sz := fs * k
	return Rect2(view.position + (view.size - sz) * 0.5, sz)


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func _setup_input() -> void:
	_key("move_f", [KEY_W, KEY_UP])
	_key("move_b", [KEY_S, KEY_DOWN])
	_key("move_l", [KEY_A, KEY_LEFT])
	_key("move_r", [KEY_D, KEY_RIGHT])
	_key("run", [KEY_SHIFT])
	_key("crouch", [KEY_CTRL, KEY_C])
	_key("use", [KEY_E, KEY_F])
	_key("pause", [KEY_ESCAPE, KEY_P])
	_key("freecam", [KEY_G])
	_key("fly_up", [KEY_SPACE])
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("use", m)
