extends MiniGame

const CHART_PATH := "res://data/taiko_chart.json"
const ART := "res://assets/minigames/taiko/"
const HIT_X := 485.0
const LANE_Y := 390.0
const SCROLL_SPEED := 650.0
const VISIBLE_AHEAD := 1.6
const PERFECT_WINDOW := 0.050
const GOOD_WINDOW := 0.100
const EMPTY_WINDOW := 0.150

var _notes: Array = []
var _next_note := 0
var _song_t := 0.0
var _fallback_t := 0.0
var _last_audio_t := 0.0
var _audio_still_t := 0.0
var _auto_times: Array[float] = []
var _auto_skips: Array[bool] = []
var _auto_index := 0
var _combo := 0
var _max_combo := 0
var _perfects := 0
var _goods := 0
var _misses := 0
var _flash_t := 0.0
var _flash_kind := "don"
var _song: AudioStreamPlayer
var _canvas: Control
var _flash_canvas: Control
var _drum: TextureRect
var _burst: TextureRect
var _combo_label: Label
var _progress_label: Label
var _note_don: Texture2D
var _note_ka: Texture2D
var _burst_tween: Tween
var _drum_tween: Tween
var _combo_tween: Tween
var _font: Font


func mg_info() -> Dictionary:
	var chart := _read_chart()
	var count: int = Array(chart.get("notes", [])).size()
	var maximum := _maximum_score(count)
	return {
		"title": "祭典太鼓",
		"subtitle": "跟着祭囃子，敲出夏夜的节拍",
		"rules": [
			"红色咚敲鼓心，蓝色咔敲鼓边。",
			"音符到达金色圆圈时敲击：良得 100 分，可得 50 分。",
			"连续敲中 10 下后，每下再加 10 分。"
		],
		"controls": "F / J 或左键 敲鼓心  ·  D / K 或右键 敲鼓边  ·  Esc 离开",
		"stars": [ceili(maximum * 0.45), ceili(maximum * 0.70), ceili(maximum * 0.92)],
		"duration": 52.0,
		"mute_bgm": true,
		"unit": "分"
	}


func mg_build(_stage: Control) -> void:
	var chart := _read_chart()
	_notes = Array(chart.get("notes", []))
	_note_don = load(ART + "note_don.png")
	_note_ka = load(ART + "note_ka.png")
	_font = load("res://assets/fonts/LXGWWenKai-Medium.ttf")

	var background := TextureRect.new()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.texture = load(ART + "background.png")
	background.position = Vector2.ZERO
	background.size = PLAY_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)

	_canvas = Control.new()
	_canvas.size = PLAY_SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_stage)
	stage.add_child(_canvas)

	_drum = TextureRect.new()
	_drum.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drum.texture = load(ART + "drum.png")
	_drum.position = Vector2(76, 236)
	_drum.size = Vector2(306, 306)
	_drum.pivot_offset = _drum.size / 2.0
	_drum.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drum.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_drum)
	_flash_canvas = Control.new()
	_flash_canvas.size = PLAY_SIZE
	_flash_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_canvas.draw.connect(_draw_flash)
	stage.add_child(_flash_canvas)

	_burst = TextureRect.new()
	_burst.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_burst.texture = load(ART + "burst.png")
	_burst.position = Vector2(HIT_X - 112, LANE_Y - 112)
	_burst.size = Vector2(224, 224)
	_burst.pivot_offset = _burst.size / 2.0
	_burst.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst.modulate.a = 0.0
	stage.add_child(_burst)

	_progress_label = UITheme.label("", 27, Color(1.0, 0.94, 0.8))
	_progress_label.position = Vector2(458, 118)
	_progress_label.add_theme_color_override("font_outline_color", Color(0.16, 0.13, 0.26, 0.85))
	_progress_label.add_theme_constant_override("outline_size", 7)
	stage.add_child(_progress_label)

	_combo_label = UITheme.label("", 39, Color(1.0, 0.86, 0.55))
	_combo_label.position = Vector2(1110, 104)
	_combo_label.custom_minimum_size = Vector2(350, 62)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.pivot_offset = Vector2(250, 24)
	_combo_label.add_theme_color_override("font_outline_color", Color(0.18, 0.13, 0.27, 0.95))
	_combo_label.add_theme_constant_override("outline_size", 8)
	stage.add_child(_combo_label)

	_song = AudioStreamPlayer.new()
	_song.bus = "Music"
	_song.volume_db = -2.0
	stage.add_child(_song)
	_update_labels()


