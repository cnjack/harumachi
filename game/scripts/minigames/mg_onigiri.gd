extends MiniGame

const ART := "res://assets/minigames/onigiri/"
const FILL_NAMES := ["梅干", "鲑鱼", "昆布", "金枪鱼蛋黄酱"]
const FILL_ART := ["umeboshi.png", "salmon.png", "kombu.png", "tuna_mayo.png"]
const PEOPLE := ["mio", "ren", "haru"]
const BOWL_X := [345.0, 650.0, 955.0, 1250.0]
const SCOOP := 0
const FILL := 1
const SHAPE := 2
const NORI := 3
const SERVE := 4

func _home_meal() -> bool:
	return str(context.get("mode", "free")) == "home_meal"

func mg_outcome() -> Dictionary:
	return {"started": round_started, "shaped": _home_meal() and served == 1, "served": served}

var phase := SCOOP
var orders: Array[Dictionary] = []
var scoop_fill := 0.0
var scoop_held := false
var scoop_points := 0.0
var shape_points := 0.0
var nori_points := 0.0
var shape_beat := 0
var beat_time := 0.0
var nori_time := 0.0
var serve_time := 0.0
var chosen_fill := -1
var combo := 0
var served := 0
var missed := 0
var perfect_count := 0
var order_happy := false
var auto_clock := 0.0
var auto_mark := -1
var auto_cursor := Vector2(780, 550)

var rice: TextureRect
var paddle: TextureRect
var nori: TextureRect
var phase_label: Label
var instruction: Label
var detail: Label
var combo_label: Label
var fx: Control
var order_panels: Array[Panel] = []
var order_faces: Array[TextureRect] = []
var order_icons: Array[TextureRect] = []
var order_names: Array[Label] = []
var order_bars: Array[ColorRect] = []
var face_keys: Array[String] = ["", "", ""]
var icon_keys: Array[String] = ["", "", ""]


func mg_info() -> Dictionary:
	if _home_meal():
		return {"title": "自己的饭团 · 捏一小份", "subtitle": "米和盐已经拌好。先试试把饭团捏出三个角。",
			"rules": ["按 A、D、A，或点击饭团三次。每一下都会把一个角收拢。", "没有倒计时。不赶时间，Esc 先回厨房，米料还留着。", "捏好后回厨房包成两份；也可以直接在灶台简单制作。"],
			"controls": "A / D 或鼠标点击 捏形 · Esc 先回厨房", "stars": [300, 550, 870], "duration": 0.0, "unit": "分"}
	return {"title": "捏饭团", "subtitle": "照着练习订单，试试盛饭、放馅和包海苔。",
		"rules": ["按住空格盛饭，在绿色区松开。", "按 1–4 选练习单上的馅；A、D 交替按三拍捏形。",
			"海苔滑到正中时按空格；每张练习单都有时间限制。"],
		"controls": "空格 盛饭／包海苔 · 1–4 选馅 · A/D 捏形 · 鼠标也可操作 · Esc 离开",
		"stars": [300, 550, 870], "duration": 75.0, "unit": "分"}


