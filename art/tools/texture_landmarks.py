"""Texture existing procedural landmarks without altering their geometry or bridge deck.
Blender -b --factory-startup -P art/tools/texture_landmarks.py -- [asset ...]
Then export with game_export.py (preserve_parts preserves the original physical coordinates).
"""
import bpy
import json
import math
import struct
import sys
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'art/models/raw/landmarks_aged_20261001'
OUT.mkdir(parents=True,exist_ok=True)
ONLY=set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
ASSETS=['P_farm_gate','P_signpost','P_bridge','P_yagura','P_gondola','P_shop_wall_frame','P_store_sidepanel']
JOINERY={'P_gondola','P_shop_wall_frame','P_store_sidepanel'}
TEXTURES=ROOT/'game/assets/textures/aged'
INFO=json.loads((TEXTURES/'material-info.json').read_text())


def linear(hex_value):
    rgb=[int(hex_value[i:i+2],16)/255 for i in (0,2,4)]
    return [x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4 for x in rgb]


def kind(name):
    if name.startswith('wood'):return 'wood'
    if name.startswith('roof'):return 'roof'
    if name.startswith('stone'):return 'stone'
    if name in ['red','cloth']:return 'cloth'
    return None


def components(mesh):
    parent=list(range(len(mesh.vertices)))
    def find(v):
        while parent[v]!=v:parent[v]=parent[parent[v]];v=parent[v]
        return v
    def union(a,b):parent[find(a)]=find(b)
    same={}
    for vertex in mesh.vertices:
        key=tuple(round(x,5) for x in vertex.co)
        if key in same:union(vertex.index,same[key])
        else:same[key]=vertex.index
    for edge in mesh.edges:union(*edge.vertices)
    groups={}
    for vertex in mesh.vertices:groups.setdefault(find(vertex.index),[]).append(vertex.index)
    lookup={}
    for ids in groups.values():
        mn=Vector([min(mesh.vertices[i].co[a] for i in ids) for a in range(3)])
        mx=Vector([max(mesh.vertices[i].co[a] for i in ids) for a in range(3)])
        major=max(range(3),key=lambda a:mx[a]-mn[a])
        for i in ids:lookup[i]=(major,mn,mx)
    return lookup


def unwrap(obj,targets):
    mesh=obj.data
    uv=mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
    comp=components(mesh)
    for poly in mesh.polygons:
        category=targets.get(poly.material_index)
        if not category:continue
        major,mn,mx=comp[poly.vertices[0]]
        if category=='wood':
            normal_axis=max(range(3),key=lambda a:abs(poly.normal[a]))
            vertical=major if normal_axis!=major else next(a for a in range(3) if a!=normal_axis)
            horizontal=next(a for a in range(3) if a not in (normal_axis,vertical))
            for li in poly.loop_indices:
                co=mesh.vertices[mesh.loops[li].vertex_index].co
                uv.data[li].uv=((co[horizontal]-mn[horizontal])/max(mx[horizontal]-mn[horizontal],.02)*.65+mn[major]*.113,
                                (co[vertical]-mn[vertical])/1.7+mn[horizontal]*.171)
        else:
            # Each roof slope gets planar UVs; cloth folds always run vertically.
            normal_axis=max(range(3),key=lambda a:abs(poly.normal[a]))
            if category=='cloth':
                vertical=2;horizontal=0 if normal_axis!=0 else 1
                u=Vector((1,0,0)) if horizontal==0 else Vector((0,1,0));v=Vector((0,0,1));scale=1.7
            elif category=='roof':
                u=Vector((1,0,0)) if abs(poly.normal.x)<.7 else Vector((0,1,0))
                v=poly.normal.cross(u).normalized()
                if v.y<0:v=-v
                scale=1.2
            else:
                axes=[a for a in range(3) if a!=normal_axis];u=Vector([1 if a==axes[0] else 0 for a in range(3)]);v=Vector([1 if a==axes[1] else 0 for a in range(3)]);scale=.85
            for li in poly.loop_indices:
                co=mesh.vertices[mesh.loops[li].vertex_index].co
                uv.data[li].uv=(co.dot(u)/scale,co.dot(v)/scale)


def patch_factors(path,factors):
    blob=path.read_bytes();length=struct.unpack_from('<I',blob,12)[0];data=json.loads(blob[20:20+length])
    for material in data.get('materials',[]):
        if material['name'] in factors:material.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=[*factors[material['name']],1]
    encoded=json.dumps(data,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4);rest=blob[20+length:]
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(rest))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+rest)


for aid in ASSETS:
    if ONLY and aid not in ONLY:continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source=ROOT/'evidence/model_textures_story_20261001/before'/f'{aid}.glb'
    bpy.ops.import_scene.gltf(filepath=str(source))
    factors={}
    targets={}
    for material in bpy.data.materials:
        category=kind(material.name)
        if aid in JOINERY and material.use_nodes:
            images=[n for n in material.node_tree.nodes if n.type=='TEX_IMAGE']
            if images:category='wood'
            elif aid=='P_store_sidepanel':category='stone'
            else:category=None
        if not category or not material.use_nodes:continue
        bsdf=material.node_tree.nodes.get('Principled BSDF')
        if not bsdf:continue
        original=list(bsdf.inputs['Base Color'].default_value)[:3]
        target={'wood_dark':'74634f','wood':'89775e','wood_light':'a49476','roof':'69788b','stone':'92978a','red':'ad4c43','cloth':'ded4b8'}.get(material.name)
        desired=linear(target) if target else original
        if aid in JOINERY and category=='wood':
            old_mean=INFO['original_cedar_mean_linear']
            old=[original[i]*old_mean[i] for i in range(3)]
            value=.2126*old[0]+.7152*old[1]+.0722*old[2]
            desired=[value*1.28,value*1.10,value*.78]
        average=INFO[category]['mean_linear']
        factors[material.name]=[min(1.0,desired[i]/max(.04,average[i])) for i in range(3)]
        tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(TEXTURES/INFO[category]['file']),check_existing=True)
        material.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
        bsdf.inputs['Roughness'].default_value=1;bsdf.inputs['Metallic'].default_value=0;bsdf.inputs['Specular IOR Level'].default_value=0
        targets[material.name]=category
    if aid not in JOINERY:
        for obj in bpy.context.scene.objects:
            if obj.type=='MESH':unwrap(obj,{i:targets[m.name] for i,m in enumerate(obj.data.materials) if m and m.name in targets})
    for img in bpy.data.images:
        if img.source=='FILE':img.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{aid}.blend'))
    path=OUT/f'{aid}.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
    patch_factors(path,factors)
    print('AGED_TEXTURES',aid,sorted(targets),path.stat().st_size)
