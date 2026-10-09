extends Control
## v0.6 prologue (序章): seven anime panels drawn by codex (art/tools/make_prologue.py, data/prologue.json).
## Each panel drifts slowly (zoom / pan) and cross-fades into the next while 空 reads his line (Qwen3-TTS,
## like every other voiced line) under the MiniMax "prologue" music. Click, Enter, Space or E moves on to the
## next panel; Esc skips to the game. --autoplay (or a missing data file) skips it.
## `-- --prologue-only` quits at the end instead of starting the game (for recording it).

const DATA := "res://data/prologue.json"
const FADE := 1.0
var panels: Array = []
var voice_who := "sora"
var _layers: Array[TextureRect] = []
var _front := 0
var _sub: Label
var _shade: TextureRect
var _hint: Label
var _next := false
var _leaving := false
var shown: Array[String] = []     # panels actually shown (the tests read this)


func _ready() -> void:
	theme = UITheme.make()
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if not FileAccess.file_exists(DATA) or "--autoplay" in OS.get_cmdline_user_args():
		_start.call_deferred()
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	panels = d.panels
	voice_who = str(d.get("voice", "sora"))
	for k in 2:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.modulate.a = 0.0
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		_layers.append(tr)
	# a soft dark band at the bottom so the subtitle reads on any picture
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.62))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	_shade = TextureRect.new()
	_shade.texture = gt
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.anchor_left = 0.0
	_shade.anchor_right = 1.0
	_shade.anchor_top = 0.72
	_shade.anchor_bottom = 1.0
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_sub = UITheme.label("", 38, Color(1.0, 0.98, 0.93))
	_sub.add_theme_constant_override("outline_size", 10)
	_sub.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.06, 0.85))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.anchor_left = 0.12
	_sub.anchor_right = 0.88
	_sub.anchor_top = 0.8
	_sub.anchor_bottom = 0.94
	_sub.modulate.a = 0.0
	add_child(_sub)
	_hint = UITheme.label("点击 / 回车 继续　Esc 跳过", 18, Color(1, 1, 1, 0.5))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.position = Vector2(-330, -40)
	add_child(_hint)
	Audio.play_amb("", 0.5)
	Audio.play_music("prologue", 1.5)
	_run()


func _run() -> void:
	for i in panels.size():
		if _leaving:
			return
		await _show(i)
	if not _leaving:
		var tw := create_tween().set_parallel()
		for n in [_layers[_front], _sub, _shade, _hint]:
			tw.tween_property(n, "modulate:a", 0.0, 1.4)
		await tw.finished
		_start()


func _show(i: int) -> void:
	var p: Dictionary = panels[i]
	shown.append(str(p.img))
	var cur := _layers[1 - _front]
	var old := _layers[_front]
	_front = 1 - _front
	move_child(cur, old.get_index())       # the new panel goes on top of the old one, under the subtitle
	cur.texture = load("res://assets/ui/prologue/%s.jpg" % p.img)
	cur.pivot_offset = size / 2.0
	var z: Array = p.get("zoom", [1.0, 1.06])
	var pan: Array = p.get("pan", [0.0, 0.0])
	var margin := 1.0 + 2.0 * maxf(absf(float(pan[0])), absf(float(pan[1])))    # never show the picture's edge
	var drift := Vector2(float(pan[0]) * size.x, float(pan[1]) * size.y)
	var line := str(p.text)
	# how long the panel stays: the line plus a breath, at least 4.5 s
	var vlen: float = Audio.voice_length(voice_who, line)
	var dur := maxf(4.5, vlen + 2.2) + float(p.get("hold", 0.0))
	cur.scale = Vector2.ONE * float(z[0]) * margin
	cur.position = -drift / 2.0
	cur.modulate.a = 0.0
	var mv := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	mv.tween_property(cur, "scale", Vector2.ONE * float(z[1]) * margin, dur + FADE)
	mv.tween_property(cur, "position", drift / 2.0, dur + FADE)
	var fd := create_tween()
	fd.tween_property(cur, "modulate:a", 1.0, FADE if i > 0 else 1.6)
	fd.tween_callback(func(): old.modulate.a = 0.0)
	var st := create_tween()
	st.tween_property(_sub, "modulate:a", 0.0, 0.3)
	st.tween_callback(func(): _sub.text = line)
	st.tween_interval(0.35)
	st.tween_property(_sub, "modulate:a", 1.0, 0.5)
	get_tree().create_timer(0.6).timeout.connect(func(): if not _leaving and shown.size() == i + 1: Audio.voice(voice_who, line))
	var t := 0.0
	_next = false
	while t < dur and not _next and not _leaving:
		await get_tree().process_frame
		t += get_process_delta_time()
	if _next:
		Audio.stop_voice()


func _unhandled_input(event: InputEvent) -> void:
	if panels.is_empty() or _leaving:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_start()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		_next = true


func _start() -> void:
	if _leaving:
		return
	_leaving = true
	Audio.stop_voice()
	if "--prologue-only" in OS.get_cmdline_user_args():
		get_tree().quit()
		return
	# The illustrated journey already reaches the house. Skipping it also skips the travel scene,
	# without claiming that a remembered fragment or the 3D bus animation was seen.
	var arrival: Dictionary = GameState.flags.get("arrival_home", {})
	if int(arrival.get("version",0)) == 1 and str(arrival.get("phase","")) == "bus":
		arrival.phase = "home"
		arrival["entry_route"] = "prologue_to_home"
	Loading.change_scene("res://scenes/main.tscn", "抵达晴町")
