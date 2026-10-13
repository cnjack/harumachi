class_name StoryResidentVisits
extends RefCounted
var s: Story
var view: ResidentVisitView

func _init(story: Story) -> void:s=story

func build() -> void:
	view=ResidentVisitView.new();view.name="ResidentVisits";s.main.add_child(view);view.setup(s)

func room_for(id: String) -> String:
	for room: String in ResidentPlaces.SPECS:
		if id==str(ResidentPlaces.SPECS[room].door_id) or id in ["visit_"+room+"_memory","visit_"+room+"_exit"]:return room
	return ""

func handles(id: String) -> bool:
	return id=="visit_trial" or not room_for(id).is_empty()

func prompt(id: String) -> Variant:
	if id=="visit_trial":return "试坐纸签 · 摆法、约定与回访" if ResidentVisits.state().measured else ""
	var room: String=room_for(id)
	if room=="":return null
	if id.ends_with("_exit"):return "回到"+str(InteriorBuilder.spec_for(str(ResidentPlaces.SPECS[room].get("return_room",""))).get("name","屋外"))
	if id=="visit_post_memory":
		var followups: Dictionary=ResidentVisits.state().followups
		if followups.has("letter_reply"):return "邮局 · 回信与下一次邀请"
		if followups.has("letter_sent"):return "邮局 · 第%d天来取回信"%(int(followups.letter_sent.day)+2)
	if id=="visit_home_mio_memory" and ResidentVisits.state().followups.has("invitation_written"):return "澪家 · 说好的下一次见面"
	if id.ends_with("_memory"):return {"home_haru":"看春家的图纸和小葵的画","toolshed":"量木件，看看高架上的旧筒","photo_room":"把旧照与今天并排看","home_mio":"看看窗边还没寄的邀请","home_tanaka":"坐下来聊一顿晚饭","home_ren":"看旧模具和没上架的小份试作","home_kazuko":"翻旧价签，帮忙收好借用品","florist":"挑一束送给认识的街坊","zakka":"看旧海报，修好长椅的靠垫扣","post":"写下并寄出这一次邀请","library":"沿旧地图找今天的路"}.get(room,"看看屋里的生活")
	var reason: String=ResidentVisits.access_reason(room)
	return "走进"+str(ResidentPlaces.SPECS[room].name) if reason=="" else "敲门 · "+str(ResidentPlaces.SPECS[room].name)

func handle(id: String) -> void:
	if id=="visit_trial":await _trial_paper();return
	var room: String=room_for(id)
	if id.ends_with("_exit"):
		s.ui.dialogue_end();await s.main.exit_interior();s.ui.dialogue_begin();return
	if id==str(ResidentPlaces.SPECS[room].door_id):
		var reason: String=ResidentVisits.access_reason(room)
		if reason!="":await s.say("narrator","",reason);return
		s.ui.dialogue_end();await s.main.enter_interior(room);ResidentVisits.visit(room);s.ui.dialogue_begin();return
	if not s.main.in_room or s.main.room_kind!=room:return
	match room:
		"home_haru":await _haru()
		"toolshed":await _tools()
		"photo_room":await _photos()
		"home_mio":await _mio()
		"home_tanaka":await _tanaka()
		"home_ren":await _ren()
		"home_kazuko":await _kazuko()
		"florist":await _flowers()
		"zakka":await _zakka()
		"post":await _post()
		"library":await _library()
	view.sync_state()

func _keepsake(id: String) -> void:
	await s.ui.show_keepsake(id)
	if Progress.find(id):GameState.save_game()

func _haru() -> void:
	var p: Dictionary=ResidentVisits.state()
	if not p.blueprint_seen:
		await s.ui.show_keepsake("col_blueprint")
		await s.say("haru","neutral","这张是健一画的。小葵把她的画也压在下面，说今年该有她的位置。")
		await s.say("aoi","happy","我不要爬高高的台子。我想让奶奶坐着也看见我跳！")
		await s.say("haru","happy","原来想留下的也不全是旧样子。带图去问问田中吧，先量量剩下的木件。")
		ResidentVisits.see_blueprint()
	else:
		var choice: int=await s.ui.choose(["再看图纸与小葵的画","说说那次试坐","把花摆在缘侧","之后再来"])
		if choice==0:await s.ui.show_keepsake("col_blueprint")
		elif choice==1:
			await s.say("haru","happy","现在坐着也看得见她了。台子的尺寸可以改，谁坐在旁边倒要记清楚。" if not p.trial.is_empty() else "你先量过，我们约个傍晚去坐坐。椅子不必多，能看见就好。")
		elif choice==2:
			if p.followups.has("flower_pick") and not p.followups.has("flower_delivered"):
				ResidentVisits.followup("flower_delivered",str(p.choices.get("flower_pick","blue")))
				await s.say("haru","happy","千代又说她的蓝比我的深？我送她的书签，她还留着呢。花就放这儿，别挡小葵的画。")
			elif p.followups.has("flower_delivered"):
				await s.say("haru","happy","花已经摆在缘侧了，小葵的画也看得见。下次去花坊，替我说一声喜欢。")
			else:await s.say("narrator","","到千代花坊，挑一束与春有关的花。她的缘侧留着一只空花瓶。")

