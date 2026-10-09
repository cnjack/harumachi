extends SceneTree
## Standalone acceptance for the small title cat and shared resting decorations.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output: String=OS.get_cmdline_user_args()[0]
	var title: Control=(load("res://scenes/title.tscn") as PackedScene).instantiate() as Control
	root.add_child(title)
	await process_frame
	await process_frame
	var results: Array[Dictionary]=[]
	var decorative: Control=title.get_node_or_null("MenuCat") as Control
	results.append({"name":"Title contains animated cat","passed":decorative!=null})
	if decorative!=null:
		results.append({"name":"Menu cat uses only 2D nodes","passed":decorative.find_children("*","Node3D",true,false).is_empty() and decorative.find_children("*","SubViewport",true,false).is_empty()})
		results.append({"name":"Decoration ignores input and avoids buttons","passed":decorative.mouse_filter==Control.MOUSE_FILTER_IGNORE and decorative.focus_mode==Control.FOCUS_NONE and not decorative.get_global_rect().intersects((title.menu as Control).get_global_rect())})
		var sprite: AnimatedSprite2D=decorative.get_node_or_null("CatSprite") as AnimatedSprite2D
		var heading: Label=title.get_node_or_null("TitleHeading") as Label
		results.append({"name":"Small cat walks directly above the title","passed":sprite!=null and heading!=null and sprite.global_position.y<heading.global_position.y+35 and sprite.scale.x<=.22})
		var states: Array[String]=[]
		var moved: bool=false
		var frame_changed: bool=false
		var initial_position: Vector2=sprite.position if sprite else Vector2.ZERO
		var previous_frame: int=sprite.frame if sprite else 0
		var held_position: Vector2=Vector2.ZERO
		var rest_held: bool=true
		var rest_seen: bool=false
		if sprite!=null:
			for sample: int in range(1500):
				await physics_frame
				var animation: String=String(sprite.animation)
				if animation not in states:states.append(animation)
				moved=moved or initial_position.distance_to(sprite.position)>20
				frame_changed=frame_changed or sprite.frame!=previous_frame
				if animation=="rest":
					if not rest_seen:held_position=sprite.position;rest_seen=true
					else:rest_held=rest_held and held_position.distance_to(sprite.position)<.01
				previous_frame=sprite.frame
		results.append({"name":"Cat walks, lies down, sways its tail and gets up","passed":moved and frame_changed and ["walk","lie_down","rest","get_up"].all(func(value: String):return value in states),"states":states})
		results.append({"name":"Resting cat holds its position while frames animate","passed":rest_seen and rest_held})
		var focus: Control=root.gui_get_focus_owner()
		results.append({"name":"Menu keeps keyboard focus","passed":focus is Button})
		var settings_button: Button
		for child: Node in title.menu.get_children():
			if child is Button and (child as Button).text=="设置":settings_button=child as Button
		await _click(settings_button.get_global_rect().get_center())
		var completion: Button
		for node: Node in title.panel_layer.find_children("*","Button",true,false):
			if (node as Button).text=="完成":completion=node as Button
		results.append({"name":"Settings click opens a panel with resting cat","passed":completion!=null and title.panel_layer.find_child("RestingCat",true,false)!=null})
		if completion!=null:
			var rest_cat: Control=title.panel_layer.find_child("RestingCat",true,false) as Control
			if rest_cat!=null:
				var body: Sprite2D=rest_cat.get_node("RestBody") as Sprite2D
				var tail: AnimatedSprite2D=rest_cat.get_node("DanglingTail") as AnimatedSprite2D
				var body_position: Vector2=body.position
				var texture: Texture2D=body.texture
				var initial_tail: int=tail.frame
				var tail_changed: bool=false
				var fixed_body: bool=true
				paused=true
				for sample: int in range(120):
					await process_frame
					tail_changed=tail_changed or tail.frame!=initial_tail
					fixed_body=fixed_body and body.texture==texture and body.position.distance_to(body_position)<.01
				paused=false
				results.append({"name":"Fixed body and dangling tail animate correctly while paused","passed":fixed_body and tail_changed and tail.position.y>body.position.y})
			await _click(completion.get_global_rect().get_center())
			await process_frame
			results.append({"name":"Done click closes the panel","passed":title.panel_layer.get_child_count()==0})
	var passed: bool=true
	for result: Dictionary in results:passed=passed and bool(result.passed)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"results":results},"\t"))
	print("TITLE_CAT_CHECKS ",passed," ",results)
	title.queue_free()
	await process_frame
	quit(0 if passed else 1)

func _click(point: Vector2) -> void:
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	await process_frame
	var press: InputEventMouseButton=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.position=point
	press.global_position=point
	press.pressed=true
	root.push_input(press,true)
	await process_frame
	var release: InputEventMouseButton=press.duplicate() as InputEventMouseButton
	release.pressed=false
	root.push_input(release,true)
	await process_frame
