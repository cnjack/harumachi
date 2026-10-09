"""Measure diagonal arm surfaces; create anatomical anchors without altering UVs or mesh."""
import bpy,sys,json,numpy as np
from pathlib import Path
from mathutils import Vector
src,dst,who=sys.argv[sys.argv.index('--')+1:]
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=src)
mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH');vs=[v.co.copy() for v in mesh.data.vertices];H=max(v.z for v in vs)
points=np.array([v[:] for v in vs]);torso=points[(points[:,2]>.5*H)&(points[:,2]<.73*H)&(abs(points[:,0])<.085*H)];yc=float((np.quantile(torso[:,1],.05)+np.quantile(torso[:,1],.95))*.5)
anchors={};fits={}
for sign,side in [(1,'L'),(-1,'R')]:
 samples=[]
 for fraction in [.19,.22,.25,.28,.31,.34]:
  cloud=points[(abs(sign*points[:,0]-fraction*H)<.008*H)&(points[:,2]>.35*H)&(points[:,2]<.86*H)]
  if len(cloud)>10:samples.append((fraction*H,float(np.median(cloud[:,2]))))
 if len(samples)<3:raise RuntimeError('Arm diagonal not measurable '+side)
 fit=np.polyfit([p[0] for p in samples],[p[1] for p in samples],1)
 if not -2.0<float(fit[0])<-.25:raise RuntimeError('Source is not a downward A pose '+side+' '+str(fit))
 fits[side]=fit
 shoulder_cloud=points[(sign*points[:,0]>.12*H)&(sign*points[:,0]<.18*H)&(abs(points[:,2]-np.polyval(fit,sign*points[:,0]))<.04*H)]
 shoulder_y=float((np.quantile(shoulder_cloud[:,1],.10)+np.quantile(shoulder_cloud[:,1],.90))*.5) if len(shoulder_cloud)>10 else yc
 shoulder=Vector((sign*.11*H,shoulder_y,float(np.polyval(fit,.11*H))))
 cloud=[v for v in vs if sign*v.x>.27*H and .3*H<v.z<.68*H];tip=max(cloud,key=lambda v:sign*v.x);near=[v for v in cloud if (v-tip).length<.025*H]
 end=sum(near,Vector())/len(near);axis=(end-shoulder).normalized();wrist=end-axis*.061*H
 elbow=shoulder.lerp(wrist,.5);anchors.update({'upper.'+side:shoulder,'fore.'+side:elbow,'hand.'+side:wrist,'hand_end.'+side:end})
shoulder_z=(anchors['upper.L'].z+anchors['upper.R'].z)/2
hips_z=.46*H if who=='aoi' else .5*H;chest_z=min(.7*H,shoulder_z-.045*H)
J={'hips':Vector((0,yc,hips_z)),'spine':Vector((0,yc,hips_z+(chest_z-hips_z)*.5)),'chest':Vector((0,yc,chest_z)),'neck':Vector((0,yc,shoulder_z+.033*H)),'head':Vector((0,yc,shoulder_z+.075*H)),'head_end':Vector((0,yc,.985*H)),**anchors}
for sign,side in [(1,'L'),(-1,'R')]:
 cloud=points[(points[:,2]>.23*H)&(points[:,2]<.285*H)&(sign*points[:,0]>.015*H)&(abs(points[:,0])<.145*H)];knee=np.median(cloud,axis=0)
 J['clav.'+side]=Vector((sign*.03*H,yc,shoulder_z-.012*H));J['thigh.'+side]=Vector((float(knee[0])*.9,yc,hips_z));J['shin.'+side]=Vector((float(knee[0]),float(knee[1]),.27*H));J['foot.'+side]=Vector((float(knee[0]),float(knee[1]),.055*H));J['toe.'+side]=Vector((float(knee[0]),float(knee[1])-.085*H,.01*H))
rig=bpy.data.objects.new('Rig',bpy.data.armatures.new('Measured A pose anchors'));bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
def bone(name,a,b,parent=None):
 e=rig.data.edit_bones.new(name);e.head=J[a];e.tail=J[b];e.use_connect=False
 if parent:e.parent=rig.data.edit_bones[parent]
bone('hips','hips','spine');bone('spine','spine','chest','hips');bone('chest','chest','neck','spine');bone('neck','neck','head','chest');bone('head','head','head_end','neck')
for side in ['L','R']:
 bone('clav.'+side,'clav.'+side,'upper.'+side,'chest');bone('upper.'+side,'upper.'+side,'fore.'+side,'clav.'+side);bone('fore.'+side,'fore.'+side,'hand.'+side,'upper.'+side);bone('hand.'+side,'hand.'+side,'hand_end.'+side,'fore.'+side)
 bone('thigh.'+side,'thigh.'+side,'shin.'+side,'hips');bone('shin.'+side,'shin.'+side,'foot.'+side,'thigh.'+side);bone('foot.'+side,'foot.'+side,'toe.'+side,'shin.'+side)
bpy.ops.object.mode_set(mode='OBJECT');mesh.parent=rig;mesh.vertex_groups.new(name='hips').add(list(range(len(mesh.data.vertices))),1.0,'REPLACE')
mod=mesh.modifiers.new('Seed','ARMATURE');mod.object=rig
bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
Path(dst).parent.mkdir(parents=True,exist_ok=True);bpy.ops.export_scene.gltf(filepath=dst,export_format='GLB',use_selection=True,export_animations=False)
report={'character':who,'height':H,'arm_fits':{k:[float(v) for v in vals] for k,vals in fits.items()},'anchors':{k:list(v) for k,v in J.items()}}
Path(dst).with_suffix('.json').write_text(json.dumps(report,indent=2));print('APOSE_ANCHORS',report,flush=True)
