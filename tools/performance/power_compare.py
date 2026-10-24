#!/usr/bin/env python3
"""Compare the same frozen scene before/after presentation budgets on an existing display.
No virtual displays, system-volume changes or privileged power samplers. CPU is the
process's cumulative user+system CPU time; thermal state is a categorical OS signal,
not a temperature. Shader GPU milliseconds are reported separately from wall FPS.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def thermal_state():
    try:
        ctypes.CDLL('/System/Library/Frameworks/Foundation.framework/Foundation')
        objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
        objc.objc_getClass.argtypes = [ctypes.c_char_p]
        objc.objc_getClass.restype = ctypes.c_void_p
        objc.sel_registerName.argtypes = [ctypes.c_char_p]
        objc.sel_registerName.restype = ctypes.c_void_p
        message = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(('objc_msgSend', objc))
        integer = ctypes.CFUNCTYPE(ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p)(('objc_msgSend', objc))
        info = message(objc.objc_getClass(b'NSProcessInfo'), objc.sel_registerName(b'processInfo'))
        return integer(info, objc.sel_registerName(b'thermalState'))
    except Exception:
        return None


def power_environment():
    result = {}
    for label, command in {"os": ["sw_vers"], "power_source": ["pmset", "-g", "batt"],
                           "power_settings": ["pmset", "-g", "custom"]}.items():
        value = subprocess.run(command, capture_output=True, text=True, timeout=5)
        result[label] = value.stdout.strip()
    return result


def process_usage(pid):
    lib = ctypes.CDLL('/usr/lib/libproc.dylib')
    data = ctypes.create_string_buffer(256)
    if lib.proc_pid_rusage(pid, 2, ctypes.byref(data)) != 0:
        return None
    user_ticks, system_ticks = struct.unpack_from('QQ', data.raw, 16)
    class Timebase(ctypes.Structure):
        _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]
    timebase = Timebase()
    ctypes.CDLL('/usr/lib/libSystem.B.dylib').mach_timebase_info(ctypes.byref(timebase))
    return {'cpu_seconds': (user_ticks + system_ticks) * timebase.numer / timebase.denom / 1e9,
            'resident_bytes': struct.unpack_from('Q', data.raw, 64)[0]}


def foreign_games(owned=0):
    result = subprocess.run(['ps', '-Ao', 'pid=,pcpu=,comm='], capture_output=True, text=True, check=True)
    busy = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) != 3 or int(fields[0]) == owned:
            continue
        pid, cpu, command = fields
        game = any(name in command for name in ('Contents/MacOS/Godot', 'Contents/MacOS/HareMachi', 'Contents/MacOS/明年夏祭'))
        if game:
            args = subprocess.run(['ps', '-p', pid, '-o', 'args='], capture_output=True, text=True).stdout.strip()
            if args == command + ' --version':
                continue  # Version-lock probes do not initialize a game or renderer.
        worker = ('Contents/MacOS/Blender' in command or Path(command).name in ('ffmpeg', 'ffprobe')) and float(cpu) >= 25
        if game or worker:
            busy.append(pid + ' ' + command)
    return busy


def quiet(timeout=900):
    started = time.monotonic()
    clear_since = None
    reported = False
    while True:
        now = time.monotonic()
        if foreign_games():
            clear_since = None
            if not reported:
                print('Waiting for another game or heavy Blender/media process to finish before measuring.', flush=True)
                reported = True
        elif clear_since is None:
            clear_since = now
        elif now - clear_since >= 10:
            return
        if now - started > timeout:
            raise RuntimeError('Another workload is still active; no uncontaminated sample can start.')
        time.sleep(2)


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def run_variant(project, folder, profile, raw, views, seconds, frames, settle, resolution):
    quiet()
    folder.mkdir(parents=True, exist_ok=False)
    override = project / 'override.cfg'
    previous_override = override.read_bytes() if override.exists() else None
    override.write_text('[display]\nwindow/size/no_focus=true\nwindow/vsync/vsync_mode=%d\n' % (0 if raw else 1))
    command = [str(ROOT / 'tools/godot'), '--path', str(project), '--screen', '0', '-t', '--position', '60,80',
               '--resolution', resolution, '--audio-driver', 'Dummy', '--script', 'res://scripts/tools/performance_bench.gd', '--',
               '--out=' + str(folder), '--views=' + views, '--frames=' + str(frames), '--settle=' + str(settle),
               '--sample-seconds=' + str(seconds), '--frame-policy=' + ('raw' if raw else 'play'), '--tag=' + folder.name,
               '--graphics-benchmark']
    if raw:
        command.append('--benchmark-uncapped')
    if profile != 'before':
        command.append('--graphics-profile=' + profile)
    env = dict(os.environ, HARUMACHI_SAVE_DIR=str(folder / 'save'))
    telemetry = []
    conflicts = set()
    phase = ''
    process = None
    failure = None
    started = time.monotonic()
    try:
        with (folder / 'engine.log').open('w') as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            log_offset = 0
            while process.poll() is None:
                time.sleep(1)
                with (folder / 'engine.log').open() as reader:
                    reader.seek(log_offset)
                    new = reader.read()
                    log_offset = reader.tell()
                for line in new.splitlines():
                    if line.startswith('BENCH_SAMPLE_BEGIN '): phase = line.split(' ', 1)[1]
                    elif line.startswith('BENCH_SAMPLE_END '): phase = ''
                if any(marker in new for marker in ('SCRIPT ERROR', 'SHADER ERROR', 'BENCH_FAIL')):
                    raise RuntimeError('Engine error; see ' + str(folder / 'engine.log'))
                usage = process_usage(process.pid)
                telemetry.append({'wall_seconds': time.monotonic() - started, 'phase': phase,
                                  'thermal_state': thermal_state(), **(usage or {})})
                conflicts.update(foreign_games(process.pid))
                if conflicts:
                    raise RuntimeError('Concurrent game or media process contaminated sample: ' + '; '.join(conflicts))
                if time.monotonic() - started > 900:
                    raise TimeoutError('Variant exceeded 15 minutes.')
        write(folder / 'telemetry.json', telemetry)
        write(folder / 'process.json', {'command': command, 'exit': process.returncode,
              'elapsed_seconds': time.monotonic() - started, 'concurrent_games': sorted(conflicts),
              'watts': None, 'temperature_celsius': None,
              'power_limit': 'powermetrics requires an administrator password; no power or temperature measured'})
        if process.returncode != 0:
            raise RuntimeError('Variant exited with error: ' + str(folder))
        result = json.loads((folder / 'result.json').read_text())
        if result.get('status') != 'complete':
            raise RuntimeError('Incomplete result: ' + str(folder))
        for row in result['samples']:
            entries = [entry for entry in telemetry if entry['phase'] == row['view'] and 'cpu_seconds' in entry]
            if len(entries) >= 2:
                first, last = entries[0], entries[-1]
                row['process_cpu_percent'] = 100 * (last['cpu_seconds'] - first['cpu_seconds']) / (last['wall_seconds'] - first['wall_seconds'])
                row['thermal_states'] = sorted({entry['thermal_state'] for entry in entries if entry['thermal_state'] is not None})
            row['gpu_ms_per_second_estimate'] = row['render_gpu_ms']['median'] * row['fps_mean']
            # Excludes sleeping; >100% CPU means more than one core-equivalent.
            print(json.dumps({'variant': folder.name, 'view': row['view'], 'fps': round(row['fps_mean'], 1),
                              'gpu_ms': round(row['render_gpu_ms']['median'], 3), 'cpu_percent': round(row['process_cpu_percent'], 1) if 'process_cpu_percent' in row else None}, ensure_ascii=False), flush=True)
        write(folder / 'result.json', result)
    except Exception as error:
        failure = str(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        write(folder / 'telemetry.json', telemetry)
        if failure is not None:
            write(folder / 'process.json', {'command': command, 'exit': process.returncode if process is not None else None, 'failure': failure, 'concurrent_workloads': sorted(conflicts), 'elapsed_seconds': time.monotonic() - started, 'watts': None, 'temperature_celsius': None})
        if previous_override is None:
            override.unlink(missing_ok=True)
        else:
            override.write_bytes(previous_override)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, default=ROOT / 'game')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--profiles', default='before,quality,balanced,eco')
    parser.add_argument('--raw', action='store_true')
    parser.add_argument('--views', default='street,plaza_day,farm,lake,store_interior,bedroom,plaza_festival_night,street_walk,street_run')
    parser.add_argument('--seconds', type=float, default=0)
    parser.add_argument('--frames', type=int, default=600)
    parser.add_argument('--settle', type=int, default=180)
    parser.add_argument('--resolution', default='2560x1440')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    # Only the measurement harness is identical on both sides. No optimized runtime
    # script is copied into the original project.
    (args.before / 'scripts/tools/performance_bench.gd').write_bytes((ROOT / 'game/scripts/tools/performance_bench.gd').read_bytes())
    profiles = args.profiles.split(',')
    if any(profile not in ['before', 'quality', 'balanced', 'eco'] for profile in profiles):
        parser.error('Unknown graphics profile')
    write(args.out / 'environment-before.json', power_environment())
    try:
        for profile in profiles:
            project = args.before.resolve() if profile == 'before' else args.after.resolve()
            run_variant(project, args.out / profile, profile, args.raw, args.views, args.seconds, args.frames, args.settle, args.resolution)
    finally:
        write(args.out / 'environment-after.json', power_environment())


if __name__ == '__main__':
    main()
