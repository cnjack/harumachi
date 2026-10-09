extends MiniGame

const SIDE := 4
const CELL := 156.0
const BOARD_POS := Vector2(131, 65)
const BOARD_SIZE := Vector2(624, 624)
const MAP_PATH := "res://assets/minigames/puzzle/map.png"
const DESK_PATH := "res://assets/minigames/puzzle/desk.png"

var _board: Array[int] = []
var _gap := 15
var _moves := 0
var _trace: Array[int] = []
var _tile_nodes: Array[TextureRect] = []
var _number_labels: Array[Label] = []
var _numbers_on := false
var _busy := false
var _solved := false
var _won := false
var _queue: Array[Dictionary] = []
var _slide_tween: Tween
var _full_map: TextureRect
var _glow: ColorRect
var _board_frame: Panel
var _auto_cursor: Polygon2D
var _auto_plan: Array[int] = []
var _auto_index := 0
var _auto_wait := 0.0
var _auto_target := Vector2.ZERO
var _auto_cursor_velocity := 10.0


func mg_info() -> Dictionary:
	return {
		"title": "晴町地图拼图",
		"subtitle": "搬家时散开的地图，能帮忙拼好吗？",
		"rules": [
			"把 15 块地图滑回原位，让晴町重新连在一起。",
			"点击与空格同行或同列的拼块，可以一次推动一整排。",
			"右边有完整地图；按 H 可以查看拼块编号。",
			"240 秒内完成得分更高，移动次数越少越好。"
		],
		"controls": "鼠标点击拼块 · 方向键 / WASD 移动 · H 编号提示 · Esc 离开",
		"stars": [300, 650, 900],
		"duration": 240.0,
		"unit": "分"
	}


func mg_build(_stage: Control) -> void:
	var desk := TextureRect.new()
	desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desk.texture = load(DESK_PATH)
	desk.position = Vector2.ZERO
	desk.size = PLAY_SIZE
	desk.stretch_mode = TextureRect.STRETCH_SCALE
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(desk)

	_board_frame = Panel.new()
	_board_frame.position = BOARD_POS - Vector2(18, 18)
	_board_frame.size = BOARD_SIZE + Vector2(36, 36)
	_board_frame.add_theme_stylebox_override("panel", UIKitStyles.slot("normal",0))
	_board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_board_frame)
	var backing := ColorRect.new()
	backing.color = Color(0.24, 0.18, 0.13)
	backing.position = BOARD_POS
	backing.size = BOARD_SIZE
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(backing)

	var map_texture: Texture2D = load(MAP_PATH)
	for tile in range(15):
		var atlas := AtlasTexture.new()
		atlas.atlas = map_texture
		atlas.region = Rect2((tile % SIDE) * 256, (tile / SIDE) * 256, 256, 256)
		var image := TextureRect.new()
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.texture = atlas
		image.size = Vector2(CELL - 4, CELL - 4)
		image.stretch_mode = TextureRect.STRETCH_SCALE
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(image)
		_tile_nodes.append(image)
		var number := UITheme.label(str(tile + 1), 22, Color(1, 0.985, 0.91))
		number.position = Vector2(8, 5)
		number.add_theme_color_override("font_outline_color", Color(0.25, 0.16, 0.1, 0.9))
		number.add_theme_constant_override("outline_size", 7)
		number.visible = false
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image.add_child(number)
		_number_labels.append(number)

	_full_map = TextureRect.new()
	_full_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_full_map.texture = map_texture
	_full_map.position = BOARD_POS
	_full_map.size = BOARD_SIZE
	_full_map.stretch_mode = TextureRect.STRETCH_SCALE
	_full_map.modulate.a = 0.0
	_full_map.visible = false
	_full_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_full_map)
	_glow = ColorRect.new()
	_glow.color = Color(1.0, 0.77, 0.36, 0.22)
	_glow.position = BOARD_POS
	_glow.size = BOARD_SIZE
	_glow.modulate.a = 0.0
	_glow.visible = false
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = glow_material
	stage.add_child(_glow)

	var reference := Panel.new()
	reference.position = Vector2(889, 55)
	reference.size = Vector2(550, 652)
	reference.add_theme_stylebox_override("panel", UIKitStyles.surface("modal",0))
	reference.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(reference)
	var title := UITheme.label("搬家前的晴町", 34, UITheme.INK)
	title.position = Vector2(1016, 82)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(title)
	var subtitle := UITheme.label("对照这张小地图，把街道接起来吧。", 23, UITheme.INK_SOFT)
	subtitle.position = Vector2(964, 128)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(subtitle)
	var thumb_frame := Panel.new()
	thumb_frame.position = Vector2(981, 181)
	thumb_frame.size = Vector2(364, 364)
	thumb_frame.add_theme_stylebox_override("panel", UIKitStyles.slot("normal",0))
	thumb_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(thumb_frame)
	var thumb := TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.texture = map_texture
	thumb.position = Vector2(988, 188)
	thumb.size = Vector2(350, 350)
	thumb.stretch_mode = TextureRect.STRETCH_SCALE
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(thumb)
	var note := UITheme.label("樱花树在中央，商店街在北边。", 25, UITheme.INK_SOFT)
	note.position = Vector2(970, 572)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(note)
	var small_note := UITheme.label("按 H 看编号，再按一次收起", 22, UITheme.INK_SOFT)
	small_note.position = Vector2(1006, 619)
	small_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(small_note)

	_auto_cursor = Polygon2D.new()
	_auto_cursor.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 31), Vector2(8, 23), Vector2(15, 39), Vector2(22, 35), Vector2(14, 19), Vector2(26, 18)])
	_auto_cursor.color = Color(0.99, 0.95, 0.81)
	_auto_cursor.position = Vector2(1210, 580)
	_auto_cursor.visible = false
	stage.add_child(_auto_cursor)
	var edge := Line2D.new()
	edge.points = PackedVector2Array([Vector2(0, 0), Vector2(0, 31), Vector2(8, 23), Vector2(15, 39), Vector2(22, 35), Vector2(14, 19), Vector2(26, 18), Vector2(0, 0)])
	edge.width = 3.0
	edge.default_color = Color(0.29, 0.19, 0.13)
	_auto_cursor.add_child(edge)