func mg_reset() -> void:
	if _song:
		_song.stop()
	_next_note = 0
	_song_t = 0.0
	_fallback_t = 0.0
	_last_audio_t = 0.0
	_audio_still_t = 0.0
	_auto_index = 0
	_combo = 0
	_max_combo = 0
	_perfects = 0
	_goods = 0
	_misses = 0
	_flash_t = 0.0
	_auto_times.clear()
	_auto_skips.clear()
	for i in range(_notes.size()):
		_auto_times.append(float(_notes[i].get("t", 0.0)) + rng.randf_range(-0.035, 0.035))
		_auto_skips.append(i % 17 == 9)
	if _burst:
		_burst.modulate.a = 0.0
	if _drum:
		_drum.scale = Vector2.ONE
		_drum.modulate = Color.WHITE
	_update_labels()
	if _canvas:
		_canvas.queue_redraw()
	set_status("听着祭囃子，等待第一拍")


func mg_begin() -> void:
	var path := "res://assets/audio/music/taiko.ogg"
	if ResourceLoader.exists(path):
		_song.stream = load(path)
		_song.play()
	set_status("跟着光点，一起敲响夏夜！")


func mg_process(delta: float) -> void:
	_update_song_time(delta)
	while _next_note < _notes.size() and _note_expired(_song_t, float(_notes[_next_note].get("t", 0.0))):
		_record_miss(false)
	_flash_t = maxf(0.0, _flash_t - delta)
	_canvas.queue_redraw()
	_flash_canvas.queue_redraw()
	if not _notes.is_empty() and _song_t >= float(_notes.back().get("t", 0.0)) + 1.5:
		_finish_song()


func mg_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.physical_keycode:
			KEY_F, KEY_J:
				_try_hit("don")
			KEY_D, KEY_K:
				_try_hit("ka")
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and Rect2(Vector2.ZERO, PLAY_SIZE).has_point(stage_mouse()):
			if click.button_index == MOUSE_BUTTON_LEFT:
				_try_hit("don")
			elif click.button_index == MOUSE_BUTTON_RIGHT:
				_try_hit("ka")


func mg_auto(_delta: float) -> void:
	while _auto_index < _auto_times.size() and _song_t >= _auto_times[_auto_index]:
		if not _auto_skips[_auto_index]:
			_try_hit(str(_notes[_auto_index].get("k", "don")))
		_auto_index += 1


func mg_time_up() -> void:
	while _next_note < _notes.size():
		_record_miss(false)
	_finish_song()


func mg_result_lines() -> Array:
	var line := "良 %d  ·  可 %d  ·  不可 %d" % [_perfects, _goods, _misses]
	var combo_line := "最高连击 %d" % _max_combo
	if _max_combo == _notes.size() and not _notes.is_empty():
		combo_line += "  ·  全连击！"
	return [line, combo_line]


func mg_simulate(skill: float, seed: int) -> int:
	var s := clampf(skill, 0.0, 1.0)
	var sim_rng := RandomNumberGenerator.new()
	sim_rng.seed = seed
	var sim_score := 0
	var combo := 0
	for note in _notes:
		var hit_roll := sim_rng.randf()
		var error_roll := sim_rng.randf_range(-1.0, 1.0)
		var kind_roll := sim_rng.randf()
		var error := absf(error_roll * (0.024 + 0.18 * (1.0 - s)))
		var correct := kind_roll < (0.72 + 0.28 * s)
		var judgement := 0
		if hit_roll < pow(s, 0.7) and correct:
			judgement = _judgement(error)
		if judgement == 0:
			combo = 0
		else:
			combo += 1
			sim_score += judgement + (10 if combo >= 10 else 0)
	return sim_score


