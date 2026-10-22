#!/usr/bin/env python3
"""Decode raw/PackBits PSD layers to channel hashes. Usage: input.psd output.json.

Compare JSON reports to verify lossless source-storage changes independently
of Cubism export. Each scanline must decode to its declared source width.
"""
import hashlib,json,struct,sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes();pos=26
for _ in range(2):
 n=struct.unpack_from('>I',b,pos)[0];pos+=4+n
pos+=4;layerlen=struct.unpack_from('>I',b,pos)[0];pos+=4
n=abs(struct.unpack_from('>h',b,pos)[0]);pos+=2
layers=[]
for _ in range(n):
 top,left,bottom,right,count=struct.unpack_from('>iiiiH',b,pos);pos+=18;channels=[]
 for c in range(count):
  ch,size=struct.unpack_from('>hI',b,pos);pos+=6;channels.append((ch,size))
 pos+=12;extra=struct.unpack_from('>I',b,pos)[0];pos+=4;start=pos
 mask=struct.unpack_from('>I',b,pos)[0];pos+=4+mask
 ranges=struct.unpack_from('>I',b,pos)[0];pos+=4+ranges
 name=b[pos+1:pos+1+b[pos]].decode();pos=start+extra
 layers.append((name,right-left,bottom-top,channels))
result=[]
for name,w,h,channels in layers:
 hashes=[]
 for ch,size in channels:
  compression=struct.unpack_from('>H',b,pos)[0];data=b[pos+2:pos+size];pos+=size
  if compression==0: raw=data
  elif compression==1:
   lengths=struct.unpack_from('>'+str(h)+'H',data,0);at=2*h;decoded=bytearray()
   for length in lengths:
    end=at+length;row=bytearray()
    while at<end:
     c=data[at];at+=1
     if c<128: row+=data[at:at+c+1];at+=c+1
     elif c>128: row+=bytes([data[at]])*(257-c);at+=1
    assert len(row)==w,(name,ch,len(row),w)
    decoded+=row
   raw=decoded
  else: raise ValueError(compression)
  assert len(raw)==w*h,(name,ch,len(raw),w*h)
  hashes.append([ch,hashlib.sha256(raw).hexdigest()])
 result.append({'name':name,'size':[w,h],'channels':hashes})
Path(sys.argv[2]).write_text(json.dumps(result,indent=2)+'\n')
print('layers',len(result),'bytes',len(b))
