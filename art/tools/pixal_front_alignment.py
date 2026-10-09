"""Measure a rigid yaw correction from rectangular prop feet, not PCA."""
import bpy,json,sys,math
import numpy as np
from pathlib import Path
from mathutils import Matrix
sys.path.insert(0,str(Path(__file__).parent))
from level_util import squareness
ROOT=Path(__file__).resolve().parents[2];report={}
for aid in sys.argv[sys.argv.index('--')+1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(ROOT/f'game/assets/models/{aid}.glb'))
    points=np.array([(o.matrix_world@v.co)[:] for o in bpy.context.scene.objects if o.type=='MESH' for v in o.data.vertices])
    angle,fill=squareness(points);candidates=[]
    for correction in [-angle,angle]:
        m=np.array(Matrix.Rotation(math.radians(correction),3,'Z'));left,ratio=squareness(points@m.T);candidates.append((abs(left),correction,left))
    chosen=min(candidates)
    report[aid]={'old_square_deg':angle,'rect_fill':fill,'correction_deg':chosen[1],'corrected_square_deg':chosen[2]}
(ROOT/'evidence/windows3d_20261003/front-alignment.json').write_text(json.dumps(report,indent=2)+'\n');print(report)
