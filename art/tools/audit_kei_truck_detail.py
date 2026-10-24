"""Measure actual kei-truck silhouette, hardware, tyres and clear apertures.

Blender -b --factory-startup -P art/tools/audit_kei_truck_detail.py -- model.glb report.json
The same geometry tests are run against the previous truck before rebuilding.
"""
import json
import hashlib
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

source, output = [Path(arg) for arg in sys.argv[sys.argv.index('--')+1:][:2]]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(source))
objects = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']


def godot(point):
    return Vector((point[0], -point[2], point[1]))


def points(obj):
    return [obj.matrix_world @ vert.co for vert in obj.data.vertices]


def bounds(obj):
    rows = points(obj)
    return (Vector([min(p[i] for p in rows) for i in range(3)]),
            Vector([max(p[i] for p in rows) for i in range(3)]))


trees = {obj.name: BVHTree.FromPolygons(points(obj), [list(poly.vertices) for poly in obj.data.polygons])
         for obj in objects if not obj.name.startswith('Glass_')}


def hits(start, end, only=None):
    start, end = godot(start), godot(end)
    direction = end-start
    length = direction.length
    result = []
    for name, tree in trees.items():
        if only and not name.startswith(tuple(only)):
            continue
        at, normal, face, distance = tree.ray_cast(start, direction.normalized(), length)
        if at is not None:
            result.append((distance, name, (at.x, at.z, -at.y)))
    return sorted(result)


def named(prefix):
    return [obj for obj in objects if obj.name.startswith(prefix)]


checks = {}
facts = {}
all_points = [p for obj in objects for p in points(obj)]
lo = Vector([min(p[i] for p in all_points) for i in range(3)])
hi = Vector([max(p[i] for p in all_points) for i in range(3)])
extent = hi-lo
facts['blender_bounds'] = [list(lo), list(hi)]
checks['compact_body_keeps_street_clearance'] = extent.x <= 2.05 and 3.25 <= extent.y <= 3.50 and 1.70 <= extent.z <= 1.89

roof = []
for x in [0, -.58, .58]:
    ray = hits((x, 2.0, .83), (x, 1.73, .83))
    roof.append(ray[0][2][1] if ray else 0)
facts['roof_crown_heights'] = roof
checks['roof_has_a_broad_pressed_crown_not_a_flat_slab'] = roof[0]-max(roof[1:]) >= .018

nose = []
for x in [0, -.63, .63]:
    ray = hits((x, 1.10, 1.9), (x, 1.10, 1.4))
    nose.append(ray[0][2][2] if ray else 0)
facts['nose_bow_depths'] = nose
checks['front_skin_wraps_toward_both_corners'] = nose[0]-max(nose[1:]) >= .018

tyre_shapes = []
for obj in named('Tyre_'):
    low, high = bounds(obj)
    centre = (low+high)*.5
    rows = points(obj)
    half_width = (high.x-low.x)*.5
    middle = [math.hypot(p.y-centre.y,p.z-centre.z) for p in rows if abs(p.x-centre.x)<half_width*.30]
    shoulder = [math.hypot(p.y-centre.y,p.z-centre.z) for p in rows if abs(p.x-centre.x)>half_width*.88]
    tyre_shapes.append({'name':obj.name,'bottom':low.z,'middle_radius':max(middle,default=0),
                        'outer_radius':max(shoulder,default=0)})
facts['tyre_profiles'] = tyre_shapes
checks['four_tyres_have_curved_sidewalls_and_ground_contact'] = len(tyre_shapes)==4 and all(
    abs(row['bottom'])<.003 and row['middle_radius']-row['outer_radius']>=.025 for row in tyre_shapes)

arch_hits = []
for side in [-1,1]:
    for axle,z in [('Front',1.075),('Rear',-1.11)]:
        name='WheelArch_'+axle+('_Left' if side<0 else '_Right')
        result=[]
        for theta in [25,55,90,125,155]:
            angle=math.radians(theta)
            y=.325+.365*math.sin(angle)
            zz=z+.365*math.cos(angle)
            ray=hits((side*1.0,y,zz),(side*.60,y,zz),[name])
            result.append(bool(ray))
        arch_hits.append({'name':name,'supported_arc_samples':result})
