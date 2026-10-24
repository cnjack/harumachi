"""Repair the owned country bus: precise apertures, fitted glass and roof route box.

Blender -b --factory-startup -P art/tools/rebuild_bus_cabin.py
Keeps the painted source roof and reconstructs the lower shell and tyres from
measured complete-source contours, with an authored finish pass in detail_bus.
Layout dimensions below are Godot metres (+X is the nose); doors and wheels
retain the gameplay articulation names and their verified axes.
"""
from pathlib import Path
import json
import math
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/models/raw/B01_bus_cabin_20261024"
LIBRARY = ROOT / "art/library/vehicles"
OUT.mkdir(parents=True, exist_ok=True)
(LIBRARY / "authoring").mkdir(parents=True, exist_ok=True)
(LIBRARY / "source").mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(LIBRARY / "source/B01_painted_predecessor.glb"))


def point(p):
    return Vector((p[0], -p[2], p[1]))


def linear(values):
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values)


def material(name, colour, alpha=1):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*linear(colour), alpha)
    bsdf.inputs["Roughness"].default_value = .72
    bsdf.inputs["Metallic"].default_value = 0
    bsdf.inputs["Specular IOR Level"].default_value = .18
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1:
        mat.surface_render_method = "DITHERED"
    return mat


ivory = material("Cabin_ivory_enamel", (.91, .925, .875))
jade = material("Door_jade_enamel", (.24, .62, .44))
seal = material("Window_rubber_seal", (.22, .29, .30))
alloy = material("Satin_aluminium", (.69, .75, .72))
cloth = material("Quiet_teal_upholstery", (.31, .47, .49))
cloth_edge = material("Seat_edge_piping", (.43, .56, .55))
floor_mat = material("Cabin_floor", (.36, .40, .37))
display = material("Route_rollsign_face", (.075, .22, .22))
glass = material("Bus_fitted_clear_glass", (.65, .82, .85), .15)
arch_paint = material("Rolled_arch_enamel", (.23, .45, .32))


def finish(obj, name, mat, bevel=.012, segments=3):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Formed_edge", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        normals = obj.modifiers.new("Face_normals", "WEIGHTED_NORMAL")
        normals.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=normals.name)
    return obj


def box(name, size, at, mat=ivory, bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=point(at))
    obj = bpy.context.object
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel)


def beam(name, a, b, width, mat=ivory):
    a, b = point(a), point(b)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(a+b)/2)
    obj = bpy.context.object
    obj.dimensions = (width, width, (b-a).length)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_euler = (b-a).to_track_quat("Z", "Y").to_euler()
    return finish(obj, name, mat, width*.23)


def quad(name, corners, mat):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([point(v) for v in corners], [], [(0, 1, 2, 3)])
    mesh.update()
    uv = mesh.uv_layers.new(name="UVMap")
    for loop, coord in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop.uv = coord
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def cylinder(name, at, radius, depth, mat=alloy, axis="X", vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=point(at))
    obj = bpy.context.object
    if axis == "X":
        obj.rotation_euler.y = math.pi/2
    elif axis == "Z":
        obj.rotation_euler.x = math.pi/2
    return finish(obj, name, mat, min(.003, depth*.18), 2)


def parent_keep(obj, parent):
    transform = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = transform


# The predecessor's old Wheel nodes were cut at guessed centres. Reassemble
# the unchanged source first; the complete rear rims mostly remained in Body.
body = bpy.data.objects["GeneratedBody"]
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
for wheel_index in range(4):bpy.data.objects[f"Wheel_{wheel_index}"].select_set(True)
bpy.context.view_layer.objects.active=body
bpy.ops.object.join();body.name="RetainedPaintedShell"
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# Measured from the complete neutral rim faces, not inherited node origins.
# Evidence: true_hub_measure.json; rear old pivot was 447mm too far back.
axles=[(-1.063,.325),(1.677,.320)]
wheel_clearance=.345
body_aperture=.381
wheel_cleanup=[];wheel_layout=[]
pixel_cache={}
bm=bmesh.new();bm.from_mesh(body.data)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
for lateral in [-.61,.61]:
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,lateral,0),plane_no=(0,1,0),dist=.000001)
# Split crossing triangles precisely, preserving UVs. No boundary projection
# or radial stretching is applied to the painted body.
for axle_x,axle_z in axles:
    region_faces=[f for f in bm.faces if any(abs(v.co.x-axle_x)<.405 and abs(v.co.z-axle_z)<.405 and abs(v.co.y)>.59 for v in f.verts)]
    region=set(region_faces)
    for face in region_faces:region.update(face.edges);region.update(face.verts)
    for radius in [wheel_clearance,body_aperture]:
        for angle in [i*math.tau/96 for i in range(96)]:
            nx,nz=math.cos(angle),math.sin(angle)
            cut=bmesh.ops.bisect_plane(bm,geom=[item for item in region if item.is_valid],plane_co=(axle_x+radius*nx,0,axle_z+radius*nz),plane_no=(nx,0,nz),dist=.000001)
            region=set(cut["geom"])

