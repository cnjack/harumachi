"""Authored B01 finish pass; called after the accepted cabin/axle reconstruction.

Replaces the fractured lower skin and tyres from measured source contours.
Keeps the roof, all moving pivots and all 13 window panes.
Small hardware is batched by material and motion parent before GLB export.
"""
import math

import bpy
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def srgb(values):
    return tuple(x/12.92 if x <= .04045 else ((x+.055)/1.055)**2.4 for x in values)


def surface(name, colour, roughness, metallic=0, specular=.25):
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*srgb(colour),1)
    tune(mat,roughness,metallic,specular)
    return mat


def tune(mat,roughness,metallic=0,specular=.25):
    bs=mat.node_tree.nodes.get('Principled BSDF')
    for label,value in [('Roughness',roughness),('Metallic',metallic),('Specular IOR Level',specular)]:
        for link in list(bs.inputs[label].links):mat.node_tree.links.remove(link)
        bs.inputs[label].default_value=value


def solid(name,vertices,faces,materials,indices=None,smooth=True):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
    obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj)
    for mat in materials:mesh.materials.append(mat)
    for i,p in enumerate(mesh.polygons):p.material_index=indices[i] if indices else 0;p.use_smooth=smooth
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    return obj


def basis(axis):
    axis=Vector(axis).normalized();u=axis.cross(Vector((0,0,1)))
    if u.length<.1:u=axis.cross(Vector((0,1,0)))
    u.normalize();return axis,u,axis.cross(u).normalized()


def revolve(name,centre,axis,profile,mat,segments=40):
    axis,u,v=basis(axis);centre=Vector(centre);points=[];rows=[]
    for r,d in profile:
        if r<.00005:
            rows.append([len(points)]*segments);points.append(centre+axis*d);continue
        row=[]
        for i in range(segments):
            a=math.tau*i/segments;row.append(len(points));points.append(centre+axis*d+(u*math.cos(a)+v*math.sin(a))*r)
        rows.append(row)
    faces=[]
    for row in range(len(profile)):
        for i in range(segments):
            face=list(dict.fromkeys([rows[row][i],rows[row][(i+1)%segments],rows[(row+1)%len(profile)][(i+1)%segments],rows[(row+1)%len(profile)][i]]))
            if len(face)>2:faces.append(face)
    return solid(name,points,faces,[mat])


def pin(name,centre,axis,radius,length,mat,sides=12):
    obj=revolve(name,centre,axis,[(.00001,-length/2),(radius*.86,-length/2),(radius,-length*.32),(radius,length*.32),(radius*.86,length/2),(.00001,length/2)],mat,sides)
    for face in obj.data.polygons:face.use_smooth=False
    return obj


def block(name,centre,size,mat,bevel=.004,segments=3):
    bpy.ops.mesh.primitive_cube_add(size=1,location=centre);obj=bpy.context.object;obj.name=name;obj.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);obj.data.materials.append(mat)
    if bevel:
        mod=obj.modifiers.new('Pressed edge','BEVEL');mod.width=bevel;mod.segments=segments
        bpy.ops.object.modifier_apply(modifier=mod.name)
        normal=obj.modifiers.new('Face normals','WEIGHTED_NORMAL');normal.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=normal.name)
    return obj


def ribbon(name,path,height,depth,mat):
    """Solid rounded strip following an actual curved panel in the XY plane."""
    points=[];count=6
    for i,p in enumerate(path):
        p=Vector(p);tangent=Vector(path[min(i+1,len(path)-1)])-Vector(path[max(0,i-1)])
        normal=Vector((-tangent.y,tangent.x,0)).normalized()
        for j in range(count):
            a=math.tau*j/count;points.append(p+normal*(depth*.5*math.cos(a))+Vector((0,0,height*.5*math.sin(a))))
    faces=[]
    for row in range(len(path)-1):
        for j in range(count):faces.append((row*count+j,row*count+(j+1)%count,(row+1)*count+(j+1)%count,(row+1)*count+j))
    faces.extend([tuple(reversed(range(count))),tuple((len(path)-1)*count+j for j in range(count))])
    return solid(name,points,faces,[mat])


def fitted_corner_ribbon(name,path,height,depth,outset,mat,tree):
    obj=ribbon(name,path,height,depth,mat)
    for i,vertex in enumerate(obj.data.vertices):
        p=vertex.co;direction=Vector((p.x,p.y,0)).normalized()
        hit=tree.ray_cast(p+direction*.25,-direction,.55)[0]
        if hit is not None:vertex.co=hit+direction*(outset+depth*.5*math.cos(math.tau*(i%6)/6))
    bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
    return obj


def batch(name,parts,parent=None):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();obj=parts[0];obj.name=name
    if parent:
        bpy.context.view_layer.update();matrix=obj.matrix_world.copy();obj.parent=parent;obj.matrix_world=matrix
    return obj


