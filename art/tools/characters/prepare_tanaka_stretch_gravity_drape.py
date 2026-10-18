#!/usr/bin/env python3
"""Rebuild Tanaka stretch sleeves with a broad, physical-ring gravity guide.

The sleeve circumference moves together perpendicular to the blended actual
upper/forearm axis. This keeps the broad coat section while moving its hanging
centre towards gravity. It is not a nearest-skin fit or a single crest clamp.
A boundary-distance taper pins shoulder/bare-skin joins; mild Taubin geometry
fairing rounds the existing cross section. Only four existing stretch P/N fields
are replaced by the shared writer; all bone curves/base/other fields stay exact.
Native acceptance is required after the offline whole-surface checks.
"""
import os
for key in ['OPENBLAS_NUM_THREADS','OMP_NUM_THREADS','VECLIB_MAXIMUM_THREADS']:os.environ[key]='1'
import argparse,heapq,json
from pathlib import Path
import numpy as np
from scipy.sparse import coo_matrix,diags
import prepare_tanaka_stretch_cap_fairing as writer


def smooth(x):
 x=np.clip(x,0,1);return x*x*(3-2*x)


def guide(s,d,world,posed,rgb,faces,groups,count,physical_edges,drop,feather):
 ng=len(count);P=np.zeros((ng,3));np.add.at(P,groups,posed);P/=count[:,None];names=[d['nodes'][j]['name'] for j in s['skin']['joints']];ids={n.get('name'):i for i,n in enumerate(d['nodes'])};blue=(rgb[:,2]>rgb[:,0]*1.08)&(rgb[:,2]>rgb[:,1]*1.01);shift=np.zeros_like(P);out=[];u,v=physical_edges.T;graph=coo_matrix((np.ones(2*len(u)),(np.r_[u,v],np.r_[v,u])),shape=(ng,ng)).tocsr();degree=np.asarray(graph.sum(1)).ravel();average=diags(1/np.maximum(degree,1))@graph
 for side,sign in [('Left',1),('Right',-1)]:
  a,e,w=[world[ids['mixamorig:'+side+x]][:3,3]for x in ['Arm','ForeArm','Hand']];upper=np.linalg.norm(e-a);fore=np.linalg.norm(w-e);U=(e-a)/upper;F=(w-e)/fore;raised=float(smooth(((w-e)[1]/fore-.1)/.35));share_mask=np.array([n.startswith('mixamorig:'+side+'Arm') or n.startswith('mixamorig:'+side+'ForeArm') or n=='TWIST_'+side for n in names]);share=(s['weights']*share_mask[s['joints']]).sum(1);allowed=blue&(share>.5)&(sign*s['positions'][:,0]>.18);allowed=np.bincount(groups,weights=allowed,minlength=ng)==count
  arc,centre,radius=writer.projection(P,a,e,w);allowed&=(arc>upper*.25)&(arc<upper+fore*.82);boundary=np.zeros(ng,bool);cross=allowed[u]!=allowed[v];boundary[np.unique(physical_edges[cross])]=True;boundary&=allowed;free=allowed&~boundary
  adj=[[]for _ in range(ng)]
  for aa,bb in physical_edges:
   if allowed[aa] and allowed[bb]:
    length=float(np.linalg.norm(P[aa]-P[bb]));adj[aa].append((int(bb),length));adj[bb].append((int(aa),length))
  dist=np.full(ng,np.inf);dist[boundary]=0.;queue=[(0.,int(x))for x in np.flatnonzero(boundary)];heapq.heapify(queue)
  while queue:
   value,at=heapq.heappop(queue)
   if value!=dist[at]:continue
   for to,length in adj[at]:
    candidate=value+length
    if candidate<dist[to]:dist[to]=candidate;heapq.heappush(queue,(candidate,to))
  blend=smooth((arc/upper-.65)/.5);axis=U*(1-blend[:,None])+F*blend[:,None];axis/=np.maximum(np.linalg.norm(axis,axis=1,keepdims=True),1e-12);gravity=np.tile([0.,-1.,0.],(ng,1));gravity-=axis*(axis@np.array([0.,-1.,0.]))[:,None];gravity/=np.maximum(np.linalg.norm(gravity,axis=1,keepdims=True),1e-12)
  gain=raised*smooth((arc/upper-.3)/.4)*smooth((upper+fore*.82-arc)/(fore*.25))*smooth(dist/feather);gain[~free]=0
  desired=gravity*(drop*gain)[:,None]
  # Fair the entire local sleeve cross section rather than removing its single
  # highest point. Only radial displacement is retained; wrist/shoulder joins pin.
  fair=P.copy()
  for _ in range(4):
   for amount in [.35,-.36]:
    change=average@fair-fair;change-=axis*np.sum(change*axis,axis=1)[:,None];fair+=amount*change*gain[:,None];fair[~free]=P[~free]
  desired+=fair-P
  # Smooth only the displacement to avoid transmitting a material cut into skin.
  for _ in range(2):
   for amount in [.35,-.36]:
    desired+=amount*(average@desired-desired);desired[~free]=0
  shift+=desired
  out.append(dict(side=side,raise_factor=raised,free_physical_vertices=int(free.sum()),affected_physical_vertices=int((np.linalg.norm(desired,axis=1)>1e-9).sum()),gravity_sag_m=drop,boundary_geodesic_feather_m=feather,max_preinverse_world_delta_m=float(np.linalg.norm(desired,axis=1).max()),radial_section_radius_p50_m=float(np.median(radius[allowed]))if allowed.any() else 0.))
 return shift[groups],out


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--native-source',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--drop',type=float,default=.024);p.add_argument('--feather',type=float,default=.04);args=p.parse_args();writer.guide_field=guide;writer.build(args);report=json.loads(args.report.read_text());report.update(stage='tanaka-stretch-broad-gravity-guide',method=__doc__,tool_sha256=writer.sha(__file__),shared_exact_writer_sha256=writer.sha(writer.__file__),geometry_taubin_passes=4,displacement_taubin_passes=2);args.report.write_text(json.dumps(report,indent=2))
if __name__=='__main__':main()