def in_wheel(face,axle_x,axle_z,side,radius=wheel_clearance):
    c=face.calc_center_median()
    return c.y*side>.61 and math.hypot(c.x-axle_x,c.z-axle_z)<radius+.00001

def green_sheet(face,uv_layer):
    mat=body.data.materials[face.material_index]
    image=next((node.image for node in mat.node_tree.nodes if node.type=="TEX_IMAGE" and node.image),None)
    if image is None or uv_layer is None:return False
    if image.name not in pixel_cache:
        w,h=image.size;pixels=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(pixels);pixel_cache[image.name]=pixels.reshape(h,w,4)
    pixels=pixel_cache[image.name]
    uv=sum((loop[uv_layer].uv for loop in face.loops),Vector((0,0)))/len(face.loops)
    red,green,blue=pixels[int((uv.y%1)*pixels.shape[0]),int((uv.x%1)*pixels.shape[1]),:3]
    return green>red*1.13 and green>blue*1.10 and green>.15

for wheel_index in range(4):
    axle_x,axle_z=axles[wheel_index//2];side=-1 if wheel_index%2==0 else 1
    tyre=bm.copy();uv_layer=tyre.loops.layers.uv.active
    discard=[];paint_count=0
    for face in tyre.faces:
        if not in_wheel(face,axle_x,axle_z,side):discard.append(face)
        elif green_sheet(face,uv_layer):discard.append(face);paint_count+=1
    bmesh.ops.delete(tyre,geom=discard,context="FACES")
    bmesh.ops.delete(tyre,geom=[v for v in tyre.verts if not v.link_faces],context="VERTS")
    tyre_bottom=min(v.co.z for v in tyre.verts)
    mesh=bpy.data.meshes.new(f"Wheel_{wheel_index}");tyre.to_mesh(mesh);tyre.free()
    for mat in body.data.materials:mesh.materials.append(mat)
    origin=Vector((axle_x,side*.80,axle_z))
    mesh.transform(Matrix.Translation(-origin))
    wheel=bpy.data.objects.new(f"Wheel_{wheel_index}",mesh);bpy.context.collection.objects.link(wheel)
    wheel.location=origin-Vector((0,0,tyre_bottom))
    wheel_layout.append({"wheel":wheel_index,"axis_x":axle_x,"axis_z":axle_z-tyre_bottom,"source_axis_z":axle_z,"source_ground_offset":tyre_bottom,"tyre_partition_radius":wheel_clearance,"body_aperture_radius":body_aperture,"arch_outer_radius":.414})
    wheel_cleanup.append({"wheel":wheel_index,"repartitioned_from_complete_source":True,"green_sheet_faces_excluded":paint_count,"faces":len(mesh.polygons)})
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if in_wheel(f,axle_x,axle_z,side,body_aperture)],context="FACES")

# Existing cabin repair is unchanged; preserve the curved painted end panels.
for co,normal in [((0,0,.59),(0,0,1)),((0,0,1.105),(0,0,1)),((0,0,1.90),(0,0,1)),((0,-.70,0),(0,1,0)),((0,.70,0),(0,1,0)),((.61,0,0),(1,0,0)),((1.20,0,0),(1,0,0)),((0,0,.32),(0,0,1)),((-1.78,0,0),(1,0,0)),((1.78,0,0),(1,0,0))]:
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=co,plane_no=normal,dist=.000001)
remove=[]
for face in bm.faces:
    c=face.calc_center_median()
    cabin_interior=.59<c.z<1.105 and abs(c.y)<.70 and -1.78<c.x<1.78
    if (1.105<c.z<1.90) or cabin_interior or (.61<c.x<1.20 and c.y<-.70 and .32<c.z<1.90):remove.append(face)
