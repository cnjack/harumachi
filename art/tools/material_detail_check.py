"""Read-only proof that new atlases contain detail beyond an interpolated source.

Compare a discrete Laplacian at actual UV-covered triangle sample positions.
The input is bilinearly sampled at the output's pixel step, so a plain upsample
would have near-zero added residual. This diagnoses authored raster changes;
it cannot replace visual review of alignment or meaningful architectural detail.
"""
import io,json,sys,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
from edit_model_atlas import load
from model_audit import primitives

ROOT=Path(__file__).resolve().parents[2]
def texture(g,b,name):
    mat=next(m for m in g['materials'] if m.get('name')==name)
    tex=mat['pbrMetallicRoughness']['baseColorTexture']['index']
    im=g['images'][g['textures'][tex]['source']];view=g['bufferViews'][im['bufferView']];start=view.get('byteOffset',0)
    return np.asarray(Image.open(io.BytesIO(b[start:start+view['byteLength']])).convert('RGB'),dtype=np.float32)/255

def sample(image,uv):
    h,w=image.shape[:2];x=np.clip(uv[:,0]*w-.5,0,w-1);y=np.clip(uv[:,1]*h-.5,0,h-1)
    x0=x.astype(int);y0=y.astype(int);x1=np.minimum(x0+1,w-1);y1=np.minimum(y0+1,h-1)
    fx=(x-x0)[:,None];fy=(y-y0)[:,None]
    return (image[y0,x0]*(1-fx)+image[y0,x1]*fx)*(1-fy)+(image[y1,x0]*(1-fx)+image[y1,x1]*fx)*fy

def run(before,after):
    ids=json.loads((ROOT/'art/models/model_quality_contracts.json').read_text())['building_density_px_m'];report={'models':{},'checks':{}}
    for aid in ids:
        oldg,oldb=load(before/f'{aid}.glb');g,b=load(after/f'{aid}.glb')
        # Every body uses the immutable provider's original UV map named model.
        uvpoints=[];weights=[]
        for p,v,idx,uv in primitives(g,b):
            mat=g['materials'][p.get('material',0)]
            if mat.get('name')!='model' or uv is None:continue
            tri=v[idx];area=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)*.5
            uvpoints.append(uv[idx].mean(1));weights.append(area)
        uvs=np.concatenate(uvpoints);areas=np.concatenate(weights)
        # Area-weighted deterministic samples include broad walls and roof.
        rng=np.random.default_rng(3403);indices=rng.choice(len(uvs),10000,p=areas/areas.sum(),replace=True);uvs=uvs[indices]
        old=texture(oldg,oldb,'model');new=texture(g,b,'model');h,w=new.shape[:2]
        def lap(image):
            values=sample(image,uvs)*4
            for d in [[1/w,0],[-1/w,0],[0,1/h],[0,-1/h]]:values-=sample(image,uvs+np.array(d))
            return values
        old_lap=lap(old)
        residual=lap(new)-old_lap
        rms=float(np.sqrt(np.mean(residual**2)))
        # Read-only analytical control: bilinear interpolation followed by the
        # actual export JPEG quality, held in memory and never saved as an asset.
        control_image=Image.fromarray((old*255).astype('uint8')).resize((w,h),Image.Resampling.BILINEAR)
        buffer=io.BytesIO();control_image.save(buffer,format='JPEG',quality=92)
        control=np.asarray(Image.open(io.BytesIO(buffer.getvalue())),dtype=np.float32)/255
        control_rms=float(np.sqrt(np.mean((lap(control)-old_lap)**2)))
        report['models'][aid]={'samples':10000,'added_pixel_laplacian_rms':rms,'interpolated_jpeg_control_rms':control_rms,'source_size':[old.shape[1],old.shape[0]],'output_size':[w,h],'passed':rms>max(.002,control_rms*1.15),'sha256':hashlib.sha256((after/f'{aid}.glb').read_bytes()).hexdigest(),'source_mtime':(after/f'{aid}.glb').stat().st_mtime}
        del old,new
    report['checks']['authored_raster_detail']=all(m['passed'] for m in report['models'].values())
    report['method']='UV-covered area-weighted samples; compared against bilinear source at final texel step; visual acceptance separate'
    return report

if __name__=='__main__':
    before,after,out=map(Path,sys.argv[1:4]);r=run(before,after);out.write_text(json.dumps(r,indent=2)+'\n');print('MATERIAL_DETAIL',r['checks'],{k:round(m['added_pixel_laplacian_rms'],5) for k,m in r['models'].items()})
    sys.exit(0 if all(r['checks'].values()) else 1)
