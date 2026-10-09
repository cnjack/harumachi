extends SceneTree
## Export the runtime nine-slice textures and icons; original generated PNGs stay unchanged.
func _initialize() -> void:call_deferred("build")
func build() -> void:
	var folder: String=""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):folder=argument.substr(6)
	if folder.is_empty():quit(1);return
	DirAccess.make_dir_recursive_absolute(folder)
	for id: String in ["primary_normal","primary_hover","primary_pressed","primary_disabled","secondary_normal","secondary_hover","secondary_pressed","secondary_disabled","slot_empty","slot_selected","notice_info","notice_warning","progress_track","progress_fill"]:
		if UIKitAssets.render_texture(id,128).get_image().save_png(folder.path_join(id+".png"))!=OK:quit(1);return
	for id: String in ["modal_paper","hud_paper"]:
		if UIKitAssets.render_texture(id,384 if id=="modal_paper" else 256).get_image().save_png(folder.path_join(id+".png"))!=OK:quit(1);return
	for id: String in ["home","map","w_festival","book","backpack","coin","calendar","settings","close","check","gift","fish","florist","w_sunny"]:
		var source: Image=UIKitAssets.icon(id).get_image()
		if source.is_compressed():source.decompress()
		var height: int=roundi(64*source.get_height()/float(source.get_width()));source.resize(64,height,Image.INTERPOLATE_LANCZOS)
		if source.save_png(folder.path_join("icon_"+id+".png"))!=OK:quit(1);return
	print("WEB_SKINS_READY");quit()
