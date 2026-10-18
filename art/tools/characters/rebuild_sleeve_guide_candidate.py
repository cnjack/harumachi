#!/usr/bin/env python3
"""Rebuild the five-control stretch guide from explicit saved source inputs.

This closes the converter/fit/midpoint code entry chain. It deliberately requires
the closed-seam parent, protected source and actual native evidence: it is not an
end-to-end reconstruction of historical rig/gait models or a visual acceptance.
"""
from pathlib import Path
import argparse, hashlib, json, subprocess, sys


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['input','protected-reference','peaks-manifest','continuous-native','output-dir']:
        p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--character',default='mio');p.add_argument('--source-kind',default='source-native-continuous-counterfactual')
    p.add_argument('--weight-smoothing',type=int,default=1000);p.add_argument('--phase',type=float,default=.5)
    args=p.parse_args()
    if args.output_dir.exists():raise FileExistsError('Use a new output directory; no model is overwritten')
    args.output_dir.mkdir(parents=True)
    here=Path(__file__).resolve().parent
    tools=[here/'convert_native_sleeve_manifest.py',here/'prepare_sleeve_weight_guide_correctives.py',here/'append_sleeve_guide_residual.py']
    converted=args.output_dir/'actual-source-rows.json';four=args.output_dir/'four-fields.glb';trace=args.output_dir/'trace';final=args.output_dir/f'CH_{args.character}.glb'
    commands=[
        [str(tools[0]),'--input',str(args.continuous_native),'--output',str(converted),'--character',args.character,'--source-kind',args.source_kind],
        [str(tools[1]),'--input',str(args.input),'--protected-reference',str(args.protected_reference),'--manifest',str(args.peaks_manifest),'--fit-manifest',str(converted),'--output',str(four),'--report',str(args.output_dir/'four-fields.json'),'--trace-dir',str(trace),'--character',args.character,'--guide-policy','monotone-arm','--guide-smoothing','0','--weight-smoothing',str(args.weight_smoothing),'--strength','1','--max-world-shift','.12'],
        [str(tools[2]),'--input',str(four),'--reference',str(args.input),'--manifest',str(converted),'--trace-dir',str(trace),'--output',str(final),'--report',str(args.output_dir/'candidate.json'),'--character',args.character,'--phase',str(args.phase),'--start','.375','--end','.625']]
    for command in commands:subprocess.run([sys.executable,*command],check=True)
    inputs={'closed_seam_parent':args.input,'protected_formal':args.protected_reference,
            'four_actual_peaks':args.peaks_manifest,'native_transition_packets':args.continuous_native}
    record={'scope':'Rebuild from saved source parent and native pose inputs; no Godot capture or naturalness acceptance.',
        'inputs':{n:{'path':str(v),'sha256':sha(v)}for n,v in inputs.items()},
        'tools':{t.name:{'path':str(t),'sha256':sha(t)}for t in [Path(__file__),*tools]},'commands':commands,
        'parameters':{'guide_policy':'monotone-arm','guide_smoothing':0,'weight_smoothing':args.weight_smoothing,'strength':1,'direct_peak_cap_m':.12,'phase_request':args.phase,'support_phase':[.375,.625]},
        'output':{'path':str(final),'sha256':sha(final)},
        'limit':'Least-squares mode does not impose the direct peak cap. Independently measure actual world displacement, seam/normal/whole support and native appearance.'}
    (args.output_dir/'rebuild-manifest.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record['output']))


if __name__=='__main__':main()
