extends Node
## Optional read-only input/state telemetry for UI play. Never issues input or changes state.
var main: Node
var file: FileAccess
var elapsed:=0.0
var next_sample:=0.0
func setup(scene: Node,path: String) -> void:
	main=scene
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	file=FileAccess.open(path,FileAccess.WRITE)
func _input(event: InputEvent) -> void:
	if file!=null and event is InputEventKey:
		var key: InputEventKey=event
		file.store_line(JSON.stringify({"event":"key","seconds":elapsed,"pressed":key.pressed,"keycode":key.keycode,"physical_keycode":key.physical_keycode,"unicode":key.unicode,"echo":key.echo,"matches_move_right":InputMap.event_is_action(key,"move_right")}))
		file.flush()
func _physics_process(delta: float) -> void:
	elapsed+=delta;next_sample-=delta
	if file==null or next_sample>0:return
	next_sample=.1
	var at: Vector3=main.player.global_position
	var movement: Vector2=Input.get_vector("move_left","move_right","move_forward","move_back")
	var contacts: Array=[]
	for index: int in main.player.get_slide_collision_count():
		var contact: KinematicCollision3D=main.player.get_slide_collision(index)
		var collider: Object=contact.get_collider()
		contacts.append(str((collider as Node).get_path()) if collider is Node else str(collider))
	file.store_line(JSON.stringify({"seconds":elapsed,"day":GameState.day,"minute":GameState.minute,"region":GameState.player_region,"room":main.room_kind,"position":[at.x,at.y,at.z],"input":[movement.x,movement.y],"frozen":main.player.frozen,"locks":GameState._ui_locks.keys(),"modal":main.ui.modal,"story_busy":main.story.busy,"target":main.player.target.id if main.player.target!=null else "","contacts":contacts}))
	file.flush()
func _exit_tree() -> void:
	if file!=null:file.close()
