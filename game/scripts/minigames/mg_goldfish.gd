extends MiniGame

const WATER := Rect2(47.0, 62.0, 1144.0, 631.0)
const PAPER_RADIUS := 53.0
const FISH_POINTS := [10, 20, 30, 60]
const FISH_WEIGHT := [8.0, 13.0, 17.0, 29.0]
const FISH_SPEED := [94.0, 64.0, 107.0, 76.0]
const FISH_NAMES := ["小红", "黑出目金", "三色", "黄金"]
const FISH_TEX := [preload("res://assets/minigames/goldfish/red.png"), preload("res://assets/minigames/goldfish/black.png"), preload("res://assets/minigames/goldfish/calico.png"), preload("res://assets/minigames/goldfish/golden.png")]
const POI_TEX := [preload("res://assets/minigames/goldfish/poi_dry.png"), preload("res://assets/minigames/goldfish/poi_wet.png"), preload("res://assets/minigames/goldfish/poi_torn.png")]

var fish: Array[Dictionary] = []
var poi_pos := Vector2(610, 380)
var poi_target := Vector2(610, 380)
var poi_dipped := false
var mouse_dip := false
var key_dip := false
var key_dir := Vector2.ZERO
var keys := {"left": false, "right": false, "up": false, "down": false}
var durability := 100.0
var poi_left := 3
var replace_wait := 0.0
var spawn_wait := 0.0
var caught := 0
var catches := [0, 0, 0, 0]
var swim_t := 0.0
var auto_pause := 0.0
var auto_hold := 0.0
var auto_goal := -1
var auto_catches := 0
var auto_elapsed := 0.0
var _bg: TextureRect
var _bowl: Sprite2D
var _poi: Sprite2D
var _meter_fill: ColorRect
var _meter_label: Label
var _poi_label: Label
var _catch_label: Label
var _ripples: Array[Dictionary] = []
var _ripple_layer: RippleLayer

class RippleLayer extends Control:
	var rings: Array[Dictionary] = []
	func _draw() -> void:
		for ring in rings:
			var radius: float = ring.radius
			var alpha: float = ring.alpha
			draw_arc(ring.pos, radius, 0.0, TAU, 48, Color(0.96, 1.0, 1.0, alpha), 2.6, true)
			draw_arc(ring.pos, radius + 9.0, 0.0, TAU, 48, Color(0.82, 0.95, 1.0, alpha * 0.4), 1.4, true)

func mg_info() -> Dictionary:
	return {"title": "捞金鱼", "subtitle": "夏日庭院 · 一池清凉", "rules": [
		"把纸捞网移到金鱼身边，按住沉入水中，松开时捞起。",
		"动作太快会惊走金鱼；泡水太久或捞得太重，纸会破。",
		"你有 3 个纸捞网，60 秒内尽量多捞几条吧。"
	], "controls": "鼠标移动 · 按住左键入水／松开捞起 · 方向键/WASD 移动 · 空格入水 · Esc 离开",
	"stars": [50, 130, 250], "duration": 60.0, "unit": "分"}

func mg_build(_stage: Control) -> void:
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.texture = preload("res://assets/minigames/goldfish/tank.png")
	_bg.position = Vector2.ZERO
	_bg.size = PLAY_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_bg)
	_bowl = Sprite2D.new()
	_bowl.texture = preload("res://assets/minigames/goldfish/bowl.png")
	_bowl.position = Vector2(1368, 357)
	stage.add_child(_bowl)
	_ripple_layer = RippleLayer.new()
	_ripple_layer.size = PLAY_SIZE
	_ripple_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_ripple_layer)
	_poi = Sprite2D.new()
	_poi.texture = POI_TEX[0]
	stage.add_child(_poi)
	var side_title := UITheme.label("今日收获", 30, Color(0.99, 0.94, 0.82))
	side_title.position = Vector2(1251, 49)
	side_title.add_theme_color_override("font_shadow_color", Color(0.24, 0.16, 0.14, 0.75))
	side_title.add_theme_constant_override("shadow_offset_x", 2)
	side_title.add_theme_constant_override("shadow_offset_y", 3)
	stage.add_child(side_title)
	_catch_label = UITheme.label("0 条", 28, Color(0.98, 0.95, 0.87))
	_catch_label.position = Vector2(1300, 95)
	_catch_label.add_theme_color_override("font_shadow_color", Color(0.23, 0.15, 0.1, 0.8))
	stage.add_child(_catch_label)
	var card := Panel.new()
	card.position = Vector2(1217, 555)
	card.size = Vector2(318, 175)
	card.add_theme_stylebox_override("panel", UIKitStyles.surface("hud",18))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(card)
	_poi_label = UITheme.label("纸捞网  ● ● ●", 26)
	_poi_label.position = Vector2(1235, 569)
	stage.add_child(_poi_label)
	_meter_label = UITheme.label("纸面 100%", 23, UITheme.INK_SOFT)
	_meter_label.position = Vector2(1235, 613)
	stage.add_child(_meter_label)
	var track := ColorRect.new()
	track.color = Color(0.78, 0.81, 0.76)
	track.position = Vector2(1238, 662)
	track.size = Vector2(273, 17)
	stage.add_child(track)
	_meter_fill = ColorRect.new()
	_meter_fill.color = UITheme.GOOD
	_meter_fill.position = track.position
	_meter_fill.size = track.size
	stage.add_child(_meter_fill)

