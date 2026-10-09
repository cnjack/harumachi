class_name MiniGame
extends Control
## Base class for the mini-games. The host (GameUI.play_minigame) adds one full-screen instance.
## The base draws the paper frame, the header (title / score / timer), the intro card, a 3-2-1
## countdown and the result card; a subclass only builds and runs the play area (`stage`).
##
## Subclass contract (override what you need):
##   mg_info() -> Dictionary      {"title", "subtitle", "rules": [String], "controls": String,
##                                 "stars": [int, int, int] (score thresholds for 1/2/3 stars),
##                                 "duration": float (seconds, 0 = untimed), "mute_bgm": bool,
##                                 "unit": String (shown after the score, e.g. "分" / "条")}
##   mg_build(stage)              build the play-area nodes once. `stage` is PLAY_SIZE and clips.
##   mg_reset()                   reset for a new round (called before every round).
##   mg_begin()                   the countdown finished; play starts.
##   mg_process(delta)            every frame while playing.
##   mg_input(event)              input while playing (never called in auto mode).
##   mg_auto(delta)               demo AI, called every frame while playing when `auto` is true.
##   mg_time_up()                 timed games only; the default ends the round.
##   mg_simulate(skill, seed)     headless: deterministic score for a player of `skill` 0..1.
##   mg_self_test() -> Array      headless logic checks: [[name, passed], ...].
##   mg_result_lines() -> Array   extra lines for the result card (e.g. "捞到 5 条").
## Helpers: add_score(), set_score(), score, time_left, playing(), rng, set_status(),
##   pop_text(), end_round(), sfx(), stage_mouse(), stars_for().

signal round_finished(result: Dictionary)
signal closed(result: Dictionary)

const PLAY_SIZE := Vector2(1560, 760)
const FRAME_SIZE := Vector2(1640, 960)

enum State { INTRO, COUNTDOWN, PLAY, RESULT, CLOSED }

var id := ""
var auto := false                 # autoplay demo: intro/result advance by themselves, mg_auto plays
var reward_cb: Callable           # (id, score, stars) -> {"coins", "lines", "new_best", "best"}
var best := 0                     # shown on the intro card
var state := State.INTRO
var score := 0
var time_left := 0.0
var rng := RandomNumberGenerator.new()
var last_result := {}
var info := {}
var context: Dictionary = {}      # story mode has no free-game reward authority
var round_started := false

var stage: Control
var frame: Panel
var _title: Label
var _score_label: Label
var _time_label: Label
var _status: Label
var _hint: Label
var _card_layer: Control
var _count_label: Label
var _auto_t := 0.0


func _ready() -> void:
	info = mg_info()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_build_frame()
	mg_build(stage)
	mg_reset()
	if context.get("start_requested", false):
		_start_round.call_deferred()
	else:
		_show_intro()


# ================================================================== overridable
func mg_info() -> Dictionary:
	return {"title": "小游戏", "rules": [], "controls": "", "stars": [1, 2, 3], "duration": 0.0}

func mg_build(_stage: Control) -> void:
	pass

func mg_reset() -> void:
	pass

func mg_begin() -> void:
	pass

func mg_process(_delta: float) -> void:
	pass

func mg_input(_event: InputEvent) -> void:
	pass

func mg_auto(_delta: float) -> void:
	pass

func mg_time_up() -> void:
	end_round()

func mg_simulate(_skill: float, _seed: int) -> int:
	return 0

func mg_self_test() -> Array:
	return []

func mg_result_lines() -> Array:
	return []

func mg_outcome() -> Dictionary:
	return {"started": round_started}


# ================================================================== helpers
func playing() -> bool:
	return state == State.PLAY

func add_score(n: int) -> void:
	set_score(score + n)

func set_score(n: int) -> void:
	score = maxi(n, 0)
	if _score_label:
		_score_label.text = "%d %s" % [score, str(info.get("unit", "分"))]

func set_status(text: String) -> void:
	if _status:
		_status.text = text

func sfx(name: String, vol_db: float = -3.0, pitch: float = 1.0) -> void:
	Audio.sfx("mg_" + name, vol_db, pitch)

## Mouse position in stage coordinates (correct under any window scaling).
func stage_mouse() -> Vector2:
	return stage.get_local_mouse_position()

func stars_for(s: int) -> int:
	var n := 0
	for t in info.get("stars", [1, 2, 3]):
		if s >= int(t):
			n += 1
	return n

