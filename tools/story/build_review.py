"""Build an offline story review from the current quest data and actual GDScript dialogue.
Run from the repository: python3 tools/story/build_review.py --snapshot YYYY-MM-DD
No gameplay or save files are changed.
"""
import argparse
import ast
import base64
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/game-design/story'
OUT.mkdir(parents=True, exist_ok=True)
NAMES = {'sora':'空','mio':'澪','ren':'莲','haru':'春','tanaka':'田中爷爷','aoi':'小葵','kazuko':'和子阿姨','narrator':'旁白','chiyo':'千代阿姨','aken':'阿健'}
FILES = ['game/scripts/story/story.gd','game/scripts/story/story_farm.gd','game/scripts/story/story_lore.gd','game/scripts/story/story_fest.gd','game/scripts/story/story_bakery.gd','game/scripts/story/story_daily.gd']


def load(name):
    return json.loads((ROOT/'game/data'/f'{name}.json').read_text())


def literal(text):
    try:
        value = ast.literal_eval(text.strip())
        return value if isinstance(value,(str,list,dict,int,float)) else None
    except (SyntaxError,ValueError):
        return None


def arguments(text, start):
    """GDScript call arguments, respecting strings, arrays and nested calls."""
    args, buf, depth, quote, escape = [], '', 0, None, False
    for char in text[start:]:
        if quote:
            buf += char
            if escape: escape = False
            elif char == '\\': escape = True
            elif char == quote: quote = None
            continue
        if char in '\"\'': quote = char;buf += char;continue
        if char in '([{': depth += 1;buf += char;continue
        if char in ')]}':
            if char == ')' and depth == 0:
                args.append(buf.strip());return args
            depth -= 1;buf += char;continue
        if char == ',' and depth == 0: args.append(buf.strip());buf = '';continue
        buf += char
    return []


def string_values(expression):
    return [literal(m.group()) for m in re.finditer(r'"(?:\\.|[^"\\])*"',expression) if literal(m.group()) is not None]


def speech(expression):
    """Do not mistake quoted quest IDs/flags inside a condition for spoken text."""
    plain=literal(expression)
    if isinstance(plain,str):return plain,[]
    token=r'("(?:\\.|[^"\\])*")'
    ternary=re.match(r'^'+token+r'\s+if\s+.+?\s+else\s+'+token+r'\s*$',expression,re.S)
    if ternary:return '',[literal(ternary[1]),literal(ternary[2])]
    if expression.lstrip().startswith('{'):
        prefix=expression[:expression.rfind('}')+1]
        table=literal(prefix)
        if isinstance(table,dict):return '',[f'{NAMES.get(k,k)}：{v}' for k,v in table.items() if isinstance(v,str)]
    first=re.match(r'^'+token,expression)
    if first:return literal(first[1]),[]
    return '',[]


def extract(path):
    source = (ROOT/path).read_text()
    lines = source.splitlines()
    starts = [i for i,line in enumerate(lines) if re.match(r'^func ',line)]
    rows, choices, functions = [], [], []
    for index, start in enumerate(starts):
        end = starts[index+1] if index+1<len(starts) else len(lines)
        name = re.search(r'func (\w+)',lines[start])[1]
        block = '\n'.join(lines[start:end])
        qids = sorted(set(re.findall(r'"(Q\d\d)"',block)))
        functions.append({'file':path,'name':name,'line':start+1,'end':end,'quests':qids,'code':block})
        stack, branches, recent_choice = [], {}, None
        for local, line in enumerate(lines[start+1:end],start+1):
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):continue
            indent = len(line)-len(line.lstrip('\t'))
            while stack and stack[-1][0]>=indent:stack.pop()
            if re.match(r'(if|elif) .+:$',stripped):
                cond = stripped.split(' ',1)[1][:-1]
                branches[indent] = cond
                stack.append((indent,cond))
            elif stripped == 'else:':
                stack.append((indent,'否则（'+branches.get(indent,'前一条件')+'）'))
            elif re.match(r'"[^\"]+":$',stripped):stack.append((indent,'匹配 '+stripped[:-1]))
            conditions = [x[1] for x in stack]
            effective_q = sorted(set(re.findall(r'"(Q\d\d)"',' '.join(conditions))))
            if not effective_q and len(qids)==1:effective_q=qids
            if name in ['_market_chat','_market_sequence'] and not effective_q:effective_q=['Q05']
            if name=='_goldfish_promise':effective_q=['Q14']
            if name in ['_hanabi_end','_revisit_hanabi']:effective_q=['Q15']
            if name=='_reunion':effective_q=['Q14']
            if path.endswith('story_bakery.gd'):effective_q=['Q16']
            cm = re.search(r'(?:s\.)?ui\.choose\(',line)
            if cm:
                tail='\n'.join(lines[local:end]);offset=tail.index('(',tail.index('choose'))+1
                args=arguments(tail,offset)
                opts=literal(args[0]) if args else None
                options=opts if isinstance(opts,list) else string_values(args[0]) if args else []
                entry={'file':path,'line':local+1,'function':name,'quests':effective_q,'conditions':conditions,'options':options,'expression':args[0] if args else ''}
                choices.append(entry);recent_choice=entry
            sm = re.search(r'await\s+(?:s\.)?(_say|say)\(',line)
            if not sm:continue
            tail='\n'.join(lines[local:end]);offset=tail.index('(',tail.index(sm.group(1)))+1
            args=arguments(tail,offset)
            if len(args)!=3:continue
            if name in ['_say','say']:continue
            who=literal(args[0]);mood=literal(args[1]);plain,values=speech(args[2])
            rows.append({'file':path,'line':local+1,'function':name,'quests':effective_q,'conditions':conditions,
                         'speaker':who if isinstance(who,str) else 'dynamic','speakerExpression':args[0],
                         'mood':mood if isinstance(mood,str) else '', 'text':plain,
                         'variants':values,'expression':args[2],
                         'choice':recent_choice['options'] if recent_choice else []})
    return rows,choices,functions


