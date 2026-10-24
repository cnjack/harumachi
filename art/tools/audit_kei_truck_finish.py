"""Check actual vehicle material separation and formed metal detail.

Blender -b --factory-startup -P art/tools/audit_kei_truck_finish.py -- model.glb report.json
Runs the existing aperture, footprint, tyre, arch and reflector audit first.
The 2026-10-24 first truck fails this extension before the detail revision.
"""
import json
import math
from pathlib import Path
import runpy
import sys

audit = runpy.run_path(str(Path(__file__).with_name('audit_kei_truck_detail.py')))
checks = audit['checks']
facts = audit['facts']
objects = audit['objects']
hits = audit['hits']
named = audit['named']
points = audit['points']
bounds = audit['bounds']

materials = {}
for obj in objects:
    for material in obj.data.materials:
        if not material or not material.use_nodes:
            continue
        bsdf = next((n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if not bsdf:
            continue
        materials[material.name] = {key: float(bsdf.inputs[key].default_value)
                                   for key in ['Metallic', 'Roughness', 'Alpha']}
facts['actual_materials'] = materials
paint = materials.get('Ivory_painted_body', {})
steel = materials.get('Matte_wheel_steel', {})
rubber = materials.get('Tyre_rubber', {})
lens = materials.get('Headlamp_optical_glass', {})
checks['paint_steel_rubber_have_distinct_physical_finishes'] = (
    .32 <= paint.get('Roughness', 1) <= .55 and paint.get('Metallic', 1) < .05
    and .54 <= steel.get('Metallic', 0) <= .9 and .24 <= steel.get('Roughness', 1) <= .45
    and rubber.get('Metallic', 1) < .01 and rubber.get('Roughness', 0) >= .85)
checks['headlamp_lenses_are_single_thin_transmitting_shells'] = (
    len(named('Headlight_Left_Lens') + named('Headlight_Right_Lens')) == 2
    and .15 <= lens.get('Alpha', 1) <= .45 and lens.get('Metallic', 1) < .01
    and .15 <= lens.get('Roughness', 1) <= .30)

rim_profiles = []
valves = []
for side in [-1, 1]:
    for z in [1.075, -1.11]:
        samples = []
        for radius in [.135, .199]:
            y = .325 + radius * math.cos(math.pi / 6)
            zz = z + radius * math.sin(math.pi / 6)
            sample = hits((side * 1.01, y, zz), (side * .79, y, zz))
            samples.append(abs(sample[0][2][0]) if sample else 0.0)
        rim_profiles.append(samples)
        angle = math.radians(-45)
        y = .325 + .177 * math.cos(angle)
        zz = z + .177 * math.sin(angle)
        valves.append(bool(hits((side * .99, y, zz), (side * .900, y, zz))))
facts['rim_bowl_and_flange_x'] = rim_profiles
checks['all_four_rims_have_a_pressed_bowl_behind_the_flange'] = all(
    outer - inner >= .017 for inner, outer in rim_profiles)
facts['actual_valve_probe_hits'] = valves
checks['all_four_wheels_have_stood_off_tyre_valves'] = all(valves)

grooves = []
for obj in named('Tyre_'):
    low, high = bounds(obj)
    centre = (low + high) * .5
    radii = [math.hypot(v.y - centre.y, v.z - centre.z) for v in points(obj)
             if abs(v.x - centre.x) < .0701]
    grooves.append(max(radii) - min(radii))
facts['physical_tread_groove_depths'] = grooves
checks['tyre_tread_has_real_circumferential_grooves'] = len(grooves) == 4 and min(grooves) >= .006

stamp_profiles = []
locking_pins = []
for side in [-1, 1]:
    depths = []
    for z in [-.76, -.442]:
        sample = hits((side * 1.01, .878, z), (side * .84, .878, z))
        depths.append(abs(sample[0][2][0]) if sample else 0.0)
    stamp_profiles.append(depths)
    for z in [-1.57, .05]:
        locking_pins.append(bool(hits((side * 1.0, 1.022, z),
                                      (side * .928, 1.022, z), ['SidegateLatch_'])))
facts['cargo_stamp_and_surround_x'] = stamp_profiles
checks['drop_sides_have_recessed_pressings_in_the_actual_metal'] = all(
    outside - inside >= .005 for inside, outside in stamp_profiles)
facts['actual_locking_pin_hits'] = locking_pins
checks['four_gate_latches_have_captive_pins_clear_of_the_mounting_plate'] = all(locking_pins)

hinge_gaps = []
for x in [-.55, .55]:
    for offset in [-.030, .030]:
        hinge_gaps.append(not hits((x + offset, .755, -1.79),
                                  (x + offset, .755, -1.742), ['TailgateHinge_']))
facts['hinge_knuckle_clearance_probes'] = hinge_gaps
checks['rear_hinges_have_distinct_knuckles_with_real_clearance'] = all(hinge_gaps)

facts['triangles'] = sum(len(p.vertices) - 2 for o in objects for p in o.data.polygons)
facts['mesh_nodes'] = len(objects)
checks['detail_stays_within_the_local_vehicle_budget'] = facts['triangles'] <= 105000 and len(objects) <= 52
report = audit['report']
report['checks'] = checks
report['measurements'] = facts
report['passed'] = all(checks.values())
audit['output'].write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'passed': report['passed'], 'checks': checks}, ensure_ascii=False))
if not report['passed']:
    sys.exit(1)
