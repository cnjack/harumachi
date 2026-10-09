extends SceneTree
## Build editor-usable resources from the same source catalog and semantic factories.
func _initialize() -> void:
	call_deferred("build")
func build() -> void:
	DirAccess.make_dir_recursive_absolute("res://ui_kit/resources")
	DirAccess.make_dir_recursive_absolute("res://ui_kit/png")
	var theme_error:=ResourceSaver.save(UIKitStyles.theme(),"res://ui_kit/resources/theme.res")
	if theme_error!=OK:quit(1);return
	for id: String in UIKitCatalog.ENTRIES:
		if UIKitCatalog.ENTRIES[id][2]=="icon":
			if ResourceSaver.save(UIKitAssets.icon(id),"res://ui_kit/resources/icon_"+id+".tres")!=OK:quit(1);return
			if UIKitAssets.icon(id).get_image().save_png("res://ui_kit/png/icon_"+id+".png")!=OK:quit(1);return
		elif UIKitCatalog.ENTRIES[id][2]=="control":
			if UIKitAssets.icon(id).get_image().save_png("res://ui_kit/png/control_"+id+".png")!=OK:quit(1);return
	for state: String in ["normal","hover","pressed","disabled"]:
		for role: String in ["primary","secondary"]:
			if ResourceSaver.save(UIKitStyles.button(role,state),"res://ui_kit/resources/button_"+role+"_"+state+".res")!=OK:quit(1);return
	for state: String in ["normal","selected","disabled","empty"]:
		if ResourceSaver.save(UIKitStyles.slot(state),"res://ui_kit/resources/slot_"+state+".res")!=OK:quit(1);return
	for role: String in ["modal","hud"]:
		if ResourceSaver.save(UIKitStyles.surface(role),"res://ui_kit/resources/surface_"+role+".res")!=OK:quit(1);return
	print("UI_KIT_RESOURCES_READY")
	quit()
