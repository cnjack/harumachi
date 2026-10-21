import fs from 'node:fs';
import assert from 'node:assert/strict';
const {SpeechTimeline,faceAttention,faceBlink}=await import('data:text/javascript;base64,'+fs.readFileSync(new URL('mio-performance.js',import.meta.url)).toString('base64'));
const result=JSON.parse(fs.readFileSync(process.argv[2]));
const cues=[[0,'welcome','欢迎回来。今天也一起慢慢来吧。'],[7,'quiet',''],[13,'waiting',''],[17,'reply','我在听，先别着急。我们可以一件一件慢慢来。'],[25,'quiet','']];
let worst=0;
for(const frame of result.frames){const [start,intent,text]=cues.findLast(c=>c[0]<=frame.t);const speech=new SpeechTimeline(text),t=frame.t-start-(intent==='welcome'?.35:0);const value=['welcome','reply'].includes(intent)?speech.mouth(t):0;worst=Math.max(worst,Math.abs(value-frame.mouth));}
assert(worst<.00001,`Swift/JS mouth mismatch: ${worst}`);
assert.equal(faceBlink(4.25),1);assert.notEqual(faceBlink(4.25),faceBlink(16.25));assert.notDeepEqual(faceAttention(3),faceAttention(15));
console.log(JSON.stringify({comparedFrames:result.frames.length,maxMouthDifference:worst,irregularBlinkAndAttention:true}));