## Floating text that rises and fades, e.g. pop_text("完美！", Vector2(700, 300), UITheme.GOOD).
func pop_text(text: String, pos: Vector2, color: Color = UITheme.ACCENT, size: int = 40) -> void:
	var l := UITheme.label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(1, 0.98, 0.92))
	l.add_theme_constant_override("outline_size", 8)
	l.position = pos - Vector2(60, 24)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)

func end_round() -> void:
	if state != State.PLAY:
		return
	state = State.RESULT
	_finish()


# ================================================================== frame
func _build_frame() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.07, 0.05, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	frame = Panel.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -FRAME_SIZE.x / 2.0
	frame.offset_right = FRAME_SIZE.x / 2.0
	frame.offset_top = -FRAME_SIZE.y / 2.0
	frame.offset_bottom = FRAME_SIZE.y / 2.0
	frame.add_theme_stylebox_override("panel", UIKitStyles.surface("modal",0))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_title = UITheme.label(str(info.get("title", "")), 40)
	_title.position = Vector2(44, 22)
	frame.add_child(_title)
	_status = UITheme.label("", 24, UITheme.INK_SOFT)
	_status.position = Vector2(44, 76)
	_status.custom_minimum_size = Vector2(1000, 0)
	frame.add_child(_status)
	_score_label = UITheme.label("", 36, UITheme.ACCENT)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.position = Vector2(FRAME_SIZE.x - 44 - 360, 22)
	_score_label.custom_minimum_size = Vector2(360, 0)
	frame.add_child(_score_label)
	_score_label.visible = str(context.get("mode", "free")) == "free"
	_time_label = UITheme.label("", 28, UITheme.INK_SOFT)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.position = Vector2(FRAME_SIZE.x - 44 - 360, 72)
	_time_label.custom_minimum_size = Vector2(360, 0)
	frame.add_child(_time_label)
	stage = Control.new()
	stage.name = "Stage"
	stage.position = Vector2((FRAME_SIZE.x - PLAY_SIZE.x) / 2.0, 124)
	stage.size = PLAY_SIZE
	stage.custom_minimum_size = PLAY_SIZE
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_PASS
	frame.add_child(stage)
	_hint = UITheme.label(str(info.get("controls", "")), 22, UITheme.INK_SOFT)
	_hint.position = Vector2(44, FRAME_SIZE.y - 60)
	frame.add_child(_hint)
	_count_label = UITheme.label("", 150, UITheme.ACCENT)
	_count_label.add_theme_color_override("font_outline_color", Color(1, 0.98, 0.92))
	_count_label.add_theme_constant_override("outline_size", 18)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.position = stage.position
	_count_label.size = PLAY_SIZE
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_label.visible = false
	frame.add_child(_count_label)
	_card_layer = Control.new()
	_card_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_card_layer)
	set_score(0)
	time_left = float(info.get("duration", 0.0))
	_update_time_label()


func _update_time_label() -> void:
	var d := float(info.get("duration", 0.0))
	_time_label.text = ("剩余 %d 秒" % ceili(maxf(time_left, 0.0))) if d > 0.0 else ""


func _card(width: float) -> VBoxContainer:
	for c in _card_layer.get_children():
		c.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0.99, 0.965, 0.9, 0.55)
	shade.position = stage.position
	shade.size = PLAY_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_layer.add_child(shade)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKitStyles.surface("modal",40))
	p.custom_minimum_size = Vector2(width, 0)
	_card_layer.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	_place_card.call_deferred(p)
	return v


func _place_card(p: Control) -> void:
	if is_instance_valid(p):
		p.position = (FRAME_SIZE - p.size) / 2.0 + Vector2(0, 20)


func _buttons(v: VBoxContainer, pairs: Array) -> Button:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	var first: Button = null
	for pr in pairs:
		var b := Button.new()
		b.text = pr[0]
		b.custom_minimum_size = Vector2(220, 60)
		b.pressed.connect(pr[1])
		h.add_child(b)
		if first == null:
			first = b
	v.add_child(h)
	if first:
		first.call_deferred("grab_focus")
	return first