def location(qid,step):
    explicit={'bakery_bake':'面包店烤箱与推车试吃纸签','bakery_trial':'面包店试吃纸签','bakery_taste':'澪、春或商店柜台的和子','bakery_menu':'面包店试吃纸签','bakery_supply':'周六庭院摊位','bakery_followup':'面包店试吃纸签','mailbox':'奶奶家信箱','enter_home':'奶奶家门口','read_board':'庭院公告栏','deliver_basket':'庭院集市摊位',
              'plant':'庭院种植箱','fill_can':'庭院饮水台','water':'庭院种植箱','get_sign':'社区活动中心','post_sign':'庭院公告栏',
              'place_seats':'庭院布置区','start':'庭院 / 澪','chat':'庭院 / 澪、莲、春','go_farm':'主街东端 → 河边农园',
              'talk_tanaka':'河边农园 / 田中','till':'农园地块','sow':'农园地块','water6':'农园地块 / 手压泵',
              'harvest':'农园地块','sell':'无人菜摊','sow_sun':'农园地块','bloom':'农园地块','give_aoi':'小葵',
              'sell_market':'周六集市摊位','open_box':'奶奶家卧室壁橱','show_mio':'澪','find_notebook':'社区中心储物间',
              'show_haru':'春','report_mio11':'澪','buy_washi':'杂货铺','get_bamboo':'农园 / 田中','make_lanterns':'春',
              'give_lanterns':'澪','take_blueprint':'春','ask_tanaka':'田中（引导到河边长椅）','carry_wood':'农园柴堆',
              'give_wood':'田中','go_fest':'庭院','bon_odori14':'庭院盆舞台','goldfish_mio':'金鱼摊 / 澪',
              'take_tube':'农园工具棚','watch_hanabi':'农园河边长椅'}
    return explicit.get(step,{'Q01':'澪','Q02':'莲','Q03':'春','Q05':'澪','Q06':'春 / 田中','Q07':'田中','Q08':'小葵','Q09':'澪'}.get(qid,'小镇'))