facts['wheel_arches'] = arch_hits
checks['all_four_wheel_arches_have_continuous_physical_lips'] = all(all(row['supported_arc_samples']) for row in arch_hits)

lamp_layers=[]
for side in ['Left','Right']:
    lens=named('Headlight_'+side+'_Lens')
    reflector=named('Headlight_'+side+'_Reflector')
    if lens and reflector:
        lens_lo,lens_hi=bounds(lens[0]); ref_lo,ref_hi=bounds(reflector[0])
        lamp_layers.append(-lens_lo.y+ref_hi.y)
facts['headlamp_recess_depths'] = lamp_layers
checks['headlamps_have_recessed_reflectors_under_separate_lenses'] = len(lamp_layers)==2 and min(lamp_layers)>.035

hardware=[]
for obj in named('TailgateHinge_')+named('SidegateLatch_'):
    low,high=bounds(obj); centre=(low+high)*.5; size=high-low
    hardware.append({'name':obj.name,'size':list(size),'height':centre.z})
facts['cargo_hardware'] = hardware
checks['cargo_gates_have_thick_hinges_and_latches'] = len(hardware)>=6 and all(
    min(row['size'])>.012 and .60<row['height']<1.10 for row in hardware)

mirror_faces=[]
for side in ['Left','Right']:
    face=named('Mirror_'+side+'_Lens'); shell=named('Mirror_'+side+'_Shell')
    if face and shell:
        a,b=bounds(face[0]); c,d=bounds(shell[0])
        mirror_faces.append({'face_depth':b.y-a.y,'shell_depth':d.y-c.y,'rear_surface_offset':b.y-d.y,
                             'face_height':b.z-a.z})
facts['mirrors']=mirror_faces
checks['mirrors_are_recessed_rear_facing_surfaces_in_deep_housings'] = len(mirror_faces)==2 and all(
    row['shell_depth']>.065 and row['face_depth']<.012 and -.020<row['rear_surface_offset']<.010 and row['face_height']>.14 for row in mirror_faces)

aperture_blockers=[]
aperture_probe_count=0
for pane in named('Glass_'):
    rows=points(pane)
    low,high=bounds(pane)
    centre=(low+high)*.5
    normal=(rows[1]-rows[0]).cross(rows[2]-rows[0]).normalized()
    if normal.dot(centre-godot((0,1.4,.8)))<0:normal=-normal
    # Match truck_glazing_checks.gd exactly: three barycentric samples per
    # triangle, with a 20 cm segment on BOTH sides of the actual glass. The
    # former 8 cm centroid probes missed the cargo guard 12.8 cm behind it.
    pane.data.calc_loop_triangles()
    for triangle in pane.data.loop_triangles:
        corners=[rows[index] for index in triangle.vertices]
        for weights in [( .2,.4,.4),(.4,.2,.4),(.4,.4,.2)]:
            p=sum((corners[i]*weights[i] for i in range(3)),Vector())
            aperture_probe_count+=1
            start=p+normal*.20; end=p-normal*.20; direction=(end-start).normalized()
            for name,tree in trees.items():
                if name.startswith(('Seat','Headrest')) or name=='SteeringWheel':continue
                at,_,_,distance=tree.ray_cast(start,direction,.40)
                if at is not None:
                    aperture_blockers.append({'pane':pane.name,'blocker':name,'weights':weights,
                                               'distance_from_glass_m':(at-p).length,
                                               'hit_godot_xyz':[at.x,at.z,-at.y]})
facts['aperture_blockers']=aperture_blockers
facts['aperture_probe_count']=aperture_probe_count
facts['aperture_probe_depth_each_side_m']=.20
checks['four_real_windows_remain_clear_of_opaque_body'] = len(named('Glass_'))==4 and not aperture_blockers
report={'asset':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'passed':all(checks.values()),'checks':checks,'measurements':facts,
        'native_visual_review_required':True}
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'checks':checks},ensure_ascii=False))
if not report['passed']:sys.exit(1)
