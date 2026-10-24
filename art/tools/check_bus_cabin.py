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
formed_finish=any(m.name=='Bus_body_paint'for o in objects for m in o.data.materials)
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
            tolerance=.005
            radiator_cavity=region=='front' and .580<start.z<.867 and abs(start.y)<.565 and formed_finish
            if radiator_cavity:
                if not 2.12<=retained_hit[2].x<=2.255:errors.append({'origin':list(start),'invalid_radiator_backing':list(retained_hit[2])})
                continue
            if region=='front' and formed_finish and min(math.hypot(start.y-side*.684,start.z-.724)for side in [-1,1])<.122:
                if not 2.18<=retained_hit[2].x<=2.255:errors.append({'origin':list(start),'invalid_headlamp_well':list(retained_hit[2])})
                continue
            if region=='front' and formed_finish and start.z>1.015:
                if not 2.120<=retained_hit[2].x<=2.255:errors.append({'origin':list(start),'invalid_front_sill_joint':list(retained_hit[2])})
                continue
            if region=='rear' and formed_finish and abs(start.y)<.10 and .97<start.z<1.02:
                tolerance=.020 # Local source paint lump removed by the continuous crowned rear panel.
            if region=='skirts' and formed_finish:
                # The source contains broken inward faces, simulated tail-lamp
                # lumps and random dimples. Preserve its broad curved envelope
                # using a local median, not the defect at one ray. Opaque skin,
                # smoothness, physical lamps and window joints are tested below.
                neighbours=[]
                for dx in [-.050,-.025,0,.025,.050]:
                    for dz in [-.036,-.018,0,.018,.036]:
                        delta=Vector((dx,0,dz));ref=first_hit(reference_trees,start+delta,end+delta)
                        if ref:neighbours.append(abs(ref[2].y))
                expected=float(np.median(neighbours));actual=abs(retained_hit[2].y)
                # Rounded rear lamp corners are now a fitted separate housing;
                # their backing must still stay inside the measured body width.
                if start.y<0 and 1.22<start.x<1.46 and start.z>.92:
                    if not .81<=actual<=.88:errors.append({'origin':list(start),'invalid_backed_intake':actual})
                elif start.y<0 and 1.24<start.x<1.50 and .60<start.z<.92:
                    # The old front-quarter crease dragged its green panel
                    # inward by 21mm below the intake; the continuous panel is
                    # now fair with the rest of the side, and checked for dents.
                    if abs(actual-expected)>.025:errors.append({'origin':list(start),'front_quarter_envelope':expected,'actual':actual})
                elif start.x<-2.0 and .65<start.z<.95:
                    if not .76<=actual<=.90:errors.append({'origin':list(start),'rear_lamp_backing_outside_body':actual})
                elif abs(actual-expected)>.020:
                    errors.append({'origin':list(start),'median_source_envelope':expected,'actual':actual,'error_m':abs(actual-expected)})
                continue
            if error > tolerance:
                errors.append({"origin": list(start), "expected": list(reference_hit[2]), "actual": list(retained_hit[2]), "error_m": error})
    shell_results[region] = {"reference_hits": count, "missing_or_changed_hits": len(errors), "maximum_error_m": maximum_error, "errors": errors[:20]}
    check(f"opaque {region} preserves body envelope and required backing", count >= 30 and not errors, shell_results[region])