bmesh.ops.delete(bm,geom=remove,context="FACES")
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context="VERTS")
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
for label in ["DoorLeaf_0","DoorLeaf_1"]:bpy.data.objects.remove(bpy.data.objects[label],do_unlink=True)

# Close inherited hairline gaps around the existing wheel openings using their
# own boundary vertices. This does not move or project painted shell vertices.
# CDT is constrained by the measured open edges; only uncovered triangles in
# the local seam are filled, with UVs extrapolated from the adjacent shell.
sheet_repairs=[]
seam_centres=[(-1.191,.878,.723),(2.027,-.863,.605),(2.097,-.859,.661),
              (1.369,-.862,.650),(1.246,-.852,.647),(1.706,.875,.746),
              (1.509,.872,.712),(1.470,.870,.693)]
for centre_tuple in seam_centres:
    centre=Vector(centre_tuple);side=1 if centre.y>0 else -1
    shell_bm=bmesh.new();shell_bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(shell_bm,verts=list(shell_bm.verts),dist=.000001)
    shell_bm.verts.ensure_lookup_table();shell_bm.verts.index_update()
    shell_tree=BVHTree.FromBMesh(shell_bm)
    local=[v for v in shell_bm.verts if abs(v.co.y-centre.y)<.045 and math.hypot(v.co.x-centre.x,v.co.z-centre.z)<.065]
    local_set=set(local);edges=[e for e in shell_bm.edges if all(v in local_set for v in e.verts)]
    lookup={v:i for i,v in enumerate(local)}
    if len(local)<3:shell_bm.free();continue
    planar=[Vector((v.co.x,v.co.z)) for v in local]
    result=delaunay_2d_cdt(planar,[(lookup[e.verts[0]],lookup[e.verts[1]]) for e in edges],[],0,.0000001)
    coordinates,_,triangles,original_indices,_,_=result
    max_seam_edge=.072 if abs(centre.x-1.246)<.002 and side<0 else .042
    candidates=0;uv=shell_bm.loops.layers.uv.active
    mapped=[]
    for planar_index,coord in enumerate(coordinates):
        if original_indices[planar_index]:mapped.append(local[original_indices[planar_index][0]]);continue
        best=None
        for edge in edges:
            start,end=[Vector((v.co.x,v.co.z)) for v in edge.verts];direction=end-start
            fraction=max(0,min(1,(coord-start).dot(direction)/max(direction.length_squared,1e-20)))
            distance=(coord-(start+fraction*direction)).length
            if best is None or distance<best[0]:best=(distance,edge.verts[0].co.lerp(edge.verts[1].co,fraction))
        mapped.append(shell_bm.verts.new((coord.x,best[1].y,coord.y)))
    original_faces=set(shell_bm.faces)
    for triangle in triangles:
        if len(triangle)!=3:continue
        verts=[mapped[i] for i in triangle]
        if len(set(verts))<3:continue
        seam_point=sum((v.co for v in verts),Vector())/3
        if math.hypot(seam_point.x-centre.x,seam_point.z-centre.z)>.048:continue
        if max((verts[i].co-verts[(i+1)%3].co).length for i in range(3))>max_seam_edge:continue
        if shell_tree.ray_cast(Vector((seam_point.x,side*1.15,seam_point.z)),Vector((0,-side,0)),.55)[0] is not None:continue
        adjacent=[f for v in verts for f in v.link_faces if f in original_faces]
        if not adjacent:adjacent=[f for f in original_faces if (f.calc_center_median()-seam_point).length<.03]
        if not adjacent:continue
        neighbour=min(adjacent,key=lambda f:(f.calc_center_median()-seam_point).length)
        reference=list(neighbour.loops)[:3];a,b,c=[loop.vert.co.copy() for loop in reference]
        normal=(b-a).cross(c-a);den=normal.length_squared
        if den<1e-14:continue
        samples=[loop[uv].uv.copy() for loop in reference]
        try:face=shell_bm.faces.new(verts)
        except ValueError:continue
        face.material_index=neighbour.material_index;face.smooth=neighbour.smooth
        for loop in face.loops:
            p=loop.vert.co;wb=(p-a).cross(c-a).dot(normal)/den;wc=(b-a).cross(p-a).dot(normal)/den
            loop[uv].uv=samples[0]*(1-wb-wc)+samples[1]*wb+samples[2]*wc
        candidates+=1
    bmesh.ops.recalc_face_normals(shell_bm,faces=list(shell_bm.faces));shell_bm.to_mesh(body.data);shell_bm.free()
    sheet_repairs.append({"centre":list(centre),"added_local_triangles":candidates,"max_new_edge_m":max_seam_edge,"existing_vertices_moved":0})