func mg_build(_stage: Control) -> void:
	var bg := _image("kitchen.png", Vector2.ZERO, PLAY_SIZE)
	stage.add_child(bg)
	var wash := ColorRect.new()
	wash.color = Color(0.22, 0.12, 0.06, 0.07)
	wash.size = PLAY_SIZE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(wash)

	for i in 3:
		var panel := Panel.new()
		panel.position = Vector2(1000, 22) if i == 0 else Vector2(478 + (i - 1) * 257, 24)
		panel.size = Vector2(520, 208) if i == 0 else Vector2(245, 154)
		panel.add_theme_stylebox_override("panel", UIKitStyles.surface("hud",18))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(panel)
		order_panels.append(panel)
		var face := _image("", Vector2(16, 15), Vector2(152, 150) if i == 0 else Vector2(88, 87))
		panel.add_child(face)
		order_faces.append(face)
		var icon := _image("umeboshi.png", Vector2(186, 49) if i == 0 else Vector2(102, 35), Vector2(82, 82) if i == 0 else Vector2(50, 50))
		panel.add_child(icon)
		order_icons.append(icon)
		var heading := _label("现在做", 25, UITheme.INK_SOFT, Vector2(185, 16)) if i == 0 else _label("等候中", 18, UITheme.INK_SOFT, Vector2(104, 10))
		panel.add_child(heading)
		var name := _label("", 29 if i == 0 else 18, UITheme.INK, Vector2(275, 66) if i == 0 else Vector2(105, 88))
		panel.add_child(name)
		order_names.append(name)
		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.85, 0.77, 0.66, 0.72)
		bar_bg.position = Vector2(184, 166) if i == 0 else Vector2(17, 119)
		bar_bg.size = Vector2(310, 13) if i == 0 else Vector2(211, 10)
		panel.add_child(bar_bg)
		var bar := ColorRect.new()
		bar.color = UITheme.GOOD
		bar.position = bar_bg.position
		bar.size = bar_bg.size
		panel.add_child(bar)
		order_bars.append(bar)

	var title_panel := Panel.new()
	title_panel.position = Vector2(250, 232)
	title_panel.size = Vector2(445, 124)
	title_panel.add_theme_stylebox_override("panel", UIKitStyles.surface("hud",18))
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(title_panel)
	phase_label = _label("", 31, UITheme.INK, Vector2(24, 12))
	title_panel.add_child(phase_label)
	instruction = _label("", 23, UITheme.INK_SOFT, Vector2(24, 58))
	title_panel.add_child(instruction)

	rice = _image("rice_loose.png", Vector2(645, 315), Vector2(280, 280))
	stage.add_child(rice)
	nori = _image("nori_strip.png", Vector2(680, 472), Vector2(110, 130))
	nori.visible = false
	stage.add_child(nori)
	paddle = _image("rice_paddle.png", Vector2(680, 500), Vector2(120, 120))
	paddle.modulate.a = 0.9
	stage.add_child(paddle)

	fx = Control.new()
	fx.size = PLAY_SIZE
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.draw.connect(_draw_fx)
	stage.add_child(fx)

	var ribbon := Panel.new()
	ribbon.position = Vector2(500, 671)
	ribbon.size = Vector2(565, 71)
	ribbon.add_theme_stylebox_override("panel", UIKitStyles.surface("hud",12))
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(ribbon)
	detail = _label("", 24, UITheme.INK, Vector2(20, 11))
	detail.custom_minimum_size = Vector2(520, 0)
	ribbon.add_child(detail)
	combo_label = _label("", 23, UITheme.ACCENT, Vector2(20, 39))
	ribbon.add_child(combo_label)
	for i in 4:
		if _home_meal(): break
		var tag := Panel.new()
		tag.position = Vector2(BOWL_X[i] - 103, 620)
		tag.size = Vector2(206, 37)
		tag.add_theme_stylebox_override("panel", UIKitStyles.surface("hud",6))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(tag)
		var l := _label("%d  %s" % [i + 1, FILL_NAMES[i]], 20, UITheme.INK, Vector2(9, 3))
		l.size = tag.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_child(l)


func mg_reset() -> void:
	orders.clear()
	for i in 3:
		orders.append(_new_order())
	combo = 0
	served = 0
	missed = 0
	perfect_count = 0
	_reset_work()
	_refresh_orders()
	_update_labels()
	if _home_meal():
		phase = SHAPE
		for panel: Panel in order_panels: panel.visible = false
		_phase_changed()


func mg_begin() -> void:
	set_status("先捏好自己的这一份。" if _home_meal() else "照着纸上的练习订单来，不用真的招待邻居。")


func mg_process(delta: float) -> void:
	if _home_meal():
		beat_time += delta
		fx.queue_redraw()
		return
	var order_changed := false
	for i in range(orders.size() - 1, -1, -1):
		if i == 0 and phase == SERVE:
			continue
		orders[i].patience -= delta
		if _patience_expired(float(orders[i].patience)):
			if i == 0:
				combo = 0
				_reset_work()
			missed += 1
			orders.remove_at(i)
			orders.append(_new_order())
			order_changed = true
			sfx("customer_leave")
			pop_text("等不及啦", Vector2(1110, 240), UITheme.BAD, 32)
	if phase == SCOOP and scoop_held:
		scoop_fill = minf(1.0, scoop_fill + delta * 0.55)
	elif phase == SHAPE:
		beat_time += delta
		if beat_time >= 0.86:
			_press_shape(false)
	elif phase == NORI:
		nori_time += delta
		nori.position.x = 730.0 + sin(nori_time * 4.4) * 165.0
	elif phase == SERVE:
		serve_time -= delta
		if serve_time <= 0.0:
			orders.pop_front()
			orders.append(_new_order())
			_reset_work()
	_refresh_orders()
	if order_changed:
		_update_labels()
	fx.queue_redraw()
	if auto:
		paddle.position = paddle.position.lerp(auto_cursor - Vector2(60, 55), minf(1.0, delta * 4.0))
	elif phase == SCOOP and scoop_held:
		paddle.position = paddle.position.lerp(stage_mouse() - Vector2(60, 55), minf(1.0, delta * 8.0))


