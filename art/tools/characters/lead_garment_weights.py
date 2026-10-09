"""Anatomical constraints and smooth garment weights for the regenerated leads."""
import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[3];args=sys.argv[sys.argv.index('--')+1:];who=args[0];base=root/'art/models/character_leads_apose_20261005'
bpy.ops.wm.open_mainfile(filepath=str(base/f'heat/authoring/{who}_proxy.blend'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:track.mute=True
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
positions=np.array([tuple(v.co) for v in mesh.data.vertices]);H=float(positions[:,2].max());x,y,z=positions.T;count=len(positions)
image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image);pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4));colours=np.zeros((count,3));counts=np.zeros(count)
for loop in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[loop.index].uv;colours[loop.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[loop.vertex_index]+=1
colours/=np.maximum(counts[:,None],1);r,g,b=colours.T
names=[group.name for group in mesh.vertex_groups];weights=np.zeros((count,len(names)),np.float32)
for vertex in mesh.data.vertices:
 for group in vertex.groups:weights[vertex.index,group.group]=group.weight
lower=[i for i,n in enumerate(names) if any(part in n for part in ['UpLeg','Toe','Foot']) or n.endswith('Leg')]
for i in lower:weights[z>.60*H,i]=0
weights/=np.maximum(weights.sum(axis=1,keepdims=True),1e-8)
torso_names=['mixamorig:Hips','mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2'];heights=np.array([rig.data.bones[n].head_local.z for n in torso_names]);torso=np.zeros_like(weights)
for index,height in enumerate(z):
 if height<=heights[0]:torso[index,names.index(torso_names[0])]=1;continue
 if height>=heights[-1]:torso[index,names.index(torso_names[-1])]=1;continue
 k=int(np.searchsorted(heights,height)-1);u=(height-heights[k])/(heights[k+1]-heights[k]);torso[index,names.index(torso_names[k])]=1-u;torso[index,names.index(torso_names[k+1])]=u
def smooth(a,c,value):
 u=np.clip((value-a)/(c-a),0,1);return u*u*(3-2*u)
core=(1-smooth(.075*H,.14*H,abs(x)))*smooth(.44*H,.53*H,z)*(1-smooth(.77*H,.83*H,z))
weights=weights*(1-core[:,None])+torso*core[:,None]
bag=np.zeros(count,dtype=bool);skirt=np.zeros(count,dtype=bool)
if who=='mio':
 yc=float(rig.data.bones['mixamorig:Hips'].head_local.y)
 cream=(r>.30)&(g>r*.82)&(b<r*1.04)
 bag=cream&(x<-.075*H)&(x>-.25*H)&(z>.34*H)&(z<.74*H)&(y<yc-.015*H)
 weights[bag]=torso[bag]
 skirt=(b>r*1.08)&(b>g*1.04)&((r+g+b)<1.0)&(z>.29*H)&(z<.60*H)&(abs(x)<.23*H)
 amount=.24*(1-smooth(.34*H,.54*H,z));left=smooth(-.12*H,.12*H,x)
 weights[skirt]=0
 weights[skirt,names.index('mixamorig:Hips')]=1-amount[skirt]
 weights[skirt,names.index('mixamorig:LeftUpLeg')]=amount[skirt]*left[skirt]
 weights[skirt,names.index('mixamorig:RightUpLeg')]=amount[skirt]*(1-left[skirt])
edges=np.array([tuple(e.vertices) for e in mesh.data.edges],np.int32);degree=np.bincount(edges.ravel(),minlength=count).astype(np.float32)
band=(z>.29*H)&(z<.82*H)&(abs(x)<.28*H)
for iteration in range(32):
 sums=np.zeros_like(weights);np.add.at(sums,edges[:,0],weights[edges[:,1]]);np.add.at(sums,edges[:,1],weights[edges[:,0]])
 weights[band]=weights[band]*.35+sums[band]/np.maximum(degree[band,None],1)*.65
for vertex in mesh.data.vertices:
 row=weights[vertex.index];ids=np.argsort(row)[-4:];total=float(row[ids].sum())
 if total<1e-8:raise RuntimeError('Constraint left an unweighted vertex '+str(vertex.index))
 for group in mesh.vertex_groups:group.remove([vertex.index])
 for i in ids:
  if row[i]>1e-6:mesh.vertex_groups[int(i)].add([vertex.index],float(row[i]/total),'REPLACE')
out=base/'garments';(out/'authoring').mkdir(parents=True,exist_ok=True);(out/'godot/assets').mkdir(parents=True,exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out/f'authoring/{who}_proxy.blend'))
for track in rig.animation_data.nla_tracks:track.mute=False
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig;target=out/f'godot/assets/{who}_proxy.glb'
bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations
match_durations(root/f'art/models/archive/characters_before_apose_20261004/CH_{who}.glb',target)
print('LEAD_GARMENTS',json.dumps({'character':who,'bag_vertices':int(bag.sum()),'skirt_vertices':int(skirt.sum()),'smoothed_vertices':int(band.sum()),'geometry_changed':False}))
