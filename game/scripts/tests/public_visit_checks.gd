extends RefCounted
## Public rooms preserve real trading and readable keepsakes alongside the new visit chain.
var t: Node
var G: Node
var m: Node

func _init(runner: Node) -> void:t=runner;G=GameState;m=t.main
func check(label: String, ok: bool) -> void:t.check("PUBLIC_VISITS",label,ok)

func use(id: String, choices: Array=[]) -> void:
	m.ui.auto_choices=choices.duplicate()
	await m.story.visits.handle(id)

func run() -> void:
	var saved: Dictionary=G.to_dict().duplicate(true)
	G.new_game();G.clock_paused=true;G._ui_locks.clear();G.flags.erase("arrival_home")
	G.day=5;G.minute=11*60;G.phase="prep";G.coins=10000
	G.quests.Q00={"state":"done","step":2};G.quests.Q11={"state":"done","step":3}
	m.in_room=false;m.room_kind="";m.world.set_region("town");m.world.set_indoor_look(false)
	m.story.busy=false;m.ui.instant=true
	var coins_before: int=G.coins
	await use("shop_zakka",[{"buy":{"washi":2}}])
	check("the street door enters a real shop without consuming an unchosen purchase",m.in_room and m.room_kind=="zakka" and G.count("washi")==0 and G.coins==coins_before)
	await use("visit_zakka_memory",[1,{"buy":{"washi":2}}])
	check("the indoor trading choice buys actual stock at its actual price",G.count("washi")==2 and G.coins==coins_before-2*int(G.item("washi").price))
	await use("visit_zakka_memory",[0])
	check("reading the poster in the new shop preserves its old keepsake entry",Progress.found("col_poster"))
	check("reading a poster does not invent a completed trial or cushion repair",ResidentVisits.state().trial.is_empty() and not ResidentVisits.state().followups.has("cushion_fixed"))
	var collected: Dictionary=G.collection.duplicate(true)
	var after_purchase: int=G.coins
	await use("visit_zakka_memory",[0])
	check("re-reading a public picture preserves collection identity and money",G.collection==collected and G.coins==after_purchase)
	await use("visit_zakka_exit")
	check("the new public exit restores its own outside street",not m.in_room and m.player.global_position.distance_to(ResidentPlaces.SPECS.zakka.exit)<.2)
	await use("shop_florist")
	await use("visit_florist_memory",[0])
	check("an old completed notebook can still find the florist's bookmark",Progress.found("col_bookmark") and not ResidentVisits.state().blueprint_seen)
	check("reading the bookmark does not invent choosing or delivering a gift",not ResidentVisits.state().followups.has("flower_pick") and not ResidentVisits.state().followups.has("flower_delivered"))
	coins_before=G.coins
	await use("visit_florist_memory",[1,{"buy":{"seed_sunflower":1}}])
	check("the flower shop trades independently of a private-house invitation",G.count("seed_sunflower")==1 and G.coins==coins_before-int(G.item("seed_sunflower").price))
	ResidentVisits.state().blueprint_seen=true
	await use("visit_florist_memory",[0,1])
	check("seeing Haru's real picture then allows one chosen flower gift",ResidentVisits.state().followups.has("flower_pick") and ResidentVisits.state().choices.get("flower_pick","")=="white")
	var florist_gift: Node3D=m.world.interiors.florist.get_node("StoryState/flowergift")
	var haru_gift: Node3D=m.world.interiors.home_haru.get_node("StoryState/flowergift")
	check("the selected gift waits in the flower shop until it is actually delivered",florist_gift.visible and not haru_gift.visible)
	ResidentVisits.followup("flower_delivered","white")
	await use("visit_florist_memory",[0])
	check("a delivered flower is remembered as delivered rather than still waiting in the basket",m.ui.dlg_text.text.contains("春家") and not m.ui.dlg_text.text.contains("留在篮里"))
	check("the same delivered gift now appears only in Haru's home",haru_gift.visible and not florist_gift.visible)
	await use("visit_florist_exit")
	await use("visit_library_door")
	await use("visit_library_memory")
	check("actually opening the reading-room map adds a reviewable keepsake",Progress.found("col_oldmap"))
	check("the library never traces an unseen photo or untested seat",not ResidentVisits.state().followups.has("map_traced"))
	Progress.find("col_photo2011")
	await use("visit_library_memory",[1])
	check("a known old photo still does not substitute for an actual new seating trial",not ResidentVisits.state().followups.has("map_traced"))
	await use("visit_library_exit")
	G.minute=20*60;coins_before=G.coins
	await use("shop_zakka",[1,{"buy":{"washi":2}}])
	check("a closed public shop refuses entry and never charges",not m.in_room and G.coins==coins_before and G.count("washi")==2)
	G.minute=18*60
	ResidentVisits.invite("home_ren","public-room regression")
	await use("visit_home_ren_door")
	await use("visit_home_ren_memory",[0])
	check("viewing Ren's real old photograph preserves it in the keepsake book",Progress.found("col_bakery1972"))
	G.day+=1
	await use("visit_home_ren_memory")
	await use("visit_home_ren_memory")
	check("a completed packing return no longer tells the player to wait until tomorrow",ResidentVisits.state().followups.has("packing_return") and not m.ui.dlg_text.text.contains("明天"))
	await use("visit_home_ren_exit");await m.exit_interior()
	ResidentVisits.invite("home_tanaka","seed handover regression")
	await use("visit_home_tanaka_door")
	await use("visit_home_tanaka_memory")
	G.day+=1
	G.remove_item("seed_radish",G.count("seed_radish"))
	var old_cap: int=G.bag_cap
	G.bag_cap=G.slots_used()
	await use("visit_home_tanaka_memory")
	check("a full bag gives a clear retry without consuming Tanaka's one seed gift",not ResidentVisits.state().followups.has("seed_received") and m.ui.dlg_text.text.contains("背包满了"))
	G.bag_cap=old_cap
	await use("visit_home_tanaka_memory")
	await use("visit_home_tanaka_memory")
	check("returning with room takes the same seed packet exactly once",ResidentVisits.state().followups.has("seed_received") and G.count("seed_radish")==1)
	await use("visit_home_tanaka_exit")
	ResidentVisits.invite("photo_room","photo recovery regression")
	G.collection.erase("col_photo2011")
	ResidentVisits.state().trial={"day":G.day,"scheme":"near"}
	await use("visit_photo_room_door")
	await use("visit_photo_room_memory")
	check("a missing old photograph sends the player to the real closet without inventing knowledge",not ResidentVisits.state().photo_compared and not Progress.found("col_photo2011") and m.ui.dlg_text.text.contains("壁橱"))
	Progress.find("col_photo2011")
	await use("visit_photo_room_memory")
	check("a failed new photograph cannot speak a successful comparison or invite Mio home",not ResidentVisits.state().photo_compared and not ResidentVisits.unlocked("home_mio") and not m.ui.dlg_text.text.contains("今晚来"))
	await use("visit_photo_room_exit");await m.exit_interior()
	G.from_dict(saved);m._restore();G.clock_paused=true
	m.ui.dialogue_end();m.story.busy=false;m.player.frozen=false
	await t.frames(2)
