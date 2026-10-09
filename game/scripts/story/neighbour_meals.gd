class_name NeighbourMeals
extends RefCounted
const STYLES: Array[String]=["thin","chunk"]
const RECIPES: Dictionary={"thin":"haru_thin_pickles","chunk":"haru_chunk_pickles"}
const NAMES: Dictionary={"thin":"薄片浅渍小碗","chunk":"脆块浅渍小碗"}
const TABLE_CENTER: Vector3=Vector3(13.6,0,17.45)

static func state() -> Dictionary:
	var G:=GameState
	if not G.flags.get("neighbour_meals",{}) is Dictionary or not G.flags.has("neighbour_meals"):
		G.flags["neighbour_meals"]={}
	var data: Dictionary=G.flags.neighbour_meals
	data.merge({"version":1,"introduced_day":G.day,"starter_offered":false,"declined":false,"deferred_day":-1,"sessions":[],"receipts":{},"learned":{},"own":{},"shared":{}},false)
	data.version=1
	data.introduced_day=int(data.introduced_day);data.deferred_day=int(data.deferred_day)
	for receipt: Dictionary in data.receipts.values():
		for key: String in ["day","n"]:
			if receipt.has(key):receipt[key]=int(receipt[key])
	for learned: Dictionary in data.learned.values():learned.day=int(learned.day)
	for shared: Dictionary in data.shared.values():
		shared.day=int(shared.day);shared.eaten=int(shared.eaten)
	for own: Dictionary in data.own.values():
		for key: String in ["made","eaten","day","eaten_day"]:
			if own.has(key): own[key]=int(own[key])
	for entry: Dictionary in data.sessions:
		entry.merge({"rice_made":0,"rice_given":0,"rice_eaten":0,"rice_known_by_haru":false,"rice_brought":false,"arranged":false,"bowls":[]},false)
		for key: String in ["day","cuts","remaining","prepared_day","received_day","npc_eaten_day","player_eaten_day","haru_kept_raw","rice_made","rice_given","rice_eaten","rice_made_day","rice_given_day","rice_presented_day"]:
			if entry.has(key): entry[key]=int(entry[key])
		for field: String in ["player_materials","haru_materials"]:
			for iid: String in entry.get(field,{}):entry[field][iid]=int(entry[field][iid])
	return data

static func current() -> Dictionary:
	for entry: Dictionary in state().sessions:
		if entry.stage not in ["received","eaten"]: return entry
	return {}

static func can_offer(resume: bool=false) -> bool:
	var data: Dictionary=state()
	return current().is_empty() and not data.starter_offered and not data.declined and (resume or data.deferred_day!=GameState.day) and DailyLife.done("tea")

static func create(source: String,player_cucumbers: int=0,receipt: String="") -> Dictionary:
	var data: Dictionary=state()
	var entry: Dictionary={"id":"haru_meal:"+str(data.sessions.size()+1),"day":GameState.day,"stage":"invited","source":source,"receipt":receipt,"player_materials":{"cucumber":mini(player_cucumbers,2)} if player_cucumbers>0 else {},"haru_materials":{"cucumber":maxi(2-player_cucumbers,0),"salt":1},"haru_kept_raw":maxi(player_cucumbers-2,0),"style":"","role":"","cuts":0,"salted":false,"drained":false,"remaining":0,"npc_ate":false,"player_received":false,"player_ate":false,"known_by_haru":false}
	data.sessions.append(entry)
	return entry

static func invite(present: bool) -> String:
	if not present: return "等春在场，再商量这碗小菜。"
	if not can_offer(): return "这次回请还留着，先按当前安排继续。"
	state().starter_offered=true
	create("haru_pantry")
	commit();return ""

static func record_request(r: Dictionary) -> void:
	if not r.get("done",false) or r.get("who","")!="haru" or r.get("item","")!="cucumber" or int(r.get("n",0))<1: return
	var key: String="request:"+str(int(r.get("issued_day",GameState.day)))+":haru:cucumber"
	if state().receipts.has(key): return
	state().receipts[key]={"day":GameState.day,"n":int(r.n)}
	create("player_request",int(r.n),key)
	# The actual delivered cucumbers belong to Haru now; they are not removed again.
	GameState.state_changed.emit()

static func defer() -> void:
	state().deferred_day=GameState.day;commit()

static func start(role: String,style: String,present: bool) -> String:
	var entry: Dictionary=current()
	if entry.is_empty() or not present: return "春这会儿没在这里，小菜和材料先留着。"
	if role not in ["prepare","watch","rice","serve"] or style not in STYLES: return "先选这顿要用的分工和切法。"
	if role=="rice" and not GameState.recipe_known("plain_onigiri"):return "先在自家饭桌学会盐饭团；这次也可以负责小菜或分装。"
	if entry.stage!="invited": return "同一碗已经开始，继续原来的半成品就好。"
	entry.role=role;entry.style=style;entry.stage="preparing"
	if role=="serve":entry.bowls=default_bowls()
	register()
	commit();return ""