func mg_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.is_echo():
			return
		if k.physical_keycode == KEY_SPACE:
			if phase == SCOOP:
				if k.pressed:
					scoop_held = true
				elif scoop_held:
					_release_scoop()
			elif phase == NORI and k.pressed:
				_wrap_nori()
		elif k.pressed and phase == FILL and k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_4:
			_choose_fill(k.physical_keycode - KEY_1)
		elif k.pressed and phase == SHAPE and (k.physical_keycode == KEY_A or k.physical_keycode == KEY_D):
			_press_shape((k.physical_keycode == KEY_A) == (shape_beat % 2 == 0))
	elif event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index != MOUSE_BUTTON_LEFT:
			return
		var pos := stage_mouse()
		if phase == SCOOP and pos.x < 240.0 and pos.y > 140.0 and pos.y < 550.0:
			if m.pressed:
				scoop_held = true
			elif scoop_held:
				_release_scoop()
		elif not m.pressed:
			if phase == SCOOP and scoop_held:
				_release_scoop()
		elif phase == FILL and pos.y >= 555.0:
			for i in 4:
				if absf(pos.x - BOWL_X[i]) < 135.0:
					_choose_fill(i)
					break
		elif phase == SHAPE:
			_press_shape(true)
		elif phase == NORI:
			_wrap_nori()


func mg_auto(delta: float) -> void:
	auto_clock += delta
	match phase:
		SCOOP:
			auto_cursor = Vector2(170, 320)
			if auto_clock > 1.35 and not scoop_held:
				scoop_held = true
			if scoop_held and scoop_fill >= 0.625:
				_release_scoop()
		FILL:
			auto_cursor = Vector2(BOWL_X[int(orders[0].filling)], 635)
			if auto_clock > 1.7:
				_choose_fill(int(orders[0].filling))
		SHAPE:
			auto_cursor = Vector2(785 + (22 if shape_beat % 2 else -22), 436)
			if auto_mark != shape_beat and beat_time >= 0.68:
				auto_mark = shape_beat
				_press_shape(true)
		NORI:
			auto_cursor = Vector2(790, 512)
			if auto_clock > 1.2 and absf(nori.position.x - 730.0) < 40.0:
				_wrap_nori()
		SERVE:
			auto_cursor = Vector2(1125, 300)


func _release_scoop() -> void:
	scoop_held = false
	scoop_points = _scoop_quality(scoop_fill) * 12.0
	phase = FILL
	sfx("rice_scoop")
	_show_feedback(scoop_points, Vector2(420, 401))
	_phase_changed()


func _choose_fill(i: int) -> void:
	if i < 0 or i >= 4 or orders.is_empty():
		return
	chosen_fill = i
	phase = SHAPE
	shape_beat = 0
	beat_time = 0.0
	sfx("filling")
	if i != int(orders[0].filling):
		pop_text("馅料拿错了", Vector2(770, 385), UITheme.BAD, 31)
	else:
		pop_text(FILL_NAMES[i] + "，刚刚好", Vector2(750, 385), UITheme.GOOD, 29)
	_phase_changed()


func _press_shape(correct_hand: bool) -> void:
	if _home_meal():
		if not correct_hand:
			set_status("下一个角按 D。也可以用鼠标点饭团。" if shape_beat % 2 == 1 else "下一个角按 A。也可以用鼠标点饭团。")
			return
		shape_beat += 1
		beat_time = 0.0
		sfx("rice_press")
		pop_text("这个角收好了", Vector2(792, 340), UITheme.GOOD, 27)
		rice.texture = load(ART + ("rice_triangle.png" if shape_beat >= 2 else "rice_lumpy.png"))
		_update_labels()
		if shape_beat >= 3:
			served = 1
			end_round()
		return
	var q := _beat_quality(beat_time) if correct_hand else 0.0
	shape_points += q * 7.0
	if q >= 0.82:
		pop_text("好手感！", Vector2(792, 340), UITheme.GOOD, 27)
	elif q <= 0.2:
		pop_text("轻一点", Vector2(792, 340), UITheme.BAD, 25)
	sfx("rice_press")
	var tw := rice.create_tween()
	tw.tween_property(rice, "scale", Vector2(1.07, 0.92), 0.10)
	tw.tween_property(rice, "scale", Vector2.ONE, 0.17).set_trans(Tween.TRANS_BACK)
	shape_beat += 1
	beat_time = 0.0
	if shape_beat >= 3:
		if _home_meal():
			served = 1
			rice.texture = load(ART + "rice_triangle.png")
			end_round()
			return
		phase = NORI
		nori_time = 0.0
		_phase_changed()
	else:
		rice.texture = load(ART + ("rice_lumpy.png" if shape_beat == 1 else "rice_triangle.png"))


