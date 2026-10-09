"""Lock the apron and draped cardigan using connected cloth regions, with smooth borders.

Skin is excluded by texture colour. Graph propagation follows mesh edges instead
of spatial proximity, so an adjacent cuff cannot inherit the apron weights.
The entire original exterior and UVs remain; no trouser mask is used.
"""
import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Matrix
root=Path(__file__).resolve().parents[3];base=root/'art/models/character_roster_apose_20261004'
bpy.ops.wm.open_mainfile(filepath=str(base/'heat/authoring/kazuko_proxy.blend'))
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH')
rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:track.mute=True
for bone in rig.pose.bones:bone.matrix_basis=Matrix.Identity(4)
H=max(v.co.z for v in mesh.data.vertices);count=len(mesh.data.vertices)
image=next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape((image.size[1],image.size[0],4))
colours=np.zeros((count,3));counts=np.zeros(count)
for loop in mesh.data.loops:
 uv=mesh.data.uv_layers.active.data[loop.index].uv
 colours[loop.vertex_index]+=pixels[int(uv.y*image.size[1])%image.size[1],int(uv.x*image.size[0])%image.size[0],:3];counts[loop.vertex_index]+=1
colours/=np.maximum(counts[:,None],1)
positions=np.array([tuple(v.co) for v in mesh.data.vertices]);x,y,z=positions.T;r,g,b=colours.T
yellow=(abs(x)<.15*H)&(z>.50*H)&(z<.78*H)&(r>g*.95)&(r<g*1.9)&(b<g*.65)&(g>.18)
pink=(abs(x)<.18*H)&(z>.48*H)&(z<.82*H)&(r>g*1.10)&(b>g*.88)&(r>.30)
seed=yellow|pink
adj=[[] for _ in range(count)]
for edge in mesh.data.edges:
 a,c=edge.vertices;distance=float(np.linalg.norm(positions[a]-positions[c]));adj[a].append((c,distance));adj[c].append((a,distance))
# Expand only a narrow connected edge band, never through open space.
import heapq
distance=np.full(count,np.inf);queue=[]
for index in np.flatnonzero(seed):distance[index]=0;heapq.heappush(queue,(0,int(index)))
while queue:
 value,index=heapq.heappop(queue)
 if value!=distance[index] or value>.012*H:continue
 for neighbour,length in adj[index]:
  candidate=value+length
  if candidate<distance[neighbour] and candidate<.012*H:
   distance[neighbour]=candidate;heapq.heappush(queue,(candidate,neighbour))
names=['mixamorig:Hips','mixamorig:Spine','mixamorig:Spine1','mixamorig:Spine2'];heights=[rig.data.bones[n].head_local.z for n in names]
def torso(height):
 if height<=heights[0]:return {names[0]:1.}
 for index in range(3):
  if height<=heights[index+1]:u=(height-heights[index])/(heights[index+1]-heights[index]);return {names[index]:1-u,names[index+1]:u}
 return {names[-1]:1.}
changed=0
for vertex in mesh.data.vertices:
 if not np.isfinite(distance[vertex.index]):continue
 # A gradual edge band keeps a surface smooth where two garments are welded.
 u=max(0.,min(1.,1-distance[vertex.index]/(.012*H)));u=u*u*(3-2*u)
 old={mesh.vertex_groups[a.group].name:a.weight for a in vertex.groups};target=torso(vertex.co.z)
 values={name:value*(1-u) for name,value in old.items()}
 for name,value in target.items():values[name]=values.get(name,0)+u*value
 values=sorted(values.items(),key=lambda pair:pair[1],reverse=True)[:4];total=sum(value for name,value in values)
 for group in mesh.vertex_groups:group.remove([vertex.index])
 for name,value in values:
  if value>1e-6:mesh.vertex_groups[name].add([vertex.index],value/total,'REPLACE')
 changed+=1
# Smooth the welded collar/upper-arm transition. A colour boundary alone cannot
# describe this continuous garment, and a sharp weight step creates long needles.
edges=np.array([tuple(e.vertices) for e in mesh.data.edges],dtype=np.int32)
groups=list(mesh.vertex_groups);weights=np.zeros((count,len(groups)),dtype=np.float32)
for vertex in mesh.data.vertices:
 for assignment in vertex.groups:weights[vertex.index,assignment.group]=assignment.weight
degree=np.bincount(edges.ravel(),minlength=count).astype(np.float32)
band=(abs(x)<.25*H)&(z>.56*H)&(z<.82*H)
for iteration in range(28):
 sums=np.zeros_like(weights)
 np.add.at(sums,edges[:,0],weights[edges[:,1]]);np.add.at(sums,edges[:,1],weights[edges[:,0]])
 weights[band]=weights[band]*.35+sums[band]/np.maximum(degree[band,None],1)*.65
for index in np.flatnonzero(band):
 vertex=mesh.data.vertices[int(index)];row=weights[index];ids=np.argsort(row)[-4:];total=float(row[ids].sum())
 for group in groups:group.remove([vertex.index])
 for group_id in ids:
  if row[group_id]>1e-6:groups[int(group_id)].add([vertex.index],float(row[group_id]/total),'REPLACE')
out=base/'final-binding';bpy.ops.wm.save_as_mainfile(filepath=str(out/'authoring/kazuko_proxy.blend'))
for track in rig.animation_data.nla_tracks:track.mute=False
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
export=out/'godot/assets/kazuko_proxy.glb'
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_bake_animation=True,export_extras=True)
sys.path.insert(0,str(root/'art/poc/character_pipeline_20261003/appearance_preserved'));from retime_glb import match_durations
match_durations(root/'art/models/archive/characters_before_apose_20261004/CH_kazuko.glb',export)
print('CONNECTED_GARMENTS',json.dumps({'seed':int(seed.sum()),'changed':changed,'removed_faces':0}))
