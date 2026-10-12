extends RefCounted
var t: Node
var main: Node
func _init(runner: Node) -> void:t=runner;main=runner.main
func check(label: String,ok: bool,detail: String="") -> void:t.check("TREE_LOCOMOTION",label,ok,detail)

func camera_contract() -> void:
 var hero: Node3D=main.world.get_node("T05_old_shade_tree") as Node3D
 var bark: MeshInstance3D=hero.find_child("Trunk*",true,false) as MeshInstance3D
 var body: StaticBody3D=bark.get_node("BarkCameraCollision") as StaticBody3D
 var collision: CollisionShape3D=body.get_child(0) as CollisionShape3D
 var shape: ConcavePolygonShape3D=collision.shape as ConcavePolygonShape3D
 var count: int=shape.get_faces().size()/3
 var source_matches: bool=str(shape.get_meta("visual_bark_sha256",""))==FileAccess.get_sha256("res://assets/models/T05_old_shade_tree.glb")
 check("camera-only bark stays within measured sweep budget instead of visual170k faces",count>=1000 and count<=20000 and source_matches and body.collision_layer==WorldBuilder.L_CAMERA and (main.player.collision_mask&WorldBuilder.L_CAMERA)==0,"triangles=%d source=%s"%[count,source_matches])
 var tree:=TriangleMesh.new();tree.create_from_faces(bark.mesh.get_faces())
 var space: PhysicsDirectSpaceState3D=hero.get_world_3d().direct_space_state
 var samples:=0;var maximum:=0.0;var missing:=0
 for height: float in [2.4,3.1,4.2]:
  for direction: int in 8:
   var angle: float=float(direction)*TAU/8.;var centre:=Vector3(0,height,.55)
   var from: Vector3=centre+Vector3(cos(angle),0,sin(angle))*7.
   var to: Vector3=centre-Vector3(cos(angle),0,sin(angle))*.6
   var visual: Dictionary=tree.intersect_segment(from,to)
   if visual.is_empty():continue
   samples+=1
   var query:=PhysicsRayQueryParameters3D.create(bark.to_global(from),bark.to_global(to),WorldBuilder.L_CAMERA)
   query.hit_back_faces=true;query.hit_from_inside=true
   var hit: Dictionary=space.intersect_ray(query)
   if hit.is_empty():missing+=1
   else:maximum=maxf(maximum,(hit.position as Vector3).distance_to(bark.to_global(visual.position)))
 var old_point:=Vector3(4.4741669,2.8000002,7.3787193)
 var old_ray:=PhysicsRayQueryParameters3D.create(old_point,Vector3(4,2.4,10.8),WorldBuilder.L_CAMERA)
 old_ray.hit_back_faces=true;old_ray.hit_from_inside=true
 check("measured camera proxy still hits real upper bark and old inside-tree ray",samples>=12 and missing==0 and maximum<=.13 and not space.intersect_ray(old_ray).is_empty(),"samples=%d missing=%d max=%.4fm"%[samples,missing,maximum])
 var leaf: MeshInstance3D=hero.get_node_or_null("Foliage_LowerBoughSprigs") as MeshInstance3D
 var low:=INF;var high:=-INF;var triangles:=0
 if leaf!=null:
  var box: AABB=leaf.mesh.get_aabb();low=box.position.y;high=box.end.y;triangles=leaf.mesh.get_faces().size()/3
 check("real lower-bough leaf sprays cover bare shelves without entering walking height",leaf!=null and leaf.is_visible_in_tree() and triangles>=300 and triangles<=2000 and low>=2.15 and high<6.2,"triangles=%d height=%.3f..%.3f"%[triangles,low,high])
 var alpha_fraction:=0.0;var transparent:=false
 if leaf!=null:
  var material: ShaderMaterial=leaf.get_active_material(0) as ShaderMaterial
  var texture: Texture2D=material.get_shader_parameter("albedo_tex") as Texture2D if material!=null else null
  if texture!=null:
   var image: Image=texture.get_image();var opaque:=0
   for row: int in 20:
    for column: int in 40:
     var pixel: Color=image.get_pixel(int(float(column+.5)/40.*image.get_width()),int(float(row+.5)/40.*image.get_height()))
     if pixel.a>.42:opaque+=1
   alpha_fraction=float(opaque)/800.
   transparent=alpha_fraction>.03 and alpha_fraction<.85 and int(material.get_shader_parameter("part_role"))==1 and image.has_mipmaps()
 check("lower foliage reuses real alpha leaves and casts no camera/player collision",transparent and leaf.find_children("*","CollisionObject3D",true,false).is_empty(),"opaque_fraction=%.3f"%alpha_fraction)