QUEST_NOTES={
 'Q00':('新游戏开始即接受。','带着钥匙回到奶奶家，给这趟归来找一个落脚点。'),
 'Q01':('Q00 完成后，找澪。愿意帮忙才接受；先逛逛保留邀请，之后找澪或从 J 接受都能继续。','澪希望先办一个小集市，让冷清的庭院重新有人坐下来。'),
 'Q02':('看完 Q01 的公告栏后自动接受，可与 Q03、Q04 任意顺序进行。','莲托你送一篮试做面包，把面包店和庭院连起来。'),
 'Q03':('看完 Q01 的公告栏后自动接受。','春带你把旧种植箱重新种上；完成后解锁河边农园。'),
 'Q04':('看完 Q01 的公告栏后自动接受。','去社区中心取标牌，贴出大家要重新办集市的消息。'),
 'Q05':('Q02、Q03、Q04 全部完成后解锁；找澪开始筹备。','摆好座位、当面邀请邻居，在周六傍晚办成第一场集市。'),
 'Q06':('Q03 完成后解锁；非集市阶段找春。无需先完成 Q05。','春的信把你带到河边，田中用第一次播种教你认识农园。'),
 'Q07':('Q06 完成后解锁；向田中报告 Q06 时会自动接受。','每天浇水，把第一次收成卖出去，再告诉田中。'),
 'Q08':('Q06 完成后解锁；非集市阶段找小葵。','小葵想送奶奶一朵向日葵，请你帮她种出来。'),
 'Q09':('Q05 完成后解锁；非集市阶段找澪接受。','周六的集市不再只办一次。带着自己的收成，成为真正的摊主。'),
 'Q10':('首次集市完成后，在下一次进入新的一天时自动开启。','奶奶的旧照片让澪认出空，十五年前的约定重新被说起。'),
 'Q11':('Q10 完成后解锁；找澪接受。','健一留下的账本把回忆变成一张可以动手准备的清单。'),
 'Q12':('Q11 完成后解锁；找春接受。','五张和纸、五根竹篾，糊成五盏会在夏祭点亮的灯笼。'),
 'Q13':('Q11 完成后解锁；找春取得图纸。田中只在 17 点后讲往事。','健一的图纸让春和田中重新愿意搭起那座盆舞台。'),
 'Q14':('Q05 完成且第 17 天及以后解锁；活动时段自动开始，散场后可找澪另约一晚。','在夏祭或树下补约时捞金鱼，拍下新的合影。'),
 'Q15':('Q14 完成后解锁；找田中接受。错过花火后可去河边长椅听他讲记录。','取下旧花火筒，在花火或节后记录中继续健一的故事。'),
 'Q16':('Q05 和 Q06 都完成后开放；去面包店推车上的试吃纸签，或按 J 接受。','免费试做、请两位街坊试吃、定菜单、留菜供货；次日有回应，可继续合作也可休息。')}

BRANCHES={
 'Q01':[{'title':'澪邀请帮忙','options':['好啊，我去看看','先让我逛逛'],'result':'愿意帮忙才接受并推进；先逛逛不接任务。之后可找澪或从 J 接受，再回澪处继续。'}],
 'Q05':[{'title':'尚未到集市时间','options':['在长椅上等到傍晚','我先去逛逛'],'result':'仅周六且尚未到 16:30 时提供。等待会把时间跳到 16:30；离开不推进。'}, {'title':'开始集市','options':['开始集市！','再等一下'],'result':'选择开始后还会检查桌椅、邀请和支持标记；条件不足不会推进。'}],
 'Q10':[{'title':'认出旧照片里的空','options':['是我。那年夏天我住在奶奶家。','……你还记得吗？'],'result':'第一种多一句“真的是你”；两条路径都回忆捞金鱼、决定把夏祭办回来。'}],
 'Q13':[{'title':'田中的时间门槛','options':['17 点前找他','17 点后找他'],'result':'17 点前只说“晚上再说吧”，不推进；17 点后讲起健一，并进入搬木料。'}],
 'Q14':[{'title':'有没有找到 2011 年合影','options':['已经找到旧合影','尚未找到旧合影'],'result':'同一段捞金鱼剧情会分别强调十五年前的约定，或庆祝夏祭回来了；都会拍下新照片。'}, {'title':'新的约定','options':['明年夏祭，还一起来吧。','如果我那时回来了，就在树下见。','今年这张照片先给我一份。'],'result':'三种回答都完成 Q14，保存在 summer_promise；后续对白分别回应。'}]}


