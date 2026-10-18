#!/usr/bin/env python3
"""Prepare a new standalone Godot viewer from real generated/retargeted clips.

Copies only verified POC models, source-proxy positions and one Chinese font.
Does not run an engine, retarget a model, synthesize motions or write game/.
"""
from __future__ import annotations
import argparse, hashlib, json, math, shutil, struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
POC=ROOT/'art/poc/motionbricks_20261018'
IDS=['sora','ren','haru','mio','aoi','tanaka','kazuko']
LABELS={'elbow_crawl_recover':'肘撑爬行 · 转向 · 起身尝试','low_crouch_turn':'低姿潜行 · 连续180度转向','boxing_direction_changes':'拳击步态 · 多次变向','dance_full_turn':'舞步 · 360度转向','crawl_style_transition':'低姿 · 手撑 · 肘撑切换','asymmetric_recovery':'负伤 · 惊惧 · 舞步切换','idle':'静止','slow_walk':'慢走','walk':'行走','walk_left':'向左行走','walk_right':'向右行走','stealth_walk':'轻步潜行','walk_stealth':'低身潜行','injured_walk':'负伤步态','walk_happy_dance':'欢快舞步','walk_boxing':'拳击步态','hand_crawling':'手足爬行','walk_zombie':'僵尸步态'}

def sha(path):
 with Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def read(path):return json.loads(Path(path).read_text())