func mg_reset() -> void:
	for f in fish:
		if is_instance_valid(f.sprite):
			f.sprite.queue_free()
	fish.clear()
	for c in stage.get_children():
		if c is Sprite2D and c != _bowl and c != _poi:
			c.queue_free()
	poi_pos = WATER.get_center()
	poi_target = poi_pos
	poi_dipped = false
	mouse_dip = false
	key_dip = false
	keys = {"left": false, "right": false, "up": false, "down": false}
	durability = 100.0
	poi_left = 3
	replace_wait = 0.0
	spawn_wait = 0.0
	caught = 0
	catches = [0, 0, 0, 0]
	swim_t = 0.0
	auto_pause = 0.35
	auto_hold = 0.0
	auto_goal = -1
	auto_catches = 0
	auto_elapsed = 0.0
	_ripples.clear()
	for type_id in [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3]:
		_spawn_fish(type_id)
	_update_ui()
	_update_poi()
	set_status("轻轻靠近，趁金鱼游进纸圈时松手")

func mg_process(delta: float) -> void:
	swim_t += delta
	if replace_wait > 0.0:
		replace_wait -= delta
		if replace_wait <= 0.0 and poi_left > 0:
			durability = 100.0
			_poi.visible = true
			_update_ui()
			sfx("new_poi")
			pop_text("新纸捞网", poi_pos + Vector2(-40, -100), UITheme.ACCENT, 29)
	var dir := Vector2(float(keys.right) - float(keys.left), float(keys.down) - float(keys.up))
	if dir.length_squared() > 0.0:
		poi_target = _water_clamp(poi_target + dir.normalized() * 410.0 * delta)
	elif not auto:
		poi_target = _water_clamp(stage_mouse())
	var before := poi_pos
	poi_pos = poi_pos.lerp(poi_target, minf(1.0, delta * 9.5))
	var speed := poi_pos.distance_to(before) / maxf(delta, 0.001)
	if poi_dipped and replace_wait <= 0.0:
		durability -= _water_drain(delta, speed)
		if durability <= 0.0:
			_tear()
		elif int(swim_t * 7.0) != int((swim_t - delta) * 7.0):
			_add_ripple(poi_pos, 38.0, 0.45)
	_update_poi()
	for i in range(fish.size()):
		_move_fish(i, delta)
	spawn_wait -= delta
	if fish.size() < 13 and spawn_wait <= 0.0:
		var t := _random_type()
		_spawn_fish(t)
		spawn_wait = rng.randf_range(0.8, 1.5)
	for ring in _ripples:
		ring.radius += delta * 80.0
		ring.alpha -= delta * 0.75
	for i in range(_ripples.size() - 1, -1, -1):
		if _ripples[i].alpha <= 0.0:
			_ripples.remove_at(i)
	_ripple_layer.rings = _ripples
	_ripple_layer.queue_redraw()
	_update_ui()

func mg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_dip = event.pressed
		_set_dipped(mouse_dip or key_dip)
	elif event is InputEventKey and not event.is_echo():
		var down: bool = event.pressed
		match event.physical_keycode:
			KEY_A, KEY_LEFT: keys.left = down
			KEY_D, KEY_RIGHT: keys.right = down
			KEY_W, KEY_UP: keys.up = down
			KEY_S, KEY_DOWN: keys.down = down
			KEY_SPACE:
				key_dip = down
				_set_dipped(mouse_dip or key_dip)

