"""Reference-driven hero tree: organic welded structure and layered alpha foliage.

References: P3_tree and K4_courtyard. Original pictures/textures remain unchanged.
Blender --background -P this_file -- [--preview-only]
"""
import bpy,bmesh,json,math,sys
from pathlib import Path
from mathutils import Vector
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
RAW=ROOT/'art/models/raw/hero_shade_tree_20261005';RAW.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
rng=np.random.default_rng(74)
verts=[];faces=[]

def tube(points,radii,segments=24,steps=7):
 points=[Vector(p) for p in points];start=len(verts);rings=[]
 for index in range(len(points)-1):
  for step in range(steps):
   t=step/steps
   p0=points[max(0,index-1)];p1=points[index];p2=points[index+1];p3=points[min(len(points)-1,index+2)]
   centre=(p1*2+(p2-p0)*t+(p0*2-p1*5+p2*4-p3)*(t*t)+(-p0+p1*3-p2*3+p3)*(t*t*t))*.5
   direction=(points[index+1]-points[index]).normalized();axis=direction.cross(Vector((0,0,1)))
   if axis.length<.01:axis=direction.cross(Vector((0,1,0)))
   axis.normalize();other=direction.cross(axis).normalized();radius=radii[index]*(1-t)+radii[index+1]*t
   ring=[]
   for side in range(segments):
    angle=side*math.tau/segments
    relief=1+.065*math.sin(side*2.3+index*.7)+.027*math.sin(side*7.7+step*.3)
    position=centre+(axis*math.cos(angle)+other*math.sin(angle))*radius*relief
    ring.append(len(verts));verts.append(position[:])
   rings.append(ring)
 centre=points[-1];direction=(points[-1]-points[-2]).normalized();axis=direction.cross(Vector((0,0,1)))
 if axis.length<.01:axis=direction.cross(Vector((0,1,0)))
 axis.normalize();other=direction.cross(axis).normalized();ring=[]
 for side in range(segments):
  angle=side*math.tau/segments;ring.append(len(verts));verts.append((centre+(axis*math.cos(angle)+other*math.sin(angle))*radii[-1])[:])
 rings.append(ring)
 for a,b in zip(rings,rings[1:]):
  for side in range(segments):n=(side+1)%segments;faces.append((a[side],a[n],b[n],b[side]))
 faces.append(tuple(reversed(rings[0])));faces.append(tuple(rings[-1]))

# Several fused buttresses form one old trunk, then split low into spreading boughs.
tube([(0,0,.06),(.18,.02,1.2),(.12,.06,2.6),(.25,.0,3.5)], [1.05,.90,.76,.64],32,9)
tube([(-.50,-.18,.05),(-.42,-.08,1.25),(-.25,.06,2.7),(-.60,.15,3.65)], [.73,.63,.54,.43],28,9)
tube([(.60,.23,.02),(.57,.23,1.3),(.46,.18,2.75),(.62,.15,3.80)], [.61,.58,.51,.38],28,9)
branches=[
 ([(0,0,2.55),(-1.20,.25,3.40),(-3.20,.52,4.15),(-5.30,.76,4.9)], [.68,.50,.29,.12]),
 ([(.25,0,2.9),(1.60,.15,3.55),(3.50,.46,4.35),(5.7,.4,5.05)], [.62,.47,.27,.11]),
 ([(0,0,3.15),(-.65,-1.5,4.1),(-1.4,-3.3,4.95),(-2.2,-5.0,5.50)], [.52,.40,.23,.10]),
 ([(.25,.2,3.25),(1.10,1.50,4.0),(2.2,3.4,4.9),(3.0,5.1,5.45)], [.52,.37,.23,.09]),
 ([(-.2,.1,3.2),(-.30,.65,4.75),(-.75,1.15,6.3),(-1.05,1.7,7.5)], [.48,.34,.20,.07]),
 ([(.30,.1,3.35),(.80,-.25,4.9),(1.65,-.65,6.4),(2.15,-1.0,7.6)], [.45,.31,.17,.07]),
 ([(-1.9,.4,3.72),(-2.6,-1.2,4.55),(-4.4,-2.0,5.4)], [.30,.19,.07]),
 ([(2.3,.3,3.95),(3.1,-1.4,4.70),(4.5,-2.6,5.55)], [.29,.18,.07]),
 ([(-2.8,.5,4.10),(-3.50,2.10,4.85),(-4.2,3.7,5.7)], [.24,.16,.065]),
 ([(2.4,3.7,4.95),(.80,4.80,5.70),(-.30,5.65,6.2)], [.23,.14,.055])]
for points,radii in branches:
 points=points+[(Vector(points[-1])+(Vector(points[-1])-Vector(points[-2])).normalized()*.45)[:]];radii=radii+[.012];tube(points,radii,24,9)
for index in range(12):
 angle=index*math.tau/12+rng.uniform(-.10,.10);length=rng.uniform(1.75,2.8)
 direction=Vector((math.cos(angle),math.sin(angle),0))
 tube([(direction*.65+Vector((0,0,.52)))[:],(direction*1.4+Vector((0,0,.21)))[:],(direction*length+Vector((0,0,.06)))[:]],[.24,.16,.025],14,6)
mesh=bpy.data.meshes.new('OldTreeStructure');mesh.from_pydata(verts,[],faces);mesh.update();trunk=bpy.data.objects.new('Trunk_OldTree',mesh);bpy.context.collection.objects.link(trunk);bpy.context.view_layer.objects.active=trunk;trunk.select_set(True)
remesh=trunk.modifiers.new('Organic branch joins','REMESH');remesh.mode='VOXEL';remesh.voxel_size=.045;remesh.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=remesh.name)
smooth=trunk.modifiers.new('Soft old branch contours','SMOOTH');smooth.factor=.65;smooth.iterations=3;bpy.ops.object.modifier_apply(modifier=smooth.name)
for polygon in trunk.data.polygons:polygon.use_smooth=True
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.025);bpy.ops.object.mode_set(mode='OBJECT')