func route_contract() -> void:
 var actor: NPC=main.npcs.aoi
 var start:=Vector3(-25,0,-11);var finish:=start+Vector3(0,0,3)
 actor.set_home(false);actor.place(start,0);actor.set_process(false)
 main.player.global_position=Vector3(20,.1,20);main.player.velocity=Vector3.ZERO
 await t.frames(3)
 var direct: Array[Vector3]=actor.MOTION_ROUTE.query(actor,start,finish)
 var stats: Dictionary=actor.get_meta("motion_route_last",{})
 check("clear corridors use one exact capsule segment without scanning a full grid",direct.size()==1 and direct[0].distance_to(finish)<.001 and stats.get("method","")=="direct_capsule" and int(stats.get("point_queries",999))<=2,str(stats))
 main.player.global_position=start+Vector3(0,0,1.5);await t.frames(3)
 var detour: Array[Vector3]=actor.MOTION_ROUTE.query(actor,start,finish)
 var safe:=not detour.is_empty();var last: Vector3=start
 for point: Vector3 in detour:
  var query:=PhysicsShapeQueryParameters3D.new();query.shape=actor.MOTION_ROUTE.capsule();query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS;query.exclude=[actor.body.get_rid()];query.transform=Transform3D(Basis.IDENTITY,last+Vector3.UP*.8);query.motion=point-last
  var cast: PackedFloat32Array=actor.get_world_3d().direct_space_state.cast_motion(query)
  safe=safe and cast.size()==2 and cast[0]>.999;last=point
 check("actual dynamic-player detour is smooth and every complete capsule segment stays clear",safe and detour.size()<=6 and last.distance_to(finish)<.001,"points=%d safe=%s"%[detour.size(),safe])
 var wall:=StaticBody3D.new();wall.collision_layer=WorldBuilder.L_PLACED
 var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,2,2);collider.shape=box;collider.position.y=1;wall.add_child(collider);main.add_child(wall);wall.global_position=finish
 main.player.global_position=Vector3(20,.1,20);await t.frames(3)
 check("occupied exact destinations remain unreachable rather than inventing a shortcut",actor.MOTION_ROUTE.query(actor,start,finish).is_empty())
 wall.queue_free();await t.frames(3)
 actor.place(start,0);actor.player=main.player
 main.player.global_position=start+Vector3(.02,0,-1)
 var left: Vector3=actor._avoid(Vector3.FORWARD,.02,5.)
 main.player.global_position=start+Vector3(-.02,0,-1)
 var right: Vector3=actor._avoid(Vector3.FORWARD,.02,5.)
 check("one passer keeps the chosen side across tiny centreline changes",left.x*right.x>.02,"%.3f / %.3f"%[left.x,right.x])
 main.player.global_position=Vector3(20,.1,20);actor.place(start,0);actor.hold=false;actor.talking=false;actor.set_process(true)
 actor.walk.call_deferred([finish],true)
 var began: int=Time.get_ticks_usec();await main.get_tree().create_timer(.08).timeout
 var distance: float=actor.global_position.distance_to(start);var first_speed: float=distance/(float(Time.get_ticks_usec()-began)/1000000.)
 await main.get_tree().create_timer(.45).timeout
 check("ordinary walking accelerates instead of jumping to full speed",first_speed>.02 and first_speed<.70 and actor.global_position.distance_to(start)>.20,"first_speed=%.3f distance=%.3f"%[first_speed,actor.global_position.distance_to(start)])
 actor.place(start,0);actor.set_process(false)
 var project_start:=Vector3(-3,0,12.5);var project_finish:=Vector3(2,0,13)
 var project: Dictionary=ProjectRoute.query(main.world,project_start,project_finish,[],"tree-motion-test")
 check("project trials share the smooth planner and retain exact ends and layout revision",bool(project.get("ok",false)) and project.get("planner","")=="lazy_capsule" and str(project.get("revision",""))=="tree-motion-test" and (project.get("path",[]) as Array).size()<=3 and ((project.path as Array)[-1] as Vector3).distance_to(project_finish)<.001,str(project))
 var outside: Dictionary=ProjectRoute.query(main.world,Vector3(50,0,0),Vector3(51,0,0))
 check("shared project smoothing still rejects routes outside the actual courtyard trial area",not bool(outside.get("ok",true)))

