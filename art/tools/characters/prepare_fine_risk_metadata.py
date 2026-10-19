"""Encode source cloth risk faces as metadata for verified native vertex mapping.

No runtime, visible mesh or binary payload changes. Original glTF face IDs are
audit references only; consumers must map descriptors to the actual imported
main mesh and validate every triangle against its full original LOD0 indices.
"""
from pathlib import Path
import argparse, copy, hashlib, json, struct
import numpy as np
from audit_local_garments import mesh_state
from glb_io import load
from prepare_local_garments import read

WEIGHT_ENCODING = 'gltf-f32-normalize-slots/unorm16-f32-floor/decode-f32'
WEIGHT_SOURCES = [
    'https://github.com/godotengine/godot/blob/c971f93e7/modules/gltf/gltf_document.cpp#L1605-L1663',
    'https://github.com/godotengine/godot/blob/c971f93e7/servers/rendering/rendering_server.cpp#L769-L783',
    'https://github.com/godotengine/godot/blob/c971f93e7/servers/rendering/rendering_server.cpp#L1521-L1531']
SKIN_ATTRIBUTES = ['POSITION', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0', 'JOINTS_1', 'WEIGHTS_1']
SIDES = ['front', 'back']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def digest_arrays(fields):
    h = hashlib.sha256()
    for name, values in fields:
        h.update(name.encode() + b'\0')
        h.update(str(values.shape).encode() + b'\0')
        h.update(values.dtype.str.encode() + b'\0')
        h.update(values.tobytes())
    return h.hexdigest()


def godot_unorm16_signature(joints, weights, joint_names):
    """Pinned Godot importer + renderer encoding, in ORIGINAL 4/8-slot order."""
    assert len(weights) in [4, 8]
    original = np.asarray(weights, dtype=np.float32)
    total = np.float32(0)
    for weight in original:
        total = np.float32(total + weight)
    normalized = original.copy()
    if total > 0:
        for slot in range(len(original)):
            normalized[slot] = np.float32(original[slot] / total)
    scaled = np.asarray(normalized * np.float32(65535), dtype=np.float32)
    # Conversion to uint16 truncates the nonnegative float. It is NOT rounding.
    codes = np.clip(scaled, 0, 65535).astype(np.uint16)
    decoded = np.asarray([np.float32(int(code) / 65535.0) for code in codes], dtype=np.float32)
    aggregated = np.zeros(len(joint_names), np.float32)
    for joint, weight in zip(joints, decoded):
        aggregated[int(joint)] = np.float32(aggregated[int(joint)] + weight)
    influences = sorted([[joint_names[j], float(w)] for j, w in enumerate(aggregated) if w != 0], key=lambda x: x[0])
    return influences, codes.tolist()


def save_json_only(document, input_path, output_path):
    """Keep every non-JSON GLB chunk bit-for-bit, including original padding."""
    original = Path(input_path).read_bytes()
    chunks = []
    offset = 12
    while offset < len(original):
        length, kind = struct.unpack_from('<II', original, offset)
        if kind == 0x4E4F534A:
            content = json.dumps(document, separators=(',', ':'), ensure_ascii=False).encode()
            content += b' ' * ((-len(content)) % 4)
            chunks.append(struct.pack('<II', len(content), kind) + content)
        else:
            chunks.append(original[offset:offset + 8 + length])
        offset += 8 + length
    content = b''.join(chunks)
    Path(output_path).write_bytes(struct.pack('<III', 0x46546C67, 2, len(content) + 12) + content)


def body_attrs(state):
    primitive = state['d']['meshes'][state['node']['mesh']]['primitives'][0]
    return primitive, {name: read(state['d'], state['b'], index) for name, index in primitive['attributes'].items()}


def _selected_faces(risk, args):
    if 'selections' in risk:
        choice = risk['selections'][args.selection][args.ring]
        face_ids = {side: choice[side]['original_glb_source_face_ids'] for side in SIDES}
    elif 'selection' in risk:
        face_ids = {side: risk['selection'][side]['original_glb_source_face_ids'] for side in SIDES}
        assert risk.get('converged') and risk.get('passes_all7_5mm'), 'Closure must be converged and pass its independent all7 gate'
        assert risk['model_sha256'] == risk['native_source_sha256'] == sha(args.input), 'Closure source identity differs from input'
    else:
        face_ids = {side: risk['panels'][side]['source_face_ids'] for side in SIDES}
    return {side: sorted(set(int(i) for i in ids)) for side, ids in face_ids.items()}


def _native_provenance(args, source_sha):
    if not args.native_trace:
        return None
    hashes_path = args.native_trace.parent / 'model-hashes.json'
    hashes = json.loads(hashes_path.read_text())
    assert hashes[f'CH_{args.character}.glb'] == source_sha, 'Native companion hash differs from input'
    rows = [json.loads(line.split(' ', 1)[1]) for line in args.native_trace.read_text().splitlines() if line.startswith('GARMENT_FULL_SOURCE ')]
    rows = [row for row in rows if row['id'] == args.character]
    assert len(rows) == 65, 'Expected the complete source-native65 capture'
    return {'trace': str(args.native_trace), 'trace_sha256': sha(args.native_trace),
            'companion_model_hashes': str(hashes_path), 'companion_model_hashes_sha256': sha(hashes_path),
            'character_source_sha256': hashes[f'CH_{args.character}.glb'], 'captured_character_poses': len(rows)}


def _assert_reference_compatible(args, state, attrs, faces):
    if not args.reference_source:
        return
    reference = mesh_state(args.reference_source, args.character)
    reference_primitive, reference_attrs = body_attrs(reference)
    for name in SKIN_ATTRIBUTES:
        assert (name in attrs) == (name in reference_attrs)
        if name in attrs:
            assert attrs[name].tobytes() == reference_attrs[name].tobytes(), name
    assert faces.tobytes() == read(reference['d'], reference['b'], reference_primitive['indices']).reshape(-1, 3).tobytes()
    old_names = reference['names']
    for name in old_names:
        if name.startswith('Garment_Local_'):
            continue
        assert reference['shapes'][old_names.index(name)].tobytes() == state['shapes'][state['names'].index(name)].tobytes(), name
    assert reference['binds'].tobytes() == state['binds'].tobytes()


def _dense_skin(state, joint_names):
    dense = np.zeros((len(state['positions']), len(joint_names)), np.float32)
    for slot in range(state['joints'].shape[1]):
        np.add.at(dense, (np.arange(len(dense)), state['joints'][:, slot]), state['weights'][:, slot])
    return dense


def _vertex_entries(state, attrs, used, joint_names, dense, morph, absolute):
    vertices = []
    for index, original in enumerate(used):
        influences = sorted([[joint_names[j], float(w)] for j, w in enumerate(dense[original]) if w != 0], key=lambda x: x[0])
        quantized, codes = godot_unorm16_signature(state['joints'][original], state['weights'][original], joint_names)
        vertices.append({'source_vertex_for_audit': int(original),
                         'position': attrs['POSITION'][original].astype(float).tolist(),
                         'uv': attrs['TEXCOORD_0'][original].astype(float).tolist(),
                         'influences': influences,
                         'godot_unorm16_influences': quantized, 'godot_unorm16_codes_by_slot': codes,
                         'godot_unorm16_bone_names_by_slot': [joint_names[int(j)] for j in state['joints'][original]],
                         'morph_delta_position_sha256': hashlib.sha256(morph[index].tobytes()).hexdigest(),
                         'morph_absolute_position_sha256': hashlib.sha256(absolute[index].tobytes()).hexdigest()})
    return vertices


def _panel_entries(state, faces, face_ids, names, compact):
    panels = {}
    for side in SIDES:
        ids = face_ids[side]
        local_ids = [i for i, name in enumerate(names) if name.startswith('Garment_Local_' + side.title() + '_')]
        support = np.sum([abs(state['shapes'][i][:, 2].astype(float)) for i in local_ids], axis=0)
        assert np.all(support[faces[ids]] >= 1e-6), 'Risk selection includes a triangle outside stable current per-side Local mask'
        panels[side] = {'indices': [[compact[int(i)] for i in face] for face in faces[ids]], 'source_face_ids_for_audit': ids}
    return panels


def _save_profile(args, state, profile):
    document = copy.deepcopy(state['d'])
    rig = next(n for n in document['nodes'] if n.get('name') == 'Rig')
    assert 'fine_risk_proxy' not in rig['extras']['garment_local_clearance'], 'Input already has a fine-risk profile'
    rig['extras']['garment_local_clearance']['fine_risk_proxy'] = profile
    args.output.parent.mkdir(parents=True, exist_ok=True)
    save_json_only(document, args.input, args.output)
    actual, binary = load(args.output)
    assert binary == state['b'], 'Metadata operation changed original BIN chunk'
    check = copy.deepcopy(actual)
    check_rig = next(n for n in check['nodes'] if n.get('name') == 'Rig')
    del check_rig['extras']['garment_local_clearance']['fine_risk_proxy']
    assert check == state['d'], 'JSON outside new profile changed'


def prepare(args):
    state = mesh_state(args.input, args.character)
    risk = json.loads(args.risk.read_text())
    assert risk.get('character', args.character) == args.character
    input_sha = sha(args.input)
    primitive, attrs = body_attrs(state)
    faces = read(state['d'], state['b'], primitive['indices']).reshape(-1, 3)
    face_ids = _selected_faces(risk, args)
    native_provenance = _native_provenance(args, input_sha)
    _assert_reference_compatible(args, state, attrs, faces)
    all_ids = [i for ids in face_ids.values() for i in ids]
    assert all_ids and min(all_ids) >= 0 and max(all_ids) < len(faces)
    used = np.unique(faces[all_ids])
    compact = {int(i): k for k, i in enumerate(used)}
    joint_names = [state['d']['nodes'][i]['name'] for i in state['skin']['joints']]
    dense = _dense_skin(state, joint_names)
    names = state['names']
    morph = np.stack([delta[used] for delta in state['shapes']], axis=1).astype('<f4')
    absolute = (state['positions'][used, None, :] + morph).astype('<f4')
    vertices = _vertex_entries(state, attrs, used, joint_names, dense, morph, absolute)
    profile = {'version': 1, 'character': args.character, 'source_glb_sha256': input_sha,
               'risk_selection_sha256': sha(args.risk), 'risk_native_source_sha256': risk.get('source_sha256', risk.get('native_source_sha256')),
               'selection': args.selection if 'selections' in risk else 'external_source_face_selection',
               'ring': args.ring if 'selections' in risk else 'external_selection',
               'risk_source_native65_provenance': native_provenance,
               'offline_closure': {'converged': risk.get('converged', False), 'passes_all7_5mm': risk.get('passes_all7_5mm', False),
                                   'model_sha256': risk.get('model_sha256'), 'native_source_sha256': risk.get('native_source_sha256'),
                                   'selection_rule': risk.get('selection_rule'), 'scope': risk.get('scope')},
               'scope': 'Preflight source-native sampled risk selection; runtime must verify imported geometry mapping and original full LOD0 triangle membership. Not final pose completeness or native acceptance.',
               'mask_policy': {'side': 'Front/Back by Local target name', 'quantity': 'sum(abs(POSITION.z)) across all Local targets of that side',
                               'minimum_total_displacement_m': 1e-6, 'basis_independent': True},
               'mapping': {'source_indices_are_audit_only': True, 'match_fields': ['position', 'uv', 'influences_by_canonical_bone_name'],
                           'canonical_bone_names': 'glTF joint node names; normalize only the known Godot mixamorig colon/underscore prefix conversion',
                           'position_tolerance_m': 1e-5, 'uv_tolerance': 1e-5, 'weight_tolerance': 1e-6,
                           'godot_weight_encoding': WEIGHT_ENCODING,
                           'godot_quantized_weight_tolerance': 1e-7,
                           'godot_weight_encoding_sources': WEIGHT_SOURCES,
                           'weight_policy': 'Strictly compare predicted Godot decoded UNORM16 influences at <=1e-7; raw source differences are diagnostic only, never broaden raw tolerance; missing prediction or one-code mismatch rejects risk mapping.',
                           'require_triangle_membership_in_actual_main_imported_full_LOD0': True,
                           'ambiguous_vertex_policy': 'compare named target POSITION fingerprints/values and original triangle topology; reject unresolved ambiguity, do not choose the first coincident vertex',
                           'fingerprint_format': 'SHA256 of target-order float32 little-endian VEC3 rows; absolute uses float32(base POSITION + target delta). Names below define row order. Exact hashes are audit aids; importer conversion may require value tolerance diagnostics.'},
               'morph_target_names': names, 'vertices': vertices, 'panels': _panel_entries(state, faces, face_ids, names, compact)}
    edge_threshold = risk.get('edge_threshold_m')
    if edge_threshold is not None:
        assert float(edge_threshold) > 0
        profile['body_query_policy'] = {'version': 1, 'centroids': 'all_physical_body_faces',
                                        'edge_rest_min_length_m': float(edge_threshold),
                                        'edge_position': 'midpoint_of_final_skinned_corners'}
    profile['offline_closure'].update({'sample_count': len(risk.get('samples', [])),
                                       'edge_threshold_m': edge_threshold,
                                       'generic_added_body_queries': risk.get('generic_added_body_queries'),
                                       'source_surface_gate': risk.get('source_surface_gate')})
    profile['geometry_skin_sha256'] = digest_arrays([(name, attrs[name]) for name in SKIN_ATTRIBUTES if name in attrs]
                                                    + [('indices', faces), ('inverseBindMatrices', state['binds'])])
    profile['joint_names_sha256'] = hashlib.sha256(json.dumps(joint_names, separators=(',', ':')).encode()).hexdigest()
    profile['local_fields_sha256'] = digest_arrays([(name, state['shapes'][i]) for i, name in enumerate(names) if name.startswith('Garment_Local_')])
    _save_profile(args, state, profile)

    args.report.parent.mkdir(parents=True, exist_ok=True)
    sidecar = args.report.with_name(args.report.stem + '-profile.json')
    sidecar.write_text(json.dumps(profile, separators=(',', ':'), ensure_ascii=False) + '\n')
    report = {'stage': 'metadata-only-fine-risk-mapping-candidate', 'input': str(args.input), 'input_sha256': input_sha,
              'risk_selection': str(args.risk), 'risk_sha256': sha(args.risk), 'output': str(args.output),
              'output_sha256': sha(args.output), 'tool_sha256': sha(__file__), 'metadata_profile': str(sidecar),
              'metadata_profile_sha256': sha(sidecar), 'used_source_vertices': len(vertices),
              'source_faces': {side: len(ids) for side, ids in face_ids.items()},
              'all_original_BIN_bytes_and_nonprofile_JSON_exact': True,
              'mesh_skin_skeleton_all_curves_all_targets_exact': True,
              'current_sumabs_mask_eligibility_confirmed': True,
              'reference_source_geometry_skin_nonlocal_morph_compatibility': str(args.reference_source) if args.reference_source else None,
              'profile_bytes': sidecar.stat().st_size,
              'native_mapping_and_reimport_validation': 'pending; no Godot started',
              'risk_source_native65_provenance': native_provenance,
              'offline_closure_converged_and_all7_passed': bool(risk.get('converged') and risk.get('passes_all7_5mm')),
              'godot_weight_encoding': WEIGHT_ENCODING}
    report['body_query_policy'] = profile.get('body_query_policy')
    report['generic_added_body_queries'] = risk.get('generic_added_body_queries')
    report['offline_closure_samples'] = len(risk.get('samples', []))
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(args.report, report['output_sha256'], len(vertices), 'vertices', flush=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--risk', required=True, type=Path)
    p.add_argument('--report', required=True, type=Path)
    p.add_argument('--character', required=True, choices=['mio', 'kazuko'])
    p.add_argument('--reference-source', type=Path)
    p.add_argument('--native-trace', type=Path)
    p.add_argument('--selection', default='actual_or_zero_near6mm')
    p.add_argument('--ring', default='shared_physical_edge_one_ring', choices=['direct', 'shared_physical_edge_one_ring'])
    prepare(p.parse_args())