func mg_reset() -> void:
	if _slide_tween and _slide_tween.is_running():
		_slide_tween.kill()
	var shuffled: Dictionary = _shuffle(rng.randi())
	_board = shuffled["board"]
	_trace = shuffled["trace"]
	_gap = int(shuffled["gap"])
	_moves = 0
	_busy = false
	_solved = false
	_won = false
	_queue.clear()
	_numbers_on = false
	for tile in range(15):
		_tile_nodes[tile].position = _tile_pos(_board.find(tile))
		_tile_nodes[tile].modulate.a = 1.0
		_number_labels[tile].visible = false
	_full_map.visible = false
	_full_map.modulate.a = 0.0
	_glow.visible = false
	_glow.modulate.a = 0.0
	_auto_plan.clear()
	for i in range(_trace.size() - 1, -1, -1):
		_auto_plan.append(_trace[i])
	_auto_index = 0
	_auto_wait = 0.8
	_auto_cursor.position = Vector2(1210, 580)
	_auto_cursor.visible = auto
	set_status("移动 0 次 · 找到空格旁边的拼块")


func mg_begin() -> void:
	_auto_cursor.visible = auto


func mg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p := stage_mouse() - BOARD_POS
		if p.x >= 0 and p.y >= 0 and p.x < BOARD_SIZE.x and p.y < BOARD_SIZE.y:
			_enqueue({"kind": "tile", "value": int(p.y / CELL) * SIDE + int(p.x / CELL)})
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_H:
				_numbers_on = not _numbers_on
				for n in _number_labels:
					n.visible = _numbers_on
				set_status("移动 %d 次 · %s" % [_moves, "编号已显示" if _numbers_on else "编号已收起"])
				sfx("hint")
			KEY_UP, KEY_W:
				_enqueue({"kind": "direction", "value": Vector2i(0, -1)})
			KEY_DOWN, KEY_S:
				_enqueue({"kind": "direction", "value": Vector2i(0, 1)})
			KEY_LEFT, KEY_A:
				_enqueue({"kind": "direction", "value": Vector2i(-1, 0)})
			KEY_RIGHT, KEY_D:
				_enqueue({"kind": "direction", "value": Vector2i(1, 0)})


func _enqueue(request: Dictionary) -> void:
	if _busy:
		_queue.append(request)
	else:
		_perform_request(request)


func _perform_request(request: Dictionary) -> void:
	var target := -1
	if request["kind"] == "tile":
		target = int(request["value"])
	else:
		var d: Vector2i = request["value"]
		var x := _gap % SIDE + d.x
		var y := _gap / SIDE + d.y
		if x >= 0 and x < SIDE and y >= 0 and y < SIDE:
			target = y * SIDE + x
	if not _slide_to(target):
		sfx("slide_blocked")


