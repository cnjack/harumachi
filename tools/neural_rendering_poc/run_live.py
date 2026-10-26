#!/usr/bin/env python3
"""Coordinate the running native game and the instrumented, otherwise normal overlay app."""
import argparse
import json
import os
from pathlib import Path
import time

parser = argparse.ArgumentParser()
parser.add_argument('evidence', type=Path)
parser.add_argument('--seconds', type=float, default=30)
parser.add_argument('--warmup', type=float, default=8)
parser.add_argument('--modes', default='baseline,bypass,natural-512-60,natural-768-60,natural-512-30,baseline-repeat')
parser.add_argument('--scenes', default='bakery_scene_front,lake_pier')
parser.add_argument('--record', action='store_true')
parser.add_argument('--prefix', default='live')
args = parser.parse_args()
root = args.evidence.resolve()
planned = [f'{args.prefix}-{scene}-{mode}' for scene in args.scenes.split(',') for mode in args.modes.split(',')]
if args.seconds <= 0 or args.warmup < 0:
    parser.error('sample duration must be positive; warmup must be nonnegative')
if any((root / (trial + suffix)).exists() for trial in planned for suffix in ('-game.json', '-overlay.json')):
    parser.error('completed samples already exist; use a new evidence directory or a new --prefix')


def read(name):
    try:
        return json.loads((root / name).read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def write(name, data):
    target = root / name
    temporary = target.with_suffix('.tmp')
    temporary.write_text(json.dumps(data))
    temporary.replace(target)


def wait(name, predicate, seconds=90):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        error = read('app-error.json')
        if error:
            raise RuntimeError(error)
        data = read(name)
        if data and predicate(data):
            return data
        time.sleep(0.25)
    raise TimeoutError(f'{name}: no matching completion; inspect real rendering and permission state')


def alive(row):
    try:
        os.kill(int(row['pid']), 0)
        return True
    except (KeyError, OSError):
        return False


wait('game-ready.json', lambda row: row.get('fixed_fps') is False and alive(row))
wait('app-ready.json', lambda row: row.get('model_loaded') is True and alive(row))
for scene in args.scenes.split(','):
    for mode in args.modes.split(','):
        trial = f'{args.prefix}-{scene}-{mode}'
        prepare = trial + '-scene'
        now = time.time()
        write('game-command.json', {'id': prepare, 'scene': scene, 'start': now + 1, 'end': now + 2})
        wait(prepare + '-game.json', lambda row: bool(row.get('frames')))
        width, fps = (int(mode.split('-')[1]), int(mode.split('-')[2])) if mode.startswith('natural-') else (512, 60)
        config = {'id': trial + '-configure', 'action': 'configure', 'mode': 'baseline' if mode.startswith('baseline') else mode,
                  'width': width, 'fps': fps}
        write('app-command.json', config)
        wait('app-ack.json', lambda row: row.get('id') == config['id'])
        start = time.time() + args.warmup
        end = start + args.seconds
        phase = {'id': trial, 'scene': scene, 'mode': mode, 'start': start, 'end': end, 'warmup_seconds': args.warmup}
        write('game-command.json', phase)
        write('app-command.json', dict(phase, action='measure'))
        print('MEASURING', scene, mode, flush=True)
        game = wait(trial + '-game.json', lambda row: bool(row.get('frames')), args.warmup + args.seconds + 25)
        wait(trial + '-overlay.json', lambda row: row.get('command', {}).get('id') == trial)
        frames = [row for row in game['frames'] if start <= row['unix'] < end]
        print('DONE', trial, f'{len(frames)/args.seconds:.2f} game render callbacks/sec', flush=True)
        if args.record and mode.startswith('natural-') and fps == 60:
            request = {'id': trial + '-recording', 'action': 'record', 'seconds': 8}
            write('app-command.json', request)
            wait('app-ack.json', lambda row: row.get('id') == request['id'], 30)
            print('RECORDED', request['id'], flush=True)
write('app-command.json', {'id': args.prefix + '-stop', 'action': 'configure', 'mode': 'baseline'})
wait('app-ack.json', lambda row: row.get('id') == args.prefix + '-stop')
print('All phases completed; overlay processing stopped.', flush=True)
