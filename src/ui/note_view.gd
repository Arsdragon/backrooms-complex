extends Control
## Чтение записки: листок бумаги поверх кадра. Мир не на паузе — читать в темноте опасно.

var paper: PanelContainer
var text: Label
var hint: Label
var _player: Player = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	paper = PanelContainer.new()
	var sb := StyleBoxTexture.new()
	sb.texture = Mats.tex("paper")
	sb.content_margin_left = 46
	sb.content_margin_right = 46
	sb.content_margin_top = 40
	sb.content_margin_bottom = 40
	paper.add_theme_stylebox_override("panel", sb)
	paper.anchor_left = 0.27
	paper.anchor_right = 0.73
	paper.anchor_top = 0.08
	paper.anchor_bottom = 0.88
	paper.rotation = -0.012
	add_child(paper)
	text = Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.add_theme_color_override("font_color", Color(0.12, 0.1, 0.1))
	paper.add_child(text)
	hint = Label.new()
	hint.anchor_left = 0.3
	hint.anchor_right = 0.7
	hint.anchor_top = 0.91
	hint.anchor_bottom = 0.96
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85, 0.85))
	add_child(hint)
	visible = false


func open(t: String, typed: bool) -> void:
	var f := SystemFont.new()
	if typed:
		f.font_names = PackedStringArray(["Courier New", "Consolas", "monospace"])
		f.font_weight = 700
		text.add_theme_font_size_override("font_size", 19)
	else:
		f.font_names = PackedStringArray(["Segoe Print", "Ink Free", "Comic Sans MS", "sans-serif"])
		text.add_theme_font_size_override("font_size", 21)
	text.add_theme_font_override("font", f)
	text.text = t
	hint.text = Loc.t("ui.close")
	visible = true
	if Game.main != null and Game.main.scene != null:
		_player = Game.main.scene.get("player")
		if _player != null:
			_player.frozen = true


func close() -> void:
	visible = false
	Snd.play("paper", -10.0)
	if _player != null and is_instance_valid(_player):
		_player.frozen = false
	_player = null