bark_path=ROOT/'art/references/hero_tree_20261005/bark.png';leaf_path=ROOT/'art/references/hero_tree_20261005/leaves.png'
if not bark_path.exists() or not leaf_path.exists():raise RuntimeError('Reference-driven texture assets are required')
material=bpy.data.materials.new('OldTreePaintedBark');material.use_nodes=True;bs=material.node_tree.nodes.get('Principled BSDF');bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(bark_path));tex.projection='BOX';tex.projection_blend=.20
coords=material.node_tree.nodes.new('ShaderNodeTexCoord');mapping=material.node_tree.nodes.new('ShaderNodeMapping');mapping.inputs['Scale'].default_value=(2.4,2.4,5.0);material.node_tree.links.new(coords.outputs['Generated'],mapping.inputs['Vector']);material.node_tree.links.new(mapping.outputs['Vector'],tex.inputs['Vector']);material.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color']);trunk.data.materials.append(material)
target=bpy.data.images.new('HeroBarkAtlas',width=2048,height=2048,alpha=False);node=material.node_tree.nodes.new('ShaderNodeTexImage');node.image=target;material.node_tree.nodes.active=node
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.use_clear=True;scene.render.bake.margin=16;bpy.ops.object.bake(type='DIFFUSE',pass_filter={'COLOR'});target.pack();material.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])

leaf_material=bpy.data.materials.new('OldTreeLeaves');leaf_material.use_nodes=True;leaf_bs=leaf_material.node_tree.nodes.get('Principled BSDF');leaf_bs.inputs['Roughness'].default_value=1;leaf_bs.inputs['Specular IOR Level'].default_value=0
leaf_tex=leaf_material.node_tree.nodes.new('ShaderNodeTexImage');leaf_tex.image=bpy.data.images.load(str(leaf_path));leaf_material.node_tree.links.new(leaf_tex.outputs['Color'],leaf_bs.inputs['Base Color']);leaf_material.node_tree.links.new(leaf_tex.outputs['Alpha'],leaf_bs.inputs['Alpha']);leaf_material.surface_render_method='DITHERED';leaf_material.use_transparency_overlap=False
leaves=[];leaf_faces=[];uvs=[];colours=[]
lobes=[(-4.5,.5,5.7,2.0,1.8,1.0),(4.3,.3,5.85,2.15,1.9,1.0),(-2.0,-3.2,6.1,2.35,2.0,1.15),(2.3,-2.7,6.35,2.5,2.0,1.15),(-2.3,3.0,6.4,2.4,2.15,1.1),(2.2,3.3,6.7,2.45,2.0,1.1),(-.8,.7,7.8,2.5,2.15,1.15),(1.8,-.4,7.6,2.35,2.0,1.05),(0,4.4,6.2,2.2,1.8,.95)]
for lobe_index,lobe in enumerate(lobes):
 centre=np.array(lobe[:3]);radius=np.array(lobe[3:])
 for index in range(310):
  direction=rng.normal(size=3);direction/=np.linalg.norm(direction);position=Vector(centre+direction*radius*rng.uniform(.58,1.0))
  normal=Vector(direction);normal.z=normal.z*.65+.35;normal.normalize();right=normal.cross(Vector((0,0,1)))
  if right.length<.1:right=Vector((1,0,0))
  right.normalize();up=normal.cross(right).normalized();half_width=rng.uniform(.28,.46);half_height=half_width*.72
  first=len(leaves);leaves.extend([(position-right*half_width-up*half_height)[:],(position+right*half_width-up*half_height)[:],(position+right*half_width+up*half_height)[:],(position-right*half_width+up*half_height)[:]]);leaf_faces.extend([(first,first+1,first+2),(first,first+2,first+3)])
  cell=index%4;u=(cell%2)*.5;v=(cell//2)*.5;uvs.extend([(u+.025,v+.025),(u+.475,v+.025),(u+.475,v+.475),(u+.025,v+.475)])
leaf_mesh=bpy.data.meshes.new('LayeredLeafSprigs');leaf_mesh.from_pydata(leaves,[],leaf_faces);leaf_mesh.update();foliage=bpy.data.objects.new('Foliage_OldTree',leaf_mesh);bpy.context.collection.objects.link(foliage);foliage.data.materials.append(leaf_material);uv=leaf_mesh.uv_layers.new(name='SprigAtlas')
for polygon in leaf_mesh.polygons:
 for loop_index in polygon.loop_indices:uv.data[loop_index].uv=uvs[leaf_mesh.loops[loop_index].vertex_index]
bpy.ops.object.select_all(action='SELECT');bpy.ops.export_scene.gltf(filepath=str(RAW/'T05_old_shade_tree.glb'),export_format='GLB',export_image_format='AUTO',export_yup=True,export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=str(RAW/'T05_old_shade_tree.blend'))
report={'reference':['game/assets/ui/prologue/P3_tree.jpg','art/references/v06/prologue/K4_courtyard.png'],'leaf_cards':len(leaf_faces)//2,'trunk_triangles':sum(len(p.vertices)-2 for p in trunk.data.polygons),'height_target_m':9,'crown_width_target_m':14,'method':'Reference-driven organic structure, layered alpha leaf sprigs, baked painted bark'};(RAW/'construction.json').write_text(json.dumps(report,indent=2)+'\n');print('HERO_TREE',report,flush=True)
