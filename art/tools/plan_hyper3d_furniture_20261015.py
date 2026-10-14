"""Record the full reusable furniture scope before paid CLI submissions."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[2]
STYLE='Japanese TV-anime game prop, clean cel colours, subtle hand-painted grain, rounded functional joinery, restrained lacquer sheen, no photorealism. '
SPECS=[
('HFF01_cafe_chair','弧背木椅',[.48,.89,.47],'One complete curved-back wooden cafe chair; shallow sculpted seat at 48cm; four separate level legs, real rails and open gaps.',['P_cafe_table chair pair','P_community_table six chairs','compatible home dining chairs']),
('HFF02_round_table','咖啡圆桌',[.72,.76,.72],'One empty round wooden pedestal table, rounded circular top, one slender central pedestal and low wide round foot.',['P_cafe_table table','community reading tea table']),
('HFF03_rect_table','长方餐桌与工作桌',[2.05,.75,1.0],'One empty rectangular cedar table with rounded thick top, four dark tapered legs, visible apron and real joinery, open knee space and flat usable top.',['P_community_table tabletop','bakery kneading table','resident desks and workbenches','postal/library/flower desks']),
('HFF04_low_table','日式矮桌',[1.45,.43,.85],'One empty low rectangular Japanese cedar table, rounded broad top, four short thick legs and real open under-table space, no cloth or props.',['FamilyLowTable','AoiDrawingDesk','RoundConversationTable','compatible low home tables']),
('HFF05_utility_stand','双层小工作架',[.90,.84,.60],'One empty compact cedar utility work stand, thick rounded flat top at84cm, one lower flat shelf at20cm, four legs, real open gaps.',['PrepShelf','HerbLedge','CafeReturnStation','WrappingBench','resident side and storage shelves']),
('HFF06_indoor_bench','室内木长凳',[1.55,.43,.52],'One empty backless indoor cedar sitting bench, softly rounded solid seat at43cm, four short sturdy legs and dark lower cross rails, real open gaps.',['VisitSeat household seating','EngawaWindowSeat','BootChangingBench','WaitingBench','ArchiveBagBench']),
('HFF07_sage_counter','鼠尾草绿木柜台',[2.11,.87,1.15],'One empty sage-green bakery counter with honey cedar rounded top, three inset green front panels, brass cup pulls and low brass foot rail. No register or attached glass case.',['I04_shop_counter bakery/store','compatible shop checkout']),
('HFF08_bread_rack4','四层面包架',[1.07,1.51,.62],'One empty narrow four-tier cedar bread rack with shallow tray lips and thin corner uprights. Exactly four level usable shelves at28/62/95/127cm. All gaps open; no products or labels.',['I05_bread_shelf two bakery racks','compatible pantry shelves']),
('HFF09_bread_rack3','三层陈列架',[1.09,1.25,.50],'One empty three-tier cedar display rack with shallow tray lips and thin corner uprights. Exactly three level usable shelves at36/66/101cm. Open spaces, no goods.',['W17_display_shelf bakery and general displays']),
('HFF10_wall_shelf','双层壁挂搁架',[1.60,.72,.30],'One complete empty two-tier wall-mounted cedar shelf with two thick rounded level boards and two slim vertical support rails, visible brackets, no wall or floor, no products.',['bakery flour wall shelf','compatible resident/public wall shelves']),
('HFF11_glass_case','透光糕点柜',[1.34,1.149,.75],'One empty bakery display cabinet: sage low plinth, slender rounded cedar frame, two ivory display shelves, thin transparent glass front/sides/top. See fully through glass into real cavity. No opaque blue slab, cakes, labels or attached counter.',['I02_cake_showcase','compatible bakery/store clear displays']),
('HFF12_reading_armchair','阅读扶手椅',[.605,.89,.51],'One cedar reading armchair with gently curved back, rounded wooden arms, muted sage fabric seat and back cushion, four level legs, visible frame joints and real gaps. Seat48cm high.',['P_reading_chair public and resident interiors']),
('HFF13_espresso_station','咖啡机与底柜',[1.0,1.325,.685],'One compact espresso station: sage cupboard, rounded cedar worktop, brushed steel espresso machine with real open work bay, two group heads, drip grid, curved steam wand, grinder with clear amber hopper and visible beans. No wall or extra furniture.',['P_coffee_station bakery station','glass hopper verification']),
('HFF14_outdoor_bench','户外木长椅',[1.80,.83,.60],'One Japanese small-town outdoor wooden bench: honey cedar rounded seat boards and gently curved slatted backrest, dark wooden supports, all four feet level, real slat gaps. Maintained slight weathering, no moss covering usable seat.',['A12_bench town/farm/lake nine existing seating points'])
]

def main():
 rows=[]
 for aid,label,size,subject,reuse in SPECS:
  prompt=STYLE+subject+' Reconstruct only the referenced object with original textures, straight level supports and actual open spaces. No background or ground platform. Keep transparent panels separate from timber; do not paint reflections onto wood.'
  assert len(prompt)<=1024
  rows.append(dict(id=aid,label=label,reference=f'art/references/hyper3d_furniture_20261015/{aid}.png',subject=subject,model_prompt=prompt,tier='Gen-2.5-High',mesh_mode='Quad',quality=18000,nominal_size_m_xyz=size,reuse_targets=reuse,status='reference_or_generation_pending'))
 inventory=[]
 for name in ['public_place_art.gd','public_room_life.gd','resident_interior_builder.gd','interior_builder.gd','house_builder.gd']:
  file=ROOT/'game/scripts/world'/name
  for number,line in enumerate(file.read_text().splitlines(),1):
   if re.search(r'(?i)(bench\(|_table\(|P_cafe_table|P_community_table|P_reading_chair|J03_dining_set|J07_kotatsu|_worktable\(|_wall_shelf\()',line):
    inventory.append(dict(file=str(file.relative_to(ROOT)),line=number,expression=line.strip()))
 payload=dict(schema_version=1,date='2026-10-15',objective='Hyper3D rebuild of all named non-Hyper3D bakery furniture plus compatible reuse throughout the game, real glass verified',provider='Hyper3D CLI Gen-2.5-High',credit_budget=dict(expected_each=.5,primary_assets=14,first_round=7,max_submission_slots=28,max_spend=14,minimum_available_after=136,pricing_source='https://docs.hyper3d.ai/en/api-specification/rodin-gen2-5#pricing'),assets=rows,existing_furniture_inventory=inventory,acceptance=['Preserve visible Hyper3D generated principal geometry and original generated UV/albedo; local repair must be recorded, never replace it wholesale with procedural furniture.','All bakery named tables/chairs/racks/counters and espresso station replaced; reuse compatible tables/seats throughout public/resident/home/outdoor areas.','Actual glass cavities, independent thin panels, visible interior stock, view-dependent subtle reflection; multi-angle/day/night native screenshots.','Actual shelf/table/seat support and use, paths/collisions, old failure proof, exclusive full suite, native package shots/seating/autoplay, latest-only package and clean temporary stages.'])
 target=ROOT/'art/manifests/hyper3d_furniture_20261015.json';target.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n')
 print('Recorded',len(rows),'Hyper3D source assets and',len(inventory),'existing furniture construction sites')

if __name__=='__main__':main()