func mg_self_test() -> Array:
	var tests := []
	var count := _notes.size()
	var maximum := _maximum_score(count)
	tests.append(["曲谱载入 104 个音符", count == 104])
	tests.append(["曲谱音符类型有效且按时间排列", _chart_is_valid()])
	tests.append(["50 毫秒属于良", _judgement(0.050) == 100])
	tests.append(["超过良窗口进入可", _judgement(0.051) == 50])
	tests.append(["100 毫秒属于可", _judgement(0.100) == 50])
	tests.append(["超过判定窗口不可", _judgement(0.101) == 0])
	tests.append(["敲错颜色判不可", _points_for_note("don", "ka", 0.0) == 0])
	tests.append(["刚过晚点窗口必须漏拍", not _note_expired(1.100, 1.0) and _note_expired(1.101, 1.0)])
	tests.append(["空敲窗口严格为 150 毫秒", _in_empty_window(0.15) and not _in_empty_window(0.151)])
	tests.append(["第十次连击才有加分", _score_for_hit(100, 9) == 100 and _score_for_hit(100, 10) == 110])
	tests.append(["全良最高分可达", mg_simulate(1.0, 5) == maximum])
	tests.append(["完全不会打得到零分", mg_simulate(0.0, 5) == 0])
	tests.append(["星级门槛顺序合理", stars_for(maximum) == 3 and stars_for(0) == 0 and stars_for(info.stars[0] - 1) == 0 and stars_for(info.stars[0]) == 1 and stars_for(info.stars[1]) == 2])
	tests.append(["模拟重复运行稳定", mg_simulate(0.63, 21) == mg_simulate(0.63, 21)])
	var prev := -1
	var monotone := true
	for i in range(11):
		var value := mg_simulate(float(i) / 10.0, 42)
		if value < prev:
			monotone = false
		prev = value
	tests.append(["同一随机种子的成绩随熟练度递增", monotone])
	return tests


func _read_chart() -> Dictionary:
	var text := FileAccess.get_file_as_string(CHART_PATH)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _maximum_score(count: int) -> int:
	return count * 100 + maxi(count - 9, 0) * 10


func _judgement(error: float) -> int:
	if error <= PERFECT_WINDOW + 0.000001:
		return 100
	if error <= GOOD_WINDOW + 0.000001:
		return 50
	return 0


func _points_for_note(kind: String, expected: String, error: float) -> int:
	return _judgement(error) if kind == expected else 0


func _note_expired(now: float, note_t: float) -> bool:
	return now > note_t + GOOD_WINDOW + 0.000001


func _in_empty_window(error: float) -> bool:
	return error <= EMPTY_WINDOW + 0.000001


func _score_for_hit(points: int, combo: int) -> int:
	return points + (10 if combo >= 10 else 0)


func _chart_is_valid() -> bool:
	var last_t := -1.0
	for note in _notes:
		var t := float(note.get("t", -1.0))
		if t <= last_t or str(note.get("k", "")) not in ["don", "ka"]:
			return false
		last_t = t
	return not _notes.is_empty()


func _update_song_time(delta: float) -> void:
	_fallback_t += delta
	if not _song.playing or DisplayServer.get_name() == "headless":
		_song_t = maxf(_song_t, _fallback_t)
		return
	var raw := _song.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	if raw > _last_audio_t + 0.0001:
		_last_audio_t = raw
		_audio_still_t = 0.0
		_song_t = maxf(_song_t, maxf(0.0, raw))
	else:
		_audio_still_t += delta
		if _audio_still_t > 0.25:
			_song_t = maxf(_song_t, _fallback_t)


func _try_hit(kind: String) -> void:
	if _next_note >= _notes.size():
		return
	var note: Dictionary = _notes[_next_note]
	var error := absf(_song_t - float(note.get("t", 0.0)))
	if not _in_empty_window(error):
		return
	sfx(kind)
	_flash_kind = kind
	_flash_t = 0.22
	_animate_drum()
	var points := _points_for_note(kind, str(note.get("k", "")), error)
	if points == 0:
		_record_miss(true)
		return
	_next_note += 1
	_combo += 1
	_max_combo = maxi(_max_combo, _combo)
	if points == 100:
		_perfects += 1
	else:
		_goods += 1
	add_score(_score_for_hit(points, _combo))
	pop_text("良 +%d" % _score_for_hit(points, _combo) if points == 100 else "可 +%d" % _score_for_hit(points, _combo), Vector2(HIT_X + 26, LANE_Y - 105), Color(1.0, 0.88, 0.57) if points == 100 else Color(0.74, 0.87, 1.0), 38)
	if points == 100:
		sfx("perfect", -9.0)
	else:
		sfx("good", -9.0)
	if _combo > 0 and _combo % 10 == 0:
		sfx("combo", -5.0)
	_animate_burst()
	_update_labels()


func _record_miss(show_feedback: bool) -> void:
	_next_note += 1
	_misses += 1
	_combo = 0
	if show_feedback or playing():
		pop_text("不可", Vector2(HIT_X + 28, LANE_Y - 96), Color(1.0, 0.65, 0.64), 35)
		sfx("miss", -10.0)
	_update_labels()