def wheel_hub(index,wheel,steel,rubber,alloy):
    pivot=wheel.matrix_world.translation.copy();side=-1 if index%2==0 else 1
    world=[wheel.matrix_world@v.co for v in wheel.data.vertices];outer=max(side*v.y for v in world);inner=min(side*v.y for v in world)
    bead=outer-(outer-inner)*.08;centre=Vector((pivot.x,side*(bead-.017),pivot.z));axis=Vector((0,side,0))
    # Six stamped ventilation pockets are backed by a dark brake drum. The
    # radial profile forms the dished web and a rolled rim instead of a disc.
    radii=[.00001,.055,.075,.105,.115,.158,.181,.195,.204]
    depths=[.032,.030,.016,.014,.014,.014,.011,.019,.017]
    segments=36;points=[]
    for r,d in zip(radii,depths):
        for i in range(segments):
            a=math.tau*i/segments;points.append(centre+Vector((r*math.cos(a),side*d,r*math.sin(a))))
    faces=[];ids=[]
    for row in range(len(radii)-1):
        for i in range(segments):
            if row==4 and i%6 in [2,3]:continue
            faces.append((row*segments+i,row*segments+(i+1)%segments,(row+1)*segments+(i+1)%segments,(row+1)*segments+i));ids.append(0)
    # Solid walls around each vent read as pressed steel at oblique angles.
    for sector in range(6):
        for angular in [sector*6+2,sector*6+4]:
            a=math.tau*angular/segments;verts=[]
            for r,d in [(.115,.014),(.158,.014),(.158,.001),(.115,.001)]:verts.append(centre+Vector((r*math.cos(a),side*d,r*math.sin(a))))
            base=len(points);points.extend(verts);faces.append(tuple(base+i for i in range(4)));ids.append(0)
    if side<0:faces=[tuple(reversed(face)) for face in faces]
    web=solid('HubWeb',points,faces,[steel],ids)
    pieces=[web,revolve('BrakeDrum',centre,axis,[(.00001,-.004),(.182,-.004),(.182,.001),(.00001,.001)],rubber,36)]
    for i in range(6):
        a=math.tau*i/6;at=centre+Vector((.087*math.cos(a),side*.024,.087*math.sin(a)))
        pieces.append(pin('HubNut',at,axis,.0095,.017,alloy,6))
        pieces.append(revolve('NutSeat',at-axis*.009,axis,[(.006,-.001),(.014,-.001),(.014,.002),(.006,.002)],steel,8))
    pieces.append(revolve('GreaseCap',centre,axis,[(.00001,.039),(.025,.037),(.040,.031),(.043,.026),(.043,.022),(.00001,.022)],steel,24))
    return batch(f'HubFinish_{index}',pieces,wheel)




def continuous_tyre(wheel,index,rubber):
    """Fit a closed, rounded rubber casing to the complete measured tyre bounds."""
    world=[wheel.matrix_world@v.co for v in wheel.data.vertices];pivot=wheel.matrix_world.translation.copy();side=-1 if index%2==0 else 1
    lo=Vector([min(v[i]for v in world)for i in range(3)]);hi=Vector([max(v[i]for v in world)for i in range(3)])
    rxp=hi.x-pivot.x;rxn=pivot.x-lo.x;rzp=hi.z-pivot.z;rzn=pivot.z-lo.z
    ys=sorted(side*v.y for v in world if math.hypot(v.x-pivot.x,v.z-pivot.z)>.235)
    outer=ys[-1];inner=ys[0];width=outer-inner
    # Two shallow circumferential tread grooves, rounded shoulders, a dished
    # sidewall and a true inner bead. No per-block meshes or normal-map noise.
    cross=[(.0,.08),(.04,.025),(.20,.0),(.47,.008),(.76,.045),(.93,.12),(1.,.23),
           (1.,.32),(.988,.337),(.988,.355),(1.,.372),(1.,.58),(.988,.598),(.988,.616),(1.,.634),
           (1.,.77),(.93,.88),(.76,.955),(.47,.992),(.20,1.),(.04,.975),(.0,.92)]
    count=96;points=[]
    for radial,depth in cross:
        for i in range(count):
            a=math.tau*i/count;c,s=math.cos(a),math.sin(a)
            outer_x=(rxp+rxn)*.5*c+(rxp-rxn)*.5*c*c
            outer_z=(rzp+rzn)*.5*s+(rzp-rzn)*.5*s*s
            x=.200*c*(1-radial)+outer_x*radial;z=.200*s*(1-radial)+outer_z*radial
            points.append(Vector((x,side*(outer-width*depth)-pivot.y,z)))
    faces=[]
    for row in range(len(cross)):
        for i in range(count):faces.append((row*count+i,row*count+(i+1)%count,((row+1)%len(cross))*count+(i+1)%count,((row+1)%len(cross))*count+i))
    replacement=solid('ContinuousTyre',points,faces,[rubber]);wheel.data=replacement.data;bpy.data.objects.remove(replacement,do_unlink=True)
    return {'wheel':index,'original_bounds':[list(lo),list(hi)],'axis':list(pivot),'profile_rows':len(cross),'angular_segments':count,'closed_surface':True,'tread_groove_depth_m':.0016}