func strict_corner_contract() -> void:
 var actor: NPC=main.npcs.aoi;var original_speed: float=actor.speed
 var start:=Vector3(-25,0,-11);var corner:=Vector3(-25,0,-8);var finish:=Vector3(-22,0,-8)
 var wall:=StaticBody3D.new();wall.collision_layer=WorldBuilder.L_PLACED
 var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(5,2,.2);collider.shape=box;wall.add_child(collider);main.add_child(wall);wall.global_position=Vector3(-23.5,1,-7.5)
 actor.set_home(false);actor.place(start,0);actor.hold=false;actor.talking=false;actor.speed=2.;actor.set_process(true);main.player.global_position=Vector3(20,.1,20)
 await t.frames(3)
 var planned_clear:=true
 for segment: Array in [[start,corner],[corner,finish]]:
  var query:=PhysicsShapeQueryParameters3D.new();query.shape=actor.MOTION_ROUTE.capsule();query.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED|WorldBuilder.L_ACTORS;query.exclude=[actor.body.get_rid()];query.transform=Transform3D(Basis.IDENTITY,(segment[0] as Vector3)+Vector3.UP*.8);query.motion=(segment[1] as Vector3)-(segment[0] as Vector3)
  var cast: PackedFloat32Array=actor.get_world_3d().direct_space_state.cast_motion(query)
  planned_clear=planned_clear and cast.size()==2 and cast[0]>.999
 actor.walk_safe.call_deferred([corner,finish]);await t.frames(3)
 var deadline: int=Time.get_ticks_msec()+8000
 while actor.is_moving() and Time.get_ticks_msec()<deadline:await t.frames(1)
 check("a strict capsule route turns beside a close wall without steering outside its checked segments",planned_clear and actor.walk_succeeded and actor.global_position.distance_to(finish)<.03,"finish=%s reason=%s"%[actor.global_position,actor.get_meta("motion_reason","")])
 actor.cancel_safe_walk();actor.speed=original_speed;actor.place(start,0);actor.set_process(false);wall.queue_free();await t.frames(3)

