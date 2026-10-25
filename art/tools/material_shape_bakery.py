"""Local, UV-preserving S02 source repairs used by build_material_shape_poc.py."""
import math
import bpy
import bmesh
import numpy as np
from mathutils import Vector


def build_bakery(root, dest, author,iteration=6):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(root/'game/assets/models/S02.glb'))
    body=next(o for o in bpy.context.scene.objects if o.type=='MESH')
    body.name='Rodin_S02_body'
    palette={'POC_Plaster':(.82,.76,.62,1),'POC_Timber':(.27,.105,.035,1),
             'POC_Eave':(.74,.70,.57,1),'POC_Canvas':(.82,.57,.045,1),
             'POC_Hem':(.94,.88,.63,1),'POC_Metal':(.19,.24,.25,1),
             'POC_UpperGlass':(.055,.17,.24,1)}
    materials={}
    for name,colour in palette.items():
        mat=bpy.data.materials.new(name);mat.diffuse_color=colour;mat.use_nodes=True
        bsdf=mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value=colour
        bsdf.inputs['Roughness'].default_value=.88 if name!='POC_UpperGlass' else .20
        materials[name]=mat
    body.data.materials.append(materials['POC_Plaster']);plaster_index=len(body.data.materials)-1
    image=next(n.image for n in body.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
    pixels=np.empty(len(image.pixels),dtype=np.float32);image.pixels.foreach_get(pixels)
    pixels=pixels.reshape(image.size[1],image.size[0],4)
    remove=[];plaster_count=0;window_removed=0;fascia_removed=0
    if iteration>=8:
        # Split crossing polygons at repair boundaries before deletion. Centroid-only
        # deletion otherwise removes adjacent wall triangles and leaves visible holes.
        cut=bmesh.new();cut.from_mesh(body.data)
        regions=[(-1.90,2.02,-5.,-2.88,2.36,3.04),
                 (-1.78,1.94,-5.,-2.73,2.95,3.50),
                 (-.61,.83,-5.,-2.60,3.89,4.92),
                 (-.12,.20,-5.,-2.55,5.50,5.88)]
        for bounds in regions:
            for axis in range(3):
                for coordinate in bounds[axis*2:axis*2+2]:
                    faces=[f for f in cut.faces if all(max(v.co[a] for v in f.verts)>=bounds[a*2]-1e-5 and min(v.co[a] for v in f.verts)<=bounds[a*2+1]+1e-5 for a in range(3))]
                    geometry=set(faces)
                    for face in faces:geometry.update(face.edges);geometry.update(face.verts)
                    point=[0.,0.,0.];point[axis]=coordinate
                    normal=[0.,0.,0.];normal[axis]=1.
                    bmesh.ops.bisect_plane(cut,geom=list(geometry),dist=1e-6,plane_co=point,plane_no=normal,clear_inner=False,clear_outer=False)
        cut.to_mesh(body.data);cut.free();body.data.update()
    for face in body.data.polygons:
        p=face.center
        if iteration>=8 and -.12<p.x<.20 and p.y<-2.55 and 5.50<p.z<5.88:
            remove.append(face.index);continue
        # Only the projecting old canvas, measured from the source front-depth scan.
        if iteration>=7 and -1.90<p.x<2.02 and p.y<-2.88 and 2.36<p.z<3.04:
            remove.append(face.index);continue
        if iteration==6 and -1.78<p.x<1.94 and p.y<-3.02 and 2.29<p.z<2.96:
            remove.append(face.index);continue
        if iteration>=7 and -.61<p.x<.83 and p.y<-2.60 and 3.89<p.z<4.92:
            remove.append(face.index);window_removed+=1;continue
        if iteration>=7 and -1.78<p.x<1.94 and p.y<-2.73 and 2.95<p.z<3.50:
            remove.append(face.index);fascia_removed+=1;continue
        if face.material_index!=0 or p.z<1.25 or abs(face.normal.z)>.36:continue
        if p.y<-2.60 and -.84<p.x<1.06 and 3.54<p.z<5.15:continue
        coord=sum((body.data.uv_layers.active.data[i].uv for i in face.loop_indices),Vector((0,0)))/len(face.loop_indices)
        rgb=pixels[int(coord.y*image.size[1])%image.size[1],int(coord.x*image.size[0])%image.size[0],:3]
        if float(rgb.max()-rgb.min())<.20 and float(rgb.mean())>.20:
            face.material_index=plaster_index;plaster_count+=1
    editable=bmesh.new();editable.from_mesh(body.data);editable.faces.ensure_lookup_table()
    bmesh.ops.delete(editable,geom=[editable.faces[i] for i in remove],context='FACES')
    editable.to_mesh(body.data);editable.free();body.data.update()
    if iteration>=7:
        custom=[tuple(n.vector) for n in body.data.corner_normals]
        for face in body.data.polygons:
            if face.material_index!=plaster_index:continue
            face.use_smooth=True
            axis=max(range(3),key=lambda a:abs(face.normal[a]))
            normal=[0.,0.,0.];normal[axis]=1. if face.normal[axis]>=0 else -1.
            for loop in face.loop_indices:custom[loop]=tuple(normal)
        body.data.normals_split_custom_set(custom)
    created=[]

    def finish(obj,name,material,bevel=0):
        obj.name=name;obj.data.materials.clear();obj.data.materials.append(materials[material])
        bpy.context.view_layer.objects.active=obj
        obj.select_set(True);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        if bevel:
            mod=obj.modifiers.new('Real edge radius','BEVEL');mod.width=bevel;mod.segments=3
            mod.harden_normals=True;bpy.ops.object.modifier_apply(modifier=mod.name)
            mod=obj.modifiers.new('Face normals','WEIGHTED_NORMAL');mod.keep_sharp=True
            bpy.ops.object.modifier_apply(modifier=mod.name)
        created.append(name);return obj

    def box(name,point,size,material,bevel=.006):
        bpy.ops.object.select_all(action='DESELECT')
        bpy.ops.mesh.primitive_cube_add(size=1,location=point)
        obj=bpy.context.object;obj.dimensions=size
        return finish(obj,name,material,bevel)

    def beam(name,a,b,width,depth,material):
        a,b=Vector(a),Vector(b);obj=box(name,(a+b)/2,(width,depth,(b-a).length),material)
        obj.rotation_mode='QUATERNION';obj.rotation_quaternion=(b-a).to_track_quat('Z','Y')
        assert (obj.rotation_quaternion@Vector((0,0,1))).dot((b-a).normalized())>.9999
        return obj

    def frame(label,x0,x1,z0,z1,front,width=.065):
        box(label+'_Left',(x0,front,(z0+z1)/2),(width,.105,z1-z0+.1),'POC_Timber')
        box(label+'_Right',(x1,front,(z0+z1)/2),(width,.105,z1-z0+.1),'POC_Timber')
        box(label+'_Top',((x0+x1)/2,front,z1),(x1-x0+.12,.12,.09),'POC_Timber')
        box(label+'_Sill',((x0+x1)/2,front-.025,z0),(x1-x0+.16,.19,.095),'POC_Timber')

    # Existing ground-floor glass and display cavities remain at their measured locations.
    frame('DisplayJoinery',-1.48,.19,.83,2.33,-3.385)
    frame('DoorJoinery',.565,1.195,1.04,2.12,-2.995,.052)
    frame('UpperJoinery',-.65,.87,3.86,4.96,-2.865,.062)
    for i,x in enumerate([-.145,.365]):
        box(f'UpperMullion_{i}',(x,-2.87,4.41),(.045,.072,1.05),'POC_Timber',.004)
    for i,z in enumerate([4.22,4.58]):
        box(f'UpperTransom_{i}',(.11,-2.87,z),(1.48,.075,.045),'POC_Timber',.004)
    box('UpperGlass',(.11,-2.845 if iteration>=7 else -2.775,4.41),(1.47,.014,1.05),'POC_UpperGlass',0)
    box('UpperDripCap',(.11,-2.99,5.04),(1.86,.31,.065),'POC_Timber',.008)
    beam('GableFascia_Left',(-1.88,-3.10,5.02),(.02,-3.10,6.42),.135,.15,'POC_Eave')
    beam('GableFascia_Right',(.02,-3.10,6.42),(1.98,-3.10,5.05),.135,.15,'POC_Eave')
    if iteration>=7:box('ContinuousFrontFascia',(.08,-2.86,3.225),(3.76,.18,.56),'POC_Plaster',.008)
    if iteration>=8:
        box('VentRecess',(.04,-2.79,5.69),(.33,.035,.39),'POC_Metal',.007)
        for i in range(4):
            louver=box(f'VentLouver_{i}',(.04,-2.825,5.545+i*.090),(.32,.050,.028),'POC_Eave',.004)
            louver.rotation_euler.x=math.radians(12)
    # A continuous tensioned canopy with a rounded hem, rather than disconnected triangles.
    vertices=[];faces=[];uv=[];nx=48;ny=8;x0=-1.73;x1=1.91
    for j in range(ny+1):
        t=j/ny
        for i in range(nx+1):
            u=i/nx;x=x0+(x1-x0)*u
            vertices.append((x,-2.91-.96*t,2.925-.455*t+.010*math.sin(u*math.pi*16)*math.sin(t*math.pi)))
            uv.append((u,t))
    for j in range(ny):
        for i in range(nx):
            a=j*(nx+1)+i;faces.append((a,a+nx+1,a+nx+2,a+1))
    mesh=bpy.data.meshes.new('TensionedCanvas');mesh.from_pydata(vertices,[],faces);mesh.update()
    canvas=bpy.data.objects.new('TensionedCanvas',mesh);bpy.context.collection.objects.link(canvas)
    canvas.data.materials.append(materials['POC_Canvas'])
    layer=mesh.uv_layers.new()
    for loop in mesh.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
    mod=canvas.modifiers.new('Canvas thickness','SOLIDIFY');mod.thickness=.012
    bpy.context.view_layer.objects.active=canvas;bpy.ops.object.modifier_apply(modifier=mod.name)
    created.append(canvas.name)
    # Curved scallops are authored geometry; neither transparency nor screen overlays.
    vertices=[];faces=[]
    for i in range(97):
        u=i/96;x=x0+(x1-x0)*u
        bottom=2.305+.034*math.cos(u*math.pi*24)
        vertices.extend([(x,-3.875,2.47),(x,-3.89,bottom)])
    for i in range(96):faces.append((i*2,i*2+1,i*2+3,i*2+2))
    mesh=bpy.data.meshes.new('ScallopedCanvas');mesh.from_pydata(vertices,[],faces);mesh.update()
    valance=bpy.data.objects.new('ScallopedCanvas',mesh);bpy.context.collection.objects.link(valance)
    valance.data.materials.append(materials['POC_Canvas']);mod=valance.modifiers.new('Hem thickness','SOLIDIFY');mod.thickness=.012
    bpy.context.view_layer.objects.active=valance;bpy.ops.object.modifier_apply(modifier=mod.name);created.append(valance.name)
    box('CanvasPaleSeam',((x0+x1)/2,-3.888,2.452),(x1-x0,.018,.025),'POC_Hem',.005)
    for i,x in enumerate([-1.48,1.63]):
        beam(f'AwningDiagonal_{i}',(x,-2.95,2.28),(x,-3.74,2.48),.022,.022,'POC_Metal')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(author/'S02_refined.blend'))
    # Retain source material names, nodes and UVs for a self-contained GLB.
    # Godot reuses the current source shaders when displaying the candidate.
    bpy.ops.export_scene.gltf(filepath=str(dest/'S02_refined.glb'),export_format='GLB',
                             export_yup=True,export_apply=True,export_materials='EXPORT',export_animations=False)
    return {'source':'game/assets/models/S02.glb','plaster_faces':plaster_count,'removed_faces_total':len(remove),'removed_window_faces':window_removed,'removed_fascia_faces':fascia_removed,
            'added_parts':created,'ground_floor_display_cavities':'retained','upper_window':'surface and joinery rebuilt; no full interior room','ground_glass_rectangles':'ShopWindows.WINDOWS.S02 unchanged',
            'joinery_bevel_m':.006,'canvas_thickness_m':.012,'repair_boundaries_clipped':iteration>=8}