func _wrap_nori() -> void:
	nori_points = _nori_quality(nori.position.x) * 7.0
	nori.visible = false
	phase = SERVE
	serve_time = 1.45
	rice.texture = load(ART + "rice_nori.png")
	sfx("nori")
	_show_feedback(nori_points, Vector2(830, 337))
	_serve()
	_phase_changed()


func _serve() -> void:
	var right := chosen_fill == int(orders[0].filling)
	var quality := scoop_points + shape_points + nori_points
	var speed := roundi(15.0 * float(orders[0].patience) / float(orders[0].max_patience))
	var perfect := right and scoop_points >= 10.9 and shape_points >= 18.5 and nori_points >= 6.0
	combo = combo + 1 if perfect else 0
	var points := _order_score(right, quality, speed, combo)
	add_score(points)
	served += 1
	if perfect:
		perfect_count += 1
	order_happy = right and quality >= 21.0
	var card := order_panels[0]
	card.pivot_offset = card.size * 0.5
	var bounce := card.create_tween()
	bounce.tween_property(card, "scale", Vector2(1.045, 1.045), 0.18).set_trans(Tween.TRANS_BACK)
	bounce.tween_property(card, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK)
	sfx("serve")
	if not right:
		sfx("order_bad")
	elif perfect:
		sfx("perfect")
	else:
		sfx("good")
	pop_text("%s +%d" % ["完美！" if perfect else ("谢谢你！" if order_happy else "下次加油"), points], Vector2(1030, 283), UITheme.GOOD if right else UITheme.BAD, 36)
	var tw := rice.create_tween()
	tw.tween_property(rice, "position", Vector2(1080, 160), 0.58).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(rice, "scale", Vector2(0.42, 0.42), 0.58)


func _reset_work() -> void:
	phase = SCOOP
	scoop_fill = 0.0
	scoop_held = false
	scoop_points = 0.0
	shape_points = 0.0
	nori_points = 0.0
	shape_beat = 0
	beat_time = 0.0
	nori_time = 0.0
	chosen_fill = -1
	order_happy = false
	auto_clock = 0.0
	auto_mark = -1
	if rice:
		rice.position = Vector2(645, 315)
		rice.scale = Vector2.ONE
		rice.texture = load(ART + "rice_loose.png")
		rice.visible = false
	if nori:
		nori.visible = false
	_phase_changed()


func _phase_changed() -> void:
	auto_clock = 0.0
	if rice:
		rice.visible = phase != SCOOP
	if nori:
		nori.visible = phase == NORI
	if paddle:
		paddle.visible = phase == SCOOP
		if phase == SCOOP:
			paddle.position = Vector2(115, 300)
	if phase == SHAPE:
		rice.texture = load(ART + "rice_lumpy.png")
	if phase == NORI:
		rice.texture = load(ART + "rice_triangle.png")
	_update_labels()


func _new_order() -> Dictionary:
	var max_p := rng.randf_range(36.0, 42.0)
	return {"person": rng.randi_range(0, 2), "filling": rng.randi_range(0, 3), "patience": max_p, "max_patience": max_p}


func _refresh_orders() -> void:
	if _home_meal(): return
	for i in 3:
		var o: Dictionary = orders[i]
		var person: String = PEOPLE[int(o.person)]
		var expression := "happy" if i == 0 and order_happy else "neutral"
		var face_key := "%s_%s" % [person, expression]
		var icon_key: String = FILL_ART[int(o.filling)]
		if face_key != face_keys[i]:
			# These are practice tickets, not claims that these neighbours are present.
			order_faces[i].texture = null
			face_keys[i] = face_key
		if icon_key != icon_keys[i]:
			order_icons[i].texture = load(ART + icon_key)
			icon_keys[i] = icon_key
		order_names[i].text = FILL_NAMES[int(o.filling)]
		var width := 310.0 if i == 0 else 211.0
		var ratio := clampf(float(o.patience) / float(o.max_patience), 0.0, 1.0)
		order_bars[i].size.x = width * ratio
		order_bars[i].color = UITheme.BAD if ratio < 0.26 else (UITheme.ACCENT if ratio < 0.5 else UITheme.GOOD)


