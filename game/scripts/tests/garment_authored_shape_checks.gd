extends RefCounted
## Real AnimationPlayer morph evaluation, independent of certificate eligibility.
## This does not qualify source geometry or enable an unsigned actor's bypass.
const GUARD = preload("res://scripts/characters/garment_authored_shape_guard.gd")
const CLIPS: Array[String] = ["idle", "walk", "run"]
var t: Node

func _init(runner: Node) -> void:
	t = runner

func run() -> void:
	for id: String in ["ren", "mio", "kazuko"]:
		var npc: NPC = t.main.npcs[id]
		var support: Node = npc.model.find_child("CharacterGarmentSupport", true, false)
		if support == null:
			t.check("GARMENT_AUTHORED_SHAPES", id + " source support exists", false)
			continue
		var mesh: MeshInstance3D = support.get("mesh") as MeshInstance3D
		var indices: PackedInt32Array = support.get("original_indices")
		var plan: Dictionary = GUARD.prepare(mesh, npc.anim.ap, indices, CLIPS)
		var valid: bool = bool(plan.get("valid", false))
		t.check("GARMENT_AUTHORED_SHAPES", id + " imported morph paths are unambiguous", valid, str(plan.get("error", "")))
		var saved: Dictionary = {"clip": npc.anim.ap.current_animation, "time": npc.anim.ap.current_animation_position, "speed": npc.anim.ap.speed_scale, "state": npc.anim._state, "oneshot": npc.anim._oneshot, "process": npc.is_processing()}
		npc.set_process(false)
		npc.anim._oneshot = ""
		npc.anim.ap.speed_scale = 0.0
		var latest := PackedFloat32Array()
		for clip: String in CLIPS:
			npc.anim._go(clip, 1.0)
			npc.anim._state = clip
			# Finish the real controller's AP blend before comparing a single
			# authored curve. A frozen blend is intentionally ineligible in product.
			npc.anim.ap.advance(.35)
			npc.anim.ap.speed_scale = 0.0
			var mismatches: Array[String] = []
			for phase: float in [0.0, .123, .5, .9375]:
				npc.anim.ap.seek(npc.anim.ap.get_animation(clip).length * phase, true)
				npc.anim.ap.advance(0.0)
				await t.get_tree().process_frame
				latest.clear()
				for shape: int in indices: latest.append(mesh.get_blend_shape_value(shape))
				var reason: String = GUARD.mismatch(plan, clip, npc.anim.ap.current_animation_position, latest)
				if reason != "": mismatches.append("%.5f %s" % [phase, reason])
			t.check("GARMENT_AUTHORED_SHAPES", id + " " + clip + " real AP values match its sampled curve", valid and mismatches.is_empty(), str(mismatches))
		var altered: PackedFloat32Array = latest.duplicate()
		if not altered.is_empty(): altered[0] += .01
		t.check("GARMENT_AUTHORED_SHAPES", id + " external morph edit is rejected", valid and not altered.is_empty() and GUARD.mismatch(plan, "run", npc.anim.ap.current_animation_position, altered) != "")
		var nonfinite: PackedFloat32Array = latest.duplicate()
		if not nonfinite.is_empty(): nonfinite[0] = NAN
		t.check("GARMENT_AUTHORED_SHAPES", id + " nonfinite morph is rejected", valid and not nonfinite.is_empty() and GUARD.mismatch(plan, "run", npc.anim.ap.current_animation_position, nonfinite) != "")
		t.check("GARMENT_AUTHORED_SHAPES", id + " unqualified clip is rejected", valid and GUARD.mismatch(plan, "wave", 0.0, latest) != "")
		npc.anim._state = saved.state
		npc.anim._oneshot = saved.oneshot
		npc.anim.ap.play(str(saved.clip), 0.0)
		npc.anim.ap.seek(float(saved.time), true)
		npc.anim.ap.speed_scale = float(saved.speed)
		npc.set_process(bool(saved.process))
