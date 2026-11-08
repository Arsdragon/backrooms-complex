extends Node
## Звук: шины, загрузка сгенерированных звуков (res://audio), разовые и зацикленные звуки.
## Звуки с суффиксом _N (step_carpet_1, step_carpet_2…) — варианты одного звука, play("step_carpet") берёт случайный.

var streams := {}      # имя -> AudioStream
var groups := {}       # префикс -> Array[String]
var loops := {}        # id -> {p: AudioStreamPlayer, target: float, speed: float}
var _lp: AudioEffectLowPassFilter
var _muffle := 0.0
var _muffle_target := 0.0
var _reverb: AudioEffectReverb


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_all()
	Cfg.changed.connect(_apply_volumes)
	_apply_volumes()


func _setup_buses() -> void:
	for b in ["Amb", "Sfx", "Voice", "World"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	# «World» — звуки мира с лёгкой реверберацией пустых комнат
	var wi := AudioServer.get_bus_index("World")
	AudioServer.set_bus_send(wi, "Sfx")
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.55
	_reverb.damping = 0.6
	_reverb.wet = 0.18
	_reverb.dry = 1.0
	_reverb.spread = 0.8
	AudioServer.add_bus_effect(wi, _reverb)
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, _lp)
	var lim := AudioEffectHardLimiter.new()
	AudioServer.add_bus_effect(0, lim)


func set_reverb(room: float, wet: float) -> void:
	_reverb.room_size = room
	_reverb.wet = wet


func _apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Cfg.vol_master, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Sfx"), linear_to_db(maxf(Cfg.vol_sfx, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Amb"), linear_to_db(maxf(Cfg.vol_amb, 0.0001)))


func _load_all() -> void:
	var files: PackedStringArray
	if ResourceLoader.has_method("list_directory"):
		files = ResourceLoader.list_directory("res://audio/")
	else:
		files = DirAccess.get_files_at("res://audio/")
	for f in files:
		var fn := String(f)
		if fn.ends_with(".import") or fn.ends_with(".remap"):
			fn = fn.get_basename()
		if not (fn.ends_with(".ogg") or fn.ends_with(".wav")):
			continue
		var nm := fn.get_basename()
		if streams.has(nm):
			continue
		var st: AudioStream = load("res://audio/" + fn)
		if st == null:
			continue
		streams[nm] = st
		var base := nm
		var us := nm.rfind("_")
		if us > 0 and nm.substr(us + 1).is_valid_int():
			base = nm.substr(0, us)
		if not groups.has(base):
			groups[base] = []
		(groups[base] as Array).append(nm)


func has(name: String) -> bool:
	return streams.has(name) or groups.has(name)


func get_stream(name: String) -> AudioStream:
	if groups.has(name):
		var g: Array = groups[name]
		return streams[g[randi() % g.size()]]
	return streams.get(name)


## Неместный (2D) звук
func play(name: String, vol_db := 0.0, pitch := 1.0, bus := "Sfx") -> AudioStreamPlayer:
	var st := get_stream(name)
	if st == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = bus
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
	return p


## Звук в точке мира. parent — узел мира (сцена), чтобы звук удалялся вместе со сценой.
func play_at(name: String, pos: Vector3, parent: Node, vol_db := 0.0, pitch := 1.0, max_dist := 60.0, unit := 3.0, bus := "World") -> AudioStreamPlayer3D:
	var st := get_stream(name)
	if st == null or parent == null or not is_instance_valid(parent):
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = unit
	p.max_distance = max_dist
	p.bus = bus
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -18.0
	parent.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	return p


## Зацикленный фоновый звук с плавной громкостью. vol — линейная 0..1
func loop(id: String, name: String, vol := 1.0, fade := 1.5, bus := "Amb", pitch := 1.0) -> void:
	var L: Dictionary = loops.get(id, {})
	if L.is_empty() or (L.p as AudioStreamPlayer).stream != get_stream(name):
		if not L.is_empty():
			(L.p as AudioStreamPlayer).queue_free()
		var st := get_stream(name)
		if st == null:
			return
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.bus = bus
		p.volume_db = -60.0
		p.pitch_scale = pitch
		add_child(p)
		p.play()
		L = {"p": p, "v": 0.0, "target": vol, "speed": 1.0 / maxf(fade, 0.01)}
		loops[id] = L
	else:
		L.target = vol
		L.speed = 1.0 / maxf(fade, 0.01)
		(L.p as AudioStreamPlayer).pitch_scale = pitch


func loop_vol(id: String, vol: float, fade := 0.5) -> void:
	if loops.has(id):
		var L: Dictionary = loops[id]
		L.target = vol
		L.speed = 1.0 / maxf(fade, 0.01)


func loop_pitch(id: String, pitch: float) -> void:
	if loops.has(id):
		(loops[id].p as AudioStreamPlayer).pitch_scale = pitch


func stop_loop(id: String, fade := 1.0) -> void:
	loop_vol(id, 0.0, fade)
	if loops.has(id):
		loops[id]["kill"] = true


func stop_all(fade := 0.5) -> void:
	for id in loops.keys():
		stop_loop(id, fade)


## Приглушить весь звук (обморок, вода, смерть). 0 — нет, 1 — сильно
func muffle(amount: float, instant := false) -> void:
	_muffle_target = clampf(amount, 0.0, 1.0)
	if instant:
		_muffle = _muffle_target


func _process(dt: float) -> void:
	for id in loops.keys():
		var L: Dictionary = loops[id]
		var p: AudioStreamPlayer = L.p
		var v: float = L.v
		var tgt: float = L.target
		v = move_toward(v, tgt, float(L.speed) * dt)
		L.v = v
		p.volume_db = linear_to_db(maxf(v, 0.0001))
		if v <= 0.0001 and L.get("kill", false):
			p.queue_free()
			loops.erase(id)
	_muffle = move_toward(_muffle, _muffle_target, dt * 1.5)
	_lp.cutoff_hz = lerpf(20000.0, 350.0, pow(_muffle, 0.5))
