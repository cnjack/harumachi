"""Author the small shop-street zelkova from tapered limbs and painted leaf sprigs.

The old six-metre courtyard tree remains untouched. No model-service generation
is used. Sources, packed authoring file and a repeatable local recipe are kept.
"""
import hashlib
import json
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
LIBRARY = ROOT / "art/library/street_trees"
EVIDENCE = ROOT / "evidence/visual_rework_20261024/street_tree"
ASSET = "T12_street_zelkova"
ATLAS = ROOT / "art/references/model_diversity_20261013/foliage_atlas.png"
RNG = random.Random(102408)
for directory in [LIBRARY / "source", LIBRARY / "authoring", EVIDENCE]:
    directory.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = 1
    shader.inputs["Specular IOR Level"].default_value = 0
    return mat


BARK = material("Zelkova_warm_grey_bark", (.112, .068, .044))
BARK_PALETTE = [
    BARK,
    material("Zelkova_broad_warm_bark_plate", (.131, .079, .050)),
    material("Zelkova_cool_bark_recess", (.095, .059, .040)),
    material("Zelkova_sparse_longitudinal_lines", (.078, .050, .036)),
]
BARK_PATHS = []


def tube(name, centres, radii, sides=12):
    centres = [Vector(point) for point in centres]
    vertices, faces = [], []
    previous_direction = None
    across = Vector((1, 0, 0))
    frames = []
    for index, (point, radius) in enumerate(zip(centres, radii)):
        direction = (centres[min(index+1, len(centres)-1)]-centres[max(index-1, 0)]).normalized()
        # Parallel transport the ring frame. Recomputing a cross product at
        # every ring flips it when a curved leader changes its lean direction.
        if previous_direction is not None:
            across = previous_direction.rotation_difference(direction) @ across
        across = (across-direction*across.dot(direction)).normalized()
        if across.length < .01:
            across = direction.cross(Vector((0, 1, 0))).normalized()
        around = direction.cross(across).normalized()
        frames.append((across.copy(), around.copy()))
        previous_direction = direction
        for side in range(sides):
            angle = math.tau*side/sides
            # Broad flutes follow the wood; no uniform photographic noise.
            local_radius = radius*(1+.035*math.sin(angle*3+.4))
            vertices.append(point+(across*math.cos(angle)+around*math.sin(angle))*local_radius)
    for row in range(len(centres)-1):
        for side in range(sides):
            following = (side+1) % sides
            faces.append((row*sides+side, row*sides+following, (row+1)*sides+following, (row+1)*sides+side))
    faces.extend([tuple(reversed(range(sides))), tuple((len(centres)-1)*sides+side for side in range(sides))])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(BARK)
    for face in mesh.polygons:
        face.use_smooth = True
    BARK_PATHS.append({"name": name, "points": centres, "radii": radii, "frames": frames})
    return obj


wood = []
wood.append(tube("Trunk_main", [(0, 0, .0), (.002, .004, .09), (.020, .006, .35), (.047, -.016, .70),
                               (.028, -.029, 1.07), (-.004, -.018, 1.38), (.08, .015, 1.82),
                               (.12, .06, 2.20), (.04, .10, 2.65), (.10, .12, 3.05)],
                 [.115, .104, .086, .071, .055, .047, .032, .022, .012, .0025], 16))
# Three unequal low buttresses curve down beneath the planting plane. At the
# runtime's 8mm embed the round tips disappear, leaving no star-shaped points.
for index, (angle, reach) in enumerate([(.22, .178), (2.31, .159), (4.52, .193)]):
    axis = Vector((math.cos(angle), math.sin(angle), 0))
    wood.append(tube("Trunk_root_%02d" % index,
                     [(axis.x*.035, axis.y*.035, .10), (axis.x*.103, axis.y*.103, .027),
                      (axis.x*reach*.80, axis.y*reach*.80, .006), (axis.x*reach, axis.y*reach, .001)],
                     [.050, .027, .010, .002], 12))

