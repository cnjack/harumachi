"""Guard editorial scope and known regressions without pretending to test literary taste.

Compare a saved source baseline to the current source. Chinese display strings may change;
quest conditions, speaker IDs, moods, choices' arity, formatting arguments and state code may
not. --style-only can demonstrate the style regression on the baseline itself.
"""
import argparse
import ast
import json
import re
from pathlib import Path
from dialogue_review import inventory, TOKEN, CHINESE, ROOT

LEAKS=[
 '不催，也不替谁完成','不会补写原夏祭的参加记录','不把那些都算成你糊的',
 '试挂架不替半成品做完','不要求两个观察点都全绿','我真的来领才记收到',
 '不退回篮子再复制','没有复制首次集市的材料','不能记成今天领取',
 '没有消耗旧试吃','不回改以前的任务','种地这件事，本来就是要传下去的',
 '种菜的人，心里要想着明年','烟花和面包一样','大家其实一直都在等一个理由',
]
FORMAT=re.compile(r'%(?:[-+0-9.]*[sdf]|[0-9]*[xX])')


def skeleton(source):
    def replace(match):
        if match[0].startswith('#'):return match[0]
        try:value=ast.literal_eval(match[0])
        except (ValueError,SyntaxError):return match[0]
        if isinstance(value,str) and CHINESE.search(value):return '"<display:'+','.join(FORMAT.findall(value))+' >"'
        return match[0]
    return TOKEN.sub(replace,source)


def data_skeleton(name,data):
    if name=='dialogue.json':
        for e in data['entries']:
            for ln in e['lines']:ln[2]='<display>'
            if 'choice' in e:
                e['choice']['options']=['<display>']*len(e['choice']['options'])
                for reply in e['choice'].get('replies',[]):
                    for ln in reply:ln[2]='<display>'
    elif name=='homage.json':
        for e in data['items']:
            e['text']='<display>'
            for key in ['inspect','complete']:
                if key in e:e[key]=['<display>']*len(e[key])
    return data


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--root',type=Path,default=ROOT);ap.add_argument('--before',type=Path,required=True)
    ap.add_argument('--style-only',action='store_true');ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    units,support=inventory(args.root);speech='\n'.join(t['text'] for u in units+support for t in u['texts'])
    checks=[]
    def check(name,ok,detail=None):checks.append(dict(name=name,passed=bool(ok),detail=detail))
    found=[text for text in LEAKS if text in speech]
    check('Known developer prose and moral conclusions are absent from player text',not found,found)
    if not args.style_only:
        before_units,before_support=inventory(args.before);old={u['id']:u for u in before_units+before_support};current={u['id']:u for u in units+support}
        check('Every conversation and dynamic source retains its identity',set(old)==set(current))
        altered=[]
        for uid,u in old.items():
            now=current[uid];check('text structure and placeholders: '+uid,len(u['texts'])==len(now['texts']) and all(FORMAT.findall(t['text'])==FORMAT.findall(s['text']) for t,s in zip(u['texts'],now['texts'])))
            if any(t['text']!=s['text'] for t,s in zip(u['texts'],now['texts'])):altered.append(uid)
        for path in sorted((args.before/'game').rglob('*')):
            if not path.is_file() or path.suffix not in ['.gd','.json']:continue
            relative=path.relative_to(args.before);current_path=args.root/relative
            if path.suffix=='.gd':ok=skeleton(path.read_text())==skeleton(current_path.read_text())
            else:ok=data_skeleton(path.name,json.loads(path.read_text()))==data_skeleton(path.name,json.loads(current_path.read_text()))
            check('Only display strings changed: '+str(relative),ok)
        check('At least 20 percent of primary interactions improved',len([u for u in units if u['id'] in altered])>=len(units)*.2)
        total=sum(len(u['texts']) for u in before_units)
        changed=sum(t['text']!=s['text'] for u in before_units for t,s in zip(u['texts'],current[u['id']]['texts']))
        check('At least 20 percent of primary text occurrences changed',changed>=total*.2,dict(changed=changed,total=total))
    result=dict(checks=len(checks),failed=sum(not c['passed'] for c in checks),results=checks)
    args.out.write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps({k:result[k] for k in ['checks','failed']}))
    raise SystemExit(1 if result['failed'] else 0)


if __name__=='__main__':main()
