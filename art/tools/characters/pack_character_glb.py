"""Losslessly compact character GLBs after authoring stages append accessors.

Floating point morph deltas use glTF sparse accessors; all decoded values and
embedded images are verified exactly. No quantization or mesh simplification.
"""
from pathlib import Path
import argparse,copy,hashlib,json
import numpy as np
from glb_io import load
from prepare_local_garments import read
from repair_head_neck import save


def pack(args):
    d,binary=load(args.input);b=bytearray(binary);before=copy.deepcopy(d);original=binary;sparse_count=0
    def view(data):
        b.extend(b'\0'*((-len(b))%4));i=len(d['bufferViews']);d['bufferViews'].append({'buffer':0,'byteOffset':len(b),'byteLength':len(data)});b.extend(data);return i
    for mesh in d.get('meshes',[]):
        for primitive in mesh['primitives']:
            for target in primitive.get('targets',[]):
                for field,old_index in list(target.items()):
                    a=copy.deepcopy(d['accessors'][old_index]);values=read(d,b,old_index);selected=np.flatnonzero(np.any(values!=0,axis=1));kind=np.uint16 if len(values)<=65536 else np.uint32
                    if len(selected)*(values.shape[1]*values.dtype.itemsize+np.dtype(kind).itemsize)>=values.nbytes*.7:continue
                    a.pop('bufferView',None);a.pop('byteOffset',None);a.pop('sparse',None)
                    if len(selected):a['sparse']={'count':len(selected),'indices':{'bufferView':view(selected.astype(kind).tobytes()),'componentType':5123 if kind==np.uint16 else 5125},'values':{'bufferView':view(values[selected].tobytes())}}
                    index=len(d['accessors']);d['accessors'].append(a);target[field]=index;sparse_count+=1
    # Keep standard glTF accessor references and explicit instancing attributes.
    pointers=[]
    for mesh in d.get('meshes',[]):
        for p in mesh['primitives']:
            for field in p.get('attributes',{}):pointers.append((p['attributes'],field))
            if 'indices' in p:pointers.append((p,'indices'))
            for target in p.get('targets',[]):
                for field in target:pointers.append((target,field))
            if 'KHR_draco_mesh_compression' in p.get('extensions',{}):raise ValueError('Draco binary references need a separate packer')
    for skin in d.get('skins',[]):
        if 'inverseBindMatrices' in skin:pointers.append((skin,'inverseBindMatrices'))
    for animation in d.get('animations',[]):
        active=sorted({c['sampler'] for c in animation['channels']});mapping={old:new for new,old in enumerate(active)};animation['samplers']=[animation['samplers'][old] for old in active]
        for c in animation['channels']:c['sampler']=mapping[c['sampler']]
        for sampler in animation['samplers']:pointers.extend([(sampler,'input'),(sampler,'output')])
    for node in d.get('nodes',[]):
        attributes=node.get('extensions',{}).get('EXT_mesh_gpu_instancing',{}).get('attributes',{})
        for field in attributes:pointers.append((attributes,field))
    active=sorted({owner[field] for owner,field in pointers});accessor_map={old:new for new,old in enumerate(active)};expected=[read(d,b,index) for index in active];d['accessors']=[d['accessors'][index] for index in active]
    for owner,field in pointers:owner[field]=accessor_map[owner[field]]
    views=[]
    for a in d['accessors']:
        if 'bufferView' in a:views.append((a,'bufferView'))
        if 'sparse' in a:views.extend([(a['sparse']['indices'],'bufferView'),(a['sparse']['values'],'bufferView')])
    for im in d.get('images',[]):
        if 'bufferView' in im:views.append((im,'bufferView'))
    active_views=sorted({owner[field] for owner,field in views});view_map={old:new for new,old in enumerate(active_views)};packed=bytearray();kept=[]
    for old in active_views:
        v=copy.deepcopy(d['bufferViews'][old]);start=v.get('byteOffset',0);blob=b[start:start+v['byteLength']];packed.extend(b'\0'*((-len(packed))%4));v['buffer']=0;v['byteOffset']=len(packed);packed.extend(blob);kept.append(v)
    d['bufferViews']=kept
    for owner,field in views:owner[field]=view_map[owner[field]]
    d['buffers']=[{'byteLength':len(packed)}];save(d,packed,args.output);after,newbinary=load(args.output);exact=all(np.array_equal(value,read(after,newbinary,index)) for index,value in enumerate(expected))
    def image_hashes(doc,blob):
        return [hashlib.sha256(blob[(v:=doc['bufferViews'][im['bufferView']]).get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]).hexdigest() for im in doc.get('images',[]) if 'bufferView' in im]
    images_exact=image_hashes(before,original)==image_hashes(after,newbinary);report={'input':str(args.input),'output':str(args.output),'input_bytes':args.input.stat().st_size,'output_bytes':args.output.stat().st_size,'sparse_target_accessors':sparse_count,'active_accessors':len(expected),'all_decoded_accessors_exact':exact,'embedded_images_exact':images_exact,'output_sha256':hashlib.sha256(args.output.read_bytes()).hexdigest()};args.report.write_text(json.dumps(report,indent=2));assert exact and images_exact;print(json.dumps(report))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--report',type=Path,required=True);pack(p.parse_args())