func _set_dipped(want: bool) -> void:
	if replace_wait > 0.0 or poi_left <= 0 or want == poi_dipped:
		return
	poi_dipped = want
	if want:
		sfx("water_in")
		_add_ripple(poi_pos, 46.0, 0.8)
	else:
		sfx("water_out")
		_lift()
		_add_ripple(poi_pos, 35.0, 0.75)
	_update_poi()

func _lift() -> void:
	var found: Array[int] = []
	var types: Array[int] = []
	for i in range(fish.size()):
		if _in_paper(poi_pos, fish[i].pos):
			found.append(i)
			types.append(fish[i].type)
	if found.is_empty():
		set_status("差一点，再轻轻试试")
		sfx("escape")
		return
	durability -= _lift_cost(types)
	if durability <= 0.0:
		_tear()
		return
	var gained := _score_types(types)
	add_score(gained)
	caught += found.size()
	for t in types:
		catches[t] += 1
	for j in range(found.size() - 1, -1, -1):
		var f: Dictionary = fish[found[j]]
		fish.remove_at(found[j])
		_fly_to_bowl(f)
	auto_catches += found.size()
	var praise := "好手气！" if found.size() > 1 else ("黄金！" if types.has(3) else "捞到了！")
	pop_text("%s +%d" % [praise, gained], poi_pos + Vector2(-25, -50), UITheme.GOOD, 33)
	sfx("catch")
	if found.size() > 1 or types.has(3):
		sfx("perfect")
	else:
		sfx("good")
	set_status("慢慢来，纸还剩 %d%%" % ceili(durability))
	_add_ripple(poi_pos, 45.0, 0.9)

func _fly_to_bowl(f: Dictionary) -> void:
	var sp: Sprite2D = f.sprite
	var target := _bowl.position + Vector2(rng.randf_range(-54, 54), rng.randf_range(-50, 50))
	var tw := sp.create_tween().set_parallel(true)
	tw.tween_property(sp, "position", target, 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "rotation", sp.rotation + TAU * 0.65, 0.65)
	tw.tween_property(sp, "scale", Vector2(0.42, 0.42), 0.65)
	tw.chain().tween_callback(sp.queue_free)

func _tear() -> void:
	if replace_wait > 0.0:
		return
	durability = 0.0
	poi_dipped = false
	mouse_dip = false
	key_dip = false
	poi_left -= 1
	_poi.texture = POI_TEX[2]
	_add_ripple(poi_pos, 50.0, 1.0)
	sfx("tear")
	sfx("splash")
	pop_text("纸破了！", poi_pos + Vector2(-20, -70), UITheme.BAD, 36)
	if poi_left <= 0:
		set_status("三个纸捞网都用完啦")
		end_round()
	else:
		set_status("等一下，换张新的纸捞网")
		replace_wait = 1.05

func _spawn_fish(t: int) -> void:
	var pos := Vector2(rng.randf_range(WATER.position.x + 90.0, WATER.end.x - 70.0), rng.randf_range(WATER.position.y + 65.0, WATER.end.y - 55.0))
	var angle := rng.randf_range(0.0, TAU)
	var sp := Sprite2D.new()
	sp.texture = FISH_TEX[t]
	sp.position = pos
	sp.rotation = angle
	sp.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.83, 1.0))
	stage.add_child(sp)
	stage.move_child(sp, _ripple_layer.get_index())
	fish.append({"type": t, "pos": pos, "vel": Vector2.RIGHT.rotated(angle) * FISH_SPEED[t], "sprite": sp, "turn": rng.randf_range(-1.0, 1.0), "turn_wait": rng.randf_range(0.3, 1.3), "startle": 0.0, "phase": rng.randf_range(0.0, TAU), "depth": rng.randf_range(0.86, 1.02)})

func _random_type() -> int:
	var roll := rng.randf()
	if roll < 0.54: return 0
	if roll < 0.79: return 1
	if roll < 0.98: return 2
	for f in fish:
		if f.type == 3:
			return 0
	return 3

