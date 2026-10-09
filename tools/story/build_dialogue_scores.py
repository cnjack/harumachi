"""Build the searchable standalone score sheet from recorded editorial ratings."""
import argparse
import base64
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--scores',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    data=json.loads(args.scores.read_text())
    data['font_license']=(ROOT/'docs/game-design/story/assets/OFL.txt').read_text()
    template=(ROOT/'tools/story/review_scores.template.html').read_text()
    font=base64.b64encode((ROOT/'docs/game-design/story/assets/story-wenkai.woff2').read_bytes()).decode()
    payload=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c')
    args.out.write_text(template.replace('__DATA__',payload).replace('__FONT__','data:font/woff2;base64,'+font))
    print(f"{len(data['units'])} score rows -> {args.out}")


if __name__=='__main__':main()