# Different fork heights, reaches and directions keep the vase asymmetric.
branches = [
    [(-.004, -.018, 1.36), (-.20, -.12, 1.78), (-.50, -.22, 2.13), (-.85, -.30, 2.48)],
    [(.018, -.008, 1.50), (.27, -.16, 1.88), (.55, -.30, 2.22), (.79, -.39, 2.68)],
    [(.060, .010, 1.70), (.09, .29, 1.99), (-.12, .54, 2.36), (-.32, .71, 2.73)],
    [(.100, .050, 1.99), (.35, .30, 2.29), (.60, .50, 2.62), (.73, .51, 2.95)],
]
twig_paths = []
for index, path in enumerate(branches):
    wood.append(tube("Trunk_branch_%02d" % index, path, [.039-index*.004, .026, .015, .004]))
    a, b, c, d = map(Vector, path)
    outward = Vector((d.x, d.y, 0)).normalized()
    sideways = Vector((-outward.y, outward.x, 0))
    for fork in [-1, 0, 1]:
        start = b.lerp(c, .48 if fork == -1 else .86)
        end = d + sideways*(fork*.31) + outward*(.12 if fork != 0 else .24)
        end.z += [.0, .20, -.08][fork+1]
        mid = start.lerp(end, .58)+Vector((0, 0, .06))
        twig = [start, mid, end]
        wood.append(tube("Trunk_twig_%02d_%02d" % (index, fork+1), twig, [.011, .007, .0018], 8))
        twig_paths.append(twig)
# A light central leader avoids the flat cut-off silhouette of a clipped hedge.
for index, offset in enumerate([(-.32, -.13, -.05), (.25, .15, .11), (-.10, .27, .02)]):
    start = Vector((.11, .06, 2.25+index*.12))
    end = Vector((.10, .12, 3.05))+Vector(offset)
    middle = start.lerp(end, .60)
    wood.append(tube("Trunk_leader_%02d" % index, [start, middle, end], [.014, .008, .0018], 8))
    twig_paths.append([start, middle, end])

# Join only the wood; leaf parts stay distinct for their independent wind role.
bpy.ops.object.select_all(action="DESELECT")
for obj in wood:
    obj.select_set(True)
bpy.context.view_layer.objects.active = wood[0]
bpy.ops.object.join()
trunk = bpy.context.object
trunk.name = "Trunk_Zelkova"
# Unite the grafts into the stem so a close view sees a continuous crotch, not
# cylinders pushed through one another. Keep the final fine twigs in the crown.
union = trunk.modifiers.new("Continuous_branch_crotches", "REMESH")
union.mode = "VOXEL"
union.voxel_size = .006
union.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier=union.name)
smooth = trunk.modifiers.new("Soft_bark_junctions", "SMOOTH")
smooth.factor = .65
smooth.iterations = 3
bpy.ops.object.modifier_apply(modifier=smooth.name)
reduce = trunk.modifiers.new("Retain_branch_silhouette", "DECIMATE")
surface_triangles = sum(len(face.vertices)-2 for face in trunk.data.polygons)
reduce.ratio = min(1.0, 9000/max(1, surface_triangles))
bpy.ops.object.modifier_apply(modifier=reduce.name)
for vertex in trunk.data.vertices:
    if vertex.co.z < .003:
        vertex.co.z = 0
clean = bmesh.new()
clean.from_mesh(trunk.data)
bmesh.ops.remove_doubles(clean, verts=clean.verts[:], dist=.00005)
bmesh.ops.dissolve_degenerate(clean, edges=clean.edges[:], dist=.00001)
remaining = set(clean.verts)
islands = []
while remaining:
    stack = [remaining.pop()]
    group = set(stack)
    while stack:
        current = stack.pop()
        for edge in current.link_edges:
            other = edge.other_vert(current)
            if other in remaining:
                remaining.remove(other)
                group.add(other)
                stack.append(other)
    faces_in_group = {face for vertex in group for face in vertex.link_faces}
    islands.append((sum(face.calc_area() for face in faces_in_group), group))
islands.sort(key=lambda pair: pair[0], reverse=True)
removed_area = sum(pair[0] for pair in islands[1:])
total_area = sum(pair[0] for pair in islands)
if removed_area/max(total_area, .000001) > .02:
    raise RuntimeError("A real bough disconnected during reduction; repair the source branch path")
