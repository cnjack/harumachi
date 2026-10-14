"""Independent rays through the actual GLB cavity and thin transparent panels.

This offline gate does not replace native renderer/stock visibility acceptance.
"""
from pathlib import Path
import argparse,json,sys,hashlib
import numpy as np
from model_audit import primitives
from edit_model_atlas import load
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();g,b=load(a.input);items=list(primitives(g,b));allv=np.concatenate([v for _,v,_,_ in items]);lo=allv.min(0);size=allv.max(0)-lo;target=np.array([1.34,1.149,.75]);opaque=[];panes=[]
 for primitive,v,idx,uv in items:
  v=(v-lo)/size*target-target*np.array([.5,0,.5]);mat=g['materials'][primitive.get('material',0)];alpha=mat.get('pbrMetallicRoughness',{}).get('baseColorFactor',[1,1,1,1])[3]
  if mat.get('alphaMode','OPAQUE')=='BLEND' and .02<alpha<=.2:
   panes.append(dict(node=primitive['_node_name'],alpha=alpha,size=(v.max(0)-v.min(0)).tolist()))
  else:opaque.append(v[idx])
 faces=np.concatenate(opaque);v0=faces[:,0];e1=faces[:,1]-v0;e2=faces[:,2]-v0
 def hit(origin,direction,limit=2.):
  origin=np.array(origin);direction=np.array(direction);h=np.cross(np.broadcast_to(direction,e2.shape),e2);det=np.einsum('ij,ij->i',e1,h);valid=np.abs(det)>1e-9;inv=np.divide(1,det,out=np.zeros_like(det),where=valid);s=origin-v0;u=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=inv*(q@direction);t=inv*np.einsum('ij,ij->i',e2,q);good=valid&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(t>=0)&(t<=limit)
  if not good.any():return None
  return (origin+direction*t[good].min()).tolist()
 front=[];side=[];heights=[.66,.71,.77,.91,.98,1.04]
 for y in heights:
  for x in np.linspace(-.50,.50,11):
   found=hit([x,y,.6],[0,0,-1],1.2)
   if found is not None:front.append(dict(origin=[float(x),y,.6],hit=found))
  for z in np.linspace(-.24,.24,5):
   found=hit([.8,y,z],[-1,0,0],1.6)
   if found is not None:side.append(dict(origin=[.8,y,float(z)],hit=found))
 support=[]
 for level in [.60,.84]:
  for x in [-.45,0,.45]:
   for z in [-.20,0,.20]:
    found=hit([x,level+.009,z],[0,-1,0],.03)
    if found is None or abs(found[1]-level)>.004:support.append(dict(level=level,x=x,z=z,hit=found))
 checks={'five_independent_thin_transparent_panes':len(panes)==5 and len({p['node'] for p in panes})==5 and all(abs(min(p['size'])-.006)<.0003 for p in panes),'front_cavity_clear_of_opaque_panels':not front,'side_cavity_clear_of_opaque_panels':not side,'eighteen_actual_shelf_support_probes':not support}
 report=dict(passed=all(checks.values()),input=str(a.input),sha256=hashlib.sha256(a.input.read_bytes()).hexdigest(),checks=checks,panes=panes,front_rays=66,front_blocked=front,side_rays=30,side_blocked=side,support_probes=18,support_failures=support,native_acceptance=False)
 a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(dict(passed=report['passed'],checks=checks,front_blocked=len(front),side_blocked=len(side),support_failures=len(support))));sys.exit(0 if report['passed'] else 1)
if __name__=='__main__':main()
