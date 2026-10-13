class_name ResidentVisits
extends RefCounted
## Invited visits, an optional appointment and its actual result live in the save database.
const TRIAL_POINT := Vector3(9.0, 0, 14.0)
const HOME_FOR := {"haru":"home_haru","aoi":"home_haru","mio":"home_mio","tanaka":"home_tanaka","ren":"home_ren","kazuko":"home_kazuko"}
const SCHEMES := {
	"near": {"name":"坐近一些，看小葵示范", "at":Vector2(-4.5,23.5), "rot":2},
	"path": {"name":"留宽通路，从东侧看", "at":Vector2(6.5,17.0), "rot":3}}

static func state() -> Dictionary:
	if not GameState.flags.get("resident_visits",{}) is Dictionary: GameState.flags.resident_visits={}
	if not GameState.flags.has("resident_visits"): GameState.flags.resident_visits={}
	var p: Dictionary=GameState.flags.resident_visits
	p.merge({"version":1,"phase":"quiet","tracked":false,"invitations":{},"visits":{},"blueprint_seen":false,"measured":false,"promise":{},"promise_history":[],"scheme":"","bench_uid":-1,"loan_received":false,"trial":{},"photo_path":"","photo_rendered":false,"photo_day":0,"photo_context":"","photo_compared":false,"followups":{},"choices":{},"resident_setup":false},false)
	# A later appointment is separate from an already completed comparison and its letters.
	# Repair older saves that regressed to "photo" or "promised" without replaying any event.
	if p.photo_compared:p.phase="settled"
	p.bench_uid=int(p.bench_uid)
	p.photo_day=int(p.photo_day)
	for key: String in p.visits: p.visits[key]=int(p.visits[key])
	# JSON-backed saves restore numbers as floats; retain the integer date schema.
	for records: Dictionary in [p.invitations,p.followups]:
		for entry: Dictionary in records.values():
			if entry.has("day"):entry.day=int(entry.day)
	if p.trial.has("day"):p.trial.day=int(p.trial.day)
	for appointment: Dictionary in [p.promise]+p.promise_history:
		for key: String in ["day","start","end","accepted_day"]:
			if appointment.has(key):appointment[key]=int(appointment[key])
	return p

static func invite_after_market(save_now: bool=true) -> void:
	var p: Dictionary=state()
	if GameState.qstate("Q05")!="done":return
	for room: String in ["home_haru","home_ren","home_kazuko"]:
		invite(room,"一起办过小集市")
	if p.phase=="quiet":
		p.phase="invited"
		if save_now:track()
	if save_now:commit()

static func invite(room: String,reason: String) -> void:
	if not state().invitations.has(room):state().invitations[room]={"day":GameState.day,"reason":reason}

static func unlocked(room: String) -> bool:
	var spec: Dictionary=ResidentPlaces.SPECS.get(room,{})
	if spec.is_empty():return false
	if str(spec.get("privacy","public"))=="public":return true
	return state().invitations.has(room)

static func access_reason(room: String) -> String:
	var spec: Dictionary=ResidentPlaces.SPECS.get(room,{})
	if spec.is_empty():return "这里没有通向屋内的门。"
	if not unlocked(room):
		return {"home_haru":"先一起办过小集市。春会请你来家里看看图纸。","toolshed":"先在春家看过图纸，再带着尺寸来问田中。","photo_room":"一起试过观看的位置后，澪会请你来比较照片。","home_mio":"在照片角共同选好邀请，再接受澪的回访邀请。","home_tanaka":"一起量过工具屋的木件后，田中会请你来吃晚饭。","home_ren":"先和莲一起办一次小集市，他会请你到后场。","home_kazuko":"一起收过小集市后，和子阿姨会留后间的门。"}.get(room,"先得到主人的邀请，再来敲门。")
	var h: float=GameState.hour()
	var opening: float=float(spec.get("open",8));var closing: float=float(spec.get("close",20))
	if h<opening or h>=closing:return "%s：%02d:00—%02d:00可以来。主人这会儿在忙自己的事。"%[str(spec.name),int(opening),int(closing)]
	if not (spec.get("owners",[]) as Array).is_empty() and (GameState.phase=="market" or GameState.festival_now()!=""):
		return "主人正在参加活动，去庭院或日历上的会场找找，散场后再来。"
	return ""

static func visit(room: String) -> void:
	if access_reason(room)!="":return
	state().visits[room]=GameState.day
	if room.begins_with("home_"):MainlineProgress.record_direction_action("visit")
	commit()