func _tools() -> void:
	var p: Dictionary=ResidentVisits.state()
	if not p.measured:
		await s.ui.show_keepsake("col_blueprint")
		await s.say("tanaka","neutral","……旧图上，坐的地方挤在台子后面。现在春不方便久站，先把观看的椅子让到前边。")
		await s.say("narrator","","木尺沿旧件量过一遍。够做一张长椅；照图把所有木件排满，反而会挡住回家的路。高架还留着一只用过的空花火筒。")
		await s.say("tanaka","neutral","筒是空的。健一说过下回换我点火……先把今年人能坐的地方做好。傍晚有空，也到南町我家吃口饭。")
		ResidentVisits.measure()
		await _appointment()
	else:
		var choice: int=await s.ui.choose(["改约庭院试坐","给木尺换一条挂绳","再看旧筒","先回去"])
		if choice==0:await _appointment()
		elif choice==1:
			ResidentVisits.followup("tool_repaired")
			await s.say("narrator","","挂绳穿过尺尾，木尺回到门边够得到的位置。下雨的时候，田中会在这里整理留种纸包。")
		elif choice==2:await s.ui.show_keepsake("col_fire_tube")

func _appointment() -> void:
	var first: int=ResidentVisits.next_free_day(GameState.day)
	var second: int=ResidentVisits.next_free_day(first)
	var choice: int=await s.ui.choose(["第%d天17:00—20:00，一起去试坐"%first,"第%d天傍晚，留多一天准备"%second,"先不答应，纸签上随时能约"])
	if choice==2:return
	var why: String=ResidentVisits.arrange((first if choice==0 else second)-GameState.day)
	await s.say("narrator","",why if why!="" else ResidentVisits.promise_text()+"。整个白天都能准备；看图与交谈时钟暂停。")

func _trial_paper() -> void:
	ResidentVisits.tick()
	var choice: int=await s.ui.choose(["摆长椅：靠近示范处","摆长椅：东侧留宽通路","按约一起走过去坐坐","改约或补约","取消这一次，材料留着","重看今天的合影","追踪这件事","先去别处"])
	if choice in [0,1]:
		var why: String=ResidentVisits.choose_scheme("near" if choice==0 else "path")
		await s.say("narrator","",why if why!="" else "同一张借来的长椅换好了位置。和子准备小份吃的，街坊负责照明；这次只试春能不能看见。")
	elif choice==2:await view.trial()
	elif choice==3:await _appointment()
	elif choice==4:ResidentVisits.cancel();await s.say("narrator","","这一场取消了。街坊先用简便座位，借来的椅子和试过的摆法都留着；下次可补约。")
	elif choice==5:
		if not ResidentVisits.state().trial.is_empty():
			var photo_choice: int=await s.ui.choose(["看看上一次","拍下现在的场地","先收好"])
			if photo_choice==0:await view.show_photo()
			elif photo_choice==1:await view.capture_photo()
	elif choice==6:ResidentVisits.track()

func _photos() -> void:
	var p: Dictionary=ResidentVisits.state()
	if not Progress.found("col_photo2011"):
		await s.say("narrator","","澪把照片角的位置留好了。先回自己卧室，打开奶奶壁橱里的箱子，把写着空和澪名字的旧合影带来；她会等你再来。")
		return
	await s.ui.show_keepsake("col_photo2011")
	if p.trial.is_empty():await s.say("narrator","","今天这一页还空着。到庭院，和春一起走过、坐过，再回来比较。") ;return
	if ResidentVisits.load_photo()==null:
		await s.say("narrator","","今天的照片还没保存好。试坐的结果没有丢；回庭院纸签选择「重看今天的合影 → 拍下现在的场地」，等拍好后再来并排看。")
		return
	await view.show_photo(true)
	if not p.photo_compared:
		if not ResidentVisits.compare_photo():return
		await s.say("mio","happy","旧照片人人都站着。春坐下以后，小葵还是看得见。没有照旧，也没有少了谁。")
		await s.say("mio","neutral","我写了好多份邀请，却一直没发出去。今晚来我住的小屋吧，帮我决定先寄给谁。")
	else:await s.say("mio","happy","照片留着你选的位置，也留着他们真的用过的样子。以后再改，我们就再拍一张。")