func _move_fish(i: int, delta: float) -> void:
	var f: Dictionary = fish[i]
	f.turn_wait -= delta
	if f.turn_wait <= 0.0:
		f.turn = rng.randf_range(-1.0, 1.0)
		f.turn_wait = rng.randf_range(0.5, 1.4) / (1.5 if f.type == 2 else 1.0)
	var desired: Vector2 = f.vel.normalized().rotated(float(f.turn) * delta * (1.2 if f.type == 2 else 0.7))
	var margin := 70.0
	if f.pos.x < WATER.position.x + margin: desired.x += 1.5
	if f.pos.x > WATER.end.x - margin: desired.x -= 1.5
	if f.pos.y < WATER.position.y + margin: desired.y += 1.5
	if f.pos.y > WATER.end.y - margin: desired.y -= 1.5
	var separation := Vector2.ZERO
	for j in range(fish.size()):
		if i == j: continue
		var off: Vector2 = f.pos - fish[j].pos
		var d2 := off.length_squared()
		if d2 > 1.0 and d2 < 5500.0:
			separation += off.normalized() * (1.0 - sqrt(d2) / 75.0)
	desired += separation * 0.85
	f.startle = maxf(0.0, float(f.startle) - delta)
	if poi_dipped and f.startle <= 0.0 and f.pos.distance_to(poi_pos) < 137.0 and _should_startle(f.pos, f.vel, poi_pos, poi_pos.distance_to(poi_target) * 9.5):
		desired += (f.pos - poi_pos).normalized() * 4.0
		f.startle = 0.85
		sfx("splash", -13.0, 1.2)
	var heading: Vector2 = desired.normalized() if desired.length_squared() > 0.01 else f.vel.normalized()
	var speed: float = FISH_SPEED[int(f.type)] * (1.8 if f.startle > 0.3 else 1.0)
	f.vel = f.vel.lerp(heading * speed, minf(1.0, delta * 3.5))
	f.pos = _fish_clamp(f.pos + f.vel * delta)
	var sp: Sprite2D = f.sprite
	sp.position = f.pos
	sp.rotation = f.vel.angle() + sin(swim_t * 8.0 + float(f.phase)) * 0.065
	sp.scale = Vector2(float(f.depth), float(f.depth) * (1.0 + sin(swim_t * 12.0 + float(f.phase)) * 0.065))

func _water_clamp(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, WATER.position.x + 62.0, WATER.end.x - 65.0), clampf(p.y, WATER.position.y + 65.0, WATER.end.y - 80.0))

func _fish_clamp(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, WATER.position.x + 34.0, WATER.end.x - 34.0), clampf(p.y, WATER.position.y + 32.0, WATER.end.y - 32.0))

func _water_drain(delta: float, speed: float) -> float:
	return delta * (3.5 + minf(speed, 500.0) * 0.025)

func _lift_cost(types: Array[int]) -> float:
	var cost := 0.0
	for t in types:
		cost += FISH_WEIGHT[t]
	return cost

func _score_types(types: Array[int]) -> int:
	var value := 0
	for t in types:
		value += FISH_POINTS[t]
	return value

func _in_paper(center: Vector2, target: Vector2) -> bool:
	return center.distance_squared_to(target) <= PAPER_RADIUS * PAPER_RADIUS

func _should_startle(pos: Vector2, vel: Vector2, paper: Vector2, paper_speed: float) -> bool:
	var to_paper := (paper - pos).normalized()
	return paper_speed > 125.0 or vel.normalized().dot(to_paper) > 0.25

func _add_ripple(pos: Vector2, radius: float, alpha: float) -> void:
	_ripples.append({"pos": pos, "radius": radius, "alpha": alpha})
	if _ripples.size() > 20:
		_ripples.pop_front()

func _update_poi() -> void:
	_poi.position = poi_pos + Vector2(21, 36)
	if replace_wait <= 0.0 and poi_left > 0:
		_poi.texture = POI_TEX[1] if poi_dipped or durability < 70.0 else POI_TEX[0]
	_poi.modulate = Color(1.0, 1.0, 1.0, 0.78 if poi_dipped else 1.0)
	_poi.scale = Vector2(0.94, 0.94) if poi_dipped else Vector2.ONE

func _update_ui() -> void:
	_poi_label.text = "纸捞网  " + "● ".repeat(poi_left) + "○ ".repeat(3 - poi_left)
	_meter_label.text = "纸面 %d%%" % ceili(maxf(0.0, durability))
	_meter_fill.size.x = 273.0 * maxf(0.0, durability) / 100.0
	_meter_fill.color = UITheme.GOOD if durability > 55.0 else (UITheme.ACCENT if durability > 25.0 else UITheme.BAD)
	_catch_label.text = "%d 条" % caught