static func cut(delta: int) -> String:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.stage!="preparing" or entry.role!="prepare": return "先把这一碗的材料放到桌面。"
	entry.cuts=clampi(int(entry.cuts)+delta,0,3);commit();return ""

static func change_style(style: String) -> void:
	var entry: Dictionary=current()
	if not entry.is_empty() and entry.stage=="preparing" and style in STYLES: entry.style=style;commit()

static func salt() -> void:
	var entry: Dictionary=current()
	if not entry.is_empty() and entry.stage=="preparing": entry.salted=true;commit()

static func drain(value: bool) -> void:
	var entry: Dictionary=current()
	if not entry.is_empty() and entry.stage=="preparing": entry.drained=value;commit()

static func finish(present: bool) -> String:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.stage!="preparing" or not present: return "春不在近处，半成品先收好，之后接着做。"
	if int(entry.cuts)<3 or not entry.salted: return "还没切好、撒盐，先看看桌上这一碗。"
	entry.stage="portioning" if entry.role=="serve" else "prepared";entry.remaining=2;entry.prepared_day=GameState.day
	entry["author"]="player_and_haru" if entry.role=="prepare" else "haru"
	state().learned[str(entry.style)]={"day":GameState.day,"source":entry.id,"method":entry.role}
	register();commit();return ""

static func observe_step(step: int,present: bool) -> bool:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.stage!="preparing" or entry.role not in ["watch","rice","serve"] or not present or step not in [1,2,3]:return false
	entry.cuts=maxi(int(entry.cuts),step)
	if step==3:entry.salted=true;entry.drained=entry.style=="thin"
	commit();return true

static func eat_haru(present: bool) -> String:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.stage!="prepared" or not present: return "先等春回到杯边。"
	if entry.npc_ate: return "春自己的那份已经吃过，不再添一份。"
	entry.npc_ate=true;entry.npc_eaten_day=GameState.day;entry.remaining=int(entry.remaining)-1
	commit();return ""

static func take(mode: String,present: bool) -> String:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.stage!="prepared" or entry.player_received or not entry.npc_ate or not present: return "先一起尝过，再决定自己的那一小份。"
	if entry.role=="rice" and int(entry.rice_given)==0:return "春的饭团还没带来，这一顿先留着。"
	if mode not in ["eat","pack"]: return "可以现在吃，也可以先留着。"
	var iid: String=gift_id(entry)
	if mode=="pack" and not GameState.can_add_bundle({iid:1}): return "背包满了，那一小份还留在杯边。"
	if mode=="pack":
		entry["carry_format"]="paper" if entry.drained else "covered_bowl"
		GameState.add_item(iid,1,true)
	entry.player_received=true;entry.received_day=GameState.day;entry.remaining=int(entry.remaining)-1
	entry.stage="received"
	if mode=="eat":
		entry.player_ate=true;entry.player_eaten_day=GameState.day;entry.known_by_haru=true;entry.stage="eaten"
		DailyLife._note_food(iid)
	commit();return ""

static func gift_id(entry: Dictionary) -> String: return "haru_side_"+str(entry.id).replace(":","_")

static func register() -> void:
	var G:=GameState
	for style: String in STYLES:
		var rid: String=RECIPES[style]
		G.recipes_db.erase(rid);G.recipes_known.erase(rid)
		G.items_db[rid]={"name":NAMES[style],"icon":"dish_pickles","dish":true,"sell":0,"key":false,"desc":"一根黄瓜切两小份，薄片容易入味，适合现在配茶。" if style=="thin" else "两根黄瓜做两份，块大一些，留着配自己的饭。"}
		if state().learned.has(style):
			G.recipes_db[rid]={"name":NAMES[style]+" · 两份","station":"kitchen","inputs":{"cucumber":1 if style=="thin" else 2,"salt":1},"output":{rid:2},"minutes":10 if style=="thin" else 20,"unlock":{}}
			G.recipes_known[rid]=true
	for entry: Dictionary in state().sessions:
		G.items_db[gift_id(entry)]={"name":"春回请的"+str(NAMES.get(str(entry.style),"浅渍小碗")),"icon":"dish_pickles","dish":true,"sell":0,"key":false,"desc":"第%d天，%s分出的一小份。吃或收好都可以。"%[int(entry.get("prepared_day",entry.day)),"和春一起切拌" if entry.role=="prepare" else "春切拌后"]}
		var portion_id: String=rice_id(entry)
		G.recipes_db.erase(portion_id);G.recipes_known.erase(portion_id)
		G.items_db[portion_id]={"name":"和春这一顿的盐饭团","icon":"onigiri","dish":true,"key":false,"sell":0,"desc":"自己用米和盐做的两份，春的一份先留着；自己的可以现在吃或带回家。"}
		if entry.role=="rice" and int(entry.rice_made)==0 and entry.stage not in ["received","eaten"] and G.recipe_known("plain_onigiri"):
			var recipe: Dictionary=G.recipe("plain_onigiri").duplicate(true)
			recipe.name="和春这一顿 · 两份饭团";recipe.output={portion_id:2}
			G.recipes_db[portion_id]=recipe;G.recipes_known[portion_id]=true