def wheel_housings(body_tree,rubber):
    """Closed six-millimetre inner wings with a curved roof and inboard wall.

    The open mouth meets the existing rolled arch's rear return. Only the
    underside is open for the rotating wheel; a real D-shaped inboard wall
    prevents looking through the upper wheel gap to the opposite pavement.
    """
    parts=[]
    for index in range(4):
        pivot=bpy.data.objects[f'Wheel_{index}'].matrix_world.translation;side=-1 if index%2==0 else 1
        angles=np.linspace(math.radians(-10),math.radians(190),37);points=[];count=len(angles)
        mouth=[]
        for angle in angles:
            attachment=max(math.radians(5),min(math.radians(175),float(angle)))
            at=Vector((pivot.x+.414*math.cos(attachment),side*1.15,pivot.z+.414*math.sin(attachment)))
            hit=body_tree.ray_cast(at,Vector((0,-side,0)),.55)[0]
            if hit is None:raise RuntimeError(f'Wheel housing {index} has no arch attachment')
            mouth.append(abs(hit.y)-.032)
        for radius,depth in [(.386,None),(.380,None),(.380,.571),(.386,.565)]:
            for sample,angle in enumerate(angles):
                points.append((pivot.x+radius*math.cos(angle),side*(mouth[sample]if depth is None else depth),pivot.z+radius*math.sin(angle)))
        faces=[]
        for i in range(count-1):
            faces += [(i,i+1,3*count+i+1,3*count+i),
                      (count+i,2*count+i,2*count+i+1,count+i+1),
                      (i,count+i,count+i+1,i+1)]
        faces += [tuple(2*count+i for i in range(count)),tuple(3*count+i for i in reversed(range(count))),
                  (0,3*count,2*count,count),(count-1,2*count-1,3*count-1,4*count-1),
                  (2*count,3*count-1,4*count-1,3*count)]
        parts.append(solid(f'InnerWing_{index}',points,faces,[rubber]))
    batch('BusWheelHousings',parts)
    return {'count':4,'arc_segments':36,'inner_radius_m':.380,'outer_radius_m':.386,'inboard_wall_depth_m':.565,'thickness_m':.006,'static_batch':'BusWheelHousings'}