func _update_labels() -> void:
	if not phase_label:
		return
	if _home_meal():
		phase_label.text = "捏出三个角 · %d/3" % shape_beat
		instruction.text = "下一下按 D，或点击饭团" if shape_beat % 2 == 1 else "下一下按 A，或点击饭团"
		detail.text = "这一小份先试手感，回厨房包成两份"
		combo_label.text = "慢慢来，米料不会因为退出而丢掉"
		set_status("把边缘轻轻收拢，不用赶拍子。")
		return
	var steps := ["① 盛饭", "② 放馅", "③ 捏形 · %d/3" % shape_beat, "④ 包海苔", "饭团送出啦"]
	var hints := ["按住空格，米量到绿色区就松开", "看订单，按 1–4 或点食材碗", "看圆环收拢，按 A、D、A 三次", "海苔来到正中时按空格", "等下一位客人"]
	phase_label.text = steps[phase]
	instruction.text = hints[phase]
	detail.text = "已完成 %d 张练习单    超时 %d 张" % [served, missed]
	combo_label.text = "连做完美 %d 个" % combo if combo > 1 else "照着纸上的练习单，试试不同馅料"
	set_status("这一张练习单：%s饭团" % FILL_NAMES[int(orders[0].filling)])


func _draw_fx() -> void:
	if phase == SCOOP:
		var rect := Rect2(285, 386, 378, 35)
		fx.draw_rect(rect, Color(0.99, 0.96, 0.88, 0.92), true)
		fx.draw_rect(Rect2(285 + 378 * 0.60, 388, 378 * 0.16, 31), Color(0.35, 0.66, 0.37, 0.83), true)
		fx.draw_rect(Rect2(285, 388, 378 * scoop_fill, 31), Color(0.97, 0.66, 0.31, 0.78), true)
		fx.draw_rect(rect, UITheme.EDGE, false, 3.0)
		fx.draw_line(Vector2(285 + 378 * 0.68, 380), Vector2(285 + 378 * 0.68, 427), UITheme.INK, 3.0)
	elif phase == SHAPE:
		var radius := 155.0 - 110.0 * minf(beat_time / 0.86, 1.0)
		fx.draw_arc(Vector2(785, 477), 87.0, 0, TAU, 64, Color(0.27, 0.59, 0.38, 0.85), 7.0, true)
		fx.draw_arc(Vector2(785, 477), radius, 0, TAU, 64, Color(1, 0.82, 0.45, 0.95), 10.0, true)
	elif phase == NORI:
		fx.draw_line(Vector2(570, 570), Vector2(1070, 570), Color(0.33, 0.23, 0.16, 0.64), 5.0)
		fx.draw_rect(Rect2(697, 565, 66, 11), UITheme.GOOD, true)
	for i in 4:
		if phase == FILL:
			fx.draw_arc(Vector2(BOWL_X[i], 649), 112.0, 0, TAU, 48, Color(0.99, 0.87, 0.56, 0.9), 5.0, true)


func _scoop_quality(v: float) -> float:
	return clampf(1.0 - absf(v - 0.68) / 0.42, 0.0, 1.0)


func _beat_quality(t: float) -> float:
	return clampf(1.0 - absf(t - 0.535) / 0.31, 0.0, 1.0)


func _nori_quality(x: float) -> float:
	return clampf(1.0 - absf(x - 730.0) / 170.0, 0.0, 1.0)


func _order_score(right: bool, quality: float, speed: int, streak: int) -> int:
	return (60 if right else 15) + roundi(clampf(quality, 0.0, 40.0)) + clampi(speed, 0, 15) + mini(maxi(streak - 1, 0) * 8, 24)


func _patience_expired(remaining: float) -> bool:
	return remaining <= 0.0


func _show_feedback(points: float, at: Vector2) -> void:
	if points >= 0.85 * (12.0 if phase == FILL else 7.0):
		pop_text("完美！", at, UITheme.GOOD, 30)
	else:
		pop_text("再稳一点", at, UITheme.ACCENT, 27)