body_tree=BVHTree.FromPolygons([body.matrix_world@v.co for v in body.data.vertices],[list(f.vertices) for f in body.data.polygons])
arch_boundary_repairs=[]
for arch_index in range(4):
    layout=wheel_layout[arch_index];axle_x,axle_z=layout["axis_x"],layout["axis_z"];side=-1 if arch_index%2==0 else 1
    angles=[math.radians(5+170*i/96) for i in range(97)]
    depths=[]
    for angle in angles:
        x,z=axle_x+.414*math.cos(angle),axle_z+.414*math.sin(angle)
        hit=body_tree.ray_cast(Vector((x,side*1.15,z)),Vector((0,-side,0)),.55)[0]
        depths.append(abs(hit.y) if hit is not None else None)
    for index,depth in enumerate(depths):
        if depth is not None:continue
        neighbours=[depths[j] for j in range(max(0,index-4),min(len(depths),index+5)) if depths[j] is not None]
        if not neighbours:raise RuntimeError(f"Measured arch {arch_index} has no adjacent sheet")
        angle=angles[index];x,z=axle_x+.414*math.cos(angle),axle_z+.414*math.sin(angle)
        nearest=body_tree.find_nearest(Vector((x,side*sum(neighbours)/len(neighbours),z)),.014)[0]
        if nearest is None:raise RuntimeError(f"Measured arch {arch_index} has a real large sheet gap at {math.degrees(angle):.1f}")
        depths[index]=abs(nearest.y)
    smooth=[sum(depths[max(0,i-2):min(len(angles),i+3)])/len(depths[max(0,i-2):min(len(angles),i+3)]) for i in range(len(angles))]
    profile=[(.414,.001),(.404,.018),(.389,.025),(.381,.019),(.379,.005),(.385,-.032),(.409,-.032)]
    vertices=[]
    for step,angle in enumerate(angles):
        for profile_index,(radius,proud) in enumerate(profile):
            depth=depths[step] if profile_index in [0,6] else smooth[step]
            vertices.append((axle_x+radius*math.cos(angle),side*(depth+proud),axle_z+radius*math.sin(angle)))
    polygons=[];mat_ids=[];count=len(profile)
    for step in range(len(angles)-1):
        for part in range(count):
            polygons.append((step*count+part,step*count+(part+1)%count,(step+1)*count+(part+1)%count,(step+1)*count+part));mat_ids.append(1 if part in [2,3,4] else 0)
    polygons.append(tuple(reversed(range(count))));mat_ids.append(0)
    polygons.append(tuple((len(angles)-1)*count+part for part in range(count)));mat_ids.append(0)
    mesh=bpy.data.meshes.new(f"WheelArch_{arch_index}");mesh.from_pydata(vertices,[],polygons);mesh.update()
    arch=bpy.data.objects.new(f"WheelArch_{arch_index}",mesh);bpy.context.collection.objects.link(arch)
    mesh.materials.append(arch_paint);mesh.materials.append(seal)
    for face,mat_id in zip(mesh.polygons,mat_ids):face.material_index=mat_id;face.use_smooth=True
    normal_bm=bmesh.new();normal_bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(normal_bm,faces=list(normal_bm.faces));normal_bm.to_mesh(mesh);normal_bm.free()

# Retain the source recess as a deliberate, backed fresh-air vent. The
# horizontal slats close the former bare dark cutout below the front pane.
box("SideAirIntakeLiner",(.154,.144,.018),(1.338,1.019,.819),seal,.008)
for index,height in enumerate([.972,1.012,1.052]):
    box(f"SideAirIntakeLouvre_{index}",(.142,.013,.031),(1.338,height,.847),jade,.003)