tyre_changes = []
shape_reference=json.loads((root / "art/library/vehicles/source/B01_bus_shape_reference.json").read_text())
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
    formed=any(m.name=='Bus_tyre_rubber'for m in tyre.data.materials)
    if formed:
        reference=shape_reference['wheels'][tyre_index];lo,hi=bounds(tyre)
        error=max(abs(actual[i]-expected[i])for actual,expected in zip([lo,hi],reference['casing_bounds'])for i in range(3))
        axis_error=(pivot-Vector(reference['axis'])).length
        if error>.001 or axis_error>.0001:tyre_changes.append({'wheel':tyre_index,'original_casing_bounds_error_m':error,'axis_error_m':axis_error})
    elif largest_delta>.00003:tyre_changes.append({"wheel":tyre_index,"changed_source_surface_m":largest_delta})
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
    hub=next((o for o in objects if o.name==f'HubFinish_{tyre_index}'),None)
    if formed and hub:
        lo,hi=bounds(hub);rim=(lo+hi)*.5
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
check("tyres preserve measured complete-source axes casing dimensions and ground support",not tyre_changes,tyre_changes[:20])
check("four wheel pivots coincide with the actual complete neutral rim centres",not axle_errors,axle_errors)
check("each complete tyre covers its full 360 degree circumference",not circle_errors,{"samples":tyre_samples,"missing":circle_errors[:30]})
check("static painted body contains no retained tyre or hub surfaces",not static_tyres,{"residual_hits":len(static_tyres),"examples":static_tyres[:30]})
check("physical wheel arches coincide with actual rim centres",not arch_axis_errors,arch_axis_errors)

