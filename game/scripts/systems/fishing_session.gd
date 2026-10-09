class_name FishingSession
extends RefCounted
## The same state machine drives keyboard play, demonstrations and regressions.
enum State { READY, CAST, WAIT, BITE, REEL, LANDED, MISSED, CLOSED }
var state := State.READY
var spot := ""
var timer := 0.0
var wait_seconds := 3.0
var reel_progress := 0.0
var tension := .28
var danger := 0.0
var difficulty := .3
var ticket := -1
var result: Dictionary = {}
var message := "按 E / 空格抛竿"
var _mistakes := 0.0
var cursor := .5
var fish_position := .5
var track_width := .26
var behaviour := "steady"
var control_quality := 0.0
var _tracked_time := 0.0
var _reel_time := 0.0
var _velocity := 0.0

func tracking() -> bool:
	return absf(cursor-fish_position)<track_width*.5

func suggested_hold() -> bool:
	return cursor+_velocity*.08<fish_position and tension<.84

func _init(spot_id: String = "fish_river") -> void:
	spot=spot_id

func tap(roll: float = -1.0, length_roll: float = -1.0) -> void:
	if state in [State.READY,State.LANDED,State.MISSED]:
		var start := GameState.begin_fishing(spot,roll,length_roll)
		if start.has("error"):
			message=str(start.error)
			return
		ticket=int(start.ticket);difficulty=float(start.difficulty);behaviour=str(start.get("behaviour","steady"));track_width=lerpf(.30,.16,difficulty)
		state=State.CAST;timer=0.0;reel_progress=0.0;tension=.28;danger=0.0;_mistakes=0.0;result={}
		cursor=.5;fish_position=.5;_velocity=0.0;_tracked_time=0.0;_reel_time=0.0;control_quality=0.0
		wait_seconds=randf_range(2.2,4.8)
		message="抛下鱼饵……"
	elif state==State.BITE:
		state=State.REEL;timer=0.0
		message="按住收线；张力偏高时松开，让鱼缓一缓"
	elif state in [State.CAST,State.WAIT]:
		message="再等一等，浮漂还没沉下去"

func step(delta: float, held: bool) -> void:
	if delta<=0.0:return
	var dt := minf(delta,.10)
	timer+=dt
	match state:
		State.CAST:
			if timer>=.65:
				state=State.WAIT;timer=0.0;message="静静等鱼咬钩，留意浮漂"
		State.WAIT:
			if timer>=wait_seconds:
				state=State.BITE;timer=0.0;message="咬钩了！现在点 E / 空格！"
		State.BITE:
			if timer>2.2:_miss("鱼游开了。下一次看到浮漂下沉时再收线")
		State.REEL:
			_reel_time+=dt
			var speed:=1.9+difficulty*2.4
			var wave:=sin(timer*speed)*.21+sin(timer*speed*.57+1.4)*.09
			if behaviour=="dart":wave+=sin(timer*speed*1.85)*.10
			elif behaviour=="dive":wave+=sin(timer*.85)*.13
			fish_position=clampf(.5+wave,.12,.88)
			_velocity=move_toward(_velocity,.68 if held else -.68,dt*4.8)
			cursor=clampf(cursor+_velocity*dt,.04,.96)
			if cursor<=.04 or cursor>=.96:_velocity=0.0
			var on_fish:=tracking()
			var strain: float=(.16+difficulty*.11) if held else -.23
			tension=clampf(tension+dt*(strain+.045*sin(timer*speed)),0.0,1.0)
			if on_fish and tension<.88:
				_tracked_time+=dt
				reel_progress+=dt*lerpf(.21,.13,difficulty)
			else:
				reel_progress=maxf(0.0,reel_progress-dt*(.048+difficulty*.04))
				_mistakes+=dt*.10
			control_quality=_tracked_time/maxf(.01,_reel_time)
			if tension>.92:
				danger+=dt;_mistakes+=dt;message="松开"
			else:
				danger=maxf(0.0,danger-dt*.7)
				message="跟住鱼影" if not on_fish else "稳住！"
			if danger>1.0:_miss("鱼线断了")
			elif reel_progress>=1.0:
				result=GameState.land_fish(ticket,control_quality)
				if result.has("error"):_miss(str(result.error))
				else:
					state=State.LANDED;timer=0.0;message="%s · %.1f cm" % [GameState.item_name(str(result.fish)),float(result.cm)]
			elif timer>38.0:_miss("鱼游回了深水")

func _miss(reason: String) -> void:
	GameState.cancel_fishing(ticket)
	state=State.MISSED;message=reason;timer=0.0

func close() -> void:
	GameState.cancel_fishing(ticket)
	state=State.CLOSED
