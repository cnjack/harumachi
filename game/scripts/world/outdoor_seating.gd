extends RefCounted
## Give existing benches an everyday use; no extra display furniture or festival props.
var points: Array[Interactable] = []

func setup(story: Story) -> void:
	for parent: Node3D in [story.world, story.world.farm]:
		var root := Node3D.new(); root.name = "OutdoorRestSeats"; parent.add_child(root)
		var farm: bool = parent == story.world.farm
		root.visible = true if farm else story.world.region == "town"
		var index: int = 0
		var benches: Array[Node] = parent.get_children()
		if farm: benches.append_array(story.world.farm.lakeside.get_children())
		for bench: Node in benches:
			if not bench is Node3D or str(bench.get_meta("model_id", "")) != "A12_bench": continue
			var seat: Node3D = bench as Node3D
			var front: Vector3 = seat.basis.z.normalized()
			var position: Vector3 = root.to_local(seat.global_position)
			# A few benches hold an illustrated discovery. Leave that part of the
			# plank free instead of seating the player through the keepsake.
			for keepsake: HomageDisplay in story.world.find_children("*","HomageDisplay",true,false):
				var on_bench: Vector3=seat.to_local(keepsake.global_position)
				if absf(on_bench.x)<.9 and absf(on_bench.z)<.3:
					position+=seat.basis.x.normalized()*(.62 if on_bench.x<=0.0 else -.62)
					break
			var top: float = WorldBuilder.surface_height(seat, Vector2(seat.global_position.x, seat.global_position.z), seat.global_position.y + .80)
			if not is_finite(top): continue
			var point: Interactable
			if farm and index==0:
				point=story.main.get_node_or_null("P_farm_bench") as Interactable
				if point!=null:point.reparent(root,true)
			if point==null:
				point=Interactable.new();point.id="public_rest_%s_%d"%["farm" if farm else "town",index];point.name=point.id;root.add_child(point)
			point.position=point.get_parent().to_local(root.to_global(position+front*.85+Vector3.UP*.7));point.radius=1.3
			point.set_meta("seat_position", position + front * .16)
			point.set_meta("stand_position", position + front * .85)
			point.set_meta("seat_yaw", rad_to_deg(atan2(front.x, front.z)))
			point.set_meta("seat_support", seat.get_path())
			point.set_meta("seat_height", top - seat.global_position.y)
			point.set_meta("rest_region","farm" if farm else "town")
			var lake: bool=farm and seat.get_parent()==story.world.farm.lakeside
			point.set_meta("rest_scene", "镜波湖畔" if lake else "田边歇脚" if farm else "树下歇脚" if str(seat.name).begins_with("OldTreeSeat") else "庭院长椅")
			point.set_meta("rest_description", "湖面映着天光。风从水上过来，坐一会儿，等远山的影子慢慢变淡。" if lake else "河风吹过田埂。先把肩膀放松，看看水面再回去。" if farm else "树叶在脚边晃动。街坊各自忙着，也可以在这里慢慢坐一会儿。")
			for body: CollisionObject3D in seat.find_children("*", "CollisionObject3D", true, false): point.body = body; break
			points.append(point); index += 1