static func see_blueprint() -> void:
	var p: Dictionary=state()
	p.blueprint_seen=true
	if not p.measured:p.phase="blueprint"
	track()
	invite("toolshed","带春家的图纸去量现有木件")
	Progress.find("col_blueprint")
	commit()

static func measure() -> bool:
	if not state().blueprint_seen:return false
	var p: Dictionary=state();p.measured=true
	if p.trial.is_empty():p.phase="measured"
	invite("home_tanaka","一起量过木件，来看看田中的晚饭")
	commit();return true

static func arrange(day_offset: int=1) -> String:
	var p: Dictionary=state()
	if not p.measured:return "先和田中量过木件，再约春一起试坐。"
	if day_offset<1 or day_offset>7:return "约定从明天开始，最多约到七天后。"
	if not date_free(GameState.day+day_offset):return "那天傍晚街坊要参加节日或周六集市，换一个明确有空的日子。"
	if not p.promise.is_empty():p.promise_history.append(p.promise.duplicate(true))
	p.promise={"status":"accepted","day":GameState.day+day_offset,"start":17*60,"end":20*60,"accepted_day":GameState.day}
	if not p.photo_compared:p.phase="promised"
	track()
	commit();return ""

static func cancel() -> void:
	var p: Dictionary=state()
	if p.promise.is_empty():return
	p.promise.status="cancelled"
	p.resident_setup=true
	if not p.photo_compared:p.phase="measured" if p.trial.is_empty() else "photo"
	commit()

static func tick() -> void:
	var p: Dictionary=state()
	if p.promise.get("status","")!="accepted":return
	if GameState.day>int(p.promise.day) or GameState.day==int(p.promise.day) and GameState.minute>=int(p.promise.end):
		p.promise.status="missed";p.resident_setup=true
		# Day settlement owns its single final save. A minute callback must not create a second one.
		GameState.state_changed.emit()

static func appointment_now() -> bool:
	var a: Dictionary=state().promise
	return a.get("status","")=="accepted" and GameState.day==int(a.day) and GameState.minute>=int(a.start) and GameState.minute<int(a.end)

static func promise_text() -> String:
	var a: Dictionary=state().promise
	if a.is_empty():return ""
	match str(a.status):
		"accepted":return "约定 · 第%d天17:00—20:00，庭院和春试坐；纸签可改约"%int(a.day)
		"missed":return "这次没赶上。街坊先摆了简便座位；庭院纸签可约补试"
		"cancelled":return "已取消这次试坐，材料留着；庭院纸签可重新约"
	return ""

static func bench() -> Dictionary:
	for item: Dictionary in GameState.placements:
		if int(item.uid)==int(state().bench_uid) and item.item=="bench":return item
	return {}

static func choose_scheme(key: String) -> String:
	if not state().measured or not SCHEMES.has(key):return "先量过木件，再选观看位置。"
	var p: Dictionary=state()
	if not p.loan_received:
		if not GameState.can_add("bench"):return "给借来的长椅留一个背包位置。"
		GameState.add_item("bench",1,true);p.loan_received=true
	var previous: String=PlacementSystem.project_context
	PlacementSystem.project_context="space"
	var saved: Dictionary=GameState.to_dict().duplicate(true)
	var old: Dictionary=bench()
	if not old.is_empty() and not GameState.remove_placement(int(old.uid)):
		PlacementSystem.project_context=previous;return "旧长椅还收不起来，先清出一个背包位置。"
	var at: Vector2=SCHEMES[key].at
	var why: String=PlacementSystem.check_rect(at,PlacementSystem.footprint("bench",int(SCHEMES[key].rot)))
	if why=="" and not GameState.has("bench"):why="借来的长椅已经另作他用，可以收回，或拿自己的一张来。"
	if why=="":
		var uid: int=GameState.add_placement("bench",at.x,at.y,int(SCHEMES[key].rot))
		p.bench_uid=uid;p.scheme=key
	else:
		GameState.from_dict(saved);GameState.placements_changed.emit()
	PlacementSystem.project_context=previous
	if why=="":commit()
	return why

static func stop_point() -> Vector3:
	var b: Dictionary=bench()
	if b.is_empty():return Vector3.INF
	return Vector3(float(b.x),0,float(b.z))+Vector3.BACK.rotated(Vector3.UP,int(b.rot)*PI/2)*.90

