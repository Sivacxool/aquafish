"""Generate native launch and app icons from the app's vector catfish mark.

Development dependency: Pillow. Assets are committed; builds do not run this.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEEP, PALE = '#181818', '#D5EAE6'

def mark(pixels, transparent=False):
    scale = 4
    image = Image.new('RGBA' if transparent else 'RGB', (pixels*scale, pixels*scale),
                      (0,0,0,0) if transparent else DEEP)
    draw = ImageDraw.Draw(image)
    unit = pixels * scale / 120
    def point(x,y): return (pixels*scale/2+x*unit, pixels*scale/2+y*unit)
    def curve(a,b,c,d):
        return [point(*[(1-t)**3*a[j]+3*(1-t)**2*t*b[j]+3*(1-t)*t*t*c[j]+t**3*d[j]
                        for j in (0,1)]) for t in [i/35 for i in range(36)]]
    body = curve((-22,0),(-8,-17),(15,-14),(21,-3))
    body += curve((21,-3),(28,-3),(31,-10),(34,-12))
    body += curve((34,-12),(30,-4),(30,4),(34,12))
    body += curve((34,12),(28,8),(26,6),(21,3))
    body += curve((21,3),(8,17),(-12,12),(-22,0))
    draw.polygon(body, fill=PALE)
    for sign in [-1,1]:
        draw.line(curve((-18,sign*2),(-25,sign*10),(-28,sign*11),(-32,sign*6)),
                  fill=PALE, width=max(1,round(unit*1.4)))
    draw.ellipse((*point(-12.7,-4.7),*point(-9.3,-1.3)), fill=DEEP)
    return image.resize((pixels,pixels),Image.Resampling.LANCZOS)

for density,pixels in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    mark(pixels).save(ROOT/f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
icons=ROOT/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for entry in json.loads((icons/'Contents.json').read_text())['images']:
    pixels=round(float(entry['size'].split('x')[0])*float(entry['scale'][:-1]))
    mark(pixels).save(icons/entry['filename'])
launch=ROOT/'ios/Runner/Assets.xcassets/LaunchImage.imageset'
for entry in json.loads((launch/'Contents.json').read_text())['images']:
    mark(168*int(entry['scale'][:-1]),True).save(launch/entry['filename'])
print('Generated Android/iOS native icons and launch mark')