bmesh.ops.delete(clean, geom=[vertex for _, group in islands[1:] for vertex in group], context="VERTS")
boundary = [edge for edge in clean.edges if edge.is_boundary]
repaired_faces = bmesh.ops.holes_fill(clean, edges=boundary, sides=0)["faces"] if boundary else []
bmesh.ops.recalc_face_normals(clean, faces=clean.faces[:])
clean.to_mesh(trunk.data)
clean.free()
trunk.data.validate()
trunk.data.update()

# The matte colour bands are authored onto the bark surface and exported as
# ordinary material regions. They follow the nearest limb's longitudinal frame,
# rather than adding a global noise texture or a runtime colour overlay.
trunk.data.materials.clear()
for bark_material in BARK_PALETTE:
    trunk.data.materials.append(bark_material)
for face in trunk.data.polygons:
    point = face.center
    nearest = None
    closest_error = math.inf
    for path_index, path in enumerate(BARK_PATHS):
        length_before = 0.0
        for segment, (first, second) in enumerate(zip(path["points"], path["points"][1:])):
            axis = second-first
            length = axis.length
            fraction = max(0.0, min(1.0, (point-first).dot(axis)/axis.length_squared))
            centre = first+axis*fraction
            radial = point-centre
            radius = path["radii"][segment]*(1-fraction)+path["radii"][segment+1]*fraction
            error = abs(radial.length-radius)
            if error < closest_error:
                closest_error = error
                across, around = path["frames"][segment]
                nearest = (math.atan2(radial.dot(around), radial.dot(across)), length_before+length*fraction, path_index)
            length_before += length
    angle, distance, path_index = nearest
    wave = math.sin(angle*3+.27*math.sin(distance*1.6+path_index))*.65+math.sin(angle*7+distance*.31)*.22
    index = 1 if wave > .39 else (2 if wave < -.32 else 0)
    line = math.sin(angle*17+.23*math.sin(distance*3.7+path_index))
    interrupted = math.sin(distance*10.5+angle*.7+path_index)
    if line > .987 and interrupted > -.12:
        index = 3
    face.material_index = index

leaf_material = material("Painted_zelkova_sprigs", (.94, 1.0, .90))
shader = leaf_material.node_tree.nodes["Principled BSDF"]
texture = leaf_material.node_tree.nodes.new("ShaderNodeTexImage")
texture.image = bpy.data.images.load(str(ATLAS))
texture.image.pack()
leaf_material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
leaf_material.node_tree.links.new(texture.outputs["Alpha"], shader.inputs["Alpha"])
leaf_material.surface_render_method = "DITHERED"
leaf_material.use_backface_culling = False

leaf_objects = []
for cluster_index, path in enumerate(twig_paths):
    start, middle, end = path
    direction = (end-middle).normalized()
    width_axis = direction.cross(Vector((0, 0, 1))).normalized()
    vertices, faces, uvs = [], [], []
    # Cards follow visible terminal branches; none are scattered on a sphere.
    # Each run is flattened, staggered and tapered toward its branch tip.
    for index in range(19):
        along = .31+(index % 7)/6*.75
        base = middle.lerp(end, along)
        side = (-1 if index % 2 else 1)*RNG.uniform(.065, .22)*(1-.35*along)
        point = base+width_axis*side+Vector((RNG.uniform(-.05, .05), RNG.uniform(-.05, .05), RNG.uniform(-.075, .09)))
        point.z = max(point.z, 2.10)
        normal = Vector((RNG.uniform(-.6, .6), RNG.uniform(-.6, .6), RNG.uniform(.25, .9))).normalized()
        right = normal.cross(Vector((0, 0, 1))).normalized()
        if right.length < .01:
            right = Vector((1, 0, 0))
        up = normal.cross(right).normalized()
        turn = RNG.uniform(-1.0, 1.0)
        across = right*math.cos(turn)+up*math.sin(turn)
        vertical = -right*math.sin(turn)+up*math.cos(turn)
        half_width = RNG.uniform(.165, .21)
        half_height = half_width*RNG.uniform(.80, 1.12)
        first = len(vertices)
        # A bent six-vertex card prevents a featureless flat leaf billboard.
        for row in range(2):
            for col in range(3):
                vertices.append(point+across*((col-1)*half_width)+vertical*((row*2-1)*half_height)
                                +normal*(half_width*.12 if col == 1 else 0))
                uvs.append((.508+col*.242, .008+row*.484))
        faces.extend([(first, first+1, first+4, first+3), (first+1, first+2, first+5, first+4)])
    mesh = bpy.data.meshes.new("Terminal_leaf_sprigs_%02d" % cluster_index)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Foliage_Branch_%02d" % cluster_index, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(leaf_material)
    uv = mesh.uv_layers.new(name="PaintedZelkovaCell")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            uv.data[loop_index].uv = uvs[mesh.loops[loop_index].vertex_index]
    leaf_objects.append(obj)