static func record_trial(result: Dictionary) -> String:
	var p: Dictionary=state()
	if not appointment_now():return "这次共同试坐不在约好的时段，可以在纸签改约。"
	if bench().is_empty() or not result.get("arrived",false) or not result.get("seated",false) or not result.get("sight_clear",false):return "春还没走到并坐稳，或看不清小葵；先把路和观看处试好。"
	if str(result.get("bench_anchor",""))!=JSON.stringify(LayoutValidity.anchor(bench())):return "椅子刚挪过，按现在的位置再试一次。"
	if not LayoutValidity.path_clear(result.get("path",[])):return "这段路刚被挡住了，挪开障碍再试。"
	p.trial=result.duplicate(true);p.trial["day"]=GameState.day;p.trial["scheme"]=p.scheme
	p.trial["food_author"]="kazuko";p.trial["light_author"]="neighbours"
	p.promise.status="kept";p.resident_setup=false
	if not p.photo_compared:p.phase="photo"
	invite("photo_room","澪想并排看旧图与今天真正试过的场地")
	commit();return ""

static func compare_photo() -> bool:
	if not Progress.found("col_photo2011"):return false
	if state().trial.is_empty() or not state().photo_rendered or not FileAccess.file_exists(str(state().photo_path)):return false
	if load_photo()==null:return false
	state().photo_compared=true;state().phase="settled";track()
	invite("home_mio","一起选好新的邀请后，澪邀请晚间回访")
	commit();return true

static func load_photo() -> Image:
	var path: String=str(state().photo_path)
	if not state().photo_rendered or not FileAccess.file_exists(path):return null
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
	if bytes.size()<8 or bytes.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]):return null
	var pixels:=Image.new()
	return pixels if pixels.load_png_from_buffer(bytes)==OK else null

static func followup(key: String,choice: String="") -> bool:
	if state().followups.has(key):return false
	state().followups[key]={"day":GameState.day,"choice":choice}
	if choice!="":state().choices[key]=choice
	commit();return true

static func tracked() -> bool:
	return bool(state().tracked) and state().phase!="quiet"

static func hud() -> Dictionary:
	var p: Dictionary=state()
	if p.phase=="quiet":return {}
	var next: Array={"quiet":["一起办一次小集市，认识想留下来的人","opening_site"],"invited":["去支巷春家，看同一张图纸上的两种愿望","visit_home_haru_door"],"blueprint":["带图纸到农园工具屋，与田中量旧木件","visit_toolshed_door"],"measured":["在庭院纸签约一次试坐，挑靠近或通路宽的摆法","visit_trial"],"promised":[promise_text(),"visit_trial"],"photo":["去社区照片侧室，把今天的变化带给澪","visit_photo_room_door"],"settled":["到澪家选一张邀请，再去邮局寄出","visit_home_mio_door"]}.get(p.phase,["继续拜访认识的街坊","visit_home_haru_door"])
	if p.phase=="invited" and (GameState.phase=="market" or GameState.hour()>=20):next[0]="明天10:00后去支巷春家看图纸；今晚可以先收摊、回家休息"
	if p.phase=="photo" and (not p.photo_rendered or not FileAccess.file_exists(str(p.photo_path))):next=["试坐已经记下；回庭院纸签拍好现场照片，再去见澪","visit_trial"]
	if p.phase=="settled":
		if p.followups.has("letter_reply"):next=["回庭院拍一张白天的照片，给下次见面留一页","visit_trial"]
		elif p.followups.has("letter_sent"):next=["第%d天回邮局取信；等待时可以拜访其他街坊"%(int(p.followups.letter_sent.day)+2),"visit_post_door"]
		elif p.followups.has("invitation_written"):next=["邀请已经写好，到邮局核对地址并亲手寄出","visit_post_door"]
	return {"title":"让春坐下，也让小葵被看见","text":str(next[0]),"target":str(next[1])}

static func commit() -> void:
	GameState.state_changed.emit()
	GameState.save_game()

static func track() -> void:
	DailyLife.clear_tracking();SummerProjects.clear_tracking();GameState.flags.erase("request_tracked")
	state().tracked=true
	GameState.state_changed.emit()

static func clear_tracking() -> void:
	state().tracked=false

static func date_free(day_number: int) -> bool:
	if GameState.weekday(day_number)==GameState.SATURDAY and GameState.qstate("Q05")=="done":return false
	var festival: Dictionary=GameState.festival(GameState.festival_on(day_number))
	return festival.is_empty() or float(festival.get("end",0))<=17 or float(festival.get("start",24))>=20

static func next_free_day(after: int) -> int:
	for candidate: int in range(after+1,GameState.day+8):
		if date_free(candidate):return candidate
	return -1
