extends CanvasLayer
## Красный экран смерти. Не плоская заливка поверх окна, а «записанный» кадр: красное поле со следом
## последнего кадра внутри 3D-вьюпорта; плёночный шейдер (vhs.gdshader при Game.main.hurt = 1) делает его
## красным с шумом, строками и пульсирующей виньеткой. За ~3,5 с поле темнеет, след кадра тает.
## Вешать в 3D-вьюпорт (дочерним узлом сцены концовки или в Game.main.vp); живёт, пока жив родитель.

const SHADER := preload("res://src/shaders/end_red.gdshader")

var mat: ShaderMaterial


func _ready() -> void:
	layer = 100
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	r.material = mat
	add_child(r)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("level", v), 1.0, 0.72, 3.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("ghost", v), 0.45, 0.0, 2.4)
