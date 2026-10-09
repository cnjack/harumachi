class_name CalendarAdvance
extends Node
## Agreed dates advance real settlements one day at a time, with a fail-stop retry.
var main: Node
var cancelled := false

static func appointments() -> Array[Dictionary]:
	var G := GameState
	var out: Array[Dictionary] = []
	if G.at_step("Q05", "start") and G.market_ready_reasons().is_empty():
		var day: int = G.next_market_day(G.weekday() == G.SATURDAY and G.minute >= G.MARKET_CLOSE)
		out.append({"id":"market", "title":"首次集市", "day":day, "minute":G.MARKET_OPEN})
	if G.qstate("Q05") == "done" and G.flags.get("summer_invitation",{}).get("presented",false) and G.qstate("Q14") != "done" and G.day <= 17:
		if G.day < 17 or G.minute < 22 * 60: out.append({"id":"summer", "title":"晴町夏祭", "day":17, "minute":int(float(G.festival("natsumatsuri").start) * 60)})
	if G.at_step("Q15", "watch_hanabi") and G.day <= 24:
		if G.day < 24 or G.minute < 21 * 60: out.append({"id":"hanabi", "title":"晴川花火", "day":24, "minute":int(float(G.festival("hanabi").start) * 60)})
	return out

static func appointment(id: String) -> Dictionary:
	for entry: Dictionary in appointments():
		if str(entry.id) == id: return entry
	return {}

func setup(scene: Node) -> void: main = scene

func run(id: String) -> bool:
	var G := GameState
	if id == "retry_save":
		if G.calendar_pending_save != G.day: return false
		if not G.save_game(): return false
		if G.minute >= G.DAY_END:
			await main._on_late_night()
			return G.calendar_pending_save != G.day
		return true
	var target: Dictionary = appointment(id)
	if target.is_empty():
		G.toast.emit("这次约定尚未准备齐，或已经过期。先看J里的当前进度。")
		return false
	cancelled = false
	G.lock_input("calendar_advance")
	await main.ui.fade_out(.25)
	main.world.set_region("town")
	G.player_region = "town"
	main._put_in_room(HouseBuilder.ORIGIN + Vector3(-4.6, .05, -.6))
	var ok := true
	# A failed day's settlement already ran. Retry only its write, never its crop/reward callbacks.
	if G.calendar_pending_save == G.day:
		ok = G.save_game()
		if ok: G.calendar_pending_save = -1
	while ok and G.day < int(target.day) and not cancelled:
		var wake: float = float(target.minute) if G.day + 1 == int(target.day) else float(G.WAKE_MIN)
		ok = G.advance_day(wake)
		if not ok:
			G.calendar_pending_save = G.day
			break
		await get_tree().process_frame
	if ok and not cancelled and G.day == int(target.day) and G.minute < float(target.minute):
		G.skip_to(float(target.minute))
		ok = G.save_game()
		if not ok: G.calendar_pending_save = G.day
	main.world.sync_festivals()
	main.world.update_time(G.minute, G.weather, true)
	main.update_npcs(true)
	main.ui.set_hud_visible(true)
	await main.ui.fade_in(.25)
	G.unlock_input("calendar_advance")
	if not ok: G.toast.emit("日期推进在保存失败处停止。重试会先保存这一日，不重复结算。" + G.last_error)
	elif cancelled: G.toast.emit("先停在今天，已有结算与保存保留。")
	else: G.toast.emit("到%s约好的时间了，准备好了就从家里出门。" % str(target.title))
	return ok and not cancelled

func _input(event: InputEvent) -> void:
	if GameState._ui_locks.has("calendar_advance") and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancelled = true
		get_viewport().set_input_as_handled()
