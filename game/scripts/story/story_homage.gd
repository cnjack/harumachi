class_name StoryHomage
extends RefCounted
var s: Story

func _init(owner: Story) -> void:
	s = owner

func handles(id: String) -> bool:
	return not Homage.definition(id).is_empty()

func prompt(id: String) -> Variant:
	var entry := Homage.definition(id)
	if entry.is_empty():
		return null
	return "看看%s" % str(entry.name)

func _record(entry: Dictionary) -> void:
	GameState.toast.emit("收进远方小记：%s · K 查看" % str(entry.name))
	Audio.sting("item")
	s.ui.panels.card("远方的小小回声", [str(entry.name), "已收进图鉴的“远方小记”（K）。"], Homage.image_path(entry), "", 4.0)

func handle(id: String) -> void:
	var entry := Homage.definition(id)
	if entry.is_empty():
		return
	if Homage.found(id):
		await s.say("narrator", "", str(entry.text))
		return
	for line: String in entry.inspect:
		await s.say("narrator", "", line)
	if entry.requires.is_empty():
		if Homage.discover(id):
			_record(entry)
		return
	var choices: Array = []
	var available: Array[String] = []
	for item_id: String in Homage.remaining(id):
		if GameState.has(item_id):
			choices.append("留下%s ×1" % GameState.item_name(item_id))
			available.append(item_id)
	choices.append("先不放，留着自己用")
	if available.is_empty():
		var names: Array[String] = []
		for item_id: String in Homage.remaining(id):
			names.append(GameState.item_name(item_id) + " ×1")
		await s.say("narrator", "", "还空着的格子：%s。等有余下的收获，再过来也不迟。" % "、".join(names))
		return
	var selected: int = await s.ui.choose(choices)
	if selected < 0 or selected >= available.size():
		return
	if not Homage.donate(id, available[selected]):
		await s.say("narrator", "", "这份作物已经放过了，或者现在不在背包里。")
		return
	if Homage.found(id):
		for line: String in entry.get("complete", []):
			await s.say("narrator", "", line)
		_record(entry)
	else:
		await s.say("narrator", "", "你把一份收获放进了木盒。余下的格子可以下次再填。")
