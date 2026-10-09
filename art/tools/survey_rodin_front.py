"""Orthographic front evidence and physical ray depths for window placement."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'evidence/scene_hyper3d_replace_20261002/front-survey';OUT.mkdir(exist_ok=True)
for aid in sys.argv[sys.argv.index('--')+1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/f'art/models/raw/scene_rodin_20261002/{aid}_body.glb'))
    obs=[o for o in bpy.context.scene.objects if o.type=='MESH'];verts=[];faces=[]
    for ob in obs:
        start=len(verts);verts.extend(ob.matrix_world@v.co for v in ob.data.vertices)
        faces.extend([start+i for i in p.vertices] for p in ob.data.polygons)
    lo=Vector([min(v[a] for v in verts) for a in range(3)]);hi=Vector([max(v[a] for v in verts) for a in range(3)])
    sc=bpy.context.scene;sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=1440;sc.render.resolution_y=1440;sc.render.resolution_percentage=100
    sc.view_settings.view_transform='Standard';sc.view_settings.look='None'
    world=bpy.data.worlds.new('Neutral');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.62,.70,1);world.node_tree.nodes['Background'].inputs[1].default_value=.8;sc.world=world
    sun=bpy.data.objects.new('Sun',bpy.data.lights.new('Sun','SUN'));sc.collection.objects.link(sun);sun.data.energy=1.3;sun.rotation_euler=(.6,-.3,-.4)
    camera=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera'));sc.collection.objects.link(camera);sc.camera=camera;camera.data.type='ORTHO'
    target=Vector((0,0,hi.z/2));camera.location=target+Vector((0,-30,0));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    size=max(hi.x-lo.x,hi.z)*1.1;camera.data.ortho_scale=size
    sc.render.filepath=str(OUT/f'{aid}.png');bpy.ops.render.render(write_still=True)
    bt=BVHTree.FromPolygons(verts,faces);rows=[]
    for y in [.4,.8,1.2,1.6,2.,2.4,2.8,3.2]:
        row={'y':y,'samples':[]}
        for i in range(25):
            x=lo.x+(hi.x-lo.x)*(i+.5)/25
            hit,n,idx,d=bt.ray_cast(Vector((x,lo.y-1,y)),Vector((0,1,0)),hi.y-lo.y+2)
            row['samples'].append([round(x,3),round(-hit.y,4) if hit else None])
        rows.append(row)
    (OUT/f'{aid}.json').write_text(json.dumps({'square_image_world_width':size,'image_center_xy':[0,hi.z/2],'bounds_blender':[list(lo),list(hi)],'front_depth_samples':rows},indent=2))
