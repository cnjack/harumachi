#!/usr/bin/env python3
"""Audit the actual 90-second promo and its sources; never approve missing media.

--media-only writes a media readiness record before publication. The final audit
also requires a matching remote commit and successful CI evidence.
"""
import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'evidence/promo_20261015'
OUTPUT = ROOT / 'outputs/harumachi-promo-20261015'
NAMES = {'bridge', 'town', 'breakfast', 'bakery', 'farm', 'fishing', 'lantern', 'festival'}


def read(path):
    return json.loads(path.read_text())


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--media-only', action='store_true')
    args = parser.parse_args()
    plan = read(ROOT / 'art/manifests/promo_20261015.json')
    assert plan['review_status'] == 'approved', 'Animation source review is unfinished'
    assert plan.get('master_review_status') == 'approved', 'Final master review is unfinished'
    assert not plan.get('pending_extra_generation'), 'Additional generation is still required'
    shots = plan['shots']
    assert len(shots) == 17 and plan['duration_seconds'] == 90
    assert abs(sum(row['duration'] for row in shots) - (len(shots) - 1) * plan['transition_seconds'] - 90) < 1e-6
    animations = [row for row in shots if row['kind'] == 'animation']
    assert {row['id'].removesuffix('_cg') for row in animations} == NAMES
    assert sum(row['duration'] for row in animations) == 60
    assert {row['id'] for row in shots if row['kind'] == 'gameplay'} == {
        'town_walk', 'cooking', 'cafe', 'harvest', 'water', 'reel_and_catch', 'lantern_assembly', 'festival_dance'
    }
    reviews = read(EVIDENCE / 'animation-reviews.json')
    generated = []
    for row in animations:
        name = row['id'].removesuffix('_cg')
        source = ROOT / row['file']
        job = read(source.parent / 'job.json')
        transfer = read(source.parent / 'range-verification.json')
        actual_hash = digest(source)
        review = reviews[name]
        assert job['model'] == 'minimax-h3' and job['status'] == 'completed'
        assert job['id'] == transfer['job_id'] and transfer['all_ranges_verified']
        assert transfer['sha256'] == actual_hash == review['source_sha256']
        assert review['approved'] and review['full_decode_passed']
        assert review['duration'] >= row['start'] + row['duration']
        assert len(review['reviewed_times']) >= row['duration'] * 2
        generated.append({'name': name, 'job_id': job['id'], 'sha256': actual_hash, 'motion_review': review})
    images = read(ROOT / 'art/manifests/images_codex.json')['images']
    for name in NAMES:
        path = 'art/references/promo_20261015/' + name + '.png'
        entry = next(row for row in images if row['file'] == path)
        assert 'built-in' in entry['tool'] and (ROOT / path).stat().st_size > 10000
        assert (ROOT / entry['reference']).is_file() and (ROOT / entry['prompt']).is_file()
    native = read(EVIDENCE / 'native-media-verification.json')
    for row in native:
        assert row['full_decode'] and digest(Path(row['file'])) == row['sha256']
    gameplay = read(EVIDENCE / 'gameplay/report.json')
    assert gameplay['passed'] and len(gameplay['checks']) == 205
    assert gameplay['fresh_run'] and gameplay['driver_player_teleports'] == 0
    assert gameplay['q05'] == 'done' and gameplay['q15'] == 'done'
    assert read(EVIDENCE / 'lake/demo.json')['passed']
    assert 'PROMO_ACTION promo_water passed=true' in (EVIDENCE / 'water-process.log').read_text()
    music_job = read(OUTPUT / 'music-90/job.json')
    assert music_job['status'] == 'succeeded' and 'Music3-MLX' in music_job['request']['model']
    assert digest(ROOT / plan['music']) == music_job['verification']['sha256']
    assert music_job['verification']['clipped_samples'] == 0
    assert not read(EVIDENCE / 'music-energy.json')['long_interior_silence']
    vocal_text = (EVIDENCE / 'music-vocal-check.log').read_text()
    vocal = json.loads(re.search(r'song.wav (\{.*\})', vocal_text).group(1))
    assert vocal['voc_hot_s'] == 0 and vocal['stem_voice_max'] < 0.15 and vocal['mix_voice_max'] < 0.08
    title = next(row for row in shots if row['kind'] == 'title')
    festival = next(row for row in animations if row['id'] == 'festival_cg')
    assert title['source_frame'] == 191 and title['source_video'] == festival['file']
    last_frame = subprocess.check_output([
        'ffmpeg', '-v', 'error', '-i', str(ROOT / festival['file']), '-vf', 'select=eq(n\\,191)',
        '-frames:v', '1', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-'
    ])
    with Image.open(ROOT / title['file']) as endcard:
        assert endcard.convert('RGB').tobytes() == last_frame, 'Endcard does not match the last animated frame'
    master = OUTPUT / 'harumachi-trailer-90s.mp4'
    media = read(EVIDENCE / 'review-master/media.json')
    visual = read(EVIDENCE / 'master-visual-review.json')
    master_hash = digest(master)
    assert media['sha256'] == master_hash == visual['sha256']
    assert media['full_decode_passed'] and visual['approved']
    assert set(visual['reviewed_shot_ids']) == {row['id'] for row in shots}
    start = 0
    required_times = []
    for index, row in enumerate(shots):
        required_times.append(start + row['duration'] / 2)
        if index:
            required_times.append(start + plan['transition_seconds'] / 2)
        start += row['duration'] - plan['transition_seconds']
    for timestamp in required_times:
        assert any(abs(timestamp - sampled) < 0.04 for sampled in media['times']), 'Missing shot or transition sample'
    streams = media['probe']['streams']
    video = next(row for row in streams if row['codec_type'] == 'video')
    audio = next(row for row in streams if row['codec_type'] == 'audio')
    assert video['codec_name'] == 'h264' and video['width'] == 1920 and video['height'] == 1080
    assert video['r_frame_rate'] == '30/1' and int(video['nb_frames']) == 2700
    assert video['pix_fmt'] == 'yuv420p'
    assert video['color_range'] == 'tv' and video['color_space'] == 'bt709'
    assert audio['codec_name'] == 'aac' and int(audio['sample_rate']) == 48000 and audio['channels'] == 2
    assert abs(float(media['probe']['format']['duration']) - 90) < 0.05
    loudness = read(EVIDENCE / 'master-audio-measure.json')
    final_vocal = read(EVIDENCE / 'master-vocal-check.json')
    assert loudness['source_sha256'] == master_hash == final_vocal['source_sha256']
    assert abs(float(loudness['input_i']) + 16) <= 1
    assert float(loudness['input_tp']) <= -1.0
    assert final_vocal['voc_hot_s'] == 0 and final_vocal['stem_voice_max'] < 0.15 and final_vocal['mix_voice_max'] < 0.08
    atoms = {}
    with master.open('rb') as source:
        while len(atoms) < 2:
            offset = source.tell()
            header = source.read(8)
            assert len(header) == 8
            size, kind = struct.unpack('>I4s', header)
            if size == 1:
                size = struct.unpack('>Q', source.read(8))[0]
            assert size >= 8
            if kind in (b'moov', b'mdat'):
                atoms[kind.decode()] = offset
            source.seek(offset + size)
    assert atoms['moov'] < atoms['mdat'], 'MP4 is not optimized for streaming'
    sys.path.insert(0, str(ROOT / 'tools'))
    from visual_qa import save_hashes
    stage = read(EVIDENCE / 'capture-stage.json')
    assert save_hashes() == stage['default_saves_before']
    assert not Path(stage['stage']).exists() and read(EVIDENCE / 'cleanup.json')['stage_removed']
    assert not subprocess.check_output(['git', 'diff', stage['source_commit'], '--', 'game'], cwd=ROOT).strip()
    assert read(EVIDENCE / 'native-delivery.json')['passed']
    assert (OUTPUT / 'native-version/harumachi-trailer-90s.mp4').is_file()
    result = {'passed': True, 'goal_complete': False, 'file': str(master.relative_to(ROOT)),
              'sha256': master_hash, 'bytes': master.stat().st_size, 'duration_seconds': 90,
              'width': 1920, 'height': 1080, 'fps': 30, 'frames': 2700,
              'animation_source_seconds': 60, 'gameplay_source_seconds': 29, 'title_source_seconds': 5,
              'transition_overlap_seconds': 4, 'full_decode': True, 'motion_sources': generated,
              'visual_review': visual, 'audio_loudness': loudness, 'music_vocal_check': vocal,
              'final_mix_vocal_check': final_vocal,
              'audio_subjective_listening': False, 'default_save_unchanged': True,
              'default_save_files': len(stage['default_saves_before']), 'game_source_unchanged': True,
              'mp4_faststart': True, 'native_version_preserved': True}
    if not args.media_only:
        push = read(EVIDENCE / 'final-source-push.json')
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        assert push['commit'] == head and push['remote_verified'] and push['ci']['conclusion'] == 'success'
        assert push['ci']['head_sha'] == head
        result.update(goal_complete=True, source_publication=push)
    target = EVIDENCE / ('delivery-media.json' if args.media_only else 'delivery.json')
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(target)


if __name__ == '__main__':
    main()