func _animate_drum() -> void:
	if _drum_tween and _drum_tween.is_running():
		_drum_tween.kill()
	_drum.scale = Vector2(0.94, 0.94)
	_drum.modulate = Color(1.0, 0.88, 0.69) if _flash_kind == "don" else Color(0.75, 0.87, 1.0)
	_drum_tween = create_tween().set_parallel(true)
	_drum_tween.tween_property(_drum, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_drum_tween.tween_property(_drum, "modulate", Color.WHITE, 0.28)


func _animate_burst() -> void:
	if _burst_tween and _burst_tween.is_running():
		_burst_tween.kill()
	_burst.scale = Vector2(0.55, 0.55)
	_burst.modulate.a = 0.95
	_burst_tween = create_tween().set_parallel(true)
	_burst_tween.tween_property(_burst, "scale", Vector2(1.15, 1.15), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_burst, "modulate:a", 0.0, 0.34)


func _update_labels() -> void:
	if _progress_label:
		_progress_label.text = "第 %d / %d 拍" % [mini(_next_note + 1, _notes.size()), _notes.size()]
	if _combo_label:
		_combo_label.text = "%d 连击" % _combo if _combo >= 2 else ""
		if _combo >= 2:
			if _combo_tween and _combo_tween.is_running():
				_combo_tween.kill()
			_combo_label.scale = Vector2(1.16, 1.16)
			_combo_tween = create_tween()
			_combo_tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _finish_song() -> void:
	if _song:
		_song.stop()
	if _max_combo == _notes.size() and not _notes.is_empty():
		sfx("full_combo")
	end_round()


func _draw_stage() -> void:
	if not _canvas:
		return
	# Translucent lacquer lane lets the painted sunset stay visible behind the notes.
	_canvas.draw_rect(Rect2(408, 306, 1118, 168), Color(0.11, 0.10, 0.22, 0.72), true)
	_canvas.draw_line(Vector2(408, 308), Vector2(1526, 308), Color(1.0, 0.75, 0.44, 0.75), 4.0, true)
	_canvas.draw_line(Vector2(408, 472), Vector2(1526, 472), Color(1.0, 0.75, 0.44, 0.72), 4.0, true)
	_canvas.draw_line(Vector2(550, LANE_Y), Vector2(1520, LANE_Y), Color(1.0, 0.86, 0.69, 0.26), 3.0, true)
	_canvas.draw_circle(Vector2(HIT_X, LANE_Y), 69, Color(0.13, 0.09, 0.22, 0.86))
	_canvas.draw_arc(Vector2(HIT_X, LANE_Y), 65, 0.0, TAU, 96, Color(1.0, 0.82, 0.49, 0.95), 7.0, true)
	_canvas.draw_arc(Vector2(HIT_X, LANE_Y), 53, 0.0, TAU, 96, Color(1.0, 0.95, 0.8, 0.38), 2.0, true)
	_canvas.draw_circle(Vector2(HIT_X, LANE_Y), 9, Color(1.0, 0.92, 0.75, 0.65))
	for i in range(_next_note, _notes.size()):
		var note: Dictionary = _notes[i]
		var dt := float(note.get("t", 0.0)) - _song_t
		if dt > VISIBLE_AHEAD:
			break
		if dt < -GOOD_WINDOW:
			continue
		var x := HIT_X + dt * SCROLL_SPEED
		var tex: Texture2D = _note_don if str(note.get("k", "")) == "don" else _note_ka
		_canvas.draw_texture_rect(tex, Rect2(x - 47, LANE_Y - 47, 94, 94), false)
	_canvas.draw_rect(Rect2(72, 620, 850, 58), Color(0.12, 0.11, 0.22, 0.55), true)
	_canvas.draw_line(Vector2(80, 614), Vector2(1480, 614), Color(1.0, 0.81, 0.53, 0.45), 2.0, true)
	_canvas.draw_string(_font, Vector2(90, 658), "鼓心  F / J  ·  左键", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, Color(1.0, 0.94, 0.83))
	_canvas.draw_string(_font, Vector2(490, 658), "鼓边  D / K  ·  右键", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, Color(0.8, 0.89, 1.0))


func _draw_flash() -> void:
	if _flash_t <= 0.0:
		return
	var flash_color := Color(1.0, 0.72, 0.39, _flash_t * 2.6) if _flash_kind == "don" else Color(0.55, 0.75, 1.0, _flash_t * 2.6)
	var center := Vector2(229, 389)
	if _flash_kind == "don":
		_flash_canvas.draw_circle(center, 108, flash_color)
	else:
		_flash_canvas.draw_arc(center, 144, 0.0, TAU, 100, flash_color, 15.0, true)


func _exit_tree() -> void:
	if _song:
		_song.stop()