func _mio() -> void:
	var p: Dictionary=ResidentVisits.state()
	if not p.followups.has("invitation_written"):
		await s.say("mio","neutral","箱子不是又要搬家，只是周末想出去看海。我也想收到一句：你不在的时候，这里有人记着你。")
		var choice: int=await s.ui.choose(["邀请小葵下个假期再来看新照片","给将来出门的澪留一封回乡邀请","先想想"])
		if choice==2:return
		ResidentVisits.followup("invitation_written","aoi" if choice==0 else "mio")
		await s.say("mio","happy","不是保证永远留下，是给下一次回来留个位置。写好地址，明天去邮局投进去吧。")
	elif not p.followups.has("letter_sent"):await s.say("mio","neutral","邀请在你随身的便笺里。邮局开门时投进柜台边的邮袋，就真的寄出去。")
	else:await s.say("mio","happy","回信到了吗？我想看看对方会约我们做什么。")

func _tanaka() -> void:
	var p: Dictionary=ResidentVisits.state()
	if not p.followups.has("tanaka_supper"):
		await s.say("narrator","","单人饭桌多摆了一只碗。田中把泥靴留在门外，递来的是煮软的萝卜，不是另一张材料清单。")
		await s.say("tanaka","neutral","一个人做饭总留多。明天分一小包种子给你，想种再种，不急着交给谁。")
		ResidentVisits.followup("tanaka_supper")
	elif not p.followups.has("seed_received") and GameState.day>int(p.followups.tanaka_supper.day):
		if GameState.can_add("seed_radish"):
			GameState.add_item("seed_radish",1,true);ResidentVisits.followup("seed_received")
			await s.say("narrator","","一包留种放在门边，纸上写着播种日期。这是田中昨天晚饭后分好的那一包。")
		else:await s.say("narrator","","田中的种子纸包还留在门边。背包满了，腾出一个位置再来拿，不会被别人领走。")
	else:await s.say("tanaka","neutral","吃得惯就好。想看木件去工具屋，家里歇一歇。")

func _ren() -> void:
	var p: Dictionary=ResidentVisits.state()
	if not p.followups.has("packing_chosen"):
		await _keepsake("col_bakery1972")
		await s.say("ren","neutral","我以为要想个更厉害的配方。可和子阿姨说，好吃归好吃，拿盘子就没法看店了。")
		var choice: int=await s.ui.choose(["用纸包小份，她能带回柜台","留成两半，在窗边一起吃","先看看旧模具"])
		if choice==2:return
		ResidentVisits.followup("packing_chosen","paper" if choice==0 else "share")
		await s.say("ren","happy","老配方留下，吃法可以变。明天后场会留这份试作，回来看看我有没有包好。")
	else:
		if p.followups.has("packing_return") or GameState.day>int(p.followups.packing_chosen.day):
			if not p.followups.has("packing_return"):ResidentVisits.followup("packing_return")
			if p.choices.packing_chosen=="paper":
				await s.say("ren","happy","照你说的试过了。忙着看店的人有自己的吃法，这回终于不用等大家坐齐。")
			else:
				await s.say("ren","happy","今天把小份切成两半了。有人愿意在窗边等另一个人坐下来。")
		else:await s.say("ren","neutral","桌上这份正按你选的办法准备，明天再看看。")

func _kazuko() -> void:
	var p: Dictionary=ResidentVisits.state()
	if not p.followups.has("tags_sorted"):
		await _keepsake("col_poster")
		await s.say("kazuko","neutral","价签背面不是欠账，是轮班。春替我顾过摊，我才有空去看女儿跳舞。")
		var choice: int=await s.ui.choose(["按名字收好，空一格给今年","保留老顺序，旁边添今年的纸签","先放回去"])
		if choice==2:return
		ResidentVisits.followup("tags_sorted","names" if choice==0 else "years")
		await s.say("kazuko","happy","今年也别让谁一直看摊。你选座位，我给春带小份的，免得她端着盘子走远。")
	else:await s.say("kazuko","happy","借东西写在小册子里，归还就划掉。你留的那一格，已经写上今年的轮班了。")