box("SideAirIntakeLowerRim",(.164,.016,.035),(1.338,.939,.842),jade,.004)
# The old generated door left an open return between the new hinge and front
# quarter panel. A narrow fixed jamb joins the sill to the lower rail; it sits
# 4mm clear of the moving leaf and is a real structural return, not a decal.
front_return=box("EntranceFrontReturn",(.064,.755,.075),(1.250,.7125,.830),jade,.007)
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True);front_return.select_set(True);bpy.context.view_layer.objects.active=body
bpy.ops.object.join();body.name="RetainedPaintedShell"

box("Cabin_floor", (3.96, .10, 1.48), (-.10, .555, 0), floor_mat, .018)
box("Cabin_ceiling", (3.96, .07, 1.49), (-.06, 1.94, 0), ivory, .035)

# The roof and lower body carry the frames. Glass uses exactly the same four
# corners as its rubber seals; it is no longer a runtime rectangle laid over
# the irregular generated surface.
side_ranges = [(-1.99, -1.20), (-1.12, -.34), (-.26, .55), (1.27, 1.99)]
for side in [-1, 1]:
    # The entrance is on the +Z side; the opposite wall has an additional pane.
    ranges = side_ranges + ([(.63, 1.19)] if side == -1 else [])
    for index, (start, end) in enumerate(ranges):
        corners = [(start, 1.16, side*.835), (end, 1.16, side*.835),
                   (end, 1.85, side*.798), (start, 1.85, side*.798)]
        quad(f"Glass_Side_{side}_{index}", corners, glass)
        for edge in range(4):
            beam(f"SideSeal_{side}_{index}_{edge}", corners[edge], corners[(edge+1)%4], .029, seal)
        # Deep painted mullions are just outside the aperture, not dark sheets
        # across the cabin; their rounded edges catch the same sun as the roof.
        beam(f"SidePillar_{side}_{index}", (start-.037, 1.105, side*.832),
             (start-.037, 1.915, side*.800), .076)
    beam(f"FrontCorner_{side}", (2.036, 1.105, side*.79), (1.976, 1.93, side*.746), .090)
    beam(f"RearCorner_{side}", (-2.06, 1.105, side*.79), (-2.02, 1.93, side*.745), .095)
    if side == 1:
        for section, (start, end) in enumerate([(-2.075, .61), (1.20, 2.025)]):
            box(f"WindowSill_{side}_{section}", (end-start, .095, .085), ((start+end)/2, 1.1075, side*.825), ivory, .019)
        beam("EntranceBackPillar", (.588, .35, .842), (.588, 1.915, .800), .072)
    else:
        box(f"WindowSill_{side}", (4.10, .095, .085), (-.025, 1.1075, side*.825), ivory, .019)
    box(f"WindowHeader_{side}", (4.10, .09, .085), (-.025, 1.902, side*.79), ivory, .021)

front_corners = [(2.075, 1.16, -.735), (2.075, 1.16, .735),
                 (1.986, 1.865, .713), (1.986, 1.865, -.713)]
quad("Glass_Windscreen", front_corners, glass)
for edge in range(4):
    beam(f"WindscreenSeal_{edge}", front_corners[edge], front_corners[(edge+1)%4], .033, seal)
beam("WindscreenCentre", (2.075, 1.16, 0), (1.986, 1.865, 0), .023, seal)
box("FrontCowl", (.16, .10, 1.54), (2.058, 1.11, 0), ivory, .028)
rear_corners = [(-2.075, 1.16, .72), (-2.075, 1.16, -.72),
                (-2.026, 1.85, -.697), (-2.026, 1.85, .697)]
quad("Glass_Rear", rear_corners, glass)
for edge in range(4):
    beam(f"RearWindowSeal_{edge}", rear_corners[edge], rear_corners[(edge+1)%4], .034, seal)

