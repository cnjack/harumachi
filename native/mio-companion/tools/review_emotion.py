#!/usr/bin/env python3
"""Contact sheets of actual Metal frames; does not edit the character's source art."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

STYLES = [('neutral','平静'),('warm','温柔'),('joyful','喜悦'),('curious','好奇'),('concerned','关心'),('surprised','惊讶'),('determined','坚定'),('sleepy','困倦')]
INTENSITIES = [('subtle','轻微'),('normal','日常'),('strong','明显')]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('directory', type=Path)
    a = p.parse_args()
    font = ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc', 20)
    def sheet(name, entries, columns):
        width, height = 300, 320
        result = Image.new('RGB',(columns*width,((len(entries)+columns-1)//columns)*height),'#f7f6f0')
        draw = ImageDraw.Draw(result)
        for i,(label,path) in enumerate(entries):
            x,y=i%columns*width,i//columns*height
            raw=Image.open(path).convert('RGBA')
            im=Image.new('RGBA',raw.size,'#f7f6f0');im.alpha_composite(raw)
            crop=im.crop((267,95,483,295)).resize((300,278),Image.Resampling.LANCZOS)
            result.paste(crop.convert('RGB'),(x,y+42));draw.text((x+12,y+10),label,font=font,fill='#33494e')
        result.save(a.directory/name)
    sheet('expressions.png',[(label,a.directory/f'{style}-strong.png') for style,label in STYLES],4)
    sheet('intensities.png',[(label+' · '+degree,a.directory/f'{style}-{intensity}.png') for style,label in STYLES for intensity,degree in INTENSITIES],3)
    print('Eight styles and 24 intensity combinations rendered in contact sheets')

if __name__ == '__main__':main()