def build(snapshot):
    quests,festivals,prologue,dialogue,collection,items = [load(x) for x in ['quests','festivals','prologue','dialogue','collection','items']]
    rows,choices,functions=[],[],[]
    for file in FILES:
        r,c,f=extract(file);rows+=r;choices+=c;functions+=f
    nodes=[]
    for qid,q in quests.items():
        node=dict(q,id=qid)
        node['chapter']=int(q.get('chapter',1 if int(qid[1:])<6 else 2 if int(qid[1:])<10 else 3))
        node['sourceData']=q
        node['entry'],node['summary']=QUEST_NOTES[qid]
        node['steps']=[dict(step,place=location(qid,step['id'])) for step in q['steps']]
        node['branches']=BRANCHES.get(qid,[])
        node['dialogue']=[r for r in rows if qid in r['quests']]
        node['sourceChoices']=[r for r in choices if qid in r['quests']]
        node['sources']=[{'file':'game/data/quests.json','line':next(i+1 for i,x in enumerate((ROOT/'game/data/quests.json').read_text().splitlines()) if f'"{qid}":' in x)}]
        node['functions']=[f for f in functions if qid in f['quests'] or (qid=='Q14' and f['name']=='_goldfish_promise')]
        nodes.append(node)
    edges=[{'from':qid,'to':other,'kind':'unlock','label':'完成后解锁'} for qid,q in quests.items() for other in q['unlocks']]
    edges += [{'from':x,'to':'Q05','kind':'and','label':'三条全部完成'} for x in ['Q02','Q03','Q04']]
    edges += [{'from':'Q05','to':'Q10','kind':'date','label':'完成后的下一次换日'}, {'from':'Q05','to':'Q14','kind':'date','label':'第 17 天及以后，错过可补约（不要求 Q12 / Q13 完成）'}]
    edges += [{'from':x,'to':'Q16','kind':'and','label':'首次集市与农园都完成'} for x in ['Q05','Q06']]
    lore=(ROOT/'docs/game-design/LORE.md').read_text();bios=[]
    for line in lore.split('## 2. 人物的过去')[1].split('## 3.')[0].splitlines():
        if line.startswith('| ') and not line.startswith(('| 人物','| ---')):
            parts=[x.strip() for x in line.strip('|').split('|')];bios.append({'name':parts[0],'past':parts[1],'wish':parts[2]})
    for fid,event in festivals.items():
        day=event['day'];month=7;dom=day+3
        while dom>{7:31,8:31,9:30,10:31,11:30,12:31}.get(month,30):dom-={7:31,8:31,9:30,10:31,11:30,12:31}.get(month,30);month+=1
        event['id']=fid;event['date']=f'{month}月{dom}日'
        event['dialogue']=[r for r in rows if r['file'].endswith('story_fest.gd') and r['function']=={'tanabata':'_tanabata','contest':'_contest','natsumatsuri':'_bon_odori','hanabi':'_hanabi','obon':'_toro','tsukimi':'_tsukimi'}[fid]]
        event['choices']=[]
    fest_source=(ROOT/'game/scripts/story/story_fest.gd').read_text()
    wish_block=fest_source.split('const WISHES := [',1)[1].split('\n]',1)[0]
    wishes=[literal(m.group()) for m in re.finditer(r'\["[^\"]+",\s*"[^\"]+"\]',wish_block)]
    festivals['tanabata']['choices']=[{'label':w[0],'effect':f'{NAMES[w[1]]}亲近度 +2'} for w in wishes]
    hanabi_code=next(f['code'] for f in functions if f['file'].endswith('story_fest.gd') and f['name']=='_hanabi')
    old_reply=re.search(r'var line: String = (\{.*?\})\.get',hanabi_code,re.S)
    reply=literal(old_reply[1]) if old_reply else {r['speaker']:r['text'] for r in rows if r['file'].endswith('story_fest.gd') and r['function']=='_hanabi' and r['speaker'] in ['mio','ren','haru','aoi','tanaka']}
    festivals['hanabi']['choices']=[{'label':'坐到'+NAMES[who]+'旁边','effect':text+'（亲近度 +3；人物需在场且距离 30 米以内）'} for who,text in reply.items()]
    festivals['contest']['choices']=[{'label':'交出持有的作物','effect':'完整分页显示未预留的作物，排名对应奖励 300 / 150 / 60 / 20 生活币。'}, {'label':'再想想','effect':'不交作物，不标记参加过品评会。'}]
    life_events=[]
    for event_id,title,day,place,names in [
        ('meal','第一顿自己的饭',1,'家 · 碗柜 → 灶台 → 饭桌',['arrival_invitation','_pantry','_table']),
        ('tea','春的麦茶',2,'菜圃 · 春实际在场时的育苗台',['_tea']),
        ('card','莲的小纸牌',3,'面包推车或店内柜台 · 莲实际在场时',['_card'])]:
        event_rows=[row for row in rows if row['file'].endswith('story_daily.gd') and row['function'] in names]
        life_events.append({'id':event_id,'title':title,'earliest':day,'place':place,'dialogue':event_rows,
            'choices':[choice for choice in choices if choice['file'].endswith('story_daily.gd') and choice['function'] in names]})
    sources=FILES+['game/data/quests.json','game/data/prologue.json','game/data/story_fragments.json','game/data/festivals.json','game/data/dialogue.json','game/data/collection.json','game/scripts/autoload/game_state.gd','docs/game-design/LORE.md','game/scripts/story/daily_life.gd']
    data={'title':'明年夏祭 · 剧情阅览','snapshot':snapshot,'names':NAMES,'quests':nodes,'edges':edges,'festivals':list(festivals.values()),'prologue':prologue['panels'],'fragments':load('story_fragments')['items'],
          'daily':dialogue['entries'],'collection':collection['items'],'characters':bios,'items':{k:v.get('name',k) for k,v in items.items()},
          'portraits':[who for who in NAMES if (ROOT/'game/assets/ui/portraits'/f'{who}_neutral.png').exists()],
          'lifeEvents':life_events,'allChoices':choices,'allDialogue':rows,'functions':functions,'sources':[{'file':f,'sha256':hashlib.sha256((ROOT/f).read_bytes()).hexdigest()} for f in sources],
          'reviewNotes':[{'title':'第二章可以提前开始','text':'Q06 由 Q03 解锁，不要求先完成首次集市。章节编号是叙事分组，不是必须顺序。'},
                         {'title':'灯笼与盆舞台有代补','text':'第 16 天起居民补完已开放的 Q12 / Q13，并记录 town_finished；不记玩家亲手完成，也不发未做工作的报酬。'},
                         {'title':'夏祭的实际解锁门槛较宽','text':'Q14 只检查 Q05 完成和第 17 天及以后。是否拿到旧照片会改变澪的台词，因此即使没走完 Q10 / Q11 也有继续 Q14 的入口。'},
                         {'title':'固定日期需要留意','text':'夏祭只在第 17 天 17:00–22:00，花火大会只在第 24 天 19:30–21:00。散场后可找澪补约金鱼与合影；错过花火仍可去河边长椅听田中讲那晚的记录，补看不记为亲自参加。'}]}
    assert len(nodes)==len(quests) and len(festivals)==6 and len(prologue['panels'])==4 and len(load('story_fragments')['items'])==3
    assert all(e['from'] in quests and e['to'] in quests for e in edges)
    payload=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c')
    template=(ROOT/'tools/story/review.template.html').read_text()
    (OUT/'index.html').write_text(template.replace('__STORY_DATA__',payload))
    (OUT/'story-data.json').write_text(json.dumps(data,ensure_ascii=False,indent=1)+'\n')
    counts={'quests':len(nodes),'steps':sum(len(q['steps']) for q in nodes),'prologue':len(prologue['panels']),'fragments':len(data['fragments']),'festivals':6,'daily_entries':len(data['daily']),'keepsakes':len(data['collection']),'script_dialogue_calls':len(rows),'choice_calls':len(choices),'life_events':len(life_events)}
    (OUT/'build-manifest.json').write_text(json.dumps({'counts':counts,'sources':data['sources']},ensure_ascii=False,indent=2)+'\n')
    from PIL import Image
    from fontTools import subset
    assets=OUT/'assets';assets.mkdir(exist_ok=True)
    for panel in prologue['panels'] + data['fragments']:
        image=Image.open(ROOT/'game/assets/ui/prologue'/f"{panel['img']}.jpg")
        image.thumbnail((900,507));image.save(assets/f"{panel['img']}.webp",quality=88)
    for who in NAMES:
        path=ROOT/'game/assets/ui/portraits'/f'{who}_neutral.png'
        if path.exists():
            image=Image.open(path);image.thumbnail((256,256));image.save(assets/f'{who}.webp',quality=90)
    options=subset.Options();options.flavor='woff2'
    font=subset.load_font(str(ROOT/'game/assets/fonts/LXGWWenKai-Medium.ttf'),options)
    subsetter=subset.Subsetter(options=options);subsetter.populate(text=payload+template)
    subsetter.subset(font);subset.save_font(font,str(assets/'story-wenkai.woff2'),options)
    shutil.copy2(ROOT/'game/assets/fonts/OFL.txt',assets/'OFL.txt')
    standalone=dict(data)
    standalone['font_license']=(assets/'OFL.txt').read_text()
    standalone['assetData']={p.name:'data:image/webp;base64,'+base64.b64encode(p.read_bytes()).decode() for p in assets.glob('*.webp')}
    embedded=json.dumps(standalone,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c')
    document=template.replace('__STORY_DATA__',embedded)
    font_data='data:font/woff2;base64,'+base64.b64encode((assets/'story-wenkai.woff2').read_bytes()).decode()
    document=document.replace('assets/story-wenkai.woff2',font_data)
    (ROOT/'docs/game-design/story.html').write_text(document)
    print(json.dumps(counts,ensure_ascii=False))


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--snapshot',required=True,help='Explicit review date YYYY-MM-DD, supplied by the reviewer')
    args=parser.parse_args()
    build(args.snapshot)
