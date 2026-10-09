"""Build precise timber fittings; imagegen cedar supplies colour only, geometry supplies depth.

Blender -b --factory-startup -P art/tools/japanese_joinery.py -- [asset ...]
Raw GLBs and editable packed .blend files go to art/models/raw/japanese_joinery_20261001.
All measurements are metres, Blender Z up / front -Y. Export through game_export.py.
"""
import bpy
import math
import sys
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art/models/raw/japanese_joinery_20261001'
OUT.mkdir(parents=True, exist_ok=True)
ONLY = set(sys.argv[sys.argv.index('--') + 1:]) if '--' in sys.argv else set()
MATS = {}
TINTS = {}


def linear(hex_value):
    rgb = [int(hex_value[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(x/12.92 if x <= .04045 else ((x+.055)/1.055)**2.4 for x in rgb)


def material(name, tint, grain=False):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*linear(tint),1)
    b.inputs['Metallic'].default_value = 0
    b.inputs['Roughness'].default_value = .95
    b.inputs['Specular IOR Level'].default_value = 0
    if grain:
        t = m.node_tree.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(str(ROOT/'game/assets/textures/architecture/cedar-grain.jpg'),check_existing=True)
        mix = m.node_tree.nodes.new('ShaderNodeMixRGB')
        mix.blend_type = 'MULTIPLY'
        mix.inputs[0].default_value = 1
        mix.inputs[2].default_value = (*linear(tint),1)
        m.node_tree.links.new(t.outputs['Color'],mix.inputs[1])
        m.node_tree.links.new(mix.outputs[0],b.inputs['Base Color'])
    MATS[name] = m
    TINTS[name] = linear(tint)
    return m


def box(name, size, loc, m, bevel=.007):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(m)
    # Grain runs along the timber's longest dimension, never across a post.
    major = max(range(3),key=lambda i:size[i])
    uv = o.data.uv_layers.active
    offset = (len(bpy.context.scene.objects)*.137)%1
    for poly in o.data.polygons:
        normal_axis = max(range(3),key=lambda i:abs(poly.normal[i]))
        vertical = major if normal_axis != major else next(i for i in range(3) if i != normal_axis)
        horizontal = next(i for i in range(3) if i not in (normal_axis,vertical))
        for li in poly.loop_indices:
            co = o.data.vertices[o.data.loops[li].vertex_index].co
            uv.data[li].uv = (co[horizontal]/max(size[horizontal],.01)+.5+offset,co[vertical]/.9+.5)
    if bevel:
        mod = o.modifiers.new('Small crisp edge','BEVEL')
        mod.width = bevel
        mod.segments = 1
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o


def gondola():
    oak = material('cedar_honey','ffffff',True)
    dark = material('cedar_joinery','a67b54',True)
    paper = material('price_paper','f5edd5')
    # Exact original 1.84 x .62 footprint and .14/.48/.82/1.16 shelf tops.
    box('base',(1.8,.60,.09),(0,0,.045),dark)
    for x in [-.875,.875]:
        for y in [-.27,.27]:
            box('upright',( .09,.08,1.56),(x,y,.82),dark)
        for z in [.14,.48,.82,1.16,1.54]:
            box('end_crossbar',(.09,.62,.055),(x,0,z-.0275),oak)
    # Slatted centre is substantial joinery, not a smooth supermarket steel panel.
    for i in range(15):
        box('back_slat',(.103,.034,1.37),(-.78+i*.1114,0,.805),oak,.003)
    for level in [.14,.48,.82,1.16]:
        box('shelf',(1.74,.57,.032),(0,0,level-.016),oak,.004)
        for side in [-1,1]:
            box('price_lip',(1.74,.027,.041),(0,side*.293,level-.0205),dark,.003)
            for i in range(6):
                box('paper_label',(.10,.002,.024),(-.72+i*.285,side*.308,level-.020),paper,0)
    box('headrail',(1.84,.12,.085),(0,0,1.5575),dark)


def wall_frame():
    dark = material('cedar_structure','a67b54',True)
    pale = material('cedar_rail','d9b07e',True)
    for x in [-.84,.84]:
        box('hashira',(.12,.12,2.8),(x,0,1.4),dark)
    for z, thickness in [(.055,.11),(.88,.075),(2.17,.09),(2.735,.13)]:
        box('nageshi',(1.8,.10,thickness),(0,-.012,z),pale)
    # End shoulders make the rails read as assembled wooden pieces.
    for x in [-.75,.75]:
        for z in [.88,2.17]:
            box('joint_shoulder',(.10,.025,.11),(x,-.073,z),dark,.003)


def side_panel():
    dark = material('cedar_structure','a67b54',True)
    pale = material('cedar_cladding','c5a27c',True)
    stone = material('foundation','85888f')
    box('stone_base',(4.8,.11,.16),(0,0,.08),stone,.003)
    # Shitami-ita overlapping horizontal boards, each casts a small real shadow.
    for i in range(6):
        z = .19+i*.134
        plank = box('weatherboard',(4.6,.031,.155),(0,-.015-i*.002,z),pale,.003)
        plank.rotation_euler.x = math.radians(4)
    for x in [-2.34,2.34]:
        box('corner_post',(.12,.14,2.97),(x,0,1.485),dark)
    for x in [-1.17,0,1.17]:
        box('board_batten',(.038,.035,.80),(x,-.05,.57),dark,.002)
    box('lower_rail',(4.8,.115,.085),(0,-.015,1.005),dark)
    box('eaves_rail',(4.8,.14,.10),(0,0,2.92),dark)


def save(asset, build):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    TINTS.clear()
    build()
    for img in bpy.data.images:
        if img.source == 'FILE': img.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(asset+'.blend')))
    path = OUT/(asset+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
    # glTF's texture * baseColorFactor expresses the material tint without altering pixels.
    # Blender's general MixRGB node does not preserve that factor in the exporter.
    blob = path.read_bytes()
    json_len = struct.unpack_from('<I',blob,12)[0]
    data = json.loads(blob[20:20+json_len])
    for m in data['materials']:
        if 'baseColorTexture' in m.get('pbrMetallicRoughness',{}):
            m['pbrMetallicRoughness']['baseColorFactor'] = [*TINTS[m['name']],1]
    encoded = json.dumps(data,separators=(',',':')).encode()
    encoded += b' ' * (-len(encoded)%4)
    rest = blob[20+json_len:]
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(rest))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+rest)
    count = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type=='MESH')
    print('JOINERY',asset,count,'triangles')


for aid, builder in {'P_gondola':gondola,'P_shop_wall_frame':wall_frame,'P_store_sidepanel':side_panel}.items():
    if not ONLY or aid in ONLY:
        save(aid,builder)
