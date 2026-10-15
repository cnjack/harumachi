#!/usr/bin/env python3
"""Submit the remaining authored CG shots serially through the existing Shuqi skill.

Existing IDs are polled, never regenerated. Image files must already exist.
"""
import argparse,fcntl,json,os,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DETAILS={
 'town':'The brown-haired young man in mint short sleeves, white T-shirt, cream cropped trousers and orange-white shoes walks along the street toward the community notice case. Show several distinct alternating steps, foot lift and ground contact, moving hips and naturally swinging arms. He slows to a stop beside the notice case and turns his head toward it. Maintain his appearance and the existing town architecture. His body must visibly travel through the scene.',
 'breakfast':'Starting seated as shown, the brown-haired young man in mint short sleeves and white T-shirt lifts both forearms off the table, stretches his arms out to either side at shoulder level, briefly tilts his head back, then lowers his arms and turns to look toward the sunlit window. Clearly animate his elbows, shoulders, hands and head through the full movement. Keep the rice ball and tea set on the table. No eating or drinking gesture.',
 'bakery':'Starting behind the green counter as shown, Ren, the dark-haired baker in a yellow headscarf, orange shirt and white apron, lifts his right arm and gives a broad welcoming wave. He lowers his hand, turns his whole body toward the oven on his right and takes two visible steps along the space behind the counter toward it. His body changes position; he does not pass through the counter. Preserve the actual bakery furniture and appliances.',
 'farm':'The brown-haired young man in mint short sleeves, white T-shirt, cream cropped trousers and orange-white shoes bends both knees and squats beside the raised tomato bed, leans forward to inspect a ripe tomato, then straightens his legs and rises to stand. Animate the changing knee angles, torso height, balancing arms and planted feet continuously. Keep the crop beds, path, glass-windowed truck and wooden bridge recognizable. No magically growing crops or extra tools.',
 'fishing':'The brown-haired young man in mint short sleeves and cream cropped trousers stands on the narrow wooden pier. He draws his fishing rod back over one shoulder, then swings it forward in one clear casting action, extending his arms as the line arcs out over the lake. The orange float lands farther out with a small splash and expanding circular ripples. He settles into a balanced standing pose. Show the complete rod and arm movement with coherent hands, rod, line and pier rails. No giant fish, boats or new people.',
 'lantern':'Starting seated at the timber worktable, the brown-haired young man in mint short sleeves reaches both hands toward the cream paper with green leaves, lifts the flexible paper from the table and curves it gently around the cylindrical bamboo lantern frame. He steadies the frame with one hand while guiding the paper with the other. Show a continuous clear sequence of arm movement and paper bending; the paper does not teleport or become a different object. Preserve the leaf design and bamboo frame on the tabletop.'}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--names',default='town,breakfast,bakery,farm,fishing,lantern')
    parser.add_argument('--motion-review',type=Path,default=ROOT/'evidence/promo_20261015/action-motion-review.json')
    args=parser.parse_args();skill=Path.home()/'.agents/skills/shuqi-video';sys.path.insert(0,str(skill/'scripts'))
    if not args.motion_review.is_file() or not json.loads(args.motion_review.read_text()).get('approved'):
        raise SystemExit('Character motion sample has not been visually approved; no batch submitted')
    from video import Client
    out=ROOT/'outputs/harumachi-promo-20261015';work=ROOT/'work/promo_20261015';evidence=ROOT/'evidence/promo_20261015'
    lock=(evidence/'cg-queue.lock').open('w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    client=Client('https://ai.szshuqi.com',(Path.home()/'.config/shuqi-video/api-key').read_text().strip())
    downloads=[];waiting=[];records=[]
    def kick():
        active=[]
        for process in downloads:
            result=process.poll()
            if result is None:active.append(process)
            elif result!=0:raise RuntimeError('Download failed; resume its existing job without regenerating')
        downloads[:]=active
        old_done=all((out/n/'video-ranged.mp4').is_file() for n in ['bridge-video','festival-video'])
        while waiting and old_done and len(downloads)<2:
            name=waiting.pop(0);folder=out/(name+'-action-v2-video')
            log=(folder/'range-download.log').open('w')
            p=subprocess.Popen([sys.executable,str(ROOT/'art/tools/download_promo_video.py'),'--out',str(folder),'--workers','2'],stdout=log,stderr=subprocess.STDOUT,cwd=ROOT);log.close();downloads.append(p)
            print('CG_DOWNLOAD',name,'pid',p.pid,flush=True)
    for number,name in enumerate(args.names.split(',')):
        if name not in DETAILS:raise ValueError('Unknown motion shot: '+name)
        folder=out/(name+'-action-v2-video');folder.mkdir(exist_ok=True);job=folder/'job.json'
        if not job.exists():
            image=ROOT/'art/references/promo_20261015'/(name+'.png')
            while not image.exists():kick();time.sleep(10)
            template=ROOT/'art/manifests/prompts/promo_20261015'/(name+'-action-v2-video.json')
            import base64
            prompt='Animate clear, purposeful character action from this Japanese anime first frame. '+DETAILS[name]+' The camera stays stable, the movement comes from the articulated character and objects rather than zooming the image. Keep the same face, hairstyle, outfit and clean flat cel shading, with expressive traditional anime movement. One continuous eight-second shot, no cuts, no speech, subtitles or logos. Quiet location ambience only, no music.'
            payload={'model':'minimax-h3','prompt':prompt,'seconds':8,'size':'1344x768','quality':'lossless','output_compression':80,'task':'fl2va','conditions':[{'type':'image','uri':'data:image/png;base64,'+base64.b64encode(image.read_bytes()).decode(),'role':'keyframe','frame_index':0}],'target':{'short_edge':768,'aspect_ratio':'16:9','duration_seconds':8},'seed':1050+number}
            safe=payload.copy();safe['conditions']=[{'type':'image','uri':str(image.relative_to(ROOT))+' (submitted as data URI)','role':'keyframe','frame_index':0}];template.write_text(json.dumps(safe,ensure_ascii=False,indent=2)+'\n')
            request=work/(name+'-action-v2-request.json');request.write_text(json.dumps(payload))
            with (folder/'submit.log').open('w') as log:subprocess.run([sys.executable,str(skill/'scripts/video.py'),'generate','--payload',str(request),'--out',str(folder),'--wait','0'],stdout=log,stderr=subprocess.STDOUT,cwd=ROOT)
        state=json.loads(job.read_text())
        if not state.get('id'):raise RuntimeError(name+': no confirmed ID; reconcile the saved submission before retrying')
        previous=None
        while True:
            try:r=client.json('/v1/videos/'+state['id'])
            except (OSError,TimeoutError):kick();time.sleep(30);continue
            status=r.get('status','unknown');state['status']=status;job.write_text(json.dumps(state,indent=2)+'\n')
            if status!=previous:print('CG_GENERATION',name,status,flush=True);previous=status
            if status=='completed':break
            if status in ['failed','cancelled','expired']:raise RuntimeError(name+': generation '+status)
            kick();time.sleep(30)
        records.append({'name':name,'id':state['id'],'status':'completed'});(evidence/'cg-action-queue.json').write_text(json.dumps(records,indent=2)+'\n')
        if not (folder/'video-ranged.mp4').exists():waiting.append(name)
        kick()
    while waiting or downloads:kick();time.sleep(10)
    print('CG_QUEUE_FINISHED',flush=True)

if __name__=='__main__':main()
