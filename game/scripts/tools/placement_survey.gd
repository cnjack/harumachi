extends Node
## Read-only measurements, including nested props and AmbientLife outside World.
var main: Node
func collect(root: Node,out: Array[Node3D]) -> void:
	for child: Node in root.get_children():
		if child is Node3D and child.has_meta("model_id"):out.append(child)
		collect(child,out)
func _ready() -> void:
	GameState.new_game();GameState.clock_paused=true;NPC.roam_enabled=false
	main=load("res://scenes/main.tscn").instantiate();add_child(main);main.ui.instant=true
	for frame in 10:await get_tree().physics_frame
	var models: Array[Node3D]=[];collect(main,models)
	var report: Dictionary={"models":models.size(),"old_world_audit_count":PropAudit.instances(main.world).size(),"targets":[],"regional_audits":{}}
	for model: Node3D in models:
		var id: String=model.get_meta("model_id")
		if id in ["D10_rocks","D02_rain_barrel","A20_cat_sleep","A22_cat_sit","T02_summer_tree","T03_round_ginkgo","T04_slender_cedar"] or (id=="T01_courtyard_tree" and model.global_position.x>25 and model.global_position.x<35):
			var bounds: AABB=model.global_transform*WorldBuilder.local_aabb(model)
			report.targets.append({"id":id,"path":str(main.get_path_to(model)),"position":[model.global_position.x,model.global_position.y,model.global_position.z],"min":[bounds.position.x,bounds.position.y,bounds.position.z],"max":[bounds.end.x,bounds.end.y,bounds.end.z],"excluded_as_loose":PropAudit.loose(id)})
	for region: String in ["town","farm"]:
		main.world.set_region(region)
		for frame in 3:await get_tree().physics_frame
		var findings: Array=PropAudit.run(main.world,Layout.WALLS if region=="town" else [])
		report.regional_audits[region]=findings.map(func(finding: Dictionary):return PropAudit.describe(finding))
	var out: String="/tmp/placement-survey.json"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--survey-out="):out=argument.substr(13)
	var file:=FileAccess.open(out,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("PLACEMENT_SURVEY models=",models.size()," legacy=",report.old_world_audit_count," findings=",report.regional_audits)
	Audio.silence();get_tree().quit()