func mg_result_lines() -> Array:
	if _home_meal(): return ["三个角收拢了。回到厨房，用这包米料包成两份饭团。"]
	return ["送出了 %d 个饭团，%d 个完美" % [served, perfect_count], "等不及离开的客人：%d 位" % missed]


func mg_simulate(skill: float, seed: int) -> int:
	if _home_meal():
		served = 1
		shape_beat = 3
		return 0
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var s := clampf(skill, 0.0, 1.0)
	var elapsed := 0.0
	var total := 0
	var streak := 0
	var queue: Array[Dictionary] = []
	for i in 3:
		var patience := r.randf_range(36.0, 42.0)
		queue.append({"due": patience, "max": patience})
	while elapsed < 75.0:
		var wait := r.randf_range(0.0, 1.0)
		var cost := 13.6 - 5.2 * s + wait
		if elapsed + cost > 75.0:
			break
		elapsed += cost
		var current: Dictionary = queue[0]
		var active_survived := float(current.due) > elapsed
		for i in range(queue.size() - 1, -1, -1):
			if _patience_expired(float(queue[i].due) - elapsed):
				queue.remove_at(i)
				var replacement_patience := r.randf_range(36.0, 42.0)
				queue.append({"due": elapsed + replacement_patience, "max": replacement_patience})
				streak = 0
		if not active_survived:
			continue
		var scoop_error := (0.51 - 0.45 * s) * r.randf_range(0.55, 1.0)
		var beat_error := (0.39 - 0.35 * s) * r.randf_range(0.6, 1.0)
		var nori_error := (0.47 - 0.42 * s) * r.randf_range(0.55, 1.0)
		var right := r.randf() < (0.18 + 0.82 * s)
		var quality := 12.0 * clampf(1.0 - scoop_error / 0.42, 0, 1)
		quality += 21.0 * clampf(1.0 - beat_error / 0.31, 0, 1)
		quality += 7.0 * clampf(1.0 - nori_error / 0.47, 0, 1)
		var speed := roundi(15.0 * clampf((float(current.due) - elapsed) / float(current.max), 0, 1))
		var perfect := right and quality >= 35.5
		streak = streak + 1 if perfect else 0
		total += _order_score(right, quality, speed, streak)
		queue.pop_front()
		var next_patience := r.randf_range(36.0, 42.0)
		queue.append({"due": elapsed + next_patience, "max": next_patience})
	return total


func mg_self_test() -> Array:
	var checks := []
	checks.append(["米量正中最高分", _scoop_quality(0.68) == 1.0 and _scoop_quality(0.3) < 0.1])
	checks.append(["捏形节拍中心最高分", _beat_quality(0.535) == 1.0 and _beat_quality(0.05) == 0.0])
	checks.append(["海苔居中最高分", _nori_quality(730.0) == 1.0 and _nori_quality(900.0) == 0.0])
	checks.append(["正确馅料比错误高45分", _order_score(true, 20, 5, 0) - _order_score(false, 20, 5, 0) == 45])
	checks.append(["质量与耐心加分封顶", _order_score(true, 100, 100, 0) == 115])
	checks.append(["连做完美有上限", _order_score(true, 40, 15, 6) == 139])
	checks.append(["空碗与错馅仍有分", _order_score(false, 0, 0, 0) == 15])
	checks.append(["耐心归零离开，正值仍等待", _patience_expired(0.0) and not _patience_expired(0.001)])
	checks.append(["星级边界严格", stars_for(299) == 0 and stars_for(300) == 1 and stars_for(550) == 2 and stars_for(870) == 3])
	checks.append(["满分九单可得三星", 9 * _order_score(true, 40, 10, 0) >= 870])
	checks.append(["零技能不到一星", stars_for(mg_simulate(0.0, 7)) == 0])
	checks.append(["满技能达到三星", stars_for(mg_simulate(1.0, 7)) == 3])
	checks.append(["模拟种子稳定", mg_simulate(0.62, 9) == mg_simulate(0.62, 9)])
	return checks


func _image(file: String, pos: Vector2, extent: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if file != "":
		t.texture = load(ART + file)
	t.position = pos
	t.size = extent
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _label(value: String, font_size: int, color: Color, pos: Vector2) -> Label:
	var l := UITheme.label(value, font_size, color)
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
