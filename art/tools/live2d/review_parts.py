#!/usr/bin/env python3
"""Inspect the uncompressed RGB8 PSD authored by MioCubismBake; no art repainting."""
import argparse
import json
import struct
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]

def read_psd(path):
    data = path.read_bytes()
    assert data[:4] == b'8BPS' and struct.unpack_from('>H', data, 4)[0] == 1
    assert struct.unpack_from('>HH', data, 22) == (8, 3), 'Expected RGB8 PSD'
    pos = 26
    for _ in range(2):
        length = struct.unpack_from('>I', data, pos)[0]
        pos += 4 + length
    pos += 8
    count = abs(struct.unpack_from('>h', data, pos)[0]); pos += 2
    layers = []
    for _ in range(count):
        top, left, bottom, right = struct.unpack_from('>4i', data, pos); pos += 16
        n = struct.unpack_from('>H', data, pos)[0]; pos += 2
        channels = []
        for _ in range(n):
            cid, length = struct.unpack_from('>hI', data, pos); pos += 6
            channels.append((cid, length))
        flags = data[pos + 10]
        pos += 12
        length = struct.unpack_from('>I', data, pos)[0]; pos += 4; end = pos + length
        for _ in range(2):
            length = struct.unpack_from('>I', data, pos)[0]; pos += 4 + length
        name = data[pos + 1:pos + 1 + data[pos]].decode('utf-8'); pos = end
        layers.append({'id': name, 'channels': channels, 'width': right-left, 'height': bottom-top, 'visible': not flags & 2})
    result = []
    for layer in layers:
        planes = {}
        for cid, length in layer.pop('channels'):
            assert data[pos:pos+2] == b'\0\0', 'Expected raw layer channel'
            planes[cid] = Image.frombytes('L', (layer['width'], layer['height']), data[pos+2:pos+length]); pos += length
        im = Image.merge('RGBA', tuple(planes[cid] for cid in [0,1,2,-1]))
        layer['bounds'] = im.getbbox()
        layer['nonemptyPixels'] = sum(n for i,n in enumerate(planes[-1].histogram()) if i)
        assert layer['nonemptyPixels'] > 0, 'Empty source component: ' + layer['id']
        result.append((layer, im))
    return list(reversed(result))

HTML = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>澪 · 源图层检查</title>
<style>body{margin:0;background:#eeeee9;color:#303e42;font:15px system-ui;display:flex;height:100vh}aside{width:300px;overflow:auto;background:#fff;padding:18px;box-sizing:border-box}h1{font-size:20px}button{padding:6px 10px;margin:3px;border:1px solid #abb7b8;border-radius:5px;background:white;cursor:pointer}label{display:flex;gap:6px;margin:8px 0;font-size:12px}main{flex:1;display:flex;justify-content:center;align-items:center;overflow:auto;background:repeating-conic-gradient(#ddd 0 25%,#f7f7f7 0 50%) 50%/20px 20px}canvas{max-height:98vh;max-width:100%;object-fit:contain}small{line-height:1.6}#count{display:block;margin:14px 0}</style>
<aside><h1>澪 · 源图层</h1><small>原 PSD 的实际图层。可独显、逐层向下检查；眉眼、口腔和手指均可单独开关。</small><p><button id="reset">默认叠合</button><button id="face">眉眼嘴部</button><button id="hand">右手掌心</button></p><output id="count"></output><div id="list"></div></aside><main><canvas width="750" height="1000"></canvas></main>
<script>
const layers=PARTS;const canvas=document.querySelector('canvas'),ctx=canvas.getContext('2d');let loaded=0;
function draw(){ctx.clearRect(0,0,750,1000);layers.forEach(l=>{if(l.show)ctx.drawImage(l.img,0,0)});document.querySelector('#count').textContent=`${layers.filter(l=>l.show).length} / ${layers.length} 层`}
for(const [i,l] of layers.entries()){l.show=l.visible;l.img=new Image();l.img.onload=()=>{loaded++;draw()};l.img.src='parts/'+l.id+'.png';const row=document.createElement('label'),box=document.createElement('input');box.type='checkbox';box.checked=l.show;box.onchange=()=>{l.show=box.checked;draw()};l.box=box;const text=document.createElement('span');text.textContent=l.id;const solo=document.createElement('button');solo.textContent='独显';solo.onclick=()=>{layers.forEach(p=>p.show=p===l);sync()};const below=document.createElement('button');below.textContent='下层';below.onclick=()=>{layers.forEach((p,j)=>p.show=j<=i&&p.visible);sync()};row.append(box,text,solo,below);document.querySelector('#list').prepend(row)}
function sync(){layers.forEach(l=>l.box.checked=l.show);draw()}
document.querySelector('#reset').onclick=()=>{layers.forEach(l=>l.show=l.visible);sync()};
document.querySelector('#face').onclick=()=>{layers.forEach(l=>l.show=/^(face|brow_|eyes_|mouth_)/.test(l.id)&&!l.id.startsWith('eyes_closed')&&!l.id.startsWith('mouth_open'));sync()};
document.querySelector('#hand').onclick=()=>{layers.forEach(l=>l.show=l.id==='hand_right_palm'||l.id.startsWith('finger_right_'));sync()};
</script></html>'''

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--psd', type=Path, default=ROOT/'art/live2d/mio/cubism/Mio.psd')
    p.add_argument('--output', type=Path, required=True)
    a=p.parse_args(); a.output.mkdir(parents=True,exist_ok=True);(a.output/'parts').mkdir(exist_ok=True)
    layers=read_psd(a.psd);metadata=[]
    for spec,im in layers:
        im.save(a.output/'parts'/(spec['id']+'.png'));metadata.append(spec)
    (a.output/'parts.json').write_text(json.dumps(metadata,indent=2)+'\n')
    (a.output/'index.html').write_text(HTML.replace('PARTS',json.dumps(metadata)))
    print(json.dumps({'layers':len(layers),'allNonempty':True,'output':str(a.output.resolve())}))
if __name__=='__main__':main()