func _flowers() -> void:
	var choice: int=await s.ui.choose(["挑花送春，看看夹着的书签","买花与种苗","改天再来"])
	if choice==1:await s.farm._open_shop("florist");return
	if choice!=0:return
	await _keepsake("col_bookmark")
	if not ResidentVisits.state().blueprint_seen:await s.say("narrator","","千代问起要送给谁。去春家看过她的缘侧和图纸，再选一束适合那个位置的花。") ;return
	if ResidentVisits.state().followups.has("flower_delivered"):await s.say("narrator","","那束花已经送到春家缘侧。千代把书签收回押花本，空下的花篮等着下一束。") ;return
	if ResidentVisits.state().followups.has("flower_pick"):await s.say("narrator","","选好的那束已经留在篮里。送到春家缘侧，不再重复拿花。") ;return
	await s.say("narrator","","押花桌上夹着春送来的书签。千代嘴上比谁的紫阳花更蓝，却仔细记着春窗边下午才晒到太阳。")
	var color: int=await s.ui.choose(["淡蓝紫阳花，放在阴凉缘侧","一束小白花，给小葵的画留颜色"])
	ResidentVisits.followup("flower_pick","blue" if color==0 else "white")

func _zakka() -> void:
	var choice: int=await s.ui.choose(["看旧海报与修理台","买生活杂货","先看看"])
	if choice==1:await s.farm._open_shop("zakka");return
	if choice!=0:return
	await _keepsake("col_poster")
	var p: Dictionary=ResidentVisits.state()
	if p.trial.is_empty():await s.say("narrator","","阿健把海报上的旧摊架指给你看：那块板如今在长椅背后。先让人坐过，再知道哪里值得修。") ;return
	if ResidentVisits.followup("cushion_fixed"):
		await s.say("narrator","","把靠垫的旧扣重新穿好，阿健帮忙缝牢。明天回到试坐的长椅，会有人把它绑上；木板也有了今天的用途。")
	else:await s.say("narrator","","那一只扣已经用上了。旧架子没有消失，换了让人舒服一点的用法。")

func _post() -> void:
	var future: Dictionary=MainlineProgress.direction()
	if GameState.qstate("Q15")=="done" and int(future.get("choice",-1))==2 and not future.get("action_done",false):
		var next_letter: int=await s.ui.choose(["把下一次回乡的邀请亲手寄出","先看看以前的回信"])
		if next_letter==0:
			MainlineProgress.record_direction_action("letter")
			ResidentVisits.followup("next_summer_letter",str(GameState.day))
			await s.say("narrator","","新信封写下今天的日期：下次回来，一起到树下坐坐。它进了邮袋，旧回信仍留在便笺里。")
			return
	var p: Dictionary=ResidentVisits.state()
	if not p.followups.has("invitation_written"):await s.say("narrator","","桌上有空白回邮纸。与澪看过今天的照片后，去她家写一封有收信人的邀请。") ;return
	if not p.followups.has("letter_sent"):
		var choice: int=await s.ui.choose(["核对地址，把邀请投进邮袋","再想想措辞"])
		if choice==0:ResidentVisits.followup("letter_sent",str(p.choices.invitation_written));await s.say("narrator","","邮戳落在今天。两天后到这里取回信；对方会告诉你想一起做什么。")
	elif not p.followups.has("letter_reply") and GameState.day>=int(p.followups.letter_sent.day)+2:
		ResidentVisits.followup("letter_reply")
		await s.say("narrator","","回信夹着一张小纸：下次回来，想在你选的长椅边拍一张白天的照片。今天就可以到庭院试坐纸签再拍，把下一页留出来。")
		ResidentVisits.track()
	elif p.followups.has("letter_reply"):await s.say("narrator","","回信已收进便笺。庭院的椅子还在，纸签可以重拍今天的照片。")
	else:await s.say("narrator","","邮袋已经出发。两天后再来，地址和这次寄信的日期都记在柜台上。")

func _library() -> void:
	await _keepsake("col_oldmap")
	if not Progress.found("col_photo2011"):await s.say("narrator","","地图上的榉树还是小小一圈。等找到一张当年的照片，就能对照街道的变化。") ;return
	var choice: int=await s.ui.choose(["沿旧图描出现在通往田中家的路","在旧舞台旁标出今年的座位","先合上地图"])
	if choice==2:return
	if choice==1 and ResidentVisits.state().trial.is_empty():await s.say("narrator","","今年的位置还没试过。等春真的坐过，再把它标在图上。") ;return
	ResidentVisits.followup("map_traced","home" if choice==0 else "seat")
	await s.say("narrator","","旧店铺和今天的门牌被细线连在一起。回到这张阅图桌，随时可以看出自己改变的是哪一处。")
