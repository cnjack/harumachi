"""Measure actual bus aperture, glass, cabin and route-box geometry in Blender.

Blender -b -P art/tools/check_bus_cabin.py -- asset.glb report.json
With --legacy-panes the previous runtime glass positions are audited against
the predecessor mesh; absent authored panes are still reported explicitly.
"""
from pathlib import Path
import hashlib
import json
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
import math

args = sys.argv[sys.argv.index("--")+1:]
source, target = Path(args[0]), Path(args[1])
legacy = "--legacy-panes" in args
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
objects = [o for o in bpy.context.scene.objects if o.type == "MESH"]


def coords(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def bounds(obj):
    verts = coords(obj)
    return Vector([min(v[i] for v in verts) for i in range(3)]), Vector([max(v[i] for v in verts) for i in range(3)])


def godot(p):
    return Vector((p[0], -p[2], p[1]))


opaque_trees = []
for obj in objects:
    if obj.name.startswith("Glass_"):
        continue
    opaque_trees.append((obj.name, BVHTree.FromPolygons(coords(obj), [list(p.vertices) for p in obj.data.polygons])))


def intersect(start, end, names=None):
    ray = end-start
    length = ray.length
    direction = ray.normalized()
    hits = []
    for name, tree in opaque_trees:
        if names and not any(name.startswith(prefix) for prefix in names):
            continue
        co, normal, index, distance = tree.ray_cast(start, direction, length)
        if co is not None:
            hits.append((distance, name, list(co)))
    return sorted(hits)


panes = [o for o in objects if o.name.startswith("Glass_")]
failures = []
checks = []


def check(label, ok, detail=None):
    checks.append({"name": label, "passed": bool(ok), "detail": detail})
    if not ok:
        failures.append(label)


check("authored glazing has front, rear, both sides and articulated door panes", len(panes) >= 12, len(panes))
apertures = []
if legacy:
    for side in [-1, 1]:
        for index, (a, b) in enumerate([(-1.92, -1.22), (-1.12, -.42), (-.32, .44), (1.32, 1.94)]):
            apertures.append((f"legacy_side_{side}_{index}", [godot(p) for p in [(a, 1.13, side*.848), (b, 1.13, side*.848), (b, 1.85, side*.848), (a, 1.85, side*.848)]]))
    apertures.append(("legacy_windscreen", [godot(p) for p in [(2.15, 1.14, -.63), (2.15, 1.14, .63), (2.15, 1.92, .63), (2.15, 1.92, -.63)]]))
else:
    for pane in panes:
        verts = coords(pane)
        # The authored glass is one planar quadrilateral. glTF triangulation
        # may repeat corners, so recover the four physical corners by UV.
        uv = pane.data.uv_layers.active
        corners = {}
        for loop in pane.data.loops:
            u, v = uv.data[loop.index].uv
            corners[(round(u), round(v))] = verts[loop.vertex_index]
        if len(corners) == 4:
            apertures.append((pane.name, [corners[p] for p in [(0, 0), (1, 0), (1, 1), (0, 1)]]))
        else:
            check(pane.name+" has four measurable planar corners", False, list(corners))

blockers = []
for name, corners in apertures:
    a, b, c, d = corners
    normal = (b-a).cross(d-a).normalized()
    centre = sum(corners, Vector())/4
    if normal.dot(Vector((centre.x, centre.y, 0))) < 0:
        normal = -normal
    for u in [.12, .32, .50, .68, .88]:
        for v in [.12, .32, .50, .68, .88]:
            at = a*(1-u)*(1-v)+b*u*(1-v)+c*u*v+d*(1-u)*v
            hits = intersect(at+normal*.055, at-normal*.10)
            # The centre windscreen divider is a real 23mm member, deliberately
            # outside the clear half-pane probes. No broad opaque shard may pass.
            hits = [hit for hit in hits if not hit[1].startswith(("WindscreenCentre", "Wiper"))]
            if hits:
                blockers.append({"pane": name, "uv": [u, v], "hit": hits[0]})
check("window clear areas are free of opaque generated faces", not blockers, blockers[:30])
transparent = []
for pane in panes:
    for mat in pane.data.materials:
        bs = mat.node_tree.nodes.get("Principled BSDF") if mat.use_nodes else None
        if bs is None or bs.inputs["Alpha"].default_value > .35:
            transparent.append(pane.name)
check("all fitted panes carry real low-opacity glass", not transparent and len(panes) >= 12, transparent)

roof = bpy.data.objects.get("RetainedPaintedShell")
housing = bpy.data.objects.get("RouteHousing")
route_face = bpy.data.objects.get("RouteDisplay")
housing_fact = {}
if housing and route_face and roof:
    lo, hi = bounds(housing)
    face_lo, face_hi = bounds(route_face)
    mounts = [o for o in objects if o.name.startswith("RouteRoofMount")]
    mounted = []
    for mount in mounts:
        ml, mh = bounds(mount)
        centre = (ml+mh)/2
        hit = intersect(centre+Vector((0, 0, .2)), centre-Vector((0, 0, .2)), ["RetainedPaintedShell", "Cabin_ceiling"])
        mounted.append(bool(hit))
    housing_fact = {"depth": hi.x-lo.x, "display_gap": face_lo.x-hi.x, "mount_hits": mounted}
    check("route sign has a deep formed housing with roof-contacting mounts", hi.x-lo.x >= .20 and len(mounted) == 2 and all(mounted), housing_fact)
    check("route lettering face is supported by its housing", -.01 <= face_lo.x-hi.x <= .025 and face_hi.z <= hi.z and face_lo.z >= lo.z, housing_fact)
else:
    check("route sign has a deep formed housing with roof-contacting mounts", False, "predecessor uses a detached 18mm runtime board" if legacy else "missing housing")
    check("route lettering face is supported by its housing", False, "no physical backing")
seat_backs = [o for o in objects if o.name.startswith("SeatBack_")]
seat_facts = []
for seat in seat_backs:
    lo, hi = bounds(seat)
    seat_facts.append({"name": seat.name, "max_height": hi.z, "side_clearance": .798-max(abs(lo.y), abs(hi.y))})
check("passenger backs stay below upper windows and clear both glass walls", len(seat_backs) == 6 and all(r["max_height"] < 1.45 and r["side_clearance"] > .10 for r in seat_facts), seat_facts)
wheel_facts = []
for index in range(4):
    obj = bpy.data.objects.get(f"Wheel_{index}")
    wheel_facts.append(bounds(obj)[0].z if obj else None)
check("all four original articulated tyres contact the ground", all(v is not None and abs(v) < .001 for v in wheel_facts), wheel_facts)
doors = [bpy.data.objects.get(f"DoorLeaf_{i}") for i in range(2)]
check("both moving door leaves contain their own window and rails", all(d and any(c.name.startswith("Glass_Door_") for c in d.children) for d in doors))

arch_errors = []
arch_contact_errors = []
arch_samples = 0
body_tree = next((tree for name, tree in opaque_trees if name.startswith("RetainedPaintedShell")), None)
for arch_index in range(4):
    arch = next((obj for obj in objects if obj.name == f"WheelArch_{arch_index}"), None)
    wheel = next((obj for obj in objects if obj.name == f"Wheel_{arch_index}"), None)
    axle = [-1.063, 1.677][arch_index//2]
    axle_z = wheel.matrix_world.translation.z if wheel else [.325,.320][arch_index//2]
    side = -1 if arch_index%2 == 0 else 1
    end_angle = 175
    if arch is None:
        arch_errors.append(f"wheel {arch_index}: no physical rolled arch")
        arch_contact_errors.append(f"wheel {arch_index}: no inspectable body joint")
        continue
    arch_coords = coords(arch)
    arch_tree = BVHTree.FromPolygons(arch_coords, [list(p.vertices) for p in arch.data.polygons])
    manifold = bmesh.new(); manifold.from_mesh(arch.data)
    bmesh.ops.remove_doubles(manifold, verts=list(manifold.verts), dist=.000001)
    boundaries = sum(len(edge.link_faces) != 2 for edge in manifold.edges)
    manifold.free()
    if boundaries:
        arch_errors.append(f"wheel {arch_index}: {boundaries} unclosed sheet edges")
    for degree in np.linspace(7, end_angle-2, 63):
        angle = math.radians(float(degree))
        origin = Vector((axle+.397*math.cos(angle), side*1.15, axle_z+.397*math.sin(angle)))
        at, normal, poly, distance = arch_tree.ray_cast(origin, Vector((0, -side, 0)), .55)
        arch_samples += 1
        if at is None:
            arch_errors.append(f"wheel {arch_index}: rolled arch gap at {degree:.1f} degrees")
    outer = [v for v in arch_coords if abs(math.hypot(v.x-axle, v.z-axle_z)-.414) < .0002]
    if not outer:
        arch_contact_errors.append(f"wheel {arch_index}: no narrow outer flange")
    for vertex in outer:
        nearest = body_tree.find_nearest(vertex, .014) if body_tree else None
        if not nearest or nearest[0] is None:
            arch_contact_errors.append({"wheel": arch_index, "floating_outer_edge": list(vertex)})
check("all four wheel arches are closed solid continuous rolled edges", not arch_errors, {"samples": arch_samples, "errors": arch_errors[:30]})
check("narrow arch flanges meet the real painted body within 14mm", not arch_contact_errors, arch_contact_errors[:30])
sheet_gaps = []
sheet_samples = 0
for arch_index in range(4):
    wheel = next((obj for obj in objects if obj.name == f"Wheel_{arch_index}"), None)
    axle = [-1.063, 1.677][arch_index//2]
    axle_z = wheel.matrix_world.translation.z if wheel else [.325,.320][arch_index//2]
    side = -1 if arch_index%2 == 0 else 1
    for degree in np.linspace(35,145,57):
        angle = math.radians(float(degree))
        for radius in [.42,.45,.48,.51,.54]:
            x,z=axle+radius*math.cos(angle),axle_z+radius*math.sin(angle)
            if arch_index==2 and x<1.22:continue
            sheet_samples+=1
            hit=body_tree.ray_cast(Vector((x,side*1.15,z)),Vector((0,-side,0)),.55)[0] if body_tree else None
            if hit is None:sheet_gaps.append({'wheel':arch_index,'angle':float(degree),'radius':radius})
check("painted sheet above every arch is continuous beyond the narrow trim",not sheet_gaps,{'samples':sheet_samples,'gaps':sheet_gaps[:30]})

texture_pixels = {}
wheel_green = []
for wheel_index in range(4):
    wheel_obj = next((obj for obj in objects if obj.name == f"Wheel_{wheel_index}"), None)
    if wheel_obj is None:
        wheel_green.append({"wheel": wheel_index, "error": "missing tyre"}); continue
    uv = wheel_obj.data.uv_layers.active
    green_count = 0
    for polygon in wheel_obj.data.polygons:
        mat = wheel_obj.data.materials[polygon.material_index]
        image = next((node.image for node in mat.node_tree.nodes if node.type == "TEX_IMAGE" and node.image), None)
        if image is None or uv is None:
            continue
        if image.name not in texture_pixels:
            width, height = image.size
            pixels = np.empty(width*height*4, dtype=np.float32)
            image.pixels.foreach_get(pixels)
            texture_pixels[image.name] = pixels.reshape(height, width, 4)
        pixels = texture_pixels[image.name]
        tex_uv = sum((uv.data[i].uv for i in polygon.loop_indices), Vector((0, 0)))/len(polygon.loop_indices)
        red, green, blue = pixels[int((tex_uv.y%1)*pixels.shape[0]), int((tex_uv.x%1)*pixels.shape[1]), :3]
        if green > red*1.13 and green > blue*1.10 and green > .15:
            green_count += 1
    wheel_green.append({"wheel": wheel_index, "green_body_faces": green_count, "faces": len(wheel_obj.data.polygons)})
check("moving tyres do not carry misassigned green body fragments", len(wheel_green) == 4 and all("error" not in row and row["green_body_faces"] <= max(12, row["faces"]*.002) for row in wheel_green), wheel_green)

# A window check must not be satisfied by cutting away the opaque body below
# it. Match dense front/rear/skirt ray profiles to the retained predecessor.
# Comparing actual intersection positions (5mm tolerance), rather than only
# accepting any opaque hit, also rejects a new flat cap over missing detail.
root = Path(__file__).resolve().parents[2]
predecessor = root / "art/library/vehicles/source/B01_painted_predecessor.glb"
before_import = set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath=str(predecessor))
imported_reference = [o for o in bpy.context.scene.objects if o not in before_import and o.type == "MESH"]
reference_objects = [o for o in imported_reference if o.name.startswith(("GeneratedBody", "Wheel_"))]
reference_trees = [(o.name, BVHTree.FromPolygons(coords(o), [list(p.vertices) for p in o.data.polygons])) for o in reference_objects]


def first_hit(trees, start, end):
    direction = (end-start).normalized()
    hits = []
    for label, tree in trees:
        co, normal, face, distance = tree.ray_cast(start, direction, (end-start).length)
        if co is not None:
            hits.append((distance, label, co))
    return min(hits, key=lambda hit: hit[0]) if hits else None


retained_trees = [(name, tree) for name, tree in opaque_trees if name.startswith(("RetainedPaintedShell", "GeneratedBody"))]
shell_profiles = {}
for end_name, direction in [("front", 1), ("rear", -1)]:
    shell_profiles[end_name] = [(Vector((direction*2.65, lateral, height)), Vector((direction*1.80, lateral, height)))
                               for height in [.60, .68, .76, .84, .92, 1.00, 1.075]
                               for lateral in [-.68, -.54, -.40, -.26, -.12, 0, .12, .26, .40, .54, .68]]
shell_profiles["skirts"] = [(Vector((longitudinal, side*1.15, height)), Vector((longitudinal, side*.61, height)))
                            for side in [-1, 1]
                            for longitudinal in np.arange(-2.08,2.081,.13)
                            for height in [.40, .55, .70, .85, 1.02]]
shell_results = {}
for region, rays in shell_profiles.items():
    errors = []
    count = 0
    maximum_error = 0.0
    for start, end in rays:
        # The previous sparse side grid mistakenly treated tyre surfaces left
        # in GeneratedBody as painted sheet. Measure the complete source and
        # omit only the real wheel apertures and the authored door opening.
        if region=="skirts":
            if any(math.hypot(start.x-x,start.z-z)<.389 for x,z in [(-1.063,.325),(1.677,.320)]):continue
            if start.y<0 and .61<start.x<1.20 and start.z>.32:continue
        reference_hit = first_hit(reference_trees, start, end)
        if reference_hit is None:
            continue
        count += 1
        retained_hit = first_hit(retained_trees, start, end)
        if retained_hit is None:
            errors.append({"origin": list(start), "expected": list(reference_hit[2]), "actual": None})
        else:
            error = (reference_hit[2]-retained_hit[2]).length
            maximum_error = max(maximum_error, error)
            if error > .005:
                errors.append({"origin": list(start), "expected": list(reference_hit[2]), "actual": list(retained_hit[2]), "error_m": error})
    shell_results[region] = {"reference_hits": count, "missing_or_changed_hits": len(errors), "maximum_error_m": maximum_error, "errors": errors[:20]}
    check(f"retained opaque {region} preserves the original curved painted shell", count >= 30 and not errors, shell_results[region])

tyre_changes = []
reference_points=[];reference_faces=[]
for obj in reference_objects:
    base=len(reference_points);reference_points.extend(coords(obj));reference_faces.extend([[base+i for i in face.vertices] for face in obj.data.polygons])
complete_source_tree=BVHTree.FromPolygons(reference_points,reference_faces)
axle_errors=[];circle_errors=[];static_tyres=[];arch_axis_errors=[];tyre_samples=0
for tyre_index in range(4):
    tyre=next((obj for obj in objects if obj.name==f"Wheel_{tyre_index}"),None)
    if tyre is None:tyre_changes.append(f"tyre {tyre_index}: missing complete wheel");continue
    expected_x,source_z=[(-1.063,.325),(1.677,.320)][tyre_index//2]
    pivot=tyre.matrix_world.translation;side=-1 if tyre_index%2==0 else 1
    ground_offset=source_z-pivot.z
    largest_delta=max(complete_source_tree.find_nearest(vertex+Vector((0,0,ground_offset)))[3] for vertex in coords(tyre))
    if largest_delta>.00003:tyre_changes.append({"wheel":tyre_index,"changed_source_surface_m":largest_delta})
    rim_sum=Vector();rim_area=0.0
    uv=tyre.data.uv_layers.active
    for face in tyre.data.polygons:
        centre=tyre.matrix_world@face.center
        if math.hypot(centre.x-expected_x,centre.z-pivot.z)>.245:continue
        material=tyre.data.materials[face.material_index]
        picture=next((n.image for n in material.node_tree.nodes if n.type=="TEX_IMAGE" and n.image),None)
        if picture is None or uv is None:continue
        if picture.name not in texture_pixels:
            w,h=picture.size;pixels=np.empty(w*h*4,dtype=np.float32);picture.pixels.foreach_get(pixels);texture_pixels[picture.name]=pixels.reshape(h,w,4)
        pixels=texture_pixels[picture.name];tex_uv=sum((uv.data[i].uv for i in face.loop_indices),Vector((0,0)))/len(face.loop_indices)
        rgb=pixels[int((tex_uv.y%1)*pixels.shape[0]),int((tex_uv.x%1)*pixels.shape[1]),:3]
        if rgb.max()>.5 and rgb.max()-rgb.min()<.15:
            area=face.area*max(.1,abs((tyre.matrix_world.to_3x3()@face.normal).y));rim_sum+=centre*area;rim_area+=area
    rim=rim_sum/rim_area if rim_area else Vector((999,0,999))
    if abs(pivot.x-expected_x)>.015 or math.hypot(rim.x-pivot.x,rim.z-pivot.z)>.015:
        axle_errors.append({"wheel":tyre_index,"pivot":list(pivot),"actual_complete_rim_centre":list(rim),"expected_source_x":expected_x})
    tyre_tree=BVHTree.FromPolygons(coords(tyre),[list(face.vertices) for face in tyre.data.polygons])
    for degrees in np.arange(0,360,5):
        angle=math.radians(float(degrees))
        for radius in [.27,.30]:
            # The retained front tyre has its original slightly oval profile.
            # Use the measured source outline, without stretching it to a circle.
            radius_x=radius if tyre_index<2 else radius*(.25/.30)
            origin=Vector((expected_x+radius_x*math.cos(angle),side*1.15,pivot.z+radius*math.sin(angle)))
            tyre_samples+=1
            if tyre_tree.ray_cast(origin,Vector((0,-side,0)),.55)[0] is None:circle_errors.append({"wheel":tyre_index,"angle":float(degrees),"radius":radius})
        for radius in [.10,.20,.29]:
            origin=Vector((expected_x+radius*math.cos(angle),side*1.15,pivot.z+radius*math.sin(angle)))
            if body_tree and body_tree.ray_cast(origin,Vector((0,-side,0)),.54)[0] is not None:static_tyres.append({"wheel":tyre_index,"angle":float(degrees),"radius":radius})
    arch=next((obj for obj in objects if obj.name==f"WheelArch_{tyre_index}"),None)
    if arch:
        lo,hi=bounds(arch);actual_axis=Vector(((lo.x+hi.x)*.5,0,hi.z-.414))
        if math.hypot(actual_axis.x-rim.x,actual_axis.z-rim.z)>.015:arch_axis_errors.append({"wheel":tyre_index,"arch_axis":list(actual_axis),"rim_centre":list(rim)})
    else:arch_axis_errors.append({"wheel":tyre_index,"missing_arch":True})
check("repartitioned tyres preserve actual complete-source surface geometry",not tyre_changes,tyre_changes[:20])
check("four wheel pivots coincide with the actual complete neutral rim centres",not axle_errors,axle_errors)
check("each complete tyre covers its full 360 degree circumference",not circle_errors,{"samples":tyre_samples,"missing":circle_errors[:30]})
check("static painted body contains no retained tyre or hub surfaces",not static_tyres,{"residual_hits":len(static_tyres),"examples":static_tyres[:30]})
check("physical wheel arches coincide with actual rim centres",not arch_axis_errors,arch_axis_errors)
result = {"asset": str(source), "passed": not failures, "checks": checks, "failed": failures,
          "sampled_apertures": len(apertures), "native_visual_review_required": True,
          "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "shell_profiles": shell_results}
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
print(json.dumps({"passed": result["passed"], "failed": failures, "checks": len(checks), "blocker_count": len(blockers)}, ensure_ascii=False))
