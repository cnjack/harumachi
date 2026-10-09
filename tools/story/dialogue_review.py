"""Source-addressable editorial inventory. Scores are editorial judgments, not AI detection.

One unit is a conditional daily conversation, a scripted interaction function (all branches),
or a data-driven monologue/encounter. Keep options beside replies, and keep source spans so
edits can be checked without changing quest/state logic. No player saves are read.
"""
import argparse
import ast
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHINESE = re.compile(r"[\u4e00-\u9fff]")
SPEECH = re.compile(r"(?<!\w)(?:_say|say|choose)\(")
FUNCTION = re.compile(r"^(?:static )?func (\w+)", re.M)
TOKEN = re.compile(r'#[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
FEEDBACK_FILES = {
    'game/scripts/autoload/game_state.gd',
    'game/scripts/world/gathering_view.gd',
    'game/scripts/world/neighbour_meal_view.gd',
    'game/scripts/world/daily_life_view.gd',
    'game/scripts/world/project_tasting.gd',
    'game/scripts/world/living_action.gd',
}


def strings(source, offset=0):
    result = []
    for match in TOKEN.finditer(source):
        if match[0].startswith('#'):
            continue
        try:
            value = ast.literal_eval(match[0])
        except (ValueError, SyntaxError):
            continue
        if CHINESE.search(value):
            result.append(dict(text=value, start=offset+match.start(), end=offset+match.end()))
    return result


def inventory(root=ROOT):
    units = []
    def data_unit(file, uid, speaker, texts, context):
        units.append(dict(id=uid, file=file, speaker=speaker, context=context, texts=texts))
    file = 'game/data/dialogue.json'
    for e in json.loads((root/file).read_text())['entries']:
        texts = [dict(text=ln[2],speaker=ln[0],path=['entries', e['id'], 'lines',i,2]) for i,ln in enumerate(e['lines'])]
        for i,t in enumerate(e.get('choice',{}).get('options',[])):
            texts.append(dict(text=t,speaker='player-option',path=['entries',e['id'],'choice','options',i]))
        for i,reply in enumerate(e.get('choice',{}).get('replies',[])):
            for j,ln in enumerate(reply):
                texts.append(dict(text=ln[2],speaker=ln[0],path=['entries',e['id'],'choice','replies',i,j,2]))
        data_unit(file,'daily:'+e['id'],e['who'],texts,e.get('when',{}))
    for name,key in [('prologue','panels'),('story_fragments','items'),('shop_life','lines'),('homage','items')]:
        file=f'game/data/{name}.json'; data=json.loads((root/file).read_text())
        for i,e in enumerate(data[key]):
            texts=[]
            if name=='homage':
                for field in ['inspect','complete']:
                    texts.extend(dict(text=t,speaker='narrator',path=[key,i,field,j]) for j,t in enumerate(e.get(field,[])))
                # Collection text is context, not a second spoken encounter.
                context={k:v for k,v in e.items() if k not in ['inspect','complete']}
            else:
                texts=[dict(text=e['text'],speaker=e.get('who',data.get('voice','sora')),path=[key,i,'text'])]
                context={k:v for k,v in e.items() if k!='text'}
            data_unit(file,name+':'+str(e.get('id',i)),e.get('who',data.get('voice','narrator')),texts,context)
    file='game/data/shops.json'
    for key,e in json.loads((root/file).read_text()).items():
        data_unit(file,'shop:'+key,e['keeper'],[dict(text=e['line'],speaker=e['keeper'],path=[key,'line'])],{k:e[k] for k in ['open','close','closed_weekday']})
    support=[]
    for path in sorted((root/'game/scripts').rglob('*.gd')):
        if any(part in ['tests','tools'] for part in path.parts):
            continue
        source=path.read_text(); file=str(path.relative_to(root)); matches=list(FUNCTION.finditer(source))
        for i,m in enumerate(matches):
            end=matches[i+1].start() if i+1<len(matches) else len(source)
            block=source[m.start():end]; texts=strings(block,m.start())
            if not texts:continue
            for item in texts:
                item['line']=source.count('\n',0,item['start'])+1
                item['speaker']='context' # Exact calls below identify the speaker of literal speech.
                prefix=source[max(m.start(),item['start']-160):item['start']]
                who=re.search(r'(?:_say|say)\(\s*"(\w+)"\s*,\s*"\w*"\s*,\s*$',prefix)
                if who:item['speaker']=who[1]
            unit=dict(id='script:'+path.stem+'.'+m[1],file=file,function=m[1],line=source.count('\n',0,m.start())+1,
                      speaker='multiple',texts=texts,context=block)
            if SPEECH.search(re.sub(r'#[^\n]*','',block)):units.append(unit)
            elif 'story' in path.parts or file in FEEDBACK_FILES:
                support.append(unit)
        if 'story' in path.parts and matches:
            top=strings(source[:matches[0].start()])
            if top:support.append(dict(id='constants:'+path.stem,file=file,speaker='context',texts=top,context=source[:matches[0].start()]))
    return units,support


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,default=ROOT);ap.add_argument('--out',type=Path,required=True)
    args=ap.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    units,support=inventory(args.root)
    (args.out/'inventory.json').write_text(json.dumps(dict(units=units,support=support),ensure_ascii=False,indent=2))
    for label,rows in [('conversations',units),('dynamic-feedback',support)]:
        compact=[]
        for i,u in enumerate(rows):
            compact.append(f"\n[{i:03d}] {u['id']} | {u['file']} | {u.get('line','')} | {u['context'] if not isinstance(u['context'],str) else ''}")
            compact.extend(f"  {t.get('speaker','')} {t['text']}" for t in u['texts'])
        (args.out/f'{label}.txt').write_text('\n'.join(compact))
    print(json.dumps(dict(conversations=len(units),text_occurrences=sum(len(u['texts']) for u in units),dynamic_feedback_units=len(support)),ensure_ascii=False))


if __name__=='__main__':main()
