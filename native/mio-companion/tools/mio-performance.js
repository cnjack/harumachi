/* Optional event/text behavior for pixi-live2d-display 0.4.0. The model itself
   remains standard MOC3 + motion3 + exp3 + physics3. No vendor code included. */
export class SpeechTimeline {
  constructor(text) {
    let cursor=.18;this.beats=[];
    Array.from(text).slice(0,300).forEach((c,i)=>{
      if('，、,:：；;'.includes(c)){cursor+=.27;return;}
      if('。！？.!?…\n'.includes(c)){cursor+=.48;return;}
      if(!c.trim()){cursor+=.06;return;}
      const length=.115+(i%4)*.012;
      this.beats.push({start:cursor,end:cursor+length,strength:.42+(i%3)*.12});cursor+=length+.035;
    });this.duration=cursor+.25;
  }
  mouth(t){const b=this.beats.find(b=>t>=b.start&&t<=b.end);if(!b)return 0;const u=(t-b.start)/(b.end-b.start);return b.strength*smooth(0,.25,u)*(1-smooth(.6,1,u));}
}
function smooth(a,b,v){const t=Math.max(0,Math.min(1,(v-a)/(b-a)));return t*t*(3-2*t);}

function noise(v){let x=(Math.imul(v,1664525)+1013904223)>>>0;x^=x>>>16;x=Math.imul(x,2246822519)>>>0;x^=x>>>13;return (x&65535)/65535;}
export function faceAttention(time){const clock=Math.max(0,time),block=Math.floor(clock/7),t=clock%7,strength=smooth(1.7,2.2,t)*(1-smooth(5.4,6.4,t));return [(noise(block*3+5)-.5)*.64*strength,(noise(block*3+8)-.5)*.25*strength];}
export function faceBlink(time){const clock=Math.max(0,time),block=Math.floor(clock/6),t=clock%6,center=block===0?4.25:block===1?3.1:2.3+noise(block+61)*2.2;const pulse=c=>t<c?smooth(c-.075,c,t):1-smooth(c,c+.13,t);return Math.max(pulse(center),(block===1||noise(block+81)<.2)?pulse(center+.37):0);}
function sampleCurve(curve,t){const v=curve.Segments;let x=v[0],y=v[1];for(let i=2;i<v.length;){const type=v[i++];if(type===1)throw new Error('Mio fixture expects authored linear/step curves');const nx=v[i++],ny=v[i++];if(t<=nx)return type===2?y:type===3?ny:y+(ny-y)*Math.max(0,(t-x)/(nx-x));x=nx;y=ny;}return y;}
export class MioPerformanceController {
  static async create(model,root='Mio/') {
    const hold=await fetch(root+'motions/think.motion3.json').then(r=>{if(!r.ok)throw Error('Missing thinking motion');return r.json();});
    return new MioPerformanceController(model,hold);
  }
  constructor(model,hold) {
    this.model=model;this.hold=hold;this.started=performance.now()/1000;this.lastWelcome=-Infinity;this.cue=null;this.state={intent:'quiet',mood:'neutral',mouth:0};
    this.faceListener=()=>{const t=performance.now()/1000-this.started,core=model.internalModel.coreModel,attention=faceAttention(t);for(const id of ['ParamEyeLOpen','ParamEyeROpen'])core.setParameterValueById(id,1-faceBlink(t));core.setParameterValueById('ParamEyeBallX',attention[0]);core.setParameterValueById('ParamEyeBallY',attention[1]);};
    model.internalModel.on('afterMotionUpdate',this.faceListener);
    this.listener=()=>this.update();model.internalModel.on('beforeModelUpdate',this.listener);
    this.model.internalModel.motionManager.on('motionStart',this.motionListener=(group)=>{this.current=group;});
  }
  event({intent='reply',mood='neutral',text=''}) {
    const now=performance.now()/1000;
    if(intent==='welcome'){if(now-this.lastWelcome<180)intent='reply';else this.lastWelcome=now;}
    this.cue={intent,mood,text,started:now,speech:new SpeechTimeline(text),phase:'',restored:false};
    this.model.expression(mood);this.model.motion('Idle',0,3);
    this.state={intent,mood,mouth:0};
  }
  setMood(mood){this.cue=null;this.model.expression(mood);this.state={intent:'manual-expression',mood,mouth:0};}
  manual(group){this.cue=null;return this.model.motion(group,0,3);}
  update(){
    if(!this.cue)return;
    const c=this.cue,t=performance.now()/1000-c.started,st=t-(c.intent==='welcome' ? .35 : 0);
    const speaking=!['quiet','waiting'].includes(c.intent)&&st>=0&&st<c.speech.duration;
    const phase=c.intent==='welcome'&&t<4.4?'wave':c.intent==='waiting'&&t>.55?'think':c.intent==='reply'&&speaking&&Array.from(c.text).length>16?'talk':'Idle';
    if(phase!==c.phase){c.phase=phase;this.model.motion(phase,0,3);}
    const core=this.model.internalModel.coreModel;
    if(c.intent==='waiting'&&t>2.75){
      // Keep the authored fingertip/chin contact; no repeating full think loop.
      for(const curve of this.hold.Curves)if(curve.Target==='Parameter'&&!['ParamHairFront','ParamHairBack','ParamEyeLOpen','ParamEyeROpen','ParamMouthForm','ParamBrowLY','ParamBrowRY'].includes(curve.Id))core.setParameterValueById(curve.Id,sampleCurve(curve,2.2));
    }
    const mouth=speaking?c.speech.mouth(st):0;core.setParameterValueById('ParamMouthOpenY',mouth);
    // Hand variants are discrete source drawings, including during interruptions.
    for(const id of ['ParamHandL','ParamHandR'])core.setParameterValueById(id,Math.round(core.getParameterValueById(id)));
    if(c.intent!=='waiting'&&t>c.speech.duration+2&&!c.restored){this.model.expression('neutral');c.restored=true;}
    this.state={intent:c.intent,mood:c.restored?'neutral':c.mood,mouth,phase,speaking,elapsed:t};
  }
  destroy(){this.model.internalModel.off('afterMotionUpdate',this.faceListener);this.model.internalModel.off('beforeModelUpdate',this.listener);this.model.internalModel.motionManager.off('motionStart',this.motionListener);}
}
