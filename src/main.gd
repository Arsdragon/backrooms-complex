extends Node
## Корень: 3D-мир рендерится в маленький SubViewport (480 строк), затем «плёнка» VHS растягивает его на экран.
## Сверху — чёткий интерфейс (меню, субтитры, записки).

const VHS_SHADER := preload("res://src/shaders/vhs.gdshader")
const Osd := preload("res://src/render/osd.gd")
const Subs := preload("res://src/ui/subs.gd")

var vp: SubViewport
var screen: TextureRect
var vhs_mat: ShaderMaterial
var back: ColorRect
var ui: CanvasLayer
var fade: ColorRect
var osd: Osd
var subs: Subs
var scene: Node = null

# параметры плёнки, которые задают сцены
var gain := 1.0
var interference := 0.0
var tracking := 0.0
var _tracking_burst := 0.0
var stopfx := 0.0
var bw := 0.0
var desat := 0.0


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
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.positional_shadow_atlas_size = 1024
	vp.handle_input_locally = false
	add_child(vp)

	var sl := CanvasLayer.new()
	sl.layer = 0
	add_child(sl)
	screen = TextureRect.new()
	screen.texture = vp.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vhs_mat = ShaderMaterial.new()
	vhs_mat.shader = VHS_SHADER
	screen.material = vhs_mat
	sl.add_child(screen)

	osd = Osd.new()
	vp.add_child(osd)

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

	Cfg.changed.connect(_apply_cfg)
	get_viewport().size_changed.connect(_apply_cfg)
	_apply_cfg()
	Game.main = self
	Game.boot.call_deferred()
	if Cfg.has_arg("shot"):
		_auto_shot.call_deferred()


func _auto_shot() -> void:
	var w := float(Cfg.arg("wait", "3"))
	await get_tree().create_timer(w).timeout
	var paths := Cfg.arg("shot").split(";")
	for i in paths.size():
		if i > 0:
			await get_tree().create_timer(float(Cfg.arg("every", "1.0"))).timeout
		await RenderingServer.frame_post_draw
		screenshot(paths[i])
		print("SHOT ", paths[i], " fps=", Engine.get_frames_per_second())
	get_tree().quit()


func _apply_cfg() -> void:
	vp.size = Cfg.frame_size()
	vhs_mat.set_shader_parameter("src_size", Vector2(vp.size))


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


func fade_to(c: Color, time: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(fade, "color", c, time)
	return tw


func set_fade(c: Color) -> void:
	fade.color = c


func _process(dt: float) -> void:
	_tracking_burst = move_toward(_tracking_burst, 0.0, dt * 1.6)
	vhs_mat.set_shader_parameter("intensity", Cfg.vhs)
	vhs_mat.set_shader_parameter("gain", gain)
	vhs_mat.set_shader_parameter("interference", interference)
	vhs_mat.set_shader_parameter("tracking", maxf(tracking, _tracking_burst))
	vhs_mat.set_shader_parameter("stopfx", stopfx)
	vhs_mat.set_shader_parameter("bw", bw)
	vhs_mat.set_shader_parameter("desat", desat)


func screenshot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)


## 3D-мир живёт в SubViewport без контейнера — сам он ввод не получает, передаём вручную
## (обзор мышью у героя, G — свободная камера). Меню и пауза (Game) получают событие как раньше.
func _unhandled_input(e: InputEvent) -> void:
	if vp != null:
		vp.push_input(e)
