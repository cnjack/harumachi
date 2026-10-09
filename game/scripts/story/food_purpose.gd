class_name FoodPurpose
extends RefCounted
const NEXT_RECIPE: String="food_next_meal"
const NEXT_PORTION: String="food_next_portion"
## Uses are attached to the same finite serving, never counted as another received serving.
static func initialize(entry: Dictionary) -> void:
	entry["units"]=[]
	for index in 3:
		entry.units.append({"id":str(entry.session_id)+":"+str(index+1),"state":"table","target":"","purpose":"public","prep":"","format":str(entry.presentation),"use":{},"index":index})

static func units(entry: Dictionary) -> Array:
	return entry.get("units",[])

static func eligible(entry: Dictionary,who: String) -> Dictionary:
	for unit: Dictionary in units(entry):
		if unit.state in ["table","reserved"] and unit.target==who: return unit
	for unit: Dictionary in units(entry):
		if unit.state=="table" and unit.target=="": return unit
	return {}

static func plan(entry: Dictionary,target: String,purpose: String,prep: String,present: bool) -> String:
	if entry.is_empty() or entry.closed or int(entry.day)!=GameState.day: return "先看看今晚的饭菜备好没有。散场后剩下的，从收拾入口包好。"
	if target not in ["haru","ren","self"] or purpose not in ["tea","later","home"] or prep not in ["drain_wrap","tray"]: return "先选这份留给谁，再选怎么装。"
	if purpose!={"haru":"tea","ren":"later","self":"home"}[target]: return "先照刚才说好的装，想换吃法再问问本人。"
	if not present and target!="self": return "人还不在，等见面问过，再留这一份。"
	if units(entry).is_empty(): return "这篮已经备好了，照原来的安排分，剩的包起来就行。"
	if entry.get("served",{}).has(target): return "这一位已经拿过了，剩的留给还没拿的人。"
	for unit: Dictionary in units(entry):
		if (unit.target==target or unit.get("holder","")==target) and unit.state not in ["table","reserved"]: return "这份已经拿走了，纸签先照刚才的安排留着。"
	var selected: Dictionary=eligible(entry,target)
	if selected.is_empty(): return "三份都留好了名字。还没拿走的可以改，或照旧分。"
	selected.target=target;selected.purpose=purpose;selected.prep=prep
	selected.format="paper" if prep=="drain_wrap" else "plate"
	selected.state="reserved"
	selected["planned_day"]=GameState.day
	commit()
	return ""

static func received(entry: Dictionary,who: String) -> Dictionary:
	var unit: Dictionary=eligible(entry,who)
	if unit.is_empty(): return {}
	unit.state="held";unit["holder"]=who;unit["received_day"]=GameState.day
	return unit

static func owned(entry: Dictionary,who: String) -> Dictionary:
	for unit: Dictionary in units(entry):
		if unit.get("holder","")==who and unit.state in ["held","placed","consumed"]: return unit
	return {}

static func place(entry: Dictionary,who: String,result: Dictionary) -> String:
	var unit: Dictionary=owned(entry,who)
	if unit.is_empty(): return "这份还在公共桌上，先去拿。"
	if unit.purpose!="tea" or who!="haru": return "这份没说要配茶，先按说好的地方留着。"
	if unit.state!="held": return "这一份已经放好，或已经吃完了。"
	if not result.get("arrived",false) or not result.get("supported",false) or not result.get("present",false): return "春已拿着这份，还没放到杯边。先找个能放的地方。"
	var standing: Dictionary=result.get("standing",{})
	var at:=Vector3(float(standing.get("x",INF)),float(standing.get("y",INF)),float(standing.get("z",INF)))
	if not at.is_finite() or at.distance_to(Vector3(14.6,0,16.1))>.7 or result.get("path",[]).is_empty(): return "还没走到杯边，饭菜先在春手里收着。"
	unit.state="placed";unit.use={"placed_day":GameState.day,"place":"tea","position":result.position.duplicate(true),"path":result.path.duplicate(true),"observed_by":"player","eaten":false,"drank":false}
	commit()
	return ""

static func packed(entry: Dictionary) -> void:
	for unit: Dictionary in units(entry):
		if unit.state in ["table","reserved"]: unit.state="packed";unit["holder"]="player";unit["packed_day"]=GameState.day

static func consume(entry: Dictionary) -> void:
	for unit: Dictionary in units(entry):
		if unit.state=="packed": unit.state="consumed";unit["eaten_day"]=GameState.day;return

