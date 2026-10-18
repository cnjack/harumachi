extends RefCounted
## Content identity for the exact imported model covered by a garment proof.
## Resource RIDs, import cache paths and exported raw GLB availability are not
## identities. Compute once at preparation, never in the deformation loop.
const VERSION := 2

static func fingerprint(mesh: MeshInstance3D, skeleton: Skeleton3D, animation: AnimationPlayer, model: Node3D, asset_root_transform: Transform3D, clips: Array[String] = ["idle", "walk", "run"], extra_identity: String = "") -> String:
	if mesh == null or skeleton == null or animation == null or model == null or not mesh.mesh is ArrayMesh or mesh.skin == null: return ""
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK: return ""
	hash.update(var_to_bytes(VERSION))
	if not extra_identity.is_empty(): hash.update(var_to_bytes(extra_identity))
	# Include asset-local carrier transforms, excluding the actor/world yaw.
	# A changed internal mesh/skeleton offset must invalidate the certificate.
	for carrier: Node3D in [mesh, skeleton]:
		var chain: Node = carrier
		while chain != model:
			if chain == null: return ""
			hash.update(var_to_bytes(String(chain.name)))
			if chain is Node3D: hash.update(var_to_bytes((chain as Node3D).transform))
			chain = chain.get_parent()
	hash.update(var_to_bytes(asset_root_transform))
	var geometry: ArrayMesh = mesh.mesh as ArrayMesh
	hash.update(var_to_bytes(geometry.blend_shape_mode))
	for shape: int in geometry.get_blend_shape_count(): hash.update(var_to_bytes(String(geometry.get_blend_shape_name(shape))))
	for surface: int in geometry.get_surface_count():
		hash.update(var_to_bytes(geometry.surface_get_primitive_type(surface)))
		var arrays: Array = geometry.surface_get_arrays(surface)
		for array: Variant in arrays: hash.update(var_to_bytes(array))
		var shapes: Array = geometry.surface_get_blend_shape_arrays(surface)
		for shape_arrays: Array in shapes:
			for array: Variant in shape_arrays: hash.update(var_to_bytes(array))
	for bind: int in mesh.skin.get_bind_count():
		hash.update(var_to_bytes(mesh.skin.get_bind_bone(bind)))
		hash.update(var_to_bytes(String(mesh.skin.get_bind_name(bind))))
		hash.update(var_to_bytes(mesh.skin.get_bind_pose(bind)))
	for bone: int in skeleton.get_bone_count():
		hash.update(var_to_bytes(skeleton.get_bone_name(bone)))
		hash.update(var_to_bytes(skeleton.get_bone_parent(bone)))
		hash.update(var_to_bytes(skeleton.get_bone_rest(bone)))
	for clip: String in clips:
		if not animation.has_animation(clip): return ""
		var resource: Animation = animation.get_animation(clip)
		hash.update(var_to_bytes(clip))
		hash.update(var_to_bytes(resource.length))
		hash.update(var_to_bytes(resource.loop_mode))
		for track: int in resource.get_track_count():
			hash.update(var_to_bytes(resource.track_get_type(track)))
			hash.update(var_to_bytes(resource.track_is_enabled(track)))
			hash.update(var_to_bytes(resource.track_get_path(track)))
			hash.update(var_to_bytes(resource.track_get_interpolation_type(track)))
			hash.update(var_to_bytes(resource.track_get_interpolation_loop_wrap(track)))
			for key: int in resource.track_get_key_count(track):
				hash.update(var_to_bytes(resource.track_get_key_time(track, key)))
				hash.update(var_to_bytes(resource.track_get_key_value(track, key)))
				hash.update(var_to_bytes(resource.track_get_key_transition(track, key)))
	return hash.finish().hex_encode()
