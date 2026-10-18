"""Verify source-pose frames and encode their actual native rendered pixels.

Use the process/sample clock, not the window draw counter: on macOS an explicit
RenderingServer draw can update the texture while the window counter is paused.
Decoded native PNG/MP4 pixel matches independently establish the frame mapping.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

import numpy as np
from PIL import Image


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def encode(folder):
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    assert ffmpeg and ffprobe
    journal = json.loads((folder/'movie-journal.json').read_text())
    frames = journal['frames']
    assert len(frames) == 720 and journal['fps'] == 30
    assert journal['game_modifiers'] == 0 and journal['explicit_native_viewport_draw']
    assert journal['no_focus'] and journal['renderer'] == 'forward_plus'
    assert [row['sample_index'] for row in frames] == list(range(720))
    clock = [row['process_frame'] for row in frames]
    assert clock == list(range(clock[0],clock[0]+720))
    for row in frames:
        assert len(row['states']) == 2
        for state in row['states']:
            assert state['clip'] == row['clip'] and abs(state['time']-row['time']) < .00002
            assert len(state['legs']) == 6 and np.isfinite(list(state['legs'].values())).all()
    for source in journal['sources'].values():
        assert sha(Path(source['path'])) == source['sha256']
    source_hashes = {row['file']:sha(folder/row['file']) for row in frames}
    assert len(source_hashes) == 720
    for filename in source_hashes:
        with Image.open(folder/filename) as source_image:
            assert source_image.size == (1920,1080), 'Native viewport was resized or cropped: '+filename
    video = folder/'video.mp4'
    assert not video.exists(), 'Choose a new output; do not overwrite accepted videos'
    command = [ffmpeg,'-v','error','-filter_threads','2','-framerate','30','-start_number','0','-i',str(folder/'frames/%04d.png'),'-vf','scale=1920:1080:in_range=full:out_range=tv:out_color_matrix=bt709,format=yuv420p',
               '-an','-c:v','libx264','-threads','2','-preset','fast','-crf','18','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709','-movflags','+faststart',str(video)]
    subprocess.run(command,check=True)
    shots = json.loads((folder/'native-stills.json').read_text())['shots']
    offsets = [-1,0,1]
    indices = sorted({shot['sample_index']+d for shot in shots for d in offsets})
    select = '+'.join('eq(n\\,'+str(n)+')' for n in indices)
    data = subprocess.check_output([ffmpeg,'-v','error','-i',str(video),'-vf',f'select={select},scale=320:180:flags=bilinear,format=rgb24','-fps_mode','passthrough','-f','rawvideo','-'])
    pixels = np.frombuffer(data,np.uint8).reshape(len(indices),180,320,3).astype(float)
    decoded = dict(zip(indices,pixels))
    matches = []
    for shot in shots:
        assert sha(folder/shot['file']) == source_hashes[frames[shot['sample_index']]['file']], 'Still/frame identity mismatch'
        source = subprocess.check_output([ffmpeg,'-v','error','-i',str(folder/shot['file']),'-vf','scale=320:180:flags=bilinear,format=rgb24','-frames:v','1','-f','rawvideo','-'])
        source = np.frombuffer(source,np.uint8).reshape(180,320,3).astype(float)
        error = {str(d):float(np.abs(source-decoded[shot['sample_index']+d]).mean()) for d in offsets}
        # At a flexion turning point the motion is almost stationary. Lossy H.264
        # quantization can make an adjacent frame marginally closer (< .01 of
        # one RGB code value averaged over the image). Keep the absolute gate,
        # allow only .02 code values locally, and require the complete sample
        # set to prefer the exact frame over either one-frame shift by .1.
        assert error['0'] < 3. and error['0'] <= min(error.values())+.02, error
        matches.append({'file':shot['file'],'sample_index':shot['sample_index'],'mean_absolute_rgb_error_by_offset':error})
    average_error = {str(d):float(np.mean([row['mean_absolute_rgb_error_by_offset'][str(d)] for row in matches])) for d in offsets}
    assert all(average_error['0'] + .1 < average_error[str(d)] for d in [-1,1]), average_error
    probe = json.loads(subprocess.check_output([ffprobe,'-v','error','-count_frames','-show_streams','-show_format','-of','json',str(video)]))
    assert len(probe['streams']) == 1
    stream = probe['streams'][0]
    assert (stream['width'],stream['height']) == (1920,1080)
    assert (stream['nb_read_frames'],stream['r_frame_rate'],stream['pix_fmt']) == ('720','30/1','yuv420p')
    assert abs(float(probe['format']['duration'])-24.) < .001
    subprocess.run([ffmpeg,'-v','error','-xerror','-err_detect','explode','-i',str(video),'-f','null','-'],check=True)
    checksums = subprocess.check_output([ffmpeg,'-v','error','-i',str(video),'-map','0:v','-f','framemd5','-'],text=True)
    frame_hashes = [line.rsplit(',',1)[-1].strip() for line in checksums.splitlines() if not line.startswith('#')]
    assert len(frame_hashes) == 720
    repeat = maximum_repeat = 1
    for previous,current in zip(frame_hashes,frame_hashes[1:]):
        repeat = repeat+1 if previous == current else 1
        maximum_repeat = max(maximum_repeat,repeat)
    assert maximum_repeat <= 3, 'Unexpected frozen video frames'
    receipt = {'passed':True,'scope':'Native GLB source animations and controlled flexion, all game modifiers absent; not a normal-gameplay or MotionBricks-retarget video',
               'frames':720,'fps':30,'seconds':24,'native_resolution':[1920,1080],'sources':journal['sources'],
               'journal_sha256':sha(folder/'movie-journal.json'),'video_sha256':sha(video),'native_frame_sha256':source_hashes,
               'same_frame_png_mp4_matches':matches,'process_frames_consecutive':True,'window_draw_counter_is_not_the_movie_clock':True,
               'native_stills_equal_exact_sequence_frames':True,'average_rgb_error_by_offset':average_error,
               'codec_tolerance_rgb_code_values':.02,'required_average_shift_rejection_margin':.1,
               'strict_full_decode_passed':True,'maximum_consecutive_equal_decoded_frames':maximum_repeat,'probe':probe,'encode_command':command}
    (folder/'media-verification.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
    shutil.rmtree(folder/'frames')
    print(json.dumps({'video':str(video),'passed':True,'frames':720,'seconds':24,'pixel_matches':len(matches)},ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder',type=Path)
    encode(parser.parse_args().folder.resolve())
