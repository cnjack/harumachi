"""Project edited orthographic albedo onto the original provider mesh.

The image and projection dimensions are recorded together. Side/back UVs remain
unchanged; this does not replace actual windows, protruding fixtures or topology.
"""
import bpy
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]

def material(aid):
    name='Lived_'+aid
    result=bpy.data.materials.get(name)
    if result:return result
    result=bpy.data.materials.new(name);result.use_nodes=True
    bs=result.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Roughness'].default_value=1;bs.inputs['Metallic'].default_value=0;bs.inputs['Specular IOR Level'].default_value=0
    tex=result.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(ROOT/f'art/references/lived_facades_20261003/{aid}_lived.png'),check_existing=True)
    result.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    return result

def apply(ob,aid,centre=(0,0,0),scale=1.0,texture_id=None):
    size,cy,min_z={'H02_unit':(3.8242807745933534,1.3248354196548462,-.07),'S01':(7.723958015441895,2.624544858932495,1.2)}[aid]
    origin=Vector((centre[0],-centre[2],centre[1]))
    mesh=ob.data;mesh.update();uv=mesh.uv_layers.active.data
    mesh.materials.append(material(texture_id or aid));slot=len(mesh.materials)-1;count=0
    for poly in mesh.polygons:
        c=(poly.center-origin)/scale
        if poly.normal.y>-.2 or -c.y<min_z:continue
        poly.material_index=slot;count+=1
        for li in poly.loop_indices:
            v=(mesh.vertices[mesh.loops[li].vertex_index].co-origin)/scale
            uv[li].uv=(v.x/size+.5,(v.z-cy)/size+.5)
    print('PROJECT_LIVED',aid,count,flush=True)

def curtain_uv(ob,centre,height):
    origin=Vector((centre[0],-centre[2],centre[1]));scale=height/2.65
    for li,loop in enumerate(ob.data.loops):
        v=(ob.data.vertices[loop.vertex_index].co-origin)/scale
        ob.data.uv_layers.active.data[li].uv=(v.x/3.8242807745933534+.5,(v.z-1.3248354196548462)/3.8242807745933534+.5)