for index, (pivot_x, direction) in enumerate([(.613, 1), (1.197, -1)]):
    leaf = bpy.data.objects.new(f"DoorLeaf_{index}", None)
    bpy.context.collection.objects.link(leaf)
    leaf.location = point((pivot_x, .34, .842))
    before = set(bpy.context.scene.objects)
    centre = pivot_x + direction*.144
    box(f"DoorPanel_{index}", (.280, .73, .045), (centre, .705, .842), jade, .017)
    for edge_x in [pivot_x+direction*.018, pivot_x+direction*.271]:
        beam(f"DoorRail_{index}", (edge_x, .365, .843), (edge_x, 1.87, .800), .034, ivory)
    box(f"DoorHeader_{index}", (.280, .055, .047), (centre, 1.864, .800), ivory, .010)
    box(f"DoorWaist_{index}", (.280, .060, .047), (centre, 1.095, .822), ivory, .009)
    x0, x1 = centre-.113, centre+.113
    corners = [(x0, 1.135, .822), (x1, 1.135, .822), (x1, 1.825, .800), (x0, 1.825, .800)]
    quad(f"Glass_Door_{index}", corners, glass)
    for edge in range(4):
        beam(f"DoorSeal_{index}_{edge}", corners[edge], corners[(edge+1)%4], .017, seal)
    beam(f"DoorHandle_{index}", (centre, .93, .883), (centre, 1.14, .883), .024, alloy)
    for obj in set(bpy.context.scene.objects)-before:
        parent_keep(obj, leaf)
box("EntranceStep", (.57, .075, .22), (.905, .36, .80), alloy, .014)
for height, z in [(.405, .75), (.465, .66)]:
    box("StepTread", (.52, .034, .11), (.905, height, z), floor_mat, .004)

for row, x in enumerate([-1.57, -.86, -.15]):
    for side in [-1, 1]:
        z = side*.435
        box(f"SeatCushion_{row}_{side}", (.47, .13, .49), (x, .78, z), cloth, .052)
        back = box(f"SeatBack_{row}_{side}", (.115, .54, .49), (x-.245, 1.075, z), cloth, .047)
        back.rotation_euler.y = -.10
        beam(f"SeatGrip_{row}_{side}", (x-.22, 1.37, z-.19), (x-.22, 1.37, z+.19), .028, cloth_edge)
        box(f"SeatPedestal_{row}_{side}", (.18, .18, .28), (x-.025, .65, z), alloy, .010)
box("DriverSeat", (.43, .13, .49), (1.29, .80, -.34), cloth, .050)
box("DriverBack", (.12, .51, .49), (1.03, 1.105, -.34), cloth, .045)
box("Dashboard", (.28, .13, 1.40), (1.88, 1.105, 0), cloth, .040)
box("InstrumentCluster", (.09, .13, .38), (1.72, 1.18, -.34), seal, .026)
beam("SteeringColumn", (1.70, 1.105, -.34), (1.55, 1.25, -.34), .034, seal)
bpy.ops.mesh.primitive_torus_add(major_segments=32, minor_segments=8, location=point((1.58, 1.28, -.34)), major_radius=.115, minor_radius=.012)
steering = bpy.context.object
steering.rotation_euler.y = math.pi/2+.26
finish(steering, "SteeringWheel", seal, 0)
for side in [-1, 1]:
    beam(f"MirrorArm_{side}", (1.98, 1.29, side*.82), (2.11, 1.32, side*.986), .026, seal)
    box(f"MirrorHousing_{side}", (.075, .235, .12), (2.10, 1.39, side*.997), seal, .025)
    box(f"MirrorFace_{side}", (.008, .185, .080), (2.142, 1.39, side*.997), alloy, .014)
    beam(f"WiperArm_{side}", (2.085, 1.18, side*.49), (2.073, 1.30, side*.24), .014, seal)
    beam(f"WiperBlade_{side}", (2.075, 1.25, side*.28), (2.043, 1.53, side*.24), .018, seal)

# A shallow formed lamp box overlaps the real roof header. The black face is
# recessed inside the ivory shell; typography is added at this fitted surface.
box("RouteHousing", (.245, .25, 1.00), (2.0375, 2.02, 0), ivory, .055)
box("RouteRecess", (.021, .173, .866), (2.164, 2.02, 0), seal, .021)
box("RouteDisplay", (.008, .135, .810), (2.178, 2.02, 0), display, .012)
for side in [-1, 1]:
    box(f"RouteRoofMount_{side}", (.38, .075, .115), (1.86, 1.919, side*.37), ivory, .018)
    cylinder(f"RouteHousingFastener_{side}", (2.171, 2.02, side*.455), .009, .009, alloy)


def join_group(name, prefixes):
    parts = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and
             any(obj.name.startswith(prefix) for prefix in prefixes)]
    if not parts:
        return
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    parts[0].name = name


