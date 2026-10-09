"""Remove temporary baking attributes from retained material outputs."""
import bpy,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]/'art/models/raw/material_detail_20261003'
for aid in sys.argv[sys.argv.index('--')+1:]:
    bpy.ops.wm.open_mainfile(filepath=str(root/f'{aid}.blend'))
    for ob in bpy.context.scene.objects:
        if ob.type!='MESH':continue
        attr=ob.data.color_attributes.get('Facade_visibility')
        if attr:ob.data.color_attributes.remove(attr)
    bpy.ops.wm.save_as_mainfile(filepath=str(root/f'{aid}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(root/f'{aid}.glb'),export_format='GLB',export_yup=True,export_apply=True,export_image_format='JPEG',export_jpeg_quality=96)
