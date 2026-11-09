extends Node3D
## Отладка: все копии, предметы и Сущность в ряд при ровном свете. --scene=gallery --set=copies|objects|lifeform|async|tv

const Props := preload("res://src/world/props.gd")
const LifeformS := preload("res://src/world/lifeform.gd")

var player = null
var cam: Camera3D


func _ready() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.09, 0.05)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 3.0
	e.glow_enabled = true
	we.environment = e
	add_child(we)
	RenderingServer.global_shader_parameter_set("g_fog", Vector4(0.1, 0.09, 0.05, 0.01))
	RenderingServer.global_shader_parameter_set("g_ambient", 0.02)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 40)
	fl.mesh = pm
	fl.material_override = Props.m_carpet()
	add_child(fl)
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(80, 2.7, 0.2)
	wall.mesh = wm
	wall.material_override = Props.m_wall()
	wall.position = Vector3(0, 1.35, -2.0)
	add_child(wall)
	var set_name := Cfg.arg("set", "copies")
	var items := []
	match set_name:
		"copies":
			var whos := ["jogger", "mother", "kid", "oldman", "couple", "suit", "vendor", "teen", "explorer", "player"]
			var wr := ["none", "stretch", "twist", "arms", "flat", "corner", "sunk", "hstretch", "back", "wall"]
			for i in whos.size():
				items.append({"k": "copy", "who": whos[i], "wrong": wr[i], "seed": i * 7 + 1, "react": false})
		"copies2":
			var w2 := ["melt_bench", "stroller_fused", "fused", "ceiling", "fused_floor", "seated_air"]
			var who2 := ["oldman", "mother", "couple", "suit", "civ_a", "teen"]
			for i in w2.size():
				items.append({"k": "copy", "who": who2[i], "wrong": w2[i], "seed": i * 5 + 3, "react": false})
		"objects":
			for w in ["bench", "lamp", "bin", "tree", "fountain", "slide", "swing", "cart", "car", "stroller", "chair", "desk", "cabinet", "tv", "hill_chair"]:
				items.append({"k": "obj", "what": w, "wrong": "none"})
		"tv":
			for ch in ["async_ad", "news", "explorers", "home", "weather", "bars"]:
				items.append({"k": "tv_on", "ch": ch})
		"async":
			for w in ["lamp_stand", "case", "case_open", "crate", "table", "spool", "generator", "board", "rover", "cones", "tripod", "radio", "winch"]:
				items.append({"k": "async", "what": w})
			items.append({"k": "threshold"})
			items.append({"k": "nest"})
			items.append({"k": "null", "id": "null_x"})
	if set_name.begins_with("models"):
		var ids := []
		for d in DirAccess.get_directories_at("res://models"):
			ids.append(String(d))
		ids.sort()
		var part := int(set_name.substr(6)) if set_name.length() > 6 else 0
		ids = ids.slice(part * 11, part * 11 + 11)
		var mx := -float(ids.size() - 1) * 1.1
		for id in ids:
			var m := Models.make(id, true)
			if m == null:
				continue
			add_child(m)
			m.position = Vector3(mx, 0, 0)
			Props.set_light(m, Color(0.45, 0.0, 0.0, 0.0))
			var lb := Props.label(id, Props.font_sign(), 0.0022, Color(1, 1, 1))
			lb.position = Vector3(mx, 0.05, 0.9)
			lb.rotation.x = -0.6
			add_child(lb)
			mx += 2.2
		cam = Camera3D.new()
		add_child(cam)
		cam.fov = 60.0
		cam.position = Vector3(0, 2.2, 13.0)
		cam.look_at(Vector3(0, 0.8, 0))
		cam.current = true
		if Game.main != null:
			Game.main.osd.shown = false
			Game.main.set_fade(Color(0, 0, 0, 0))
		return
	var x := -float(items.size() - 1) * 1.6
	for d in items:
		var dd: Dictionary = d
		dd["p"] = Vector3(x, 0, 0)
		var n: Node3D = Props.spawn(self, dd, 0)
		if n != null:
			add_child(n)
			n.position = dd.p
			n.rotation.y = 0.0
			Props.set_light(n, Color(0.45, 0.0, 0.0, 0.0))
		x += 3.2
	if set_name == "anim":
		var spec := [["jogger", "run"], ["mother", "walk"], ["suit", "walk"], ["explorer", "walk"], ["oldman", "read"], ["teen", "sit"]]
		for k in spec.size():
			var hh := Human.make(String(spec[k][0]), 5 + k, false)
			add_child(hh)
			hh.position = Vector3(-5.0 + k * 2.0, 0, 0)
			hh.rotation.y = 0.5
			var pn: String = spec[k][1]
			if pn == "walk" or pn == "run":
				hh.pose_name = pn
			else:
				hh.pose(pn)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.8, 0.6, 0)
		add_child(sun)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.5, 0.5, 0.5)
	if set_name == "lifeform":
		for k in 3:
			var lf := LifeformS.new()
			add_child(lf)
			lf._build()
			lf.position = Vector3(-4.0 + k * 4.0, 0, 0)
			lf.cur_speed = [0.0, 1.3, 5.0][k]
			lf.state_t = 1.0
			lf._animate(0.3 + k * 0.2)
			LifeformS._apply_light(lf, Vector4(0.9, 0, 0, 0))
			for eye in lf.eyes:
				(eye as Node3D).visible = true
	cam = Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	var span := maxf(float(items.size()) * 3.2, 10.0)
	var dist := float(Cfg.arg("dist", str(minf(span * 0.75, 30.0))))
	var lx := float(Cfg.arg("cx", "0"))
	cam.position = Vector3(lx + float(Cfg.arg("ox", "0")), float(Cfg.arg("cy", "1.6")), dist)
	cam.look_at(Vector3(lx, float(Cfg.arg("ly", "1.0")), 0))
	cam.current = true
	if Game.main != null:
		Game.main.osd.shown = false
		Game.main.set_fade(Color(0, 0, 0, 0))