# ================================================================== flow
func _show_intro() -> void:
	state = State.INTRO
	_auto_t = 0.0
	var v := _card(820)
	var t := UITheme.label(str(info.get("title", "")), 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if str(info.get("subtitle", "")) != "":
		var st := UITheme.label(str(info.subtitle), 24, UITheme.INK_SOFT)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(st)
	for r in info.get("rules", []):
		var l := UITheme.label("· " + str(r), 26)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(740, 0)
		v.add_child(l)
	var th: Array = info.get("stars", [1, 2, 3])
	var unit := str(info.get("unit", "分"))
	v.add_child(UITheme.label("★ %d%s   ★★ %d%s   ★★★ %d%s      最好成绩 %d%s" % [th[0], unit, th[1], unit, th[2], unit, best, unit], 24, UITheme.INK_SOFT))
	_buttons(v, [["开始", _start_round], ["离开", _leave]])


func _start_round() -> void:
	if state == State.PLAY or state == State.COUNTDOWN or state == State.CLOSED:
		return
	round_started = false
	for c in _card_layer.get_children():
		c.queue_free()
	get_viewport().gui_release_focus()
	set_score(0)
	mg_reset()
	time_left = float(info.get("duration", 0.0))
	_update_time_label()
	state = State.COUNTDOWN
	_count_label.visible = true
	for n in ["3", "2", "1"]:
		_count_label.text = n
		sfx("count")
		await get_tree().create_timer(0.6).timeout
		if state != State.COUNTDOWN:
			return
	_count_label.text = "开始！"
	sfx("go")
	state = State.PLAY
	round_started = true
	mg_begin()
	await get_tree().create_timer(0.5).timeout
	if _count_label.text == "开始！":
		_count_label.visible = false


func _finish() -> void:
	_count_label.visible = false
	var stars := stars_for(score)
	var rew: Dictionary = reward_cb.call(id, score, stars) if reward_cb.is_valid() else {}
	best = maxi(best, int(rew.get("best", score)))
	last_result = {"id": id, "score": score, "stars": stars, "new_best": bool(rew.get("new_best", false)),
			"coins": int(rew.get("coins", 0)), "lines": rew.get("lines", []), "completed": true,
			"outcome": mg_outcome(), "mode": str(context.get("mode", "free"))}
	round_finished.emit(last_result)
	if is_inside_tree():
		sfx("result")
		if stars > 0:
			Audio.sting("sparkle")
		_show_result()


func _show_result() -> void:
	_auto_t = 0.0
	var v := _card(760)
	v.modulate.a=0;v.create_tween().tween_property(v,"modulate:a",1.0,.45)
	if int(last_result.stars)>0:
		var effects:=Celebration.new();effects.effects_only();effects.lifetime=2.1;_card_layer.add_child(effects)
	var story_mode := str(context.get("mode", "free")) != "free"
	var t := UITheme.label(str(context.get("result_title", "这一小份捏好了")) if story_mode else "本局结果", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var stars: int = last_result.stars
	var sl := UITheme.label("★".repeat(stars) + "☆".repeat(3 - stars), 72, UITheme.ACCENT)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	sl.visible = not story_mode
	var unit := str(info.get("unit", "分"))
	var sc := UITheme.label("%d %s%s" % [score, unit, "   新纪录！" if last_result.new_best else "   最好 %d %s" % [best, unit]], 32)
	sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sc)
	sc.visible = not story_mode
	for ln in mg_result_lines() + Array(last_result.lines):
		var l := UITheme.label(str(ln), 26, UITheme.INK_SOFT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(680, 0)
		v.add_child(l)
	_buttons(v, [[str(context.get("return_label", "回到厨房")), _leave]] if story_mode else [["再来一局", _start_round], ["离开", _leave]])


func _leave() -> void:
	if state == State.CLOSED:
		return
	var was_playing := state == State.PLAY or state == State.COUNTDOWN
	var actual_outcome := mg_outcome()
	state = State.CLOSED
	if was_playing or last_result.is_empty():
		last_result = {"id": id, "score": 0, "stars": 0, "completed": false, "coins": 0, "lines": [],
			"outcome": actual_outcome, "mode": str(context.get("mode", "free"))}
	closed.emit(last_result)


## Tests: resolve one round instantly through mg_simulate and the reward callback.
func run_instant(skill: float, seed: int = 7) -> Dictionary:
	round_started = true
	score = maxi(mg_simulate(skill, seed), 0)
	state = State.PLAY
	end_round()
	state = State.CLOSED
	return last_result


# ================================================================== loop and input
func _process(delta: float) -> void:
	match state:
		State.INTRO:
			if auto:
				_auto_t += delta
				if _auto_t > 2.2:
					_start_round()
		State.PLAY:
			if float(info.get("duration", 0.0)) > 0.0:
				time_left -= delta
				_update_time_label()
				if time_left <= 0.0:
					time_left = 0.0
					mg_time_up()
					if state != State.PLAY:
						return
			if auto:
				mg_auto(delta)
			mg_process(delta)
		State.RESULT:
			if auto:
				_auto_t += delta
				if _auto_t > 3.2:
					_leave()


func _input(event: InputEvent) -> void:
	if state == State.CLOSED:
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_leave()
		return
	if state == State.PLAY and not auto:
		mg_input(event)
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