static func move_bowl(index: int,at: Vector3) -> void:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.stage!="portioning" or index not in [0,1] or not at.is_finite():return
	entry.bowls[index]={"x":snappedf(at.x,.05),"z":snappedf(at.z,.05)};entry.arranged=false;commit()

static func default_bowls() -> Array:return [{"x":TABLE_CENTER.x-.2,"z":TABLE_CENTER.z+.1},{"x":TABLE_CENTER.x+.2,"z":TABLE_CENTER.z+.1}]

static func reset_bowls() -> void:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.stage!="portioning":return
	entry["previous_bowls"]=entry.bowls.duplicate(true);entry.bowls=default_bowls();entry.arranged=false;commit()

static func retain_layout(reason: String,present: bool) -> String:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.stage!="portioning" or not present:return "等春在杯边再看这一摆法。"
	if reason!="":return reason
	entry.arranged=true;entry.stage="prepared";entry.author="haru_cooked_player_portioned";commit();return ""

static func rice_id(entry: Dictionary) -> String:return "haru_rice_"+str(entry.id).replace(":","_")

static func rice_recipe(id: String) -> bool:return id.begins_with("haru_rice_haru_meal_")

static func can_rice_craft(id: String,n: int) -> bool:
	var entry: Dictionary=current()
	return not entry.is_empty() and id==rice_id(entry) and entry.role=="rice" and int(entry.rice_made)==0 and n==1 and GameState.recipe_known("plain_onigiri")

static func held(iid: String) -> int:
	for entry: Dictionary in state().sessions:
		if iid==rice_id(entry) and entry.role=="rice" and int(entry.rice_made)>0 and int(entry.rice_given)==0:return 1
	return 0

static func give_rice(present: bool) -> String:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.role!="rice" or not present:return "春的一份先留着，等她在杯边再一起吃。"
	if int(entry.rice_given)>0:return "春的饭团已经递过，不再添一份。"
	if int(entry.rice_made)!=2 or not entry.rice_brought or GameState.count(rice_id(entry))<1:return "这一顿的饭团还没带来；收进箱子的也可以取回来。"
	GameState.remove_item(rice_id(entry),1);entry.rice_given=1;entry["rice_given_day"]=GameState.day
	commit();return ""

static func present_rice(present: bool) -> String:
	var entry: Dictionary=current()
	if entry.is_empty() or entry.role!="rice" or not present or int(entry.rice_made)!=2 or GameState.count(rice_id(entry))<1:return "饭团还没带到杯边，收进箱子的那份也可以先取回来。"
	entry.rice_brought=true;entry["rice_presented_day"]=GameState.day;commit();return ""

static func record_craft(rid: String,n: int) -> void:
	var entry: Dictionary=current()
	if not entry.is_empty() and entry.role=="rice" and rid==rice_id(entry) and int(entry.rice_made)==0:
		entry.rice_made=2;entry.rice_made_day=GameState.day;register();return
	if rid not in RECIPES.values(): return
	var own: Dictionary=state().own.get(rid,{})
	own["made"]=int(own.get("made",0))+n*2;own["day"]=GameState.day
	state().own[rid]=own

static func record_eaten(iid: String,together: bool=false) -> void:
	for entry: Dictionary in state().sessions:
		if iid==rice_id(entry):
			entry.rice_eaten=int(entry.rice_eaten)+1
			if together:entry.rice_known_by_haru=true
		if iid==gift_id(entry) and entry.player_received:
			entry.player_ate=true;entry.player_eaten_day=GameState.day;entry.stage="eaten"
			if together: entry.known_by_haru=true
	if iid in RECIPES.values():
		var own: Dictionary=state().own.get(iid,{"made":0})
		own["eaten"]=int(own.get("eaten",0))+1;own["eaten_day"]=GameState.day
		state().own[iid]=own
	if together and DailyLife.edible(iid):state().shared[iid]={"day":GameState.day,"source":"same_meal","eaten":int(state().shared.get(iid,{}).get("eaten",0))+1}

static func notes() -> Array[String]:
	var lines: Array[String]=[]
	var entry: Dictionary=current()
	if not entry.is_empty():
		lines.append("春的回请："+{"invited":"麦茶旁一起备一碗小菜，也可以改天。","preparing":"桌上还有半成品，下次接着做。","portioning":"两只碗放好后，可直接保留安排。","prepared":"同一碗分两份；自己的可以吃或带回家。"}.get(str(entry.stage),"杯边歇脚。"))
		if entry.role=="rice" and int(entry.rice_made)==0:lines.append("自家灶台，用米2、盐1做这一顿的两份饭团；春备小菜。")
	for style: String in state().learned: lines.append("学过%s，家里灶台可用自己的黄瓜和盐做。" % NAMES[style])
	return lines

static func commit() -> void:
	GameState.state_changed.emit();GameState.save_game()
