"""Inspect repaired GLBs with rest projections and actual skinned curl samples.

These are mathematical orthographic diagnostics, not game renderer screenshots.
The parent QA pass must additionally verify the candidate in Godot.
"""
from pathlib import Path
import argparse, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.spatial.transform import Rotation
from repair_joint_fit import P, PEOPLE, FINGERS, HANDS, load, read, parts, world_matrices, diagnose, hand_frame, hand_cloud

FONT='/System/Library/Fonts/Menlo.ttc'

def font(size):
    for candidate in [FONT,'/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']:
        try:return ImageFont.truetype(candidate,size)
        except OSError:pass
    return ImageFont.load_default(size=size)
COLORS=[(197,87,129),(209,143,60),(63,155,184),(115,109,202),(91,166,119)]


def render(draw, ps, center, right, up, depth, screen, scale, hand_side=None):
    faces=[]
    for p in ps:
        if p['name'].startswith('HiddenArm'):continue
        pp=p['xyz'];xy=screen+np.c_[(pp-center)@right,-(pp-center)@up]*scale
        ids=p['faces']
        if hand_side:
            family=p['dense'][:,[i for i,n in enumerate(p['names']) if n.startswith(P+hand_side+'Hand')]].sum(axis=1)
            ids=ids[(family[ids]>.5).all(axis=1)]
        tt=pp[ids];norm=np.cross(tt[:,1]-tt[:,0],tt[:,2]-tt[:,0]);norm/=np.maximum(np.linalg.norm(norm,axis=1)[:,None],1e-12)
        shade=np.clip(.78+.18*(norm@depth),.55,.97)
        color=np.tile(np.array([158.,178.,195.]),(len(ids),1))
        if hand_side:
            fingerweights=np.array([p['dense'][:,[i for i,n in enumerate(p['names']) if n.startswith(P+hand_side+'Hand'+f)]].sum(axis=1) for f in FINGERS]).T
            shares=fingerweights[ids].mean(axis=1);best=shares.argmax(axis=1)
            for k,c in enumerate(COLORS): color[(best==k)&(shares.max(axis=1)>.3)]=c
        for face,z,sh,c in zip(ids,tt.mean(axis=1)@depth,shade,color):faces.append((z,xy[face],tuple((c*sh).astype(int))))
    for z,poly,color in sorted(faces,key=lambda x:x[0]):draw.polygon([tuple(v) for v in poly],fill=color)


def five_views(doc,blob,path,label):
    ps=parts(doc,blob);world,parents=world_matrices(doc,blob);points=np.concatenate([p['xyz'] for p in ps]);center=(points.min(axis=0)+points.max(axis=0))*.5;H=np.ptp(points[:,1]);W=400;HH=650
    canvas=Image.new('RGB',(W*5,HH),'#f5f7fa');draw=ImageDraw.Draw(canvas);text_font=font(14)
    views=[('FRONT',[1,0,0],[0,1,0],[0,0,1]),('BACK',[-1,0,0],[0,1,0],[0,0,-1]),('LEFT',[0,0,-1],[0,1,0],[1,0,0]),('RIGHT',[0,0,1],[0,1,0],[-1,0,0]),('TOP',[1,0,0],[0,0,-1],[0,1,0])]
    for vi,(name,r,u,z) in enumerate(views):
        r,u,z=map(np.array,[r,u,z]);screen=np.array([W*(vi+.5),HH*.52]);scale=min(540/H,350/max(np.ptp(points[:,0]),np.ptp(points[:,2])))
        render(draw,ps,center,r,u,z,screen,scale)
        def project(p):return screen+np.array([(p-center)@r,-(p-center)@u])*scale
        for i,node in enumerate(doc['nodes']):
            nm=node.get('name','')
            if not nm.startswith(P) or i not in parents:continue
            parent=parents[i]
            if not doc['nodes'][parent].get('name','').startswith(P):continue
            a=project(world[parent][:3,3]);b=project(world[i][:3,3]);draw.line([tuple(a),tuple(b)],fill='#04abc1',width=2)
            x,y=b;rad=2 if 'Hand' in nm else 3;draw.ellipse((x-rad,y-rad,x+rad,y+rad),fill='#ef3d7b')
        draw.text((vi*W+14,14),label+' / '+name,font=text_font,fill='#223344')
        draw.text((vi*W+10,HH-44),'GLB geometry / bones through shell',font=text_font,fill='#446078')
        draw.text((vi*W+10,HH-24),'Not a Godot screenshot',font=text_font,fill='#446078')
    canvas.save(path)