model_objects = [trunk]+leaf_objects
source = LIBRARY / "source" / (ASSET+".glb")
authoring = LIBRARY / "authoring" / (ASSET+".blend")
bpy.ops.object.select_all(action="DESELECT")
for obj in model_objects:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(source), export_format="GLB", export_image_format="AUTO", use_selection=True,
                          export_yup=True, export_apply=True, export_animations=False, export_extras=False)
bpy.ops.wm.save_as_mainfile(filepath=str(authoring))
manifest = {
    "asset_id": ASSET,
    "role": "One shop-street tree at (-18, 0, -16.2); other courtyard and landscape trees keep T01",
    "provider": "Project Blender authoring; existing project imagegen leaf atlas reused",
    "license": "Project-authored geometry; existing generated artwork under service terms",
    "source": str(source.relative_to(ROOT)),
    "authoring": str(authoring.relative_to(ROOT)),
    "recipe": "art/tools/rebuild_street_tree.py",
    "audit": "art/tools/audit_street_tree.py",
    "foliage_atlas": str(ATLAS.relative_to(ROOT)),
    "foliage_atlas_sha256": hashlib.sha256(ATLAS.read_bytes()).hexdigest(),
    "foliage_atlas_cell": "bottom-right: painted small serrated zelkova sprig",
    "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
    "bark_cleanup": {"voxel_tip_fragments_removed": len(islands)-1, "removed_area_fraction": removed_area/max(total_area,.000001), "collapsed_boundary_caps": len(repaired_faces)},
    "geometry": "Slender gently asymmetric stem, three unequal rounded root buttresses turning beneath the soil, four staggered primary forks, fifteen terminal twig groups. Bent alpha sprigs follow twigs, with gaps and unequal crown heights.",
    "bark_finish": "Four restrained warm grey-brown matte regions follow the limb frames: broad bark plates, shallow recesses and sparse interrupted longitudinal lines. These are authored material regions, with no photographic noise and no runtime overlay.",
    "source_finish_feedback": "After native 13/13 street-tree and 12/12 placement checks, the uniform light bark and pointed star-shaped root outline were refined in the source. Native rephotography remains pending.",
    "street_support": "street_tree.gd cuts a 1.24 m square through stone/gravel patches, recesses exposed soil and installs an open stone perimeter; root collar rests in that soil.",
    "legacy_negative": "evidence/visual_rework_20261024/street_tree/negative_old_scaled.json",
    "native_review": "Before source finish: street-tree 13/13 and placement 12/12 passed. The source bark/root refinement awaits native rephotography.",
}
(ROOT / "art/manifests/models_street_tree_20261024.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n")

if "--preview" in sys.argv:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 20
    scene.world = bpy.data.worlds.new("Preview_sky")
    scene.world.color = (.70, .80, .95)
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.025))
    ground = bpy.context.object
    ground.data.materials.append(material("Preview_ground", (.58, .57, .52)))
    bpy.ops.object.light_add(type="AREA", location=(-3, -4, 7))
    light = bpy.context.object
    light.data.energy = 650
    light.data.shape = "DISK"
    light.data.size = 4
    bpy.ops.object.camera_add(location=(4.0, -6.0, 3.1))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((0, 0, 1.65))-camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 4.3
    scene.camera = camera
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = str(EVIDENCE / "source_preview.png")
    bpy.ops.render.render(write_still=True)
print("STREET_TREE_SOURCE", source, flush=True)
