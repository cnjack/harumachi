"""Remove detached reconstruction debris before measuring a dessert's standing plane.
The untouched Pixal3D result remains alongside the cleaned authoring input.
"""
import bpy,bmesh,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
src=ROOT/'art/models/raw/inhabited_places_20261010/B15_fruit_tart.glb'
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(src))
report=[]
for ob in [o for o in bpy.context.scene.objects if o.type=='MESH']:
    bpy.context.view_layer.objects.active=ob;ob.select_set(True)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=max(ob.dimensions)*.0002)
    bm.faces.ensure_lookup_table();seen=set();islands=[]
    for face in bm.faces:
        if face.index in seen:continue
        stack=[face];seen.add(face.index);component=[]
        while stack:
            current=stack.pop();component.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.index not in seen:seen.add(other.index);stack.append(other)
        islands.append(component)
    biggest=max(len(x) for x in islands)
    removed=[f for component in islands if len(component)<biggest*.002 for f in component]
    bounds=[]
    for component in sorted(islands,key=len,reverse=True):
        vertices={v for f in component for v in f.verts}
        bounds.append({'faces':len(component),'min':[min(v.co[a] for v in vertices) for a in range(3)],'max':[max(v.co[a] for v in vertices) for a in range(3)]})
    main_bounds=bounds[0]
    front_limit=main_bounds['min'][1]-(main_bounds['max'][0]-main_bounds['min'][0])*.035
    shadow_faces=[]
    for component in islands:
        if len(component)>biggest*.10:continue
        if min(v.co.y for f in component for v in f.verts)<front_limit:shadow_faces.extend(component)
    removed=list(set(removed+shadow_faces))
    report.append({'node':ob.name,'components':bounds,'removed_faces':len(removed),'detached_front_shadow_limit_y':front_limit,'shadow_faces':len(shadow_faces)})
    if removed:bmesh.ops.delete(bm,geom=removed,context='FACES')
    loose=[v for v in bm.verts if not v.link_faces]
    if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
    bm.to_mesh(ob.data);bm.free()
bpy.ops.export_scene.gltf(filepath=str(src.with_stem(src.stem+'_clean')),export_format='GLB')
(ROOT/'evidence/inhabited_places_20261010/dessert-cleanup.json').write_text(json.dumps(report,indent=2)+'\n')