static func claim_self(entry: Dictionary) -> String:
	if entry.is_empty() or entry.closed or int(entry.day)!=GameState.day: return "上回那篮剩的，从散场收拾那里包起来就行。"
	var unit: Dictionary=eligible(entry,"self")
	if unit.is_empty() or unit.target!="self": return "还没留自己的那份。先从纸签上选一份带回家。"
	var id: String=SummerGathering.leftover_id(str(entry.context))
	if not GameState.can_add_bundle({id:1}): return "背包先留一个小份位置，这份仍在桌上。"
	GameState.add_item(id,1,true);entry.remaining=int(entry.remaining)-1;entry.packed=int(entry.packed)+1
	unit.state="packed";unit["holder"]="player";unit["packed_day"]=GameState.day
	commit()
	return ""

static func followup_state() -> Dictionary:
	if not GameState.flags.get("food_followup",{}) is Dictionary or not GameState.flags.has("food_followup"): GameState.flags["food_followup"]={}
	var p: Dictionary=GameState.flags.food_followup;p.merge({"presented":{},"disclosed":{},"next":{}},false)
	for field: String in ["day","made_day","made","eaten","eaten_day","shared_day"]:
		if p.next.has(field): p.next[field]=int(p.next[field])
	return p

static func followup_key(entry: Dictionary,who: String) -> String:
	return str(entry.get("session_id","opening:"+str(entry.get("day",0))+":"+str(entry.get("trial_batch",0))))+":"+who

static func was_presented(entry: Dictionary,who: String) -> bool: return followup_state().presented.has(followup_key(entry,who))

static func mark_followup(entry: Dictionary,who: String) -> void:
	followup_state().presented[followup_key(entry,who)]={"day":GameState.day,"source":who}
	commit()

static func next_meal(origin: String,choice: String) -> String:
	if choice not in ["home","tea","later","none"]: return "先按自己的打算选，也可以不安排。"
	var p: Dictionary=followup_state()
	if not p.next.is_empty() and p.next.choice!="later": return "下一顿的便笺已经写好了，先照那张来。"
	p.next={"origin":origin,"choice":choice,"day":GameState.day,"state":"declined" if choice=="none" else "intention","recipe":"plain_onigiri" if GameState.recipe_known("plain_onigiri") else "","shared_with":"haru" if choice=="tea" else ""}
	register_meal()
	commit()
	return ""

static func register_meal() -> void:
	var G:=GameState
	var next: Dictionary=followup_state().next
	if not next.is_empty() and next.state=="intention" and next.get("recipe","")=="" and G.recipe_known("plain_onigiri"): next.recipe="plain_onigiri"
	G.recipes_known.erase(NEXT_RECIPE)
	G.recipes_db.erase(NEXT_RECIPE)
	G.items_db[NEXT_PORTION]={"name":"自己下一顿的盐饭团","icon":"onigiri","key":false,"dish":true,"sell":0,"desc":"给自己做的两份盐饭团。适合在家慢慢吃，也能带去配麦茶。"}
	if next.is_empty() or next.get("recipe","")=="" or next.state!="intention" or next.choice not in ["home","tea"]: return
	var recipe: Dictionary=G.recipe("plain_onigiri").duplicate(true)
	recipe.name="自己下一顿 · 一批两份"
	recipe.output={NEXT_PORTION:2}
	G.recipes_db[NEXT_RECIPE]=recipe
	if next.state=="intention" and next.choice in ["home","tea"]: G.recipes_known[NEXT_RECIPE]=true

static func can_craft(n: int) -> bool:
	var next: Dictionary=followup_state().next
	return n==1 and not next.is_empty() and next.state=="intention" and next.choice in ["home","tea"] and next.get("recipe","")!=""

static func record_craft(rid: String) -> void:
	if rid!=NEXT_RECIPE: return
	var next: Dictionary=followup_state().next
	next.state="prepared";next["made_day"]=GameState.day;next["made"]=2;next["eaten"]=0
	register_meal()

static func record_eaten(iid: String,together: bool=false) -> void:
	if iid!=NEXT_PORTION: return
	var next: Dictionary=followup_state().next
	if next.is_empty(): return
	next.eaten=int(next.get("eaten",0))+1;next["eaten_day"]=GameState.day
	if together and next.choice=="tea":
		next.state="completed_tea";next["shared_day"]=GameState.day;next["known_by"]="haru";next["knowledge_source"]="actually_together"
	elif not next.has("known_by"):
		next.state="completed_home"
	# Private eating never supplies resident knowledge; sharing belongs to this consumption.

static func commit() -> void:
	GameState.state_changed.emit();GameState.save_game()