if "--finish" in args:
    finish_materials={mat.name:mat for obj in objects for mat in obj.data.materials}
    expected={"Bus_body_paint_atlas":(.42,0),"Bus_tyre_rubber":(.92,0),
              "Bus_stamped_wheel_steel":(.36,.62),"Bus_satin_hardware":(.32,.68),
              "Bus_lamp_reflector":(.29,.65),"Bus_headlamp_optic":(.23,0),
              "Bus_detail_rubber":(.92,0),"Bus_fitted_clear_glass":(.24,0)}
    finish_errors=[]
    for name,(roughness,metallic) in expected.items():
        mat=finish_materials.get(name);bs=mat.node_tree.nodes.get("Principled BSDF") if mat else None
        if not bs or abs(bs.inputs['Roughness'].default_value-roughness)>.015 or abs(bs.inputs['Metallic'].default_value-metallic)>.015:finish_errors.append(name)
    check("vehicle paint rubber metal and optics retain distinct source responses",not finish_errors,finish_errors)
    tyre_finish=[]
    for index in range(4):
        wheel=next((o for o in objects if o.name==f'Wheel_{index}'),None)
        used={wheel.data.materials[f.material_index].name for f in wheel.data.polygons} if wheel else set()
        hub=next((o for o in objects if o.name==f'HubFinish_{index}'),None)
        hub_mats={m.name for m in hub.data.materials}if hub else set()
        if used!={'Bus_tyre_rubber'} or not {'Bus_stamped_wheel_steel','Bus_satin_hardware'}.issubset(hub_mats):tyre_finish.append({'wheel':index,'used':sorted(used),'hub':sorted(hub_mats)})
    check("continuous tyre casing distinguishes clean rubber from formed metal hub",not tyre_finish,tyre_finish)
    hub_errors=[];hub_samples=0
    for index in range(4):
        wheel=next((o for o in objects if o.name==f'Wheel_{index}'),None);hub=next((o for o in objects if o.name==f'HubFinish_{index}'),None)
        if not hub or hub.parent!=wheel:hub_errors.append({'wheel':index,'missing_or_wrong_parent':True});continue
        pivot=wheel.matrix_world.translation;side=-1 if index%2==0 else 1
        tree=BVHTree.FromPolygons(coords(hub),[list(f.vertices)for f in hub.data.polygons])
        for sector in range(6):
            depths=[]
            for radius,degrees in [(.135,sector*60+30),(.135,sector*60),(.087,sector*60)]:
                angle=math.radians(degrees);origin=Vector((pivot.x+radius*math.cos(angle),side*1.15,pivot.z+radius*math.sin(angle)))
                hit=tree.ray_cast(origin,Vector((0,-side,0)),.4)[0];depths.append(abs(hit.y) if hit is not None else None);hub_samples+=1
            if any(v is None for v in depths) or depths[1]-depths[0]<.008 or depths[2]-depths[1]<.010:hub_errors.append({'wheel':index,'sector':sector,'surface_depths':depths})
        if max(math.hypot(v.x-pivot.x,v.z-pivot.z)for v in coords(hub))>.214:hub_errors.append({'wheel':index,'rim_exceeds_original_tyre':True})
    check("four moving hubs have real recessed vents rolled rims and raised lugs",not hub_errors,{'rays':hub_samples,'errors':hub_errors})
    bead_errors=[];bead_samples=0
    for index in range(4):
        wheel=next((o for o in objects if o.name==f'Wheel_{index}'),None);hub=next((o for o in objects if o.name==f'HubFinish_{index}'),None)
        if not wheel or not hub:bead_errors.append({'wheel':index,'missing':True});continue
        pivot=wheel.matrix_world.translation;tree=BVHTree.FromPolygons(coords(wheel),[list(f.vertices)for f in wheel.data.polygons])
        for v in coords(hub):
            if math.hypot(v.x-pivot.x,v.z-pivot.z)<.193:continue
            bead_samples+=1
            if tree.find_nearest(v,.008)[0] is None:bead_errors.append({'wheel':index,'unsupported_rim_point':list(v)})
    check("metal rims seat in actual measured rubber beads rather than floating",not bead_errors,{'samples':bead_samples,'errors':bead_errors[:12]})
    head=next((o for o in objects if o.name=='HeadlampFinish'),None);head_errors=[]
    if not head:head_errors.append('no formed optics')
    else:
        tree=BVHTree.FromPolygons(coords(head),[list(f.vertices)for f in head.data.polygons])
        for side in [-1,1]:
            profile=[]
            for radius in [0,.045,.080,.107]:
                hit=tree.ray_cast(Vector((2.6,side*.684+radius,.724)),Vector((-1,0,0)),.6)[0];profile.append(hit.x if hit is not None else None)
            if any(x is None for x in profile) or max(profile)-min(profile)<.006:head_errors.append({'side':side,'profile':profile})
        if not {'Bus_lamp_reflector','Bus_headlamp_optic'}.issubset({m.name for m in head.data.materials}):head_errors.append('single undifferentiated lens surface')
    check("both headlights have shaped optical faces and inset reflector depth",not head_errors,head_errors)
    lens_errors=[]
    if not head:lens_errors.append('no optical assembly')
    else:
        lens_faces=[list(f.vertices)for f in head.data.polygons if head.data.materials[f.material_index].name=='Bus_headlamp_optic']
        lens_tree=BVHTree.FromPolygons(coords(head),lens_faces)if lens_faces else None
        lens_mat=next((m for m in head.data.materials if m.name=='Bus_headlamp_optic'),None)
        alpha=lens_mat.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value if lens_mat else 1
        if not .10<=alpha<=.24:lens_errors.append({'lens_opacity':alpha})
        for side in [-1,1]:
            for dy,dz in [(0,0),(.035,0),(-.060,0),(0,.080),(0,-.045)]:
                ray=Vector((2.6,side*.684+dy,.724+dz));hits=[]
                for step in range(3):
                    hit=lens_tree.ray_cast(ray,Vector((-1,0,0)),.45)[0]if lens_tree else None
                    if hit is None:break
                    hits.append(hit.x);ray=hit-Vector((.0001,0,0))
                if len(hits)!=1:lens_errors.append({'side':side,'ray':[dy,dz],'transparent_surfaces':len(hits)})
            reflect=[head.matrix_world@head.data.vertices[i].co for f in head.data.polygons if head.data.materials[f.material_index].name=='Bus_lamp_reflector' and f.center.y*side>0 for i in f.vertices]
            if not reflect or not .028<=max(v.x for v in reflect)-min(v.x for v in reflect)<=.055:lens_errors.append({'side':side,'shallow_or_missing_bowl':True})
        if not any(m.name=='Bus_headlamp_bulb'for m in head.data.materials):lens_errors.append('no readable internal bulb')
    check('headlights have one transparent lens per lamp and readable deep bowls and bulbs',not lens_errors,lens_errors)
    lamp_mount=next((o for o in objects if o.name=='BusExteriorRubber'),None);lamp_mount_errors=[];lamp_mount_samples=[]
    for side in [-1,1]:
        supported=[]
        if lamp_mount:
            for v in coords(lamp_mount):
                if v.x<2 or abs(math.hypot(v.y-side*.684,v.z-.724)-.135)>.0002:continue
                if body_tree and body_tree.find_nearest(v,.004)[0] is not None:supported.append(v)
        lamp_mount_samples.append(len(supported))
        if len(supported)<44:lamp_mount_errors.append({'side':side,'supported_outer_ring_points':len(supported),'required':44})
    check('headlamp housing rear rims follow and touch the curved painted nose',not lamp_mount_errors,{'supported_ring_points':lamp_mount_samples,'errors':lamp_mount_errors})
    rear=next((o for o in objects if o.name=='RearLampFinish'),None);rear_errors=[];colours={}
    if not rear:rear_errors.append('no wrapped rear optics')
    else:
        for f in rear.data.polygons:
            c=rear.matrix_world@f.center
            if c.x<-2.0:colours.setdefault(rear.data.materials[f.material_index].name,[]).append(list(c))
        for name in ['Bus_red_optic','Bus_amber_optic','Bus_reverse_optic']:
            pts=colours.get(name,[])
            if len(pts)<10 or max(p[1]for p in pts)-min(p[1]for p in pts)<1.65:rear_errors.append(name)
        if not rear_errors:
            means={n:sum(p[2]for p in pts)/len(pts)for n,pts in colours.items()}
            if not means['Bus_red_optic']>means['Bus_amber_optic']>means['Bus_reverse_optic']:rear_errors.append(means)
    check("rear corner lamps have curved red amber and reverse sections",not rear_errors,{'materials':sorted(colours),'errors':rear_errors})
    tail_mount=next((o for o in objects if o.name=='BusExteriorRubber'),None);tail_errors=[];tail_samples=0
    if not tail_mount:tail_errors.append('no fitted tail-lamp housing')
    else:
        for v in coords(tail_mount):
            if v.x>-2.0 or not .65<v.z<.95:continue
            tail_samples+=1
            if body_tree.find_nearest(v,.020)[0] is None:tail_errors.append(list(v))
        if tail_samples<100:tail_errors.append('no curved tail contact coverage')
    check("rear lamp housings follow real body corners with physical contact",not tail_errors,{'samples':tail_samples,'errors':tail_errors[:12]})
    hardware_errors=[]
    for index,hinge in enumerate([.613,1.197]):
        hardware=next((o for o in objects if o.name==f'DoorHardware_{index}'),None);leaf=bpy.data.objects.get(f'DoorLeaf_{index}')
        if not hardware or hardware.parent!=leaf:hardware_errors.append({'door':index,'missing_or_static':True});continue
        tree=BVHTree.FromPolygons(coords(hardware),[list(f.vertices)for f in hardware.data.polygons])
        for height in [.48,1.025]:
            if tree.ray_cast(Vector((hinge,-1.1,height)),Vector((0,1,0)),.35)[0] is None:hardware_errors.append({'door':index,'hinge_height':height})
        lo,hi=bounds(hardware)
        if hi.z-lo.z<.65 or hi.y-lo.y<.02:hardware_errors.append({'door':index,'flat_or_incomplete_hardware':True})
    check("door hinges handle feet and latch fittings follow both moving leaves",not hardware_errors,hardware_errors)
    trim=next((o for o in objects if o.name=='BusExteriorMetal'),None);trim_errors=[];trim_samples=0
    if not trim:trim_errors.append('no pressed body moulding')
    else:
        for vertex in coords(trim):
            if abs(vertex.x)>1.9 or not 1.04<vertex.z<1.065:continue
            trim_samples+=1;nearest=body_tree.find_nearest(vertex,.018)
            if nearest[0] is None:trim_errors.append(list(vertex))
        if trim_samples<160:trim_errors.append('insufficient curved side coverage')
    check("narrow pressed body strips follow real shell corners without floating",not trim_errors,{'samples':trim_samples,'errors':trim_errors[:10]})
    body=next((o for o in objects if o.name=="RetainedPaintedShell"),None)
    coating_errors=[];coated_faces=0;seam_faces=0
    for name in ['Bus_body_paint','Bus_tyre_rubber']:
        material=bpy.data.materials.get(name)
        if not material or material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].is_linked:coating_errors.append(name+' retains noisy source colour or is missing')
    if body:
        for face in body.data.polygons:
            name=body.data.materials[face.material_index].name
            if name=='Bus_body_paint':coated_faces+=1
            if name not in ['Bus_body_paint','Cabin_ivory_enamel']:continue
            verts=[body.matrix_world@body.data.vertices[i].co for i in face.vertices]
            if not all(.9<v.z<1.11 for v in verts):continue
            if not all(abs(v.y)>.70 or abs(v.x)>1.78 for v in verts):continue
            if any(v.x>2.025 and abs(v.y)>.80 and v.z<.80 for v in verts):continue
            signs=[]
            for v in verts:
                boundary=1.055 if v.x<=1.95 else (.985 if v.x>=2.15 else 1.055-.35*(v.x-1.95))
                signs.append(v.z-boundary)
            seam_faces+=1
            if min(signs)<-.0001 and max(signs)>.0001:coating_errors.append({'face':face.index,'crosses_paint_join_m':[min(signs),max(signs)]})
    if coated_faces<2000 or seam_faces<500:coating_errors.append({'missing_clean_panel_coverage':coated_faces,'seam_faces':seam_faces})
    check("paint join is physically split and paint rubber omit baked black seam atlas",not coating_errors,{'coated_faces':coated_faces,'seam_faces':seam_faces,'errors':coating_errors[:10]})
    radiator_errors=[];radiator_samples=0
    grille=next((o for o in objects if o.name=='BusExteriorMetal'),None)
    if grille:
        grille_tree=BVHTree.FromPolygons(coords(grille),[list(f.vertices)for f in grille.data.polygons])
        for z in [.635,.680,.725,.770,.815]:
            for y in [-.40,0,.40]:
                start=Vector((2.6,y,z));front=grille_tree.ray_cast(start,Vector((-1,0,0)),.5)[0];back=body_tree.ray_cast(start,Vector((-1,0,0)),.5)[0];radiator_samples+=1
                if front is None or back is None or not .060<front.x-back.x<.125:radiator_errors.append({'y':y,'z':z,'front':list(front)if front is not None else None,'back':list(back)if back is not None else None})
    else:radiator_errors.append('no framed radiator grille')
    check("formed radiator has five supported vanes and an opaque recessed cavity",not radiator_errors,{'samples':radiator_samples,'errors':radiator_errors})
    casing_errors=[]
    for index in range(4):
        wheel=next((o for o in objects if o.name==f'Wheel_{index}'),None)
        if not wheel:casing_errors.append({'wheel':index,'missing':True});continue
        bm=bmesh.new();bm.from_mesh(wheel.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
        broken=sum(len(e.link_faces)!=2 for e in bm.edges);bm.free()
        if broken:casing_errors.append({'wheel':index,'open_or_nonmanifold_edges':broken})
    check("all four formed rubber casings are closed without fractured triangle seams",not casing_errors,casing_errors)
    skin_errors=[]
    if body:
        bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
        for edge in bm.edges:
            c=sum((v.co for v in edge.verts),Vector())/2
            if not (.34<c.z<1.045 and abs(c.y)>.76):continue
            if c.y<0 and .59<c.x<1.22:continue
            if any(math.hypot(c.x-x,c.z-z)<.430 for x,z in [(-1.063,.325),(1.677,.320)]):continue
            if len(edge.link_faces)!=2:skin_errors.append(list(c))
        bm.free()
        if any(abs(v.y)>.96 and .29<v.z<1.105 for v in coords(body)):skin_errors.append('formed lower skin exceeds original lateral envelope')
    else:skin_errors.append('no painted shell')
    check("formed lower panels have continuous joined surfaces and bounded silhouette",not skin_errors,{'broken_edges':len(skin_errors),'examples':skin_errors[:12]})
    fair_errors=[];fair_samples=0;max_dimple=0
    if body_tree:
        for side in [-1,1]:
            for x in np.arange(-1.92,1.931,.060):
                for z in np.arange(.40,1.016,.055):
                    if side<0 and .55<x<1.26:continue
                    if side<0 and 1.20<x<1.48 and z>.90:continue # Deliberate backed intake opening.
                    if any(math.hypot(x-ax,z-az)<.49 for ax,az in [(-1.063,.325),(1.677,.320)]):continue
                    hits=[body_tree.ray_cast(Vector((x+dx,side*1.15,z)),Vector((0,-side,0)),.50)[0]for dx in [-.04,0,.04]]
                    if any(p is None for p in hits):fair_errors.append({'point':[float(x),side,float(z)],'hole':True});continue
                    deviation=abs(abs(hits[1].y)-(abs(hits[0].y)+abs(hits[2].y))*.5);max_dimple=max(max_dimple,deviation);fair_samples+=1
                    if deviation>.003:fair_errors.append({'point':[float(x),side,float(z)],'local_dimple_m':deviation})
    else:fair_errors.append('no paint surface')
    check('coach side paint has no random inward dimples or fractured highlight steps',not fair_errors,{'samples':fair_samples,'maximum_dimple_m':max_dimple,'errors':fair_errors[:20]})
    waist_errors=[];waist_samples=0
    for side in [-1,1]:
        for x in np.arange(-1.9,1.901,.10):
            if side<0 and .55<x<1.26:continue
            hit=body_tree.ray_cast(Vector((x,side*1.15,1.079)),Vector((0,-side,0)),.5)[0]if body_tree else None;waist_samples+=1
            if hit is None or abs(abs(hit.y)-.845)>.003:waist_errors.append({'x':float(x),'side':side,'paint_rim':list(hit)if hit is not None else None})
    check('upper painted rim fits beneath the straight window sill without ragged overlap',not waist_errors,{'samples':waist_samples,'errors':waist_errors[:15]})
    corner_errors=[];corner_samples=0;max_bend=0
    for side in [-1,1]:
        for height in [.94,1.04,1.079]:
            previous=None
            for degrees in np.arange(17,27.51,.25):
                angle=math.radians(degrees);direction=Vector((math.cos(angle),side*math.sin(angle),0))
                hit,normal,face,dist=body_tree.ray_cast(direction*3+Vector((0,0,height)),-direction,1.25)if body_tree else (None,None,None,None)
                if hit is None:corner_errors.append({'side':side,'height':height,'degrees':float(degrees),'missing':True});continue
                horizontal=Vector((normal.x,normal.y,0)).normalized();corner_samples+=1
                if previous is not None:
                    bend=math.degrees(math.acos(max(-1,min(1,horizontal.dot(previous)))));max_bend=max(max_bend,bend)
                    if bend>25:corner_errors.append({'side':side,'height':height,'degrees':float(degrees),'abrupt_normal_turn_degrees':bend})
                previous=horizontal
    check('front paint and ivory sill turn continuously without vertical folded seams',not corner_errors,{'samples':corner_samples,'maximum_adjacent_normal_turn_degrees':max_bend,'errors':corner_errors[:15]})
    wheel_gap_errors=[];wheel_gap_samples=0
    for index in range(4):
        wheel=next((o for o in objects if o.name==f'Wheel_{index}'),None)
        if not wheel:wheel_gap_errors.append({'wheel':index,'missing':True});continue
        pivot=wheel.matrix_world.translation;side=-1 if index%2==0 else 1
        local=[(name,tree)for name,tree in opaque_trees if name in ['RetainedPaintedShell','BusWheelHousings',f'Wheel_{index}',f'WheelArch_{index}']]
        for angle in np.linspace(math.radians(30),math.radians(150),15):
            for radius in [.355,.365,.375]:
                start=Vector((pivot.x+radius*math.cos(angle),side*.915,pivot.z+radius*math.sin(angle)))
                for dx,dz in [(0,0),(-.15,-.30),(.15,-.30),(-.15,.20),(.15,.20)]:
                    direction=Vector((dx,-side,dz)).normalized();end=start+direction*(.415/abs(direction.y));wheel_gap_samples+=1
                    hit=first_hit(local,start,end)
                    if hit is None:wheel_gap_errors.append({'wheel':index,'angle':round(math.degrees(float(angle)),2),'radius':radius,'direction':[dx,dz]})
    check('wheel arch gaps are occluded locally before they can reveal opposite pavement',not wheel_gap_errors,{'samples':wheel_gap_samples,'clear_rays':len(wheel_gap_errors),'errors':wheel_gap_errors[:20]})
    housing=next((o for o in objects if o.name=='BusWheelHousings'),None);housing_errors=[];housing_tris=0
    if not housing:housing_errors.append('no physical inner wings')
    else:
        housing_tris=sum(len(f.vertices)-2 for f in housing.data.polygons)
        bm=bmesh.new();bm.from_mesh(housing.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
        broken=sum(len(e.link_faces)!=2 for e in bm.edges);bm.free()
        if broken:housing_errors.append({'open_or_nonmanifold_edges':broken})
        if housing.parent and housing.parent.name.startswith(('Wheel_','DoorLeaf_')):housing_errors.append('inner wings rotate with a moving part')
        if housing_tris>1400:housing_errors.append({'excessive_triangles':housing_tris})
        for mat in housing.data.materials:
            bs=mat.node_tree.nodes.get('Principled BSDF')
            if bs.inputs['Alpha'].default_value<.999 or bs.inputs['Roughness'].default_value<.85:housing_errors.append('inner wing material is transparent or glossy')
        tree=BVHTree.FromPolygons(coords(housing),[list(f.vertices)for f in housing.data.polygons])
        for index in range(4):
            wheel=next((o for o in objects if o.name==f'Wheel_{index}'),None)
            if wheel and any(tree.find_nearest(v,.018)[0] is not None for v in coords(wheel)):housing_errors.append({'wheel':index,'less_than_18mm_casing_clearance':True})
        if any(v.y<-.50 and .65<v.x<1.285 for v in coords(housing)):housing_errors.append('front inner wing enters the door threshold')
    check('four static inner wings are thick closed dark shells with tyre and door clearance',not housing_errors,{'triangles':housing_tris,'errors':housing_errors})
    triangles=sum(len(f.vertices)-2 for o in objects for f in o.data.polygons)
    alpha_objects=[]
    for o in objects:
        if any(m.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value<.999 for m in o.data.materials):alpha_objects.append(o.name)
    budget_ok=len(objects)<=84 and triangles<=290000 and len(alpha_objects)==14 and all(n.startswith('Glass_')or n=='HeadlampFinish'for n in alpha_objects)
    check("vehicle detail stays within mesh triangle and single-layer glass budgets",budget_ok,{'meshes':len(objects),'triangles':triangles,'transparent_meshes':alpha_objects})

result = {"asset": str(source), "passed": not failures, "checks": checks, "failed": failures,
          "sampled_apertures": len(apertures), "native_visual_review_required": True,
          "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "shell_profiles": shell_results}
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
print(json.dumps({"passed": result["passed"], "failed": failures, "checks": len(checks), "blocker_count": len(blockers)}, ensure_ascii=False))