def curl_world(doc,blob,side,amount):
    rest,_=world_matrices(doc,blob);names={n.get('name'):i for i,n in enumerate(doc['nodes'])};wrist,axis,cross,normal=hand_frame(doc,rest,names,side,hand_cloud(parts(doc,blob,rest),side));rotations={}
    for finger in FINGERS:
        for k,factor in zip([1,2,3],[1,.8,.6]):
            i=names[P+side+'Hand'+finger+str(k)]
            j=names[P+side+'Hand'+finger+str(k+1)] if k<3 else None
            direction=(rest[j][:3,3]-rest[i][:3,3]) if j else rest[i][:3,:3]@np.array([0,1,0])
            # The metadata normal points out of the palm. Positive curl must
            # move the next phalanx toward that surface, as current_motion.py
            # does. The opposite sign is hyperextension, not a grip sample.
            axis=np.cross(direction,normal);axis/=np.linalg.norm(axis)
            assert np.dot(np.cross(axis,direction),normal)>0,'curl axis points away from palm'
            local_axis=np.linalg.inv(rest[i][:3,:3])@axis;local_axis/=np.linalg.norm(local_axis)
            rotations[i]=(Rotation.from_quat(doc['nodes'][i].get('rotation',[0,0,0,1]))*Rotation.from_rotvec(local_axis*math.radians(amount*factor))).as_quat()
    return world_matrices(doc,blob,rotations=rotations)[0]


