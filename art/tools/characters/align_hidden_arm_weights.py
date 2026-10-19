"""Match existing sleeve-fill skin to adjacent real arm skin; geometry stays exact.

This is a diagnostic candidate tool. Apply only after the same-pose HiddenArm
visibility A/B confirms a fill tube is the protruding surface.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from scipy.spatial import cKDTree
from glb_io import load
from prepare_local_garments import read,colours
from repair_head_neck import append,save


def fit(args):
    d,binary=load(args.input);b=bytearray(binary);body_node=next(n for n in d['nodes'] if n.get('name')=='CharacterBody');body_skin=d['skins'][body_node['skin']];p=d['meshes'][body_node['mesh']]['primitives'][0];pos=read(d,b,p['attributes']['POSITION']);rgb=colours(d,b,p);j=read(d,b,p['attributes']['JOINTS_0']);w=read(d,b,p['attributes']['WEIGHTS_0'])
    if 'JOINTS_1' in p['attributes']:j=np.c_[j,read(d,b,p['attributes']['JOINTS_1'])];w=np.c_[w,read(d,b,p['attributes']['WEIGHTS_1'])]
    ids=body_skin['joints'];bone_names=[d['nodes'][i].get('name','') for i in ids];report={'input':str(args.input),'input_sha256':hashlib.sha256(args.input.read_bytes()).hexdigest(),'preserved':['all positions','all normals','UVs','textures','real CharacterBody weights','sleeve cloth weights','skeleton','animations'],'tubes':[]}
    for node in d['nodes']:
        if not node.get('name','').startswith('HiddenArm_'):continue
        side=node['name'].split('_')[-1];own=np.array([n in ['mixamorig:'+side+'Arm','mixamorig:'+side+'ForeArm','TWIST_'+side] for n in bone_names]);share=np.sum(w*own[j],axis=1);skin_hue=(rgb[:,0]>rgb[:,1]*1.07)&(rgb[:,0]>rgb[:,2]*1.15);select=np.flatnonzero(skin_hue&(share>.75));tree=cKDTree(pos[select]);target_skin=d['skins'][node['skin']];mapping={joint:i for i,joint in enumerate(target_skin['joints'])}
        for primitive in d['meshes'][node['mesh']]['primitives']:
            attrs=primitive['attributes'];tp=read(d,b,attrs['POSITION']);tj=read(d,b,attrs['JOINTS_0']);tw=read(d,b,attrs['WEIGHTS_0']);distance,nearest=tree.query(tp,k=min(12,len(select)));dense=np.zeros((len(tp),len(target_skin['joints'])))
            for vi in range(len(tp)):
                strength=np.exp(-((distance[vi]-distance[vi].min())/.012)**2);strength/=strength.sum()
                for source,amount in zip(select[nearest[vi]],strength):
                    for joint,weight in zip(j[source],w[source]):
                        if ids[int(joint)] in mapping:dense[vi,mapping[ids[int(joint)]]]+=float(weight*amount)
            old_dense=np.zeros_like(dense)
            for slot in range(tj.shape[1]):np.add.at(old_dense,(np.arange(len(tp)),tj[:,slot]),tw[:,slot])
            chosen=np.argsort(dense,axis=1)[:,-tj.shape[1]:][:,::-1];values=np.take_along_axis(dense,chosen,axis=1);values/=np.maximum(values.sum(1,keepdims=True),1e-9);attrs['JOINTS_0']=append(d,b,attrs['JOINTS_0'],chosen.astype(tj.dtype));attrs['WEIGHTS_0']=append(d,b,attrs['WEIGHTS_0'],values.astype(tw.dtype));report['tubes'].append({'mesh':node['name'],'vertices':len(tp),'source_visible_skin_vertices':len(select),'nearest_skin_distance_p95_m':float(np.percentile(distance[:,0],95)),'maximum_weight_change':float(np.abs(dense-old_dense).max())})
    save(d,b,args.output);report['output']=str(args.output);report['output_sha256']=hashlib.sha256(args.output.read_bytes()).hexdigest();args.report.write_text(json.dumps(report,indent=2));print(args.report)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--report',required=True,type=Path);fit(p.parse_args())
