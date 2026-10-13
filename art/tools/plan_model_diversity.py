"""Write the fixed 60-asset scope and 120-slot credit plan; never calls a service."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'art/manifests/model_diversity_20261013.json'
STYLE = ('Japanese TV anime slice-of-life game prop. Clean confident fine contours, '
         'simple but carefully constructed solid shapes, flat matte colours with two crisp '
         'cel shadow bands, pale lavender shadows and warm highlights. No photographic '
         'texture, gritty weathering, metallic reflections, random noise, oil painting or '
         'faceted triangular low-poly leaves. The same clean anime art direction throughout. ')
MODEL_STYLE = ('Japanese TV anime game asset. Clean matte flat colours, crisp two-tone shadows, '
               'pale lavender shade. No photo texture, noise, dirty weathering, glossy metal, '
               'oil painting or triangular leaf shards. ')
REPLACEMENTS = [
 ('D01_wheelbarrow','独轮车','farm','One complete single-wheel garden wheelbarrow. Muted sage-green enamel open shallow tray, pale cedar handles, dark charcoal rubber wheel, two metal support legs. Empty tray; visible gap below the tray and around the wheel. Straight practical frame, all three ground contacts level.', 'max',1.4,10000),
 ('D02_rain_barrel','雨水桶','farm,home','One lidded cedar rain barrel on two small stone supports, three blue-grey iron hoops and a small separate projecting brass tap near the bottom. Cream clean wood, discrete stave joints, no dark dirty grain. Tap is an actual open-ended tube, barrel lid flat.', 'h',.95,8000),
 ('D03_veg_crates','三层蔬菜筐','farm,store','Three stable open cedar produce crates stacked with narrow gaps. Bottom holds orange carrots, middle green cucumbers, top a few red tomatoes. Real individual thick slats, visible rectangular hand holes and distinct vegetable shapes. Crates align vertically; no ground slab.', 'h',.85,16000),
 ('D04_stone_lantern','石灯','farm,town','One small Japanese square stone lantern, smooth pale blue-grey stone, broad gently curved hip roof, four actual open window apertures, hollow lantern chamber, square column and a stable stepped foot. Sparse moss only near the foot. No glowing painted window squares.', 'h',1.3,12000),
 ('D05_hokora','小祠堂','farm,town','One small Japanese roadside hokora shrine on a low stone pedestal. Matte indigo tiled gable roof, crisp symmetrical cedar pillars, open deep front alcove with small closed inner shrine doors, clear beam joinery and roof thickness. Clean cream wood and muted vermilion accents. No offerings or text.', 'h',1.2,16000),
 ('D08_tool_rack','园艺工具架','farm','One simple freestanding cedar A-frame garden-tool rack, holds exactly one spade, one rake and one straw hat. Straight frame, independent tool silhouettes, clear open gaps, broad wooden feet coplanar. Smooth dark iron tools, no glossy metal or random bundles.', 'h',1.6,12000),
 ('D09_log_pile','柴垛','farm','One tidy stack of short cedar firewood logs held between two low wooden end supports, broad stable base. Separate split log shapes with visible flat cut ends in warm cream and cinnamon. Small sparse ring lines, no photographic bark or axe or ground slab.', 'max',1.0,10000),
 ('D12_flower_planter','混植花箱','farm,town','One rectangular cedar flower planter, with separate rounded green leaves and small marigold orange, white daisy and pale purple flowers. Moderate density with readable stems and air gaps, no triangular shards. Straight wooden box and four flush small feet. No ground slab.', 'w',1.2,10000),
 ('A14_hydrangea_pot','蓝绣球盆栽','town,home','One terracotta pot containing a blue and lavender hydrangea bush. Three rounded clusters made of readable four-petal florets, broad clean heart-shaped leaves, visible branching stems. Compact graceful silhouette, actual pot rim, no triangular flat-color shards.', 'h',.75,8000),
 ('A15_potted_plant','常绿陶盆','town,home','One pale cream ceramic pot with a compact evergreen shrub. Oval rounded leaves in separated sprays, subtle asymmetrical branching, actual circular rim and visible soil, stable pot base. Summer leaf green with a few warm new shoots, no flowers and no triangular shards.', 'h',.8,8000),
 ('A16_planter_box','街边花箱','town','One long low cedar planter box with pink and white petunia flowers. Clean rectangular box, thick corner joints, small separate trumpet-shaped flowers and rounded green leaves with visible gaps. Flat level bottom, matte flat anime colours, no ground slab.', 'w',1.1,9000),
 ('C09_carrot','胡萝卜植株','crop','One growing carrot plant, fine feathery green leaves in a small upright rosette and a small orange carrot shoulder at the soil line. No pot, no soil block or ground disk, no harvested loose carrots. Readable branched leaf geometry, clean green tones.', 'h',.35,6000),
 ('C10_potato','土豆植株','crop','One mature potato plant with three short branching green stems, rounded oval leaves and two tiny white five-petal blossoms. No exposed potato tubers, no pot, no soil or ground disk. Bush stays compact, distinct clean leaf shapes and open gaps.', 'h',.5,6000),
 ('C11_eggplant','茄子植株','crop','One compact mature Japanese eggplant plant with branching stems, broad rounded green leaves and three slender curved purple fruits hanging below the foliage. Green fruit calyx clearly modeled. No pot or soil or ground slab; visible stem base.', 'h',.8,6500),
 ('C12_corn','玉米植株','crop','One mature corn stalk with long graceful green leaves branching at alternating heights, two cobs inside partly opened green husks and a small golden tassel. Clear slender straight main stalk, no pot, no soil or ground slab. Simplified clean anatomy.', 'h',1.8,6500),
 ('C13_pumpkin','南瓜藤','crop','One low compact pumpkin vine cluster with broad lobed leaves, one ribbed orange pumpkin, one small green pumpkin and two yellow blossoms. Distinct short curling tendrils, readable leaf gaps. No pot, no soil disk, no ground slab.', 'max',.8,7000),
 ('C14_watermelon','西瓜藤','crop','One low compact watermelon vine with two oval striped green watermelons, small deeply lobed leaves, visible branching vines and one yellow blossom. Smooth fruit surfaces with simple clean dark-green painted stripes. No pot, no ground disk or slab.', 'max',.9,7000),
 ('C15_wheat','麦穗丛','crop','One small upright clump of six wheat stems, each ends in a distinct golden ear with a few short awns, slender pale green leaves. Natural separated stalks and small height differences, no pot or soil or tied ribbon or ground slab.', 'h',.9,6500),
 ('C16_onion','洋葱植株','crop','One growing onion plant, a pale round onion bulb with its lower half intended below the soil line, four long upright tubular blue-green leaves with gently curved tips. Smooth clean surfaces, no pot or soil or loose extra onions.', 'h',.45,5000),
 ('F04_scarecrow','稻草人','farm','One friendly Japanese garden scarecrow on a single straight wooden stake, broad straw conical hat, simple round cloth face with two dots and a small smile, faded indigo shirt with broad clean sleeves, straw hands. Clear consistent anime contours, no gritty burlap texture or ground disk.', 'h',1.9,10000),
 ('F06_veggie_stand','菜摊','farm','One small wooden roadside vegetable stand, sloped cedar roof, two straight vertical sides, three open shelves. Each shelf holds one shallow crate: tomatoes, cucumbers, eggplants. Clear real openings, slats and shelf depth. No text, no flags, no extra furniture or ground slab.', 'h',1.9,15000),
 ('P07','社区菜床','town','One compact pair of low rectangular cedar raised vegetable beds, back bed slightly taller. Soil surface level and inset, one tomato plant with three red tomatoes and short upright bamboo stakes in back, compact leafy vegetables in front. Clean warm wood, flat colours, moderate plant density, no unrelated garden props.', 'w',2.4,16000),
 ('P08','育苗工作台','town','One freestanding straight cedar potting workbench with an open lower shelf and a narrow upright tool rail. Broad level unobstructed main worktop, one small terracotta pot at the back, one hanging hand trowel, one seed tray on lower shelf. Clear actual openings and independent legs, no stool or ground platform.', 'h',1.9,14000),
 ('H06','庭院工具房','town','One small Japanese cedar garden tool shed with a shallow indigo-grey pitched roof, one straight closed cream front door, one small side louver window. Subtle panel joints, actual eaves depth and roof ridge, slim rain gutter. Clean anime painted surfaces, no surrounding props or pavement slab.', 'h',2.3,18000),
]
ADDITIONS = [
 ('T06_camphor','樟树','trees','One mature summer camphor tree, wide asymmetrical umbrella crown with distinct overlapping rounded foliage clusters, clear visible sturdy branching warm-grey trunk, separate tapered roots. Clean anime grouped small oval leaves, foliage gaps. No ground disk, scene, fruit or pot.',6.5,20000),
 ('T07_summer_maple','青枫','trees','One airy Japanese green maple tree, several graceful spreading branches, light translucent-looking summer green lobed leaf clusters with open gaps and a slightly flattened layered crown. Slender forked trunk, clean anime shapes, no ground disk or pot.',4.0,18000),
 ('T08_green_cherry','夏日樱树','trees','One summer cherry tree in green foliage with no flowers, gently angled branched brown-grey trunk, broad irregular rounded crown, distinct separated leaf sprays and visible sky gaps. Clean anime tree, no pink flowers, ground disk or pot.',5.5,20000),
 ('T09_bamboo_grove','竹丛','trees','One small bamboo clump of five slender segmented green bamboo culms at different heights, separate long narrow leaf sprays, ample open air gaps, graceful upright silhouette. Clean anime flat colours, no pot, ground or fences.',4.8,16000),
 ('T10_weeping_willow','垂柳','trees','One weeping willow tree with visibly hanging thin branch sprays and long narrow summer-green leaves, broad airy cascading crown, grey-brown forked trunk. Each hanging spray separated by gaps, no solid blob crown, no ground disk or pot.',6.0,20000),
 ('T11_young_zelkova','幼榉树','trees','One young Japanese zelkova tree, upright slender trunk with elegant vase-shaped V branches, small oval summer green leaves in separated airy clusters, narrow crown. Clean anime shapes, no ground disk or pot.',4.5,18000),
 ('V20_morning_glory','朝颜竹架盆','planters','One round terracotta pot with a compact morning-glory vine climbing a small triangular bamboo trellis. Five blue trumpet flowers with pale centers, rounded heart leaves and visible twisting stems. Actual pot rim and clean gaps.',.85,9000),
 ('V21_white_hydrangea','白绣球盆','planters','One low broad pale blue ceramic pot with two rounded white hydrangea flower clusters, individually readable four-petal florets and broad green leaves, visible stems and dark soil. Clean airy compact anime shape.',.65,8000),
 ('V22_shiso_planter','紫苏种植箱','planters','One small rectangular cedar kitchen herb planter with four purple-green shiso stems, crisp serrated but rounded broad leaves and distinct individual branching. Open leaf gaps, real box rim and soil visible. No text or extra tools.',.45,6500),
 ('V23_cosmos_pot','波斯菊陶盆','planters','One pale cream ceramic pot with five pink and white cosmos flowers on slender separated stems at varied heights, delicate feathery green foliage, eight rounded petals per flower. Clean readable anime silhouette, actual pot rim.',.72,7000),
 ('V24_fern_pot','蕨类陶盆','planters','One low ochre ceramic pot with a graceful green fern, five separate arching fronds with neatly paired rounded leaflets, visible stems and open spaces. Clean anime flat leaf tones and actual thick pot rim.',.5,7000),
 ('V25_dwarf_lemon','矮柠檬盆栽','planters','One terracotta pot with a small dwarf lemon tree, distinct slim branched trunk, dark green oval leaves in sparse sprays and three bright yellow lemons. Clear air gaps, actual pot rim and visible soil. Clean anime matte colours.',1.1,9000),
 ('N01_enamel_kettle','搪瓷水壶','home','One cream enamel stovetop kettle with blue rim, curved dark handle, separate curved spout with visible mouth and removable fitted lid. Clean smooth matte anime surfaces. No stove or background objects.',.24,4500),
 ('N02_kyusu','侧柄茶壶','home','One small Japanese brown clay kyusu teapot, cylindrical side handle, short curved spout and round lid. Subtle cream glaze accent only, clean matte anime pottery, clear separate handle and spout openings. No tea cups or tray.',.16,4500),
 ('N03_tea_pair','茶杯对','home','Exactly two small Japanese handleless ceramic tea cups side by side, one pale indigo and one cream with one blue stripe. Real open circular rims, hollow interiors and stable feet. No tray or teapot or liquid.',.09,4000),
 ('N04_fruit_bowl','陶果盘','home','One broad low cream ceramic fruit bowl holding two small oranges and one pale yellow pear, separate clear fruit shapes. Real rim and bowl depth, smooth clean anime surfaces. No table or fabric.',.18,5500),
 ('N05_sewing_basket','针线篮','home','One small oval woven bamboo sewing basket with lid propped open, two neat spools of indigo and red thread and a folded cream cloth inside. Sparse simplified weave, clear real rim and handle, clean anime colours, no needles protruding.',.25,6500),
 ('N06_house_slippers','家居拖鞋','home','Exactly one pair of simple muted blue Japanese house slippers placed neatly parallel, each with visible hollow foot opening, rounded fabric upper and cream flat sole. Clean anime shapes, no feet, no floor mat.',.065,4500),
 ('N07_watering_can','搪瓷浇水壶','farm,home','One pale sage-green enamel watering can with rounded body, actual open top rim, arched handle and a long upward spout ending in a small perforated rose. Clean matte anime colours, no glossy metal or water stream.',.36,6500),
 ('N08_broom_dustpan','扫帚与簸箕','home,town','One short cedar-handled straw broom resting upright beside one pale blue dustpan, distinct separate silhouettes, simple straw bundles and real dustpan mouth. Both grounded on the same plane, clean anime surfaces.',.8,5500),
 ('N09_shopping_basket','买菜竹篮','store,home','One empty oval Japanese woven bamboo shopping basket with two curved handles folded upward, actual open hollow interior and thick woven rim. Simplified precise weave, clean warm ochre anime tones, no produce or ground slab.',.34,7000),
 ('N10_apple_crate','苹果筐','store','One shallow open cedar produce crate holding six clean red and pale green apples, individual rounded fruit, short stems. Real thick slats, clear side hand holes and flat stable base. No stacked crates or text.',.28,7000),
 ('N11_daikon_crate','萝卜筐','store,farm','One shallow open cedar crate holding four Japanese white daikon radishes with green leafy tops, individually recognizable tapered roots. Clear real slats and side hand holes, flat stable base, clean anime surfaces.',.3,7500),
 ('N12_carrot_crate','胡萝卜筐','store,farm','One shallow open cedar crate holding eight orange carrots with short green tops, distinct tapered roots and small shape differences. Real thick slats, side hand holes and flat stable base. Clean anime surfaces.',.24,6500),
 ('N13_empty_crate','空木筐','store,farm','One single empty rectangular cedar harvest crate, open hollow interior, thick evenly spaced slats, real oblong hand holes on both short sides, sturdy square corners and flat base. Clean anime warm wood, no labels or contents.',.3,6000),
 ('N14_paper_parcels','纸包组','store','Three small neatly wrapped cream kraft-paper parcels with simple red or indigo twine, two rectangular and one square, stable short stack, crisp folded corners. Clean anime matte surfaces, no writing or logos.',.25,5000),
 ('N15_umbrella_stand','伞架','town,home','One pale blue cylindrical ceramic umbrella stand holding two closed Japanese umbrellas, indigo and muted yellow, curved wooden handles. Actual open container rim, distinct straight umbrella shafts, clean anime surfaces.',.72,6000),
 ('N16_wooden_crate_seat','木箱坐凳','town','One small low cedar box stool with a thick flat unobstructed seat, four sturdy short legs and two simple lower crossbars, actual gaps below seat. Clean anime warm wood, no cushion or ground platform.',.38,6000),
 ('N17_seedling_tray','育苗盘','farm','One shallow dark indigo seedling tray with six distinct square cells, each contains one small bright green two-leaf seedling. Actual grid depth and inset soil, clean smooth matte anime surfaces. No labels or extra tools.',.12,6500),
 ('N18_harvest_basket','收获藤篮','farm','One round low woven bamboo harvest basket with one arched handle, holding two small yellow squash, three red tomatoes and one purple eggplant. Distinct produce shapes, actual open rim, sparse clean weave and anime colours.',.34,8000),
 ('N19_burlap_sacks','麻袋组','farm','Exactly two upright cream canvas grain sacks, one tied closed with indigo twine, one open showing a small flat mound of golden grain. Clear folded cloth shapes, simple seam lines, flat stable bottoms. No photo weave or labels.',.48,6500),
 ('N20_coiled_hose','盘绕水管','farm','One neat coil of muted blue rubber garden hose resting flat, five clearly separate loops, one short end with a cream spray nozzle, visible hose tube thickness. Clean matte anime surfaces, no reel or ground slab.',.12,6500),
 ('N21_tool_basket','手工具篮','farm','One low rectangular cedar garden-tool caddy with central arched handle, contains one small hand trowel, one small fork and folded cream gloves. Real open compartments and separate silhouettes, clean anime warm wood.',.28,7000),
 ('N22_festival_masks','夏祭面具架','festival','One small cedar freestanding summer-festival mask display, three slim horizontal rails holding exactly three simple festival masks: white fox with red accents, smiling blue cat, small orange fox. No copyrighted characters, no writing, stable A feet and clear gaps.',1.05,10000),
 ('N23_goldfish_scoops','捞鱼纸网托','festival','One low oval pale blue enamel tray holding three Japanese goldfish scoops with small round paper heads and slender red, cream and indigo handles, neatly arranged with separate silhouettes. No fish or water, clean anime shapes.',.05,4500),
 ('N24_bamboo_lantern','竹灯','festival,town','One small cylindrical Japanese bamboo standing lantern, thin spaced vertical bamboo ribs around a matte cream washi paper inner cylinder, low round wooden base and small handle on top. Clean anime shapes, no writing, no flame or electrical cord.',.4,6500),
]


def main():
    previous = json.loads((ROOT/'art/models/game_assets.json').read_text())['assets']
    rows=[]
    for aid,label,contexts,subject,fit,size,tris in REPLACEMENTS:
        rows.append(dict(id=aid,label=label,action='replace',contexts=contexts.split(','),
                         subject=subject,fit=fit,size_m=size,triangle_budget=tris,
                         previous_export=previous[aid],existing_game_path=f'game/assets/models/{aid}.glb'))
    for aid,label,contexts,subject,size,tris in ADDITIONS:
        rows.append(dict(id=aid,label=label,action='add',contexts=contexts.split(','),
                         subject=subject,fit='h',size_m=size,triangle_budget=tris))
    for row in rows:
        row['reference']=f'art/references/model_diversity_20261013/{row["id"]}.png'
        row['reference_prompt']=(f'Use case: stylized-concept. Asset type: one isolated image-to-3D reference for Harumachi. {STYLE}'
                                  f'Subject: {row["subject"]} '
                                  'Composition: complete object centered, three-quarter front view from slightly above, generous margin; '
                                  'plain ivory background, even neutral illumination with minimal contact shadow. '
                                  'No people, scene, other objects, diorama, labels, watermark or text. '
                                  'Every structural gap must remain visibly open. All surfaces are drawn with restrained clean flat colour.')
        row['model_style']=MODEL_STYLE
        row['model_prompt']=MODEL_STYLE+row['subject']+' Reconstruct only this complete object. Actual open holes, separated parts, level base. No background, ground platform or extra objects.'
        assert len(row['model_prompt'])<=1024
        row['candidates']=['a','b']
        row['tier']='Gen-2.5-High'
        row['mesh_mode']='Raw' if row['contexts'][0] in ['trees','planters','crop'] else 'Quad'
        row['quality']=60000 if row['mesh_mode']=='Raw' else 18000
    assert len(rows)==60 and sum(r['action']=='replace' for r in rows)==24
    OUT.parent.mkdir(parents=True,exist_ok=True)
    OUT.write_text(json.dumps(dict(schema_version=1,date='2026-10-13',
        status='scope_fixed; references and generation pending',
        credit_budget=dict(initial_total=210,target_total=150,max_spend=60,
                           verified_wallet=dict(balance=25,subscription_balance=185,frozen=0),
                           expected_per_generation=.5,max_submission_slots=120,
                           pricing_source='https://docs.hyper3d.ai/en/api-specification/rodin-gen2-5#pricing'),
        primary_deliverables=60,replacements=24,additions=36,assets=rows),ensure_ascii=False,indent=2)+'\n')
    refs=ROOT/'art/references/model_diversity_20261013';refs.mkdir(parents=True,exist_ok=True)
    prompts=ROOT/'art/manifests/prompts/model_diversity_20261013';prompts.mkdir(parents=True,exist_ok=True)
    for row in rows:(prompts/(row['id']+'.txt')).write_text(row['reference_prompt']+'\n')
    print('Fixed scope:',len(rows),'assets, 120 generation slots, 60 credits maximum')


if __name__=='__main__':main()
