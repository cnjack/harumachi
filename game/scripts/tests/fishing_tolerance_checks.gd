extends RefCounted
## Human-scale reaction intervals exercise the same session and inventory rules as the panel.
var t: Node
const SPOT_FOR := {"fish_crucian":"fish_river","fish_carp":"fish_pier","fish_ayu":"fish_river","fish_trout":"fish_bend","fish_bass":"fish_pier","fish_eel":"fish_reeds"}

func _init(runner: Node) -> void:t=runner

func check(label: String,ok: bool,detail: String="") -> void:t.check("FISHING_TOLERANCE",label,ok,detail)

func _cast(species: String="fish_crucian") -> FishingSession:
	GameState.new_game();GameState.clock_paused=true;GameState.minute=7*60
	GameState.borrow_fishing_kit()
	var spot: String=str(SPOT_FOR[species])
	var pool: Array=GameState.spot_fish_pool(spot)
	var total: float=0.0
	for row: Dictionary in pool:total+=float(row.weight)
	var before: float=0.0
	var selection: float=0.0
	for candidate: Dictionary in pool:
		if str(candidate.id)==species:
			selection=(before+float(candidate.weight)*.5)/total;break
		before+=float(candidate.weight)
	var session:=FishingSession.new(spot)
	session.tap(selection,.5);session.wait_seconds=.01
	for frame: int in 30:
		if session.state==FishingSession.State.BITE:break
		session.step(.05,false)
	return session

func _advance(session: FishingSession,seconds: float,held: bool) -> void:
	for frame: int in ceili(seconds/.05):session.step(.05,held)

func run() -> void:
	var saved: Dictionary=GameState.to_dict().duplicate(true)
	var delayed:=_cast()
	var ticket: int=delayed.ticket
	_advance(delayed,3.0,false)
	var still_biting: bool=delayed.state==FishingSession.State.BITE
	delayed.tap()
	check("a three-second bite reaction still hooks the original cast",still_biting and delayed.state==FishingSession.State.REEL and delayed.ticket==ticket and GameState.count("fishing_bait")==9 and int(GameState.fishing.casts)==1 and int(GameState.fishing.landed)==0,delayed.message)
	delayed.close()
	var ignored:=_cast();_advance(ignored,5.0,false)
	check("ignoring the wider bite window still loses only that cast",ignored.state==FishingSession.State.MISSED and GameState._fishing_ticket.is_empty() and GameState.count("fishing_bait")==9 and int(GameState.fishing.landed)==0)
	ignored.close()
	for species: String in SPOT_FOR:
		var samples: Array[Dictionary]=[]
		var all_landed: bool=true
		for fps: int in [30,60]:
			var session:=_cast(species);session.tap()
			var elapsed: float=0.0
			var next_reaction: float=.35
			var held: bool=false
			while session.state==FishingSession.State.REEL and elapsed<30.0:
				# React to visible positions only every 350 ms, not to private velocity or next-frame advice.
				if elapsed>=next_reaction:
					held=session.cursor<session.fish_position and session.tension<.84
					next_reaction+=.35
				session.step(1.0/float(fps),held);elapsed+=1.0/float(fps)
			var landed: bool=session.state==FishingSession.State.LANDED and str(session.result.get("fish",""))==species
			all_landed=all_landed and landed and GameState.count(species)==1 and int(GameState.fishing.landed)==1 and GameState.count("fishing_bait")==9
			samples.append({"fps":fps,"state":session.state,"seconds":elapsed,"quality":session.control_quality,"fish":session.result.get("fish","")})
			session.close()
		check(species+" can be caught with 350 ms reaction intervals at 30 and 60 fps",all_landed,JSON.stringify(samples))
	var recover:=_cast();recover.tap();recover.reel_progress=.5;recover.cursor=.04
	_advance(recover,.30,false)
	check("a brief 300 ms tracking slip preserves progress while the player reacts",recover.state==FishingSession.State.REEL and is_equal_approx(recover.reel_progress,.5) and not recover.tracking(),"progress=%s"%recover.reel_progress)
	_advance(recover,.45,false)
	check("remaining outside the fish still loses progress after the grace period",recover.reel_progress<.5)
	recover.close()
	var strain:=_cast();strain.tap();strain.tension=.93;strain.reel_progress=.35
	_advance(strain,1.15,true);_advance(strain,.7,false)
	check("releasing after a late red-line reaction can save the unlanded fish",strain.state==FishingSession.State.REEL and strain.tension<.92 and int(GameState.fishing.landed)==0,"state=%s tension=%s danger=%s"%[strain.state,strain.tension,strain.danger])
	strain.close()
	for held_forever: bool in [false,true]:
		var idle:=_cast();idle.tap();_advance(idle,40.0,held_forever)
		check("holding forever still fails" if held_forever else "never reeling still fails",idle.state==FishingSession.State.MISSED and GameState._fishing_ticket.is_empty() and int(GameState.fishing.landed)==0 and GameState.count("fishing_bait")==9,idle.message)
		idle.close()
	GameState.from_dict(saved)