def animated_parts(doc,blob,animation,time):
    """Apply the actual clip's morphs as well as its bone transforms."""
    world,_=world_matrices(doc,blob,animation,time);ps=parts(doc,blob,world)
    for part in ps:
        node=doc['nodes'][part['node']];mesh=doc['meshes'][node['mesh']]
        count=len(part['primitive'].get('targets',[]))
        if not count:continue
        values=np.array(node.get('weights',mesh.get('weights',[0]*count)),float)
        for channel in animation['channels']:
            if channel['target']!={'node':part['node'],'path':'weights'}:continue
            sampler=animation['samplers'][channel['sampler']];times=read(doc,blob,sampler['input']).ravel();output=read(doc,blob,sampler['output']).reshape(-1,count)
            assert sampler.get('interpolation','LINEAR')=='LINEAR'
            values=np.array([np.interp(time,times,output[:,i]) for i in range(count)])
        delta=np.zeros_like(part['raw'])
        for value,target in zip(values,part['primitive']['targets']):
            if abs(value)>1e-10:delta+=value*read(doc,blob,target['POSITION'])
        if not np.any(delta):continue
        skin=doc['skins'][node['skin']];bind=read(doc,blob,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
        matrix=np.array([world[j]@ib for j,ib in zip(skin['joints'],bind)])
        part['xyz']+=np.sum(np.einsum('nvij,nj->nvi',matrix[part['ids'],:3,:3],delta)*part['weights'][:,:,None],axis=1)
    return ps


def hand_views(before,after,path,side,label):
    bd,bb=before;ad,ab=after;rest,_=world_matrices(ad,ab);names={n.get('name'):i for i,n in enumerate(ad['nodes'])};wrist,axis,cross,normal=hand_frame(ad,rest,names,side,hand_cloud(parts(ad,ab,rest),side))
    candidates=[(bd,bb,world_matrices(bd,bb)[0],'BEFORE REST'),(ad,ab,rest,'AFTER REST'),(ad,ab,curl_world(ad,ab,side,35),'AFTER CURL 35'),(ad,ab,curl_world(ad,ab,side,65),'AFTER CURL 65')]
    W=450;HH=500;canvas=Image.new('RGB',(W*4,HH*2),'#f5f7fa');draw=ImageDraw.Draw(canvas);text_font=font(15)
    # Original hand frame keeps all panels directly comparable.
    for ci,(d,b,world,title) in enumerate(candidates):
        ps=parts(d,b,world)
        cloud=np.concatenate([p['xyz'][p['dense'][:,[i for i,n in enumerate(p['names']) if n.startswith(P+side+'Hand')]].sum(axis=1)>.5] for p in ps])
        radius=max(np.linalg.norm(cloud-wrist,axis=1).max(),.1);scale=320/max(radius,.115)
        for row,(right,up,depth,view) in enumerate([(cross,axis,normal,'PALM'),(normal,axis,-cross,'SIDE')]):
            screen=np.array([W*(ci+.5),HH*(row+1)-70]);center=wrist+axis*.015
            render(draw,ps,center,right,up,depth,screen,scale,side)
            def project(v):return screen+np.array([(v-center)@right,-(v-center)@up])*scale
            for i,node in enumerate(d['nodes']):
                nm=node.get('name','')
                if not nm.startswith(P+side+'Hand') or nm==P+side+'Hand':continue
                p=project(world[i][:3,3]);x,y=p;draw.ellipse((x-3,y-3,x+3,y+3),fill='#ef3d7b',outline='white')
            draw.text((ci*W+10,row*HH+10),label+' '+side+' '+view,font=text_font,fill='#223344');draw.text((ci*W+10,row*HH+32),title,font=text_font,fill='#223344')
    canvas.save(path)


def authored_hand_views(before,after,path,side,label):
    """Compare actual authored clips in a common hand frame, without arm pose."""
    states=[]
    for source,(doc,blob) in zip(['SOURCE','REPAIRED'],[before,after]):
        names={n.get('name'):i for i,n in enumerate(doc['nodes'])}
        rest,_=world_matrices(doc,blob);hand=names[P+side+'Hand']
        for clip,phase in [('idle',0),('wave',.875)]:
            animation=next(a for a in doc['animations'] if a['name']==clip)
            duration=max(float(read(doc,blob,s['input']).max()) for s in animation['samplers'])
            pose,_=world_matrices(doc,blob,animation,duration*phase)
            ps=animated_parts(doc,blob,animation,duration*phase);normalize=rest[hand]@np.linalg.inv(pose[hand])
            for part in ps:
                part['xyz']=(np.c_[part['xyz'],np.ones(len(part['xyz']))]@normalize.T)[:,:3]
            states.append((ps,source+' '+clip+' '+str(phase)))
    doc,blob=after;names={n.get('name'):i for i,n in enumerate(doc['nodes'])};rest,_=world_matrices(doc,blob)
    wrist,axis,cross,normal=hand_frame(doc,rest,names,side,hand_cloud(parts(doc,blob),side))
    canvas=Image.new('RGB',(1800,1000),'#f5f7fa');draw=ImageDraw.Draw(canvas);text_font=font(15)
    for column,(ps,title) in enumerate(states):
        for row,(right,up,depth,view) in enumerate([(cross,axis,normal,'PALM'),(normal,axis,-cross,'SIDE')]):
            render(draw,ps,wrist+axis*.015,right,up,depth,np.array([450*(column+.5),500*(row+1)-60]),2600,side)
            draw.text((450*column+10,500*row+10),label+' '+side+' '+view,font=text_font,fill='#223344')
            draw.text((450*column+10,500*row+32),title,font=text_font,fill='#223344')
            draw.text((450*column+10,500*(row+1)-22),'Actual GLB clip / CPU skinning',font=font(12),fill='#446078')
    canvas.save(path)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--before-dir',type=Path,required=True);parser.add_argument('--after-dir',type=Path,required=True);parser.add_argument('--output-dir',type=Path,required=True);parser.add_argument('--characters',nargs='+',choices=PEOPLE,default=PEOPLE);parser.add_argument('--skip-hands',action='store_true');parser.add_argument('--authored-only',action='store_true');args=parser.parse_args();args.output_dir.mkdir(parents=True,exist_ok=True)
    for who in args.characters:
        before=load(args.before_dir/('CH_'+who+'.glb'));after=load(args.after_dir/('CH_'+who+'.glb'))
        if not args.authored_only:
            five_views(*before,args.output_dir/(who+'-before-five-views.png'),who.upper()+' BEFORE')
            five_views(*after,args.output_dir/(who+'-after-five-views.png'),who.upper()+' AFTER')
        for side in ([] if args.skip_hands else HANDS.get(who,[])):
            if not args.authored_only:hand_views(before,after,args.output_dir/(who+'-'+side.lower()+'-curl.png'),side,who.upper())
            authored_hand_views(before,after,args.output_dir/(who+'-'+side.lower()+'-authored.png'),side,who.upper())
        print(who,flush=True)


if __name__=='__main__':main()