def write(path,data):Path(path).write_text(json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
def glb_doc(path):
 with Path(path).open('rb') as stream:
  header=stream.read(20);magic,version,total,length,kind=struct.unpack('<5I',header)
  assert magic==0x46546c67 and version==2 and kind==0x4e4f534a
  return json.loads(stream.read(length))
def safe_project(path):
 path=Path(path).resolve()
 if POC not in path.parents or path==POC:raise ValueError('Viewer project must be a new subdirectory of '+str(POC))
 if path.exists() and any(path.iterdir()):raise ValueError('Refuse to overwrite an existing viewer; choose a new --project path')
 return path

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--retargeted',type=Path,default=POC/'retargeted')
 p.add_argument('--project',type=Path,default=POC/'godot')
 p.add_argument('--motions',nargs='+',help='Explicit motion IDs, preserving this order')
 p.add_argument('--challenge-suite',action='store_true',help='Six new multi-mode control challenges, with internal generated transitions')
 p.add_argument('--allow-smoke',action='store_true',help='Allow fewer than8 generated actions; label as incomplete smoke, never pad/loop a short recording')
 args=p.parse_args()
 manifest=args.retargeted.resolve()/'manifest.json';receipt=read(manifest)
 actors={x['character']:x for x in receipt['characters']}
 if not actors or not set(actors).issubset(IDS) or (not args.allow_smoke and set(actors)!=set(IDS)):raise ValueError('All seven retargeted characters are required except explicit incomplete smoke')
 selected_actors=[actor for actor in IDS if actor in actors]
 first=actors[selected_actors[0]]['clips'];records={x['motion_id']:x for x in first}
 motion_ids=args.motions or list(records)
 if len(motion_ids)!=len(set(motion_ids)) or any(k not in records for k in motion_ids):raise ValueError('Unknown/duplicate generated motion selection')
 if not args.allow_smoke and not args.challenge_suite and not 8<=len(motion_ids)<=10:raise ValueError('Production POC review requires8–10 real generated actions; choose --motions, or explicitly --allow-smoke')
 import numpy as np
 models={};sources={};source_motion={};clips=[];names=None;parents=None
 for actor in selected_actors:
  row=actors[actor];src=Path(row['output_glb']).resolve()
  if sha(src)!=row['output_sha256']:raise ValueError('Retargeted GLB identity mismatch '+actor)
  doc=glb_doc(src);animations={x.get('name'):x for x in doc.get('animations',[])}
  for image in doc.get('images',[]):
   if image.get('uri'):raise ValueError('External image needs explicit companion copying; embedded GLB required: '+str(src))
  actor_clips={x['motion_id']:x for x in row['clips']}
  for mid in motion_ids:
   base=records[mid];item=actor_clips[mid]
   if not str(item['clip']).startswith('motionbricks_poc_') or item['clip'] not in animations or item['looping']:raise ValueError('Missing/non-genuine generated clip '+actor+'/'+mid)
   for field in ['clip','frames','fps','duration_s','source_npz_sha256']:
    if item[field]!=base[field]:raise ValueError('Shared source clip metadata differs across actors: '+field)
  models[actor]={'file':src,'sha256':row['output_sha256'],'production_source_sha256':row['source_sha256']}
 for mid in motion_ids:
  row=records[mid];path=Path(row['source_npz']).resolve();meta_path=path.with_suffix('.json')
  if sha(path)!=row['source_npz_sha256']:raise ValueError('Generated source NPZ identity mismatch '+mid)
  meta=read(meta_path)
  with np.load(path,allow_pickle=False) as payload:
   required=['joint_names','joint_parents','global_positions','fps','coordinate_system']
   if any(key not in payload for key in required):raise ValueError('Missing source proxy arrays')
   these_names=payload['joint_names'].tolist();these_parents=payload['joint_parents'].tolist();positions=np.asarray(payload['global_positions'],dtype=float);fps=float(payload['fps'])
   basis=str(payload['coordinate_system'].reshape(-1)[0]);assert 'Y-up/Z-forward' in basis
   assert len(these_names)==len(these_parents)==34 and positions.shape==(row['frames'],34,3) and np.isfinite(positions).all() and fps==30
   if names is None:names,parents=these_names,these_parents
   if names!=these_names or parents!=these_parents:raise ValueError('Source skeleton schema differs between clips')
   proxy={'fps':fps,'frames':len(positions),'global_positions':positions.tolist(),'source_npz_sha256':sha(path)}
   for optional in ['generation_ids','buffer_roles','command_modes','source_buffer_indices']:
    if optional in payload:proxy[optional]=payload[optional].tolist()
  mode=meta['official_mode']
  if args.challenge_suite and (mode!='multi-mode-sequence' or len(meta['commands'])<5):raise ValueError('Challenge requires real multi-segment generated controls')
  duration=(row['frames']-1)/fps
  if abs(duration-row['duration_s'])>1e-6:raise ValueError('Source duration differs')
  # Show every real source frame. Short smoke remains short; no repeated source
  # samples are created to make an action look like an eight-second generation.
  frames=int(row['frames']);display_seconds=frames/fps
  if not args.allow_smoke and not args.challenge_suite and not 6<=display_seconds<=8.05:raise ValueError('Review clips must actually contain6–8 seconds, got '+mid)
  clips.append({'motion_id':mid,'clip':row['clip'],'official_mode':mode,'label':LABELS.get(meta['action'],LABELS.get(mode,mode))+'  ['+mode+']','frames':frames,'fps':fps,'duration_s':duration,'display_frames':frames,'display_seconds':display_seconds,'tail_policy':'Native AnimationPlayer exact source sample n/30, first0/last(T-1)/30; no resampling, looping or extended terminal hold. Each next clip explicitly resets.','source_npz_sha256':sha(path),'source_meta_sha256':sha(meta_path),'commands':meta.get('commands',[]),'upstream_commit':meta.get('upstream_commit'),'checkpoint_sha256':meta.get('checkpoint_sha256',{})})
  source_motion[mid]=proxy;sources[str(path)]=sha(path);sources[str(meta_path)]=sha(meta_path)
 project=safe_project(args.project);project.mkdir(parents=True,exist_ok=True);(project/'assets').mkdir()
 for actor,row in models.items():shutil.copyfile(row['file'],project/'assets'/('CH_'+actor+'.glb'))
 font=ROOT/'game/assets/fonts/LXGWWenKai-Medium.ttf';shutil.copyfile(font,project/'font.ttf')
 viewer=Path(__file__).with_name('viewer.gd');shutil.copyfile(viewer,project/'viewer.gd')
 (project/'main.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://viewer.gd" id="1"]\n[node name="MotionBricksPOC" type="Node"]\nscript = ExtResource("1")\n')
 (project/'project.godot').write_text('''config_version=5
[application]
config/name="MotionBricks · G1人物重定向POC"
config/use_custom_user_dir=true
config/custom_user_dir_name="HarumachiMotionBricksPOC"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.8", "Forward Plus")
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/window_width_override=1920
window/size/window_height_override=1080
window/size/no_focus=true
window/vsync/vsync_mode=0
[rendering]
renderer/rendering_method="forward_plus"
movie_writer/fps=30
[physics]
common/physics_ticks_per_second=60
[debug]
file_logging/enable_file_logging=false
''')
 write(project/'source-motion.json',{'kind':'Real generated MotionBricks G1 FK34-joint source proxy, not an official human model','coordinate_system':'Y-up/Z-forward/metres','joint_names':names,'joint_parents':parents,'root_index':names.index('pelvis_skel'),'motions':source_motion})
 write(project/'showcase.json',{'input_manifest_sha256':sha(manifest),'clips':clips,'actors':selected_actors,'source_kind':'MotionBricks public G1 model output retargeted to existing characters','no_game_autoloads_or_modifiers':True,'challenge_suite':args.challenge_suite,'incomplete_smoke':args.allow_smoke,'group_layout':'Three independent same-motion comparison panels; four independent panels in a2x2 grid, no side-view actor occlusion','original_character_materials_preserved':True})
 inputs={'retarget_manifest':{'path':str(manifest),'sha256':sha(manifest)},'models':{actor:{k:str(v) if isinstance(v,Path) else v for k,v in row.items()} for actor,row in models.items()},'source_files':sources,'viewer_source_sha256':sha(viewer),'prepare_script_sha256':sha(Path(__file__)),'font_source_sha256':sha(font),'game_assets_written':False,'engine_started':False,'source_actions':[x['official_mode'] for x in clips]}
 write(project/'preparation-receipt.json',inputs)
 print(json.dumps({'project':str(project),'clips':len(clips),'seconds_per_take':sum(x['display_seconds'] for x in clips),'frame_count_per_take':sum(x['display_frames'] for x in clips),'takes':['solo-'+i for i in selected_actors]+['source-motion']+(['group-three','group-four'] if len(selected_actors)==7 else []),'source_proxy_frames':sum(x['frames'] for x in clips),'engine_started':False},ensure_ascii=False))

if __name__=='__main__':main()
