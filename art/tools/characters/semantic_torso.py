"""Keep successful welded automatic arm weights; lock torso garments to the torso."""
import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[3];who=sys.argv[sys.argv.index('--')+1];base=root/'art/models/character_roster_apose_20261004';path=base/f'heat/authoring/{who}_proxy.blend';bpy.ops.wm.open_mainfile(filepath=str(path));rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=True
for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
H=max(v.co.z for v in mesh.data.vertices);image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4));colours=np.zeros((len(mesh.data.vertices),3));counts=np.zeros(len(mesh.data.vertices))
for lp in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[lp.index].uv;colours[lp.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[lp.vertex_index]+=1
colours/=np.maximum(counts[:,None],1);names=['mixamorig:Hips','mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2'];heights=[rig.data.bones[n].head_local.z for n in names]
def torso(z):
 if z<=heights[0]:return {names[0]:1}
 for i in range(3):
  if z<=heights[i+1]:u=(z-heights[i])/(heights[i+1]-heights[i]);return {names[i]:1-u,names[i+1]:u}
 return {names[-1]:1}
# Include pale edge texels immediately neighbouring the yellow apron.
yellow_points=[v.co.copy() for v in mesh.data.vertices if abs(v.co.x)<.18*H and .20*H<v.co.z<.78*H and colours[v.index,0]>=colours[v.index,1]*.85 and colours[v.index,1]>colours[v.index,2]*1.10] if who=='kazuko' else []
from mathutils.kdtree import KDTree
yellow_tree=KDTree(len(yellow_points)) if yellow_points else None
if yellow_tree:
 for index,point in enumerate(yellow_points):yellow_tree.insert(point,index)
 yellow_tree.balance()
changed=0
for v in mesh.data.vertices:
 p=v.co;r,g,b=colours[v.index];inside=abs(p.x)<.17*H
 vest=who=='haru' and .38*H<p.z<.80*H and inside and ((g>r*.98 and g>b*1.18 and r>b*1.10) or p.y<rig.data.bones['mixamorig:Hips'].head_local.y-.005*H)
 apron=who=='ren' and inside and .27*H<p.z<.76*H and min(r,g,b)>.4 and max(r,g,b)-min(r,g,b)<.16
 yellow=who=='kazuko' and inside and .20*H<p.z<.78*H and r>=g*.85 and g>b*1.10
 pink=who=='kazuko' and abs(p.x)<.25*H and .48*H<p.z<.82*H and r>g*1.05 and b>g*.90 and r>.30
 if who=='kazuko' and inside and .20*H<p.z<.78*H and yellow_tree and yellow_tree.find(p)[2]<.018*H:yellow=True
 if not (vest or apron or yellow or pink):continue
 for group in mesh.vertex_groups:group.remove([v.index])
 for n,w in torso(p.z).items():mesh.vertex_groups[n].add([v.index],w,'REPLACE')
 changed+=1
out=base/'final-binding';(out/'authoring').mkdir(exist_ok=True,parents=True);(out/'godot/assets').mkdir(exist_ok=True,parents=True);bpy.ops.wm.save_as_mainfile(filepath=str(out/'authoring'/f'{who}_proxy.blend'))
for t in rig.animation_data.nla_tracks:t.mute=False
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig;export=out/'godot/assets'/f'{who}_proxy.glb';bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations;match_durations(root/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb',export);print('HEAT_TORSO_REPAIR',who,changed)