func _slide_to(target: int) -> bool:
	if not _can_slide(_gap, target):
		return false
	var step := _step_toward(_gap, target)
	var cursor := _gap
	_busy = true
	_slide_tween = create_tween().set_parallel(true)
	while cursor != target:
		var next := cursor + step
		var tile := _board[next]
		_board[cursor] = tile
		_board[next] = -1
		_slide_tween.tween_property(_tile_nodes[tile], "position", _tile_pos(cursor), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		cursor = next
	_gap = target
	_moves += 1
	set_status("移动 %d 次 · %s" % [_moves, "编号提示开启" if _numbers_on else "慢慢来，地图快接上了"])
	sfx("slide")
	_slide_tween.finished.connect(_on_slide_done)
	return true


func _on_slide_done() -> void:
	_busy = false
	if not playing():
		return
	if _is_solved(_board):
		_solve()
		return
	while not _queue.is_empty() and not _busy:
		_perform_request(_queue.pop_front())


func _solve() -> void:
	_solved = true
	_won = true
	_queue.clear()
	var seconds := ceili(240.0 - time_left)
	set_score(_solved_score(_moves, seconds))
	set_status("晴町的地图复原了！")
	sfx("solved")
	pop_text("地图复原啦！", Vector2(375, 335), UITheme.GOOD, 43)
	_full_map.visible = true
	_glow.visible = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_full_map, "modulate:a", 1.0, 0.65)
	for tile in _tile_nodes:
		tw.tween_property(tile, "modulate:a", 0.0, 0.5)
	var light_tw := create_tween()
	light_tw.tween_property(_glow, "modulate:a", 1.0, 0.32)
	light_tw.tween_property(_glow, "modulate:a", 0.0, 0.72)
	tw.chain().tween_interval(0.55)
	tw.chain().tween_callback(end_round)


func mg_time_up() -> void:
	if not _solved:
		set_score(25 * _right_count(_board))
		set_status("时间到，晴町还留着一点小秘密。")
		sfx("miss")
	end_round()


func mg_result_lines() -> Array:
	return ["%s · 移动 %d 次" % ["地图已复原" if _won else "时间到", _moves]]

func mg_outcome() -> Dictionary:
	return {"started": round_started, "solved": _won}


func mg_auto(delta: float) -> void:
	if _solved or _auto_index >= _auto_plan.size():
		return
	var target: int = _auto_plan[_auto_index]
	_auto_target = _tile_pos(target) + Vector2(CELL * 0.53, CELL * 0.53)
	_auto_cursor.position = _auto_cursor.position.lerp(_auto_target, minf(delta * _auto_cursor_velocity, 1.0))
	if _busy:
		return
	_auto_wait -= delta
	if _auto_wait > 0.0 or _auto_cursor.position.distance_to(_auto_target) > 12.0:
		return
	if _slide_to(target):
		_auto_index += 1
		_auto_wait = rng.randf_range(0.65, 0.95)
		if _auto_index % 11 == 0:
			_auto_wait += rng.randf_range(0.45, 0.9)
		_auto_cursor_velocity = rng.randf_range(8.0, 13.0)


func mg_simulate(skill: float, seed: int) -> int:
	_won = false
	var level := clampf(skill, 0.0, 1.0)
	var shuffled: Dictionary = _shuffle(seed)
	var board: Array[int] = shuffled["board"].duplicate()
	var gap := int(shuffled["gap"])
	var sim_rng := RandomNumberGenerator.new()
	sim_rng.seed = seed + 918273
	var elapsed := 0.0
	var moves := 0
	if level <= 0.0:
		while elapsed < 240.0:
			var neighbors := _adjacent_indices(gap)
			gap = _slide_array(board, gap, neighbors[sim_rng.randi_range(0, neighbors.size() - 1)])
			moves += 1
			elapsed += 3.45
		return 25 * _right_count(board)
	var trace: Array[int] = shuffled["trace"]
	var i := trace.size() - 1
	while i >= 0:
		var target: int = trace[i]
		var step := _step_toward(gap, target)
		var consumed := 1
		if sim_rng.randf() < level:
			while i - consumed >= 0 and consumed < 3 and int(trace[i - consumed]) - target == step:
				target = trace[i - consumed]
				consumed += 1
		var action_time := 3.3 - 2.6 * level + sim_rng.randf_range(0.0, 0.12) * (1.0 - level)
		if elapsed + action_time > 240.0:
			return 25 * _right_count(board)
		elapsed += action_time
		gap = _slide_array(board, gap, target)
		moves += 1
		i -= consumed
	if not _is_solved(board):
		return 25 * _right_count(board)
	_won = true
	return _solved_score(moves, ceili(elapsed))


