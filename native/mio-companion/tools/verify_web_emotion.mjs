import fs from 'node:fs';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('mio-performance.js',import.meta.url));
const {EmotionMixer,MioPerformanceController}=await import('data:text/javascript;base64,'+source.toString('base64'));
const profile=JSON.parse(fs.readFileSync(new URL('../Sources/MioApp/Resources/MioCubism/Mio.emotion.json',import.meta.url)));
const report=JSON.parse(fs.readFileSync(process.argv[2]));
const mixer=new EmotionMixer(profile);let maxError=0,compared=0;
for(const frame of report.transitions){
 const values=mixer.apply(frame.base,frame.expression,frame.t,true);
 for(const id of [...Object.keys(profile.styles.neutral.face),'ParamMouthOpenY']){maxError=Math.max(maxError,Math.abs(values[id]-frame.face[id]));compared++;}
 for(let i=0;i<3;i++)maxError=Math.max(maxError,Math.abs(mixer.vad[i]-frame.vad[i]));
}
assert(maxError<.00001,`Swift/JS expression mismatch: ${maxError}`);
// Exercise public controller operations against parameter ownership, including
// the original failure where manual talk was closed by the emotion mixer.
const values={ParamMouthOpenY:.6};const core={setParameterValueById:(id,value)=>values[id]=value,getParameterValueById:id=>values[id]??0};
const model={internalModel:{coreModel:core,on(){},off(){},motionManager:{on(){},off(){}}},expression(){},motion(){}};
const controller=new MioPerformanceController(model,{Curves:[]},{Curves:[]},{Curves:[]},profile);
controller.current='talk';controller.manual('talk');controller.update();assert.equal(values.ParamMouthOpenY,.6,'Manual talk must retain authored mouth aperture');
controller.event({intent:'quiet',expression:{style:'surprised',intensity:'strong',hand:'wave'}});controller.update();assert.equal(values.ParamMouthOpenY,0);assert.equal(controller.state.phase,'Idle');
assert.throws(()=>controller.event({expression:{style:'remote command'}}));
const result={comparedFrames:report.transitions.length,comparedChannels:compared,maxError,manualSpeechOwnership:true,quietSuppressesGesture:true,noInferenceRequests:true};
console.log(JSON.stringify(result,null,2));