func pose_contract() -> void:
 for who: String in ["mio","aoi"]:
  var actor: NPC=main.npcs[who];actor.set_home(false);actor.place(Vector3(-8,.01,-10),0);actor.set_process(false)
  var controller: CharAnim=actor.anim;controller._oneshot="";controller.idle_clip="idle";controller.ap.play("idle",0);controller.ap.speed_scale=0;controller.ap.seek(.2,true)
  await t.frames(3)
  var sk: Skeleton3D=actor.model.find_child("Skeleton3D",true,false) as Skeleton3D
  var probe: SkeletonModifier3D=load("res://scripts/tools/character_qa_pose_probe.gd").new();probe.name="NaturalGaitContactProbe";sk.add_child(probe);probe.call("prepare",actor.model);probe.set("measure_feet",true)
  var widths: Array[float]=[];var gaps: Array[float]=[];var phase_values: Array[float]=[0.,.125,.25,.375,.5,.625,.75,.875]
  for phase: float in phase_values:
   controller.ap.play("walk" if who=="mio" else "idle",0);controller.ap.speed_scale=0;controller.ap.seek(controller.ap.current_animation_length*phase,true);await t.frames(2)
   # SkeletonModifier poses are restored on the public skeleton after
   # evaluation. Read the final renderer-stage probe, not restored bones.
   var rendered_joints: Dictionary=probe.get("joints")
   var left_joint: Array=rendered_joints["foot.L"]
   var right_joint: Array=rendered_joints["foot.R"]
   var a: Vector3=actor.model.to_local(Vector3(float(left_joint[0]),float(left_joint[1]),float(left_joint[2])))
   var b: Vector3=actor.model.to_local(Vector3(float(right_joint[0]),float(right_joint[1]),float(right_joint[2])))
   widths.append(a.x-b.x)
   var soles: Dictionary=probe.get("soles")
   var planted: String="L" if phase<.5 else "R"
   if who=="aoi":gaps.append(minf(float(soles.get("L",INF)),float(soles.get("R",INF)))-.01)
   else:gaps.append(float(soles.get(planted,INF))-.01)
  widths.sort();gaps.sort()
  if who=="mio":
   check("Mio keeps two natural foot lanes instead of crossing onto a single line",widths[0]>=.12 and widths[-1]<=.21,str(widths))
   check("Mio's actual stance shoe stays planted across the real authored cycle",gaps[0]>=.003 and gaps[-1]<=.026,str(gaps))
  else:
   controller.ap.play("talk",0);controller.ap.speed_scale=0;controller.ap.seek(controller.ap.current_animation_length*.5,true);await t.frames(2)
   var talking_joints: Dictionary=probe.get("joints");var talk_left: Array=talking_joints["foot.L"];var talk_right: Array=talking_joints["foot.R"]
   var talk_width: float=float(talk_left[0])-float(talk_right[0])
   check("Aoi's real idle and talking keep relaxed foot spacing and grounded shoes",widths[0]>=.13 and widths[-1]<=.18 and gaps[0]>=.003 and gaps[-1]<=.018 and talk_width>=.13 and talk_width<=.18,"widths=%s gaps=%s talking=%.3f"%[widths,gaps,talk_width])
  probe.queue_free();controller.ap.speed_scale=1.;controller.ap.play("idle",0)
 var child: NPC=main.npcs.aoi;child.set_process(false);child.set_home(false)
 var playful:=true
 for entry: Array in [[10.5,"P06"],[11.9,"P04"]]:
  child.apply_schedule(float(entry[0]),main.player.global_position,true)
  var toy: Node3D=main.world.get_node(str(entry[1])) as Node3D
  var to: Vector3=toy.global_position-child.global_position;to.y=0
  playful=playful and to.length()>1.05 and to.length()<2.3 and child.model.global_basis.z.normalized().dot(to.normalized())>.95
  var placement:=PhysicsShapeQueryParameters3D.new();placement.shape=child.MOTION_ROUTE.capsule();placement.collision_mask=WorldBuilder.L_SOLID|WorldBuilder.L_PLACED;placement.exclude=[child.body.get_rid()];placement.transform=Transform3D(Basis.IDENTITY,child.global_position+Vector3.UP*.8)
  playful=playful and child.get_world_3d().direct_space_state.intersect_shape(placement,1).is_empty()
 check("Aoi actually stands beside and faces the sandbox and swing on her day schedule",playful)
 var rain: Array=Layout.daily_schedule("aoi",2,"rain");var rain_region: String=""
 for entry: Array in rain:
  if float(entry[0])<=10.5:rain_region=str(entry[1])
 var sun: Array=Layout.daily_schedule("aoi",2,"sunny")
 check("wet toys stay empty while Aoi's original grandma morning remains available",rain_region=="home" and float(sun[0][0])==7.5 and (sun[0][2] as Vector3).distance_to(Layout.NPC.aoi.prep)<.001)
 child.hold=true;child._idle_t=1000.;child._greeted_day=GameState.day;child.set_process(true)
 child.apply_fest(["town",[-5.15,0,4.4],-90,"cheer"],"qa:child-reaction")
 var gesture_seconds: float=child.anim.ap.get_animation("cheer").length
 await main.get_tree().create_timer(gesture_seconds+.4).timeout
 check("a finite festival cheer returns Aoi to natural idle instead of freezing the pose",child.anim.ap.current_animation=="idle" and child.anim.idle_clip=="idle" and not child.anim.busy(),child.anim.ap.current_animation)
 child.hold=false;child.set_process(false)

func run() -> void:
 var saved: Dictionary=GameState.to_dict().duplicate(true);var player_at: Vector3=main.player.global_position;var player_process: bool=main.player.is_physics_processing();var was_freeze: bool=NPC.freeze
 var controls: Dictionary={}
 for id: String in main.npcs:
  var npc: NPC=main.npcs[id];controls[id]=npc.is_processing();npc.set_process(false);npc.set_home(true)
 main.player.set_physics_process(false);NPC.freeze=false
 await camera_contract();await route_contract();await strict_corner_contract();await pose_contract()
 GameState.from_dict(saved);GameState.clock_paused=true;main.player.global_position=player_at;main.player.set_physics_process(player_process);NPC.freeze=was_freeze
 for id: String in main.npcs:(main.npcs[id] as Node).set_process(bool(controls[id]))
 main.update_npcs(true)