# Keep the authored construction inspectable while batching static members of
# the same material. Animated leaves and their own panes stay independent.
join_group("CabinFrame", ["SidePillar_", "FrontCorner_", "RearCorner_", "WindowSill_", "WindowHeader_", "FrontCowl", "EntranceBackPillar"])
join_group("WindowSeals", ["SideSeal_", "WindscreenSeal_", "RearWindowSeal_"])
join_group("SeatCushions", ["SeatCushion_"])
join_group("SeatGrips", ["SeatGrip_"])
join_group("SeatPedestals", ["SeatPedestal_"])
join_group("WiperAssembly", ["WiperArm_", "WiperBlade_"])
for index in range(2):
    join_group(f"DoorFrame_{index}", [f"DoorRail_{index}", f"DoorHeader_{index}", f"DoorWaist_{index}"])
    join_group(f"DoorRubberSeal_{index}", [f"DoorSeal_{index}_"])

sys.path.insert(0,str(ROOT / "art/tools"))
from detail_bus import apply_bus_finish
finish_record = apply_bus_finish()

source = OUT / "ready.glb"
bpy.ops.wm.save_as_mainfile(filepath=str(LIBRARY / "authoring/B01_bus.blend"))
bpy.ops.export_scene.gltf(filepath=str(source), export_format="GLB", export_yup=True, export_animations=False)
bpy.ops.export_scene.gltf(filepath=str(LIBRARY / "source/B01_bus.glb"), export_format="GLB", export_yup=True, export_animations=False)
record = {
    "asset": "B01_bus", "date": "2026-10-24",
    "source": "art/library/vehicles/source/B01_painted_predecessor.glb",
    "method": "Owned Rodin roof and measured body contours; continuous formed lower shell and closed tyre casings, authored apertures, articulated doors, glazing, cabin, mounted route box and material-specific vehicle details",
    "generator": "art/tools/rebuild_bus_cabin.py", "output": str(source.relative_to(ROOT)),
    "authoring": "art/library/vehicles/authoring/B01_bus.blend",
    "library_source": "art/library/vehicles/source/B01_bus.glb",
    "preserve_parts": True, "preserve_origin": True, "level": False,
    "game_image_format": "AUTO",
    "preserve_source_materials": True,
    "vehicle_finish": finish_record,
    "route_text_at_godot": [2.184, 2.02, 0],
    "wheel_cleanup": wheel_cleanup,
    "wheel_layout": wheel_layout,
    "arch_boundary_repairs": arch_boundary_repairs,
    "sheet_repairs": sheet_repairs,
    "shape_reference": "art/library/vehicles/source/B01_bus_shape_reference.json",
    "notes": [
        "Owned source roof and underbody remain; the fractured lower skin is replaced by a continuous curved shell measured from the source, with an 8mm inner return",
        "Original window apertures, four verified wheel axes, door pivots, cabin and roof-mounted route box remain unchanged",
        "Real radiator vanes and backed headlamp wells replace fragmented source details; separate ray checks validate those recesses and their physical fixtures",
        "Paint shape checks retain body envelopes, axes and required opaque backing; the front-quarter dent, rear-centre paint lump, backed intake and straight window-sill joint are documented local forming regions, with added dimple and corner-continuity checks",
        "Four closed rubber casings preserve the complete accepted tyres' measured axes, casing bounds and ground support; the independent source reference records the original SHA256",
        "Rolled 35mm wheel flanges, genuine inner wheel openings, seated metal rims, six recessed vents and raised hex fasteners remain separate from body paint",
        "Four 6mm dark inner wings follow the rear arch returns, with curved upper shells and inboard D-shaped walls; one static batch blocks opposite-pavement sightlines without moving accepted outer meshes",
        "Clean cream/jade enamel and rubber use independent colour materials; retained source image regions keep PNG pixels",
        "Each headlamp has one thin alpha lens, a 38mm reflector bowl, an unlit bulb and a curved contacting housing; formed bumper corners, tow recesses, door hinges and locks are batched by material and movement parent",
        "Runtime preserves source PBR differences with VehicleFinish; view-dependent single-layer glass uses no emissive whitening or added real-time lights",
        "No new paid generation"
    ],
}
(ROOT / "art/manifests/models_bus_cabin_20261024.json").write_text(json.dumps(record, ensure_ascii=False, indent=2)+"\n")
print("BUS_CABIN_REBUILT", source)