func mg_auto(delta: float) -> void:
	auto_elapsed += delta
	if replace_wait > 0.0 or fish.is_empty(): return
	if auto_pause > 0.0:
		auto_pause -= delta
		return
	if auto_hold > 0.0:
		auto_hold -= delta
		if auto_hold <= 0.0:
			_set_dipped(false)
			auto_pause = rng.randf_range(3.3, 4.0)
			auto_goal = -1
		return
	if auto_goal < 0 or auto_goal >= fish.size():
		auto_goal = _auto_choose_fish()
	var f: Dictionary = fish[auto_goal]
	poi_target = _water_clamp(f.pos - f.vel.normalized() * 22.0)
	if poi_pos.distance_to(f.pos) < 41.0:
		_set_dipped(true)
		auto_hold = rng.randf_range(0.16, 0.29)
		poi_target = _water_clamp(f.pos + f.vel * auto_hold * 0.2)

func _auto_choose_fish() -> int:
	var best_idx := 0
	var best_value := -100000.0
	for i in range(fish.size()):
		var f: Dictionary = fish[i]
		var preference: float = [44.0, 49.0, 30.0, -200.0][int(f.type)]
		var value := preference - poi_pos.distance_to(f.pos) * 0.18
		if value > best_value:
			best_value = value
			best_idx = i
	return best_idx

func mg_result_lines() -> Array:
	return ["捞到 %d 条金鱼 · 用了 %d 张纸捞网" % [caught, 3 - poi_left + (1 if poi_left > 0 else 0)],
		"小红 %d · 黑出目金 %d · 三色 %d · 黄金 %d" % [catches[0], catches[1], catches[2], catches[3]]]

func mg_simulate(skill: float, seed: int) -> int:
	caught = 0
	var srng := RandomNumberGenerator.new()
	srng.seed = seed
	var ability := clampf(skill, 0.0, 1.0)
	var paper := 100.0
	var sheets := 3
	var total := 0
	var elapsed := 0.0
	while elapsed < 60.0 and sheets > 0:
		var encounter := srng.randf()
		var t := 0 if encounter < 0.55 else (1 if encounter < 0.8 else (2 if encounter < 0.98 else 3))
		var distance := srng.randf_range(0.0, 1.0)
		var facing := srng.randf_range(0.0, 1.0)
		var timing := srng.randf_range(0.0, 1.0)
		var caught_now := ability > 0.0 and distance < 0.18 + 0.8 * ability and facing < 0.2 + 0.75 * ability and timing < 0.12 + 0.86 * ability
		elapsed += 2.2 + (1.0 - ability) * 0.8
		paper -= 4.0 + (1.0 - ability) * 4.0
		if caught_now:
			paper -= FISH_WEIGHT[t]
			if paper > 0.0:
				total += FISH_POINTS[t]
				caught += 1
		if paper <= 0.0:
			sheets -= 1
			paper = 100.0
	return total

func mg_outcome() -> Dictionary:
	return {"started": round_started, "caught": caught}

func mg_self_test() -> Array:
	var checks := []
	checks.append(["四种鱼分值", _score_types([0, 1, 2, 3]) == 120])
	checks.append(["多鱼纸重累加", is_equal_approx(_lift_cost([0, 2, 3]), 54.0)])
	checks.append(["纸圈边缘可捞", _in_paper(Vector2.ZERO, Vector2(PAPER_RADIUS, 0))])
	checks.append(["纸圈外不能捞", not _in_paper(Vector2.ZERO, Vector2(PAPER_RADIUS + 1.0, 0))])
	checks.append(["高速入水惊鱼", _should_startle(Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, 200.0)])
	checks.append(["鱼背后慢靠不惊鱼", not _should_startle(Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, 40.0)])
	checks.append(["正面慢靠仍会惊鱼", _should_startle(Vector2.ZERO, Vector2.RIGHT, Vector2.RIGHT, 40.0)])
	checks.append(["游动更快纸耗更快", _water_drain(1.0, 200.0) > _water_drain(1.0, 0.0)])
	checks.append(["满纸承得住单条黄金", 100.0 - _lift_cost([3]) > 0.0])
	checks.append(["残纸捞重鱼会破", 20.0 - _lift_cost([3]) <= 0.0])
	checks.append(["三星目标可达", stars_for(mg_simulate(1.0, 3)) == 3])
	checks.append(["零技巧没有星", stars_for(mg_simulate(0.0, 3)) == 0])
	checks.append(["模拟相同种子稳定", mg_simulate(0.62, 17) == mg_simulate(0.62, 17)])
	return checks