func mg_self_test() -> Array:
	var checks := []
	var solved: Array[int] = []
	for i in range(15):
		solved.append(i)
	solved.append(-1)
	checks.append(["完整地图判定", _is_solved(solved)])
	checks.append(["角落只有两个相邻格", _adjacent_indices(0).size() == 2 and _adjacent_indices(15).size() == 2])
	checks.append(["跨行点击不会滑动", not _can_slide(15, 0) and not _can_slide(15, 15)])
	checks.append(["同一行可以推动整排", _can_slide(15, 12) and _can_slide(15, 13)])
	var sample := solved.duplicate()
	var gap := _slide_array(sample, 15, 12)
	checks.append(["整排滑动顺序与空格正确", gap == 12 and sample[15] == 14 and sample[14] == 13 and sample[13] == 12])
	checks.append(["逆向滑动可还原", _slide_array(sample, gap, 15) == 15 and _is_solved(sample)])
	checks.append(["得分按步数与秒数扣除", _solved_score(70, 50) == 980 and _solved_score(300, 240) == 0])
	checks.append(["超时只按正位拼块给分", 25 * _right_count(solved) == 375 and _right_count(sample) == 15])
	var shuffled: Dictionary = _shuffle(42)
	var trace: Array[int] = shuffled["trace"]
	checks.append(["打乱 70 到 90 步且至少 12 块错位", trace.size() >= 70 and trace.size() <= 90 and _misplaced(shuffled["board"]) >= 12])
	var undo_free := true
	for i in range(2, trace.size()):
		if trace[i] == trace[i - 2]:
			undo_free = false
	checks.append(["打乱不立即走回头路", undo_free])
	var reverse_board: Array[int] = shuffled["board"].duplicate()
	gap = int(shuffled["gap"])
	for i in range(trace.size() - 1, -1, -1):
		gap = _slide_array(reverse_board, gap, trace[i])
	checks.append(["每局打乱都能沿原路解开", gap == 15 and _is_solved(reverse_board)])
	checks.append(["模拟新手零星、熟手三星", stars_for(mg_simulate(0.0, 42)) == 0 and stars_for(mg_simulate(1.0, 42)) == 3])
	return checks


func _tile_pos(index: int) -> Vector2:
	return BOARD_POS + Vector2(index % SIDE, index / SIDE) * CELL + Vector2(2, 2)


func _can_slide(gap: int, target: int) -> bool:
	return target >= 0 and target < 16 and target != gap and (target / SIDE == gap / SIDE or target % SIDE == gap % SIDE)


func _step_toward(gap: int, target: int) -> int:
	if gap / SIDE == target / SIDE:
		return 1 if target > gap else -1
	return SIDE if target > gap else -SIDE


func _slide_array(board: Array[int], gap: int, target: int) -> int:
	if not _can_slide(gap, target):
		return gap
	var step := _step_toward(gap, target)
	while gap != target:
		var next := gap + step
		board[gap] = board[next]
		board[next] = -1
		gap = next
	return gap


func _adjacent_indices(index: int) -> Array[int]:
	var neighbors: Array[int] = []
	if index % SIDE > 0:
		neighbors.append(index - 1)
	if index % SIDE < SIDE - 1:
		neighbors.append(index + 1)
	if index / SIDE > 0:
		neighbors.append(index - SIDE)
	if index / SIDE < SIDE - 1:
		neighbors.append(index + SIDE)
	return neighbors


func _shuffle(seed: int) -> Dictionary:
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = seed
	var best := {}
	for _attempt in range(40):
		var board: Array[int] = []
		for tile in range(15):
			board.append(tile)
		board.append(-1)
		var gap := 15
		var previous := -1
		var trace: Array[int] = []
		var count := local_rng.randi_range(70, 90)
		for _step in range(count):
			var options := _adjacent_indices(gap)
			options.erase(previous)
			var old_gap := gap
			var target: int = options[local_rng.randi_range(0, options.size() - 1)]
			gap = _slide_array(board, gap, target)
			trace.append(old_gap)
			previous = old_gap
		best = {"board": board, "gap": gap, "trace": trace}
		if _misplaced(board) >= 12:
			return best
	return best


func _misplaced(board: Array[int]) -> int:
	var count := 0
	for i in range(15):
		if board[i] != i:
			count += 1
	return count


func _right_count(board: Array[int]) -> int:
	return 15 - _misplaced(board)


func _is_solved(board: Array[int]) -> bool:
	return board.size() == 16 and board[15] == -1 and _misplaced(board) == 0


func _solved_score(moves: int, seconds: int) -> int:
	return maxi(0, 1500 - 6 * moves - 2 * seconds)