def formed_lower_shell(body,jade,ivory,rubber,pixels):
    """Replace the fractured lower skin by a continuous measured curved shell.

    The original is sampled, not covered. Wheel/door openings are cut in this
    new source surface, and its inner return provides real sheet thickness.
    """
    tree=BVHTree.FromPolygons([v.co for v in body.data.vertices],[list(f.vertices)for f in body.data.polygons])
    # The generated atlas includes dark inner triangles behind holes, lamp
    # imitations and rubber edges. They are not samples of painted bodywork.
    # Reject those faces instead of reproducing their false inward dents.
    uv=body.data.uv_layers.active.data;paint_samples=[]
    for face in body.data.polygons:
        t=sum((uv[j].uv for j in face.loop_indices),Vector((0,0)))/len(face.loop_indices)
        r,g,b=pixels[int(t.y%1*pixels.shape[0]),int(t.x%1*pixels.shape[1]),:3]
        paint_samples.append(bool((g>.16 and g>r*1.10 and g>b*1.08)or(min(r,g,b)>.45 and max(r,g,b)-min(r,g,b)<.30)))
    def paint_hit(start,direction,distance):
        co,normal,index,depth=tree.ray_cast(start,direction,distance)
        return co if co is not None and paint_samples[index] else None
    def rounded_perimeter(angle,end_extent,side_extent,radius):
        dx,dy=math.cos(angle),math.sin(angle);sx=1 if dx>=0 else -1;sy=1 if dy>=0 else -1
        on_end=end_extent*abs(dy)/max(abs(dx),1e-9)
        if on_end<=side_extent-radius:return np.array([sx*end_extent,sy*on_end])
        on_side=side_extent*abs(dx)/max(abs(dy),1e-9)
        if on_side<=end_extent-radius:return np.array([sx*on_side,sy*side_extent])
        centre=np.array([sx*(end_extent-radius),sy*(side_extent-radius)]);direction=np.array([dx,dy]);projection=float(np.dot(centre,direction))
        distance=projection+math.sqrt(max(0,projection*projection-float(np.dot(centre,centre))+radius*radius))
        return direction*distance
    def eased(value):
        value=max(0,min(1,value));return value*value*(3-2*value)
    # Uniform distance along each panel avoids undersampling curved corners.
    perimeter=[(x,side*.86)for side in [-1,1]for x in np.linspace(-2.24,2.24,181)]
    perimeter += [(x,side*.86)for side in [-1,1]for x in [1.255,1.263,1.413,1.421]]
    perimeter += [(end*2.24,y)for end in [-1,1]for y in np.linspace(-.86,.86,71)]
    angles=np.array(sorted({round(math.atan2(y,x)%math.tau,10)for x,y in perimeter}));count=len(angles)
    # Structural rows retain bumper centres/lips, lamp rails and the paint join.
    heights=np.array(sorted(set(np.linspace(.300,1.105,55))|{.320,.400,.510,.550,.600,.850,.950,.958,1.053,1.055,1.061}))
    guide=np.array([[min(2.24/max(abs(math.cos(a)),.00001),.86/max(abs(math.sin(a)),.00001))*math.cos(a),min(2.24/max(abs(math.cos(a)),.00001),.86/max(abs(math.sin(a)),.00001))*math.sin(a)]for a in angles])
    points_by_row=np.zeros((len(heights),count,2));valid=np.zeros((len(heights),count),dtype=bool)
    for row,z in enumerate(heights):
        for i,a in enumerate(angles):
            px,py=guide[i];side_face=abs(py)>.8599
            if side_face:
                side=1 if py>0 else -1;hit=paint_hit(Vector((px,side*1.18,z)),Vector((0,-side,0)),.48)
            else:
                end=1 if px>0 else -1;hit=paint_hit(Vector((end*2.6,py,z)),Vector((-end,0,0)),.55)
            if hit is None:
                direction=Vector((math.cos(a),math.sin(a),0));estimate=math.hypot(px,py)
                hit=paint_hit(direction*(estimate+.20)+Vector((0,0,z)),-direction,.35)
            if hit is not None and abs(hit.x)<=2.32 and abs(hit.y)<=.95:
                points_by_row[row,i]=[hit.x,hit.y];valid[row,i]=True
        ids=np.flatnonzero(valid[row]);offset=points_by_row[row]-guide
        for axis in [0,1]:points_by_row[row,:,axis]=guide[:,axis]+np.interp(np.arange(count),np.r_[ids-count,ids,ids+count],np.tile(offset[ids,axis],3))
    smooth=points_by_row.copy()
    for row in range(len(heights)):
        neighbours=np.stack([np.roll(points_by_row[max(0,min(len(heights)-1,row+dz))],da,axis=0)for dz in [-2,-1,0,1,2]for da in [-2,-1,0,1,2]])
        smooth[row]=np.median(neighbours,axis=0)
    # A broad, shallow coach panel is fair between its boundary features.
    # Averaging only the normal coordinate keeps sampled longitudinal/height
    # coordinates intact, so corner curvature and wheel cuts do not migrate.
    median_field=smooth.copy()
    for row in range(len(heights)):
        for i in range(count):
            normal_axis=1 if abs(guide[i,1])>.8599 else 0
            smooth[row,i,normal_axis]=np.mean([median_field[max(0,min(len(heights)-1,row+dz)),(i+da)%count,normal_axis]for dz in [-1,0,1]for da in [-2,-1,0,1,2]])
    # Fit each complete cross-section to its measured width, centre nose depth
    # and broad end-panel crown. A single section avoids the discontinuity that
    # blending a separate rounded corner into a noisy old panel would create.
    end_profiles={};side_profiles={};crown_profiles={}
    for end in [-1,1]:
        end_profiles[end]=np.array([abs(float(np.median(smooth[row,(guide[:,0]*end>2.239)&(abs(guide[:,1])<.15),0])))for row in range(len(heights))])
        outer=np.array([abs(float(np.median(smooth[row,(guide[:,0]*end>2.239)&(abs(guide[:,1])>.60)&(abs(guide[:,1])<.70),0])))for row in range(len(heights))])
        crown_profiles[end]=np.clip((end_profiles[end]-outer)/(.65/.87)**2,0,.12 if end>0 else .07)
    for side in [-1,1]:side_profiles[side]=np.array([abs(float(np.median(smooth[row,(guide[:,1]*side>.8599)&(abs(guide[:,0])<1.8),1])))for row in range(len(heights))])
    for profiles in [end_profiles,side_profiles,crown_profiles]:
        for key,values in profiles.items():
            profiles[key]=np.array([np.mean(values[max(0,row-1):min(len(values),row+2)])for row in range(len(values))])
    points=[]
    for row,z in enumerate(heights):
        ends={end:float(end_profiles[end][row])for end in [-1,1]};sides={side:float(side_profiles[side][row])for side in [-1,1]}
        for i,a in enumerate(angles):
            p=Vector((math.cos(a),math.sin(a),z))
            end=1 if p.x>=0 else -1;side=1 if p.y>=0 else -1
            curved=rounded_perimeter(a,ends[end],sides[side],.080 if end>0 else .10)
            p.x=float(curved[0]);p.y=float(curved[1])
            p.x-=end*float(crown_profiles[end][row])*(p.y/sides[side])**2*eased((abs(p.x)-1.85)/.35)
            if z>1.015:
                # One continuous curved upper contour replaces the former hard
                # longitudinal cutoff. It tucks beneath the front and side sill.
                upper=rounded_perimeter(a,2.126 if end>0 else ends[end],.845,.080 if end>0 else .10)
                if end<0:upper[0]+=float(crown_profiles[end][row])*(upper[1]/.845)**2*eased((abs(upper[0])-1.85)/.35)
                join=eased((z-1.015)/.060);p.x=p.x*(1-join)+float(upper[0])*join;p.y=p.y*(1-join)+float(upper[1])*join
            if p.y<-.70 and 1.255<p.x<1.421 and .950<z<1.061:
                pocket=min((p.x-1.255)/.008,(1.421-p.x)/.008,(z-.950)/.008,(1.061-z)/.008,1)
                p.y=p.y*(1-pocket)-.820*pocket
            if p.x>2.05 and abs(p.y)<.565 and .580<z<.867:
                border=min((.565-abs(p.y))/.022,(z-.580)/.018,(.867-z)/.018,1);p.x=p.x*(1-max(0,border))+2.140*max(0,border)
            if p.x>2.05:
                lamp_radius=min(math.hypot(p.y-side*.684,z-.724)for side in [-1,1])
                recess=max(0,min(1,(.122-lamp_radius)/.016))
                p.x=p.x*(1-recess)+min(p.x,2.198)*recess
            points.append(p)
    faces=[]
    for row in range(len(heights)-1):
        for i in range(count):faces.append((row*count+i,row*count+(i+1)%count,(row+1)*count+(i+1)%count,(row+1)*count+i))
    part=solid('FormedLowerShell',points,faces,[jade,ivory,rubber]);bm=bmesh.new();bm.from_mesh(part.data)
    for index in range(4):
        pivot=bpy.data.objects[f'Wheel_{index}'].matrix_world.translation;side=-1 if index%2==0 else 1
        region_faces=[f for f in bm.faces if f.calc_center_median().y*side>.60 and abs(math.hypot(f.calc_center_median().x-pivot.x,f.calc_center_median().z-pivot.z)-.381)<.035]
        region=set(region_faces)
        for f in region_faces:region.update(f.edges);region.update(f.verts)
        for angle in np.arange(96)*math.tau/96:
            nx,nz=math.cos(angle),math.sin(angle)
            result=bmesh.ops.bisect_plane(bm,geom=[v for v in region if v.is_valid],plane_co=(pivot.x+.381*nx,0,pivot.z+.381*nz),plane_no=(nx,0,nz),dist=.000001);region=set(result['geom'])
        discard=[f for f in bm.faces if f.calc_center_median().y*side>.60 and math.hypot(f.calc_center_median().x-pivot.x,f.calc_center_median().z-pivot.z)<.38101]
        bmesh.ops.delete(bm,geom=discard,context='FACES')
    for co,normal in [((.61,0,0),(1,0,0)),((1.20,0,0),(1,0,0)),((0,0,.32),(0,0,1)),((2.11,0,0),(1,0,0)),((0,0,.50),(0,0,1))]:
        bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=co,plane_no=normal,dist=.000001)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if (f.calc_center_median().y<-.60 and .61<f.calc_center_median().x<1.20 and f.calc_center_median().z>.32)or(f.calc_center_median().x>2.11 and f.calc_center_median().z<.50)],context='FACES')
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    # This sheet is open at the window rim and sill. Recalculate alone cannot
    # know which of its two orientations is outside; force the inner return in.
    remaining=set(bm.faces)
    while remaining:
        component=[];queue=[remaining.pop()]
        while queue:
            face=queue.pop();component.append(face)
            for edge in face.edges:
                for neighbour in edge.link_faces:
                    if neighbour in remaining:remaining.remove(neighbour);queue.append(neighbour)
        orientation=sum(face.calc_area()*face.normal.dot(Vector((face.calc_center_median().x/2.24,face.calc_center_median().y/.86,0)))for face in component)
        if orientation<0:
            for face in component:face.normal_flip()
    bm.to_mesh(part.data);bm.free()
    bpy.context.view_layer.objects.active=part;mod=part.modifiers.new('Inner sheet return','SOLIDIFY');mod.thickness=.008;mod.offset=-1;bpy.ops.object.modifier_apply(modifier=mod.name)
    # Remove exactly the replaced source region, retaining the roof, inner
    # deck and underbody. This is a new connected skin, not a masking overlay.
    bm=bmesh.new();bm.from_mesh(body.data)
    for height in [.300,1.105]:bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,0,height),plane_no=(0,0,1),dist=.000001)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if .29999<f.calc_center_median().z<1.10501 and (abs(f.calc_center_median().y)>.60 or abs(f.calc_center_median().x)>1.7)],context='FACES')
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bm.to_mesh(body.data);bm.free()
    bpy.ops.object.select_all(action='DESELECT');body.select_set(True);part.select_set(True);bpy.context.view_layer.objects.active=body;bpy.ops.object.join()
    body['formed_lower_shell']=True
    return {'radial_sections':count,'height_rows':len(heights),'source_paint_hits':int(valid.sum()),'sample_count':int(valid.size),'sheet_thickness_m':.008,'fairing':'paint-only measured widths, end depths and broad crown fitted as continuous rounded cross-sections; upper rim joins fitted sill','original_lower_faces_removed':True}


