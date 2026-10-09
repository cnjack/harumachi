"""Restore readable timber, real shelves and thin glazing within the accepted cabinet bounds."""
import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
folder=ROOT/'art/models/raw/I02_cake_showcase_clear_20261006';folder.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
def material(name,colour):
    value=bpy.data.materials.new(name);value.diffuse_color=(*colour,1);value.use_nodes=True
    shader=value.node_tree.nodes['Principled BSDF'];shader.inputs['Base Color'].default_value=(*colour,1);shader.inputs['Roughness'].default_value=1;shader.inputs['Specular IOR Level'].default_value=0
    return value
wood=material('Painted_cedar',(.44,.25,.12));cream=material('Warm_ivory',(.91,.86,.73));glass=material('Thin_glazing',(.73,.86,.90))
def box(name,size,at,mat):
    # Author directly in Godot coordinates, then convert to Blender's Z-up axes.
    bpy.ops.mesh.primitive_cube_add(size=1,location=(at[0],-at[2],at[1]));obj=bpy.context.object;obj.name=name;obj.dimensions=(size[0],size[2],size[1]);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);obj.data.materials.append(mat);return obj
w,d,h=1.34,.744,1.149
box('CabinetBase',(w,.52,d),(0,.26,0),wood)
box('InsetFront',(w-.13,.38,.015),(0,.28,d/2+.001),cream)
for side in [-1,1]:
    for end in [-1,1]:box(f'Post_{side}_{end}',(.035,h-.52,.035),(side*(w/2-.022),(h+.52)/2,end*(d/2-.022)),wood)
for index,y in enumerate([.56,.80]):box(f'Shelf_{index}',(w-.08,.027,d-.065),(0,y,0),cream)
box('TopRail',(w,.035,.045),(0,h-.018,d/2-.02),wood)
box('BackRail',(w,.035,.045),(0,h-.018,-d/2+.02),wood)
box('GlassFront',(w-.07,h-.565,.006),(0,(h+.555)/2,d/2-.011),glass)
for side in [-1,1]:box(f'GlassSide_{side}',(.006,h-.565,d-.05),(side*(w/2-.01),(h+.555)/2,0),glass)
box('GlassTop',(w-.06,.006,d-.05),(0,h-.009,0),glass)
bpy.ops.wm.save_as_mainfile(filepath=str(folder/'showcase.blend'))
bpy.ops.export_scene.gltf(filepath=str(folder/'ready.glb'),export_format='GLB',export_yup=True,export_apply=True,export_animations=False)
(folder/'construction.json').write_text(json.dumps({'preserved_size_godot_xyz':[w,h,d],'shelf_tops':[.5735,.8135],'source':'Blender reconstruction; original Pixal3D raw and exports retained as evidence','glass':'runtime shop_glass shader on named Glass nodes'},indent=2))