def formed_front_fittings(jade,alloy,rubber):
    # Pressed bumper has a generous formed radius and two backed towing slots.
    bumper=block('PressedBumper',(2.20,0,.400),(.20,1.85,.220),jade,.045,8)
    pieces=[]
    for side in [-1,1]:
        cutter=block('TowSlotCut',(2.302,side*.42,.402),(.075,.174,.058),rubber,.015)
        bpy.context.view_layer.objects.active=bumper;mod=bumper.modifiers.new('Backed tow recess','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cutter,do_unlink=True)
        pieces.append(block('TowSlotBack',(2.268,side*.42,.402),(.009,.154,.043),rubber,.008))
    for face in bumper.data.polygons:face.use_smooth=True
    bumper.data.set_sharp_from_angle(angle=math.radians(40))
    bpy.context.view_layer.objects.active=bumper;normal=bumper.modifiers.new('Finished bumper normals','WEIGHTED_NORMAL');normal.keep_sharp=True;bpy.ops.object.modifier_apply(modifier=normal.name)
    # Rounded grille surround and separate horizontal vanes, with the source
    # curved rubber backing twelve millimetres behind the metal face.
    for z in [.600,.850]:pieces.append(block('GrilleDepthReturn',(2.181,0,z),(.092,1.105,.010),alloy,.003))
    for y in [-.548,.548]:pieces.append(block('GrilleDepthReturn',(2.181,y,.725),(.092,.010,.250),alloy,.003))
    for z in [.600,.850]:pieces.append(block('GrilleRail',(2.226,0,z),(.025,1.105,.020),alloy,.008))
    for y in [-.548,.548]:pieces.append(block('GrilleEnd',(2.226,y,.725),(.025,.022,.250),alloy,.008))
    for z in [.635,.680,.725,.770,.815]:pieces.append(block('GrilleVane',(2.226,0,z),(.022,1.075,.012),alloy,.004))
    return bumper,pieces

def refinish_shell(body,jade,ivory,alloy,rubber,amber,pixels):
    """Clean two-tone enamel and bounded fairing of the existing panels.

    Face/UV detail is retained inside cavities. This changes the source paint
    regions and existing points, rather than hiding the shell with a new skin.
    """
    materials=[jade,ivory,alloy,rubber,amber]
    slots=[]
    for mat in materials:
        if mat not in list(body.data.materials):body.data.materials.append(mat)
        slots.append(list(body.data.materials).index(mat))
    bm=bmesh.new();bm.from_mesh(body.data)
    def split(co,normal,region):
        faces=[f for f in bm.faces if region([v.co for v in f.verts])]
        edges={e for f in faces for e in f.edges};verts={v for f in faces for v in f.verts}
        bmesh.ops.bisect_plane(bm,geom=list(verts)+list(edges)+faces,plane_co=co,plane_no=normal,dist=.000001)
    for cut in [1.95,2.15]:
        split((cut,0,0),(1,0,0),lambda vv:min(v.x for v in vv)<cut<max(v.x for v in vv) and min(v.z for v in vv)<1.065 and max(v.z for v in vv)>.975)
    split((0,0,1.055),(0,0,1),lambda vv:min(v.x for v in vv)<1.951)
    split((0,0,.985),(0,0,1),lambda vv:max(v.x for v in vv)>2.149)
    split((1.95,0,1.055),(.35,0,1),lambda vv:min(v.x for v in vv)<2.15001 and max(v.x for v in vv)>1.94999)
    uv=bm.loops.layers.uv.active;paint_faces=set()
    for face in bm.faces:
        c=face.calc_center_median()
        if c.z>1.895:
            face.material_index=slots[1];paint_faces.add(face);continue
        if not (.25<c.z<1.105 and (abs(c.y)>.70 or abs(c.x)>1.78)):continue
        if c.x>2.045 and abs(c.y)<.56 and .585<c.z<.86:
            t=sum((loop[uv].uv for loop in face.loops),Vector((0,0)))/len(face.loops)
            rgb=pixels[int(t.y%1*pixels.shape[0]),int(t.x%1*pixels.shape[1]),:3]
            face.material_index=slots[3] if body.get('formed_lower_shell',False) else (slots[2] if rgb.mean()>.31 else slots[3])
            continue
        if c.x>2.08 and .27<c.z<.43 and .28<abs(c.y)<.56:
            face.material_index=slots[3];continue
        boundary=1.055 if c.x<=1.95 else (.985 if c.x>=2.15 else 1.055-.35*(c.x-1.95))
        face.material_index=slots[1] if c.z>boundary else slots[0];paint_faces.add(face)
    candidates=[v for v in bm.verts if (not body.get('formed_lower_shell',False) or v.co.z>1.895) and len(v.link_faces)>2 and all(f in paint_faces for f in v.link_faces) and len({f.material_index for f in v.link_faces})==1 and not any(e.is_boundary for e in v.link_edges)]
    original={v:v.co.copy()for v in candidates}
    for iteration in range(4):
        bmesh.ops.smooth_vert(bm,verts=candidates,factor=.28,use_axis_x=True,use_axis_y=True,use_axis_z=True)
        for v in candidates:
            delta=v.co-original[v]
            if delta.length>.0025:v.co=original[v]+delta.normalized()*.0025
    for face in bm.faces:face.smooth=True
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
    return {'paint_faces':len(paint_faces),'faired_vertices':len(candidates),'maximum_point_move_m':.0025,'two_tone_line':'side 1.055m; front .985m; linear corner transition x1.95..2.15m'}

def apply_bus_finish():
    settings={
        'Cabin_ivory_enamel':(.44,0,.25),'Door_jade_enamel':(.42,0,.25),
        'Rolled_arch_enamel':(.44,0,.25),'Satin_aluminium':(.34,.65,.28),
        'Window_rubber_seal':(.91,0,.08),'Cabin_floor':(.95,0,.06),
        'Quiet_teal_upholstery':(.94,0,.06),'Seat_edge_piping':(.88,0,.08),
        'Route_rollsign_face':(.92,0,.06),'Bus_fitted_clear_glass':(.24,0,.32)}
    for name,values in settings.items():tune(bpy.data.materials[name],*values)
    body=bpy.data.objects['RetainedPaintedShell']
    atlas=next(m for m in body.data.materials if any(n.type=='TEX_IMAGE' and n.image for n in m.node_tree.nodes))
    atlas.name='Bus_body_paint_atlas';tune(atlas,.42,0,.25)
    rubber_atlas=surface('Bus_tyre_rubber',(.12,.15,.16),.92,0,.08)
    image=next(n.image for n in atlas.node_tree.nodes if n.type=='TEX_IMAGE' and n.image)
    w,h=image.size;pixels=np.empty(w*h*4,np.float32);image.pixels.foreach_get(pixels);pixels=pixels.reshape(h,w,4)
    steel=surface('Bus_stamped_wheel_steel',(.71,.73,.69),.36,.62,.28)
    alloy=surface('Bus_satin_hardware',(.66,.72,.72),.32,.68,.28)
    rubber=surface('Bus_detail_rubber',(.12,.17,.18),.92,0,.08)
    reflector=surface('Bus_lamp_reflector',(.70,.77,.79),.29,.65,.30)
    optic=surface('Bus_headlamp_optic',(.75,.85,.86),.23,0,.34)
    optic.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value=.18
    optic.surface_render_method='DITHERED';optic.use_backface_culling=True
    bulb=surface('Bus_headlamp_bulb',(.96,.90,.72),.40,0,.25)
    amber=surface('Bus_amber_optic',(.95,.49,.10),.25,0,.30)
    red=surface('Bus_red_optic',(.70,.12,.095),.25,0,.30)
    clear=surface('Bus_reverse_optic',(.78,.84,.80),.25,0,.30)
    jade=surface('Bus_body_paint',(.29,.61,.45),.42,0,.25)
    tyre_records=[continuous_tyre(bpy.data.objects[f'Wheel_{i}'],i,rubber_atlas)for i in range(4)]
    shell_record=formed_lower_shell(body,jade,bpy.data.materials['Cabin_ivory_enamel'],rubber,pixels)
    body_finish=refinish_shell(body,jade,bpy.data.materials['Cabin_ivory_enamel'],alloy,rubber,amber,pixels)
    for name in ['Door_jade_enamel','Rolled_arch_enamel']:
        bpy.data.materials[name].node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*srgb((.29,.61,.45)),1)
    bumper,grille=formed_front_fittings(jade,alloy,rubber)
    bpy.ops.object.select_all(action='DESELECT');body.select_set(True);bumper.select_set(True);bpy.context.view_layer.objects.active=body;bpy.ops.object.join()
    metal_parts=grille;rubber_parts=[];head_parts=[];rear_parts=[]
    body_tree=BVHTree.FromPolygons([body.matrix_world@v.co for v in body.data.vertices],[list(f.vertices)for f in body.data.polygons])
    housing_record=wheel_housings(body_tree,rubber)
    for arch_index in range(4):
        arch=bpy.data.objects[f'WheelArch_{arch_index}'];side=-1 if arch_index%2==0 else 1
        # Keep its accepted seven-point rolled section and radial wheel cut.
        # Only its mounting depth follows the newly faired painted sheet.
        for step in range(97):
            section=list(arch.data.vertices)[step*7:(step+1)*7];outer=section[0].co
            hit=body_tree.ray_cast(Vector((outer.x,side*1.15,outer.z)),Vector((0,-side,0)),.55)[0]
            if hit is None:raise RuntimeError(f'New shell lacks arch mount {arch_index}/{step}')
            shift=hit.y+side*.001-outer.y
            for vertex in section:vertex.co.y+=shift
        arch.data.update()
    for index,side in enumerate([-1,1]):
        centre=Vector((2.220,side*.684,.724));axis=(1,0,0)
        gasket=revolve('HeadlampGasket',centre,axis,[(.113,-.002),(.135,-.002),(.135,.007),(.113,.007)],rubber,48)
        for vertex in gasket.data.vertices:
            if abs(vertex.co.x-(centre.x-.002))>.00001:continue
            hit=body_tree.ray_cast(Vector((2.6,vertex.co.y,vertex.co.z)),Vector((-1,0,0)),.60)[0]
            if hit is not None:vertex.co.x=hit.x-.002
        gasket.data.update();rubber_parts.append(gasket)
        metal_parts.append(revolve('HeadlampBezel',centre,axis,[(.113,.002),(.132,.002),(.132,.012),(.126,.022),(.115,.022),(.113,.011)],alloy,48))
        head_parts.append(revolve('HeadlampReflector',centre,axis,[(.00001,-.016),(.108,-.016),(.113,.013),(.111,.022),(.090,.010),(.055,-.008),(.00001,-.012)],reflector,40))
        head_parts.append(pin('HeadlampBulb',centre+Vector((.006,0,0)),axis,.010,.014,bulb,16))
        # One thin convex alpha surface per lamp, no transparent backing cap.
        # The bowl and small non-emissive bulb stay readable through the lens.
        radii=[.023,.045,.067,.086,.101,.109];verts=[centre+Vector((.03015,0,0))]
        for r in radii:
            for j in range(48):
                a=math.tau*j/48;y=r*math.cos(a);z=r*math.sin(a)
                d=.020+.010*(1-(r/.11)**2)+.00015*math.cos(y/.045*math.tau)
                verts.append(centre+Vector((d,y,z)))
        faces=[(0,1+j,1+(j+1)%48)for j in range(48)]
        for row in range(len(radii)-1):
            for j in range(48):faces.append((1+row*48+j,1+row*48+(j+1)%48,1+(row+1)*48+(j+1)%48,1+(row+1)*48+j))
        lens=solid('HeadlampOptic',verts,faces,[optic]);bm=bmesh.new();bm.from_mesh(lens.data)
        for face in bm.faces:
            if face.normal.x<0:face.normal_flip()
        bm.to_mesh(lens.data);bm.free();head_parts.append(lens)
        for a in [math.pi/2,math.pi*7/6,math.pi*11/6]:
            metal_parts.append(pin('BezelScrew',centre+Vector((.021,.123*math.cos(a),.123*math.sin(a))),axis,.004,.004,alloy,8))
        # A continuous curved housing wraps around the original rear corner.
        path=[(-2.253,side*.703,.802),(-2.253,side*.830,.802)]
        path.extend([(-2.180-.073*math.cos(a),side*(.830+.073*math.sin(a)),.802)for a in np.linspace(.1,math.pi/2,7)])
        path.append((-2.075,side*.903,.802))
        rubber_parts.append(fitted_corner_ribbon('RearLampHousing',path,.244,.018,.009,rubber,body_tree))
        for height,span,mat in [(.860,.078,red),(.770,.065,amber),(.711,.030,clear)]:
            lens_path=[(x-.005,y+side*.005,height)for x,y,z in path]
            rear_parts.append(fitted_corner_ribbon('RearLampLens',lens_path,span,.015,.018,mat,body_tree))
            for shift in [-span*.24,span*.24]:rear_parts.append(fitted_corner_ribbon('OpticRib',[(x-.008,y+side*.008,height+shift)for x,y,z in path],.003,.003,.026,mat,body_tree))
        for marker_y in [side*.676]:
            marker_body=body_tree.ray_cast(Vector((2.6,marker_y,.548)),Vector((-1,0,0)),.60)[0]
            marker_x=marker_body.x if marker_body is not None else 2.217
            signal_mount=block('FrontSignalGasket',(marker_x+.010,marker_y,.548),(.020,.174,.058),rubber,.006)
            signal_lens=block('FrontSignalLens',(marker_x+.023,marker_y,.548),(.012,.157,.042),amber,.006)
            for part in [signal_mount,signal_lens]:
                for vertex in part.data.vertices:
                    world=part.matrix_world@vertex.co;hit=body_tree.ray_cast(Vector((2.6,world.y,world.z)),Vector((-1,0,0)),.60)[0]
                    if hit is not None:vertex.co.x+=hit.x-marker_x
                part.data.update()
            rubber_parts.append(signal_mount);rear_parts.append(signal_lens)
    # Existing panel intersections supply the curve; the trim never floats at
    # a guessed constant side offset or cuts the accepted painted body.
    tree=BVHTree.FromPolygons([body.matrix_world@v.co for v in body.data.vertices],[list(f.vertices)for f in body.data.polygons])
    for side in [-1,1]:
        marker=[]
        for x in np.linspace(2.045,2.17,8):
            hit=tree.ray_cast(Vector((x,side*1.15,.706)),Vector((0,-side,0)),.40)[0]
            if hit is not None:marker.append((x,hit.y+side*.007,.706))
        if len(marker)>4:
            rubber_parts.append(ribbon('CornerSignalGasket',marker,.064,.014,rubber))
            rear_parts.append(ribbon('CornerSignalLens',[(x,y+side*.004,z)for x,y,z in marker],.046,.013,amber))
    trim_paths=[]
    for side in [-1,1]:
        ranges=[(-1.99,.555),(1.29,2.00)]if side==-1 else[(-1.99,2.00)]
        for start,end in ranges:
            path=[]
            for x in np.linspace(start,end,max(10,int((end-start)/.10))):
                hit=tree.ray_cast(Vector((x,side*1.13,1.052)),Vector((0,-side,0)),.48)[0]
                if hit is not None:path.append((x,hit.y+side*.006,1.052))
            if len(path)>3:metal_parts.append(ribbon('WaistMoulding',path,.012,.008,alloy));trim_paths.append(len(path))
    for end in [-1,1]:
        path=[];strip_height=.468 if end==1 else .416
        for y in np.linspace(-.72,.72,24):
            hit=tree.ray_cast(Vector((end*2.6,y,strip_height)),Vector((-end,0,0)),.8)[0]
            if hit is not None:path.append((hit.x+end*.005,y,strip_height))
        if len(path)>3:rubber_parts.append(ribbon('BumperContactStrip',path,.027,.010,rubber))
    batch('BusExteriorMetal',metal_parts);batch('BusExteriorRubber',rubber_parts)
    batch('HeadlampFinish',head_parts);batch('RearLampFinish',rear_parts)
    for index in range(4):wheel_hub(index,bpy.data.objects[f'Wheel_{index}'],steel,rubber,alloy)
    for index,(hinge,direction)in enumerate([(.613,1),(1.197,-1)]):
        pieces=[];leaf=bpy.data.objects[f'DoorLeaf_{index}']
        for height in [.48,1.025]:
            pieces.append(pin('DoorHinge',(hinge,-.842,height),(0,0,1),.011,.074,alloy,12))
            pieces.append(block('HingeLeaf',(hinge+direction*.029,-.850,height),(.052,.014,.050),alloy,.004))
            for shift in [-.015,.015]:pieces.append(pin('HingeScrew',(hinge+direction*.036,-.861,height+shift),(0,-1,0),.0035,.004,alloy,8))
        centre=hinge+direction*.144
        for height in [.942,1.126]:pieces.append(block('HandleFoot',(centre,-.863,height),(.044,.026,.040),alloy,.008))
        latch_x=.879 if index==0 else .931
        pieces.append(block('LatchPlate',(latch_x,-.870,.962),(.036,.009,.072),alloy,.005))
        pieces.append(pin('LatchPin',(latch_x,-.879,.962),(0,-1,0),.007,.011,alloy,12))
        batch(f'DoorHardware_{index}',pieces,leaf)
    return {'method':'source geometry and separated PBR finish; single-layer view-dependent window shader',
            'added_groups':['BusExteriorMetal','BusExteriorRubber','BusWheelHousings','HeadlampFinish','RearLampFinish','HubFinish_0','HubFinish_1','HubFinish_2','HubFinish_3','DoorHardware_0','DoorHardware_1'],
            'inner_wings':housing_record,
            'body_finish':body_finish,'formed_lower_shell':shell_record,'continuous_tyres':tyre_records,'waist_curve_samples':trim_paths,'headlamp_centres_blender':[[2.220,-.684,.724],[2.220,.684,.724]],
            'extra_lights':0,'headlamp_single_layer_lenses':2,'window_panes':13,'motion_parents_preserved':True,
            'materials':{m.name:{'roughness':m.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value,'metallic':m.node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value}for m in bpy.data.materials if m.use_nodes and m.node_tree.nodes.get('Principled BSDF')}}
