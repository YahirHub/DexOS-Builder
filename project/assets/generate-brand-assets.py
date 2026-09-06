#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path

OUT=Path(__file__).resolve().parent
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
FONTB='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

def font(path,size):
    try:return ImageFont.truetype(path,size)
    except:return ImageFont.load_default()

def gradient_text_mask(size,text,xy,fnt):
    m=Image.new('L',size,0); d=ImageDraw.Draw(m); d.text(xy,text,font=fnt,fill=255)
    return m

def neon_line(layer, pts, width=13):
    # warm orange -> red across x
    d=ImageDraw.Draw(layer)
    for i in range(len(pts)-1):
        x=(pts[i][0]+pts[i+1][0])/2/layer.width
        col=(255,128-int(70*x),0+int(35*x))
        d.line([pts[i],pts[i+1]],fill=col,width=width,joint='curve')

def draw_logo(base,cx,cy,scale=1.0):
    glow=Image.new('RGBA',base.size,(0,0,0,0)); fg=Image.new('RGBA',base.size,(0,0,0,0))
    def P(x,y): return (int(cx+x*scale),int(cy+y*scale))
    # cat ears/head outline, deliberately close to supplied Dex OS artwork
    outline=[P(-165,-90),P(-165,-225),P(-90,-140),P(80,-140),P(165,-225),P(165,-90),P(205,-10),P(150,55)]
    neon_line(fg,outline,14)
    neon_line(fg,[P(-165,-90),P(-205,-10),P(-150,55)],14)
    # code eyes
    neon_line(fg,[P(-85,-35),P(-125,0),P(-85,35)],12)
    neon_line(fg,[P(80,-35),P(125,0),P(80,35)],12)
    neon_line(fg,[P(20,-45),P(-5,45)],12)
    # nose / mouth
    d=ImageDraw.Draw(fg)
    d.polygon([P(-28,72),P(28,72),P(0,102)],fill=(255,95,0,255))
    neon_line(fg,[P(0,102),P(-10,128),P(-40,139),P(-64,130)],9)
    neon_line(fg,[P(0,102),P(10,128),P(40,139),P(64,130)],9)
    # whiskers
    for y,dy in [(72,-6),(98,4)]:
        neon_line(fg,[P(-150,y),P(-225,y+dy)],7)
        neon_line(fg,[P(150,y),P(225,y+dy)],7)
    alpha=fg.getchannel('A').filter(ImageFilter.GaussianBlur(int(10*scale)))
    glow.paste((255,70,0,170),(0,0,base.width,base.height),alpha)
    base.alpha_composite(glow); base.alpha_composite(fg)

def add_gradient_text(base,text,y,size,center=True):
    f=font(FONTB,size); d=ImageDraw.Draw(base); box=d.textbbox((0,0),text,font=f); w=box[2]-box[0]
    x=(base.width-w)//2 if center else 60
    mask=gradient_text_mask(base.size,text,(x,y),f)
    grad=Image.new('RGBA',base.size)
    gp=grad.load()
    for xx in range(base.width):
        t=xx/max(1,base.width-1); c=(255,int(140-70*t),int(0+35*t),255)
        for yy in range(max(0,y-5),min(base.height,y+size+20)): gp[xx,yy]=c
    glow=Image.new('RGBA',base.size,(255,70,0,0)); glow.putalpha(mask.filter(ImageFilter.GaussianBlur(10)))
    base.alpha_composite(glow); base.alpha_composite(Image.composite(grad,Image.new('RGBA',base.size),(mask)))

def boot():
    W,H=1280,720
    img=Image.new('RGBA',(W,H),(0,0,0,255))
    draw_logo(img,W//2,280,.78)
    add_gradient_text(img,'Dex OS',430,84)
    add_gradient_text(img,'Iniciando…',535,42)
    d=ImageDraw.Draw(img); f=font(FONT,28)
    txt='ThowiLabs'; box=d.textbbox((0,0),txt,font=f); tw=box[2]-box[0]; x=(W-tw)//2
    d.text((x,650),txt,font=f,fill=(255,125,10,255)); d.line((x-145,667,x-20,667),fill=(175,55,12,255),width=2); d.line((x+tw+20,667,x+tw+145,667),fill=(175,55,12,255),width=2)
    rgb=img.convert('RGB'); rgb.save(OUT/'dexos-boot.jpg','JPEG',quality=93,optimize=True,progressive=True); rgb.resize((640,360),Image.Resampling.LANCZOS).save(OUT/'dexos-boot.ppm','PPM')

def wallpaper():
    W,H=1920,1080
    img=Image.new('RGBA',(W,H),(3,5,9,255)); d=ImageDraw.Draw(img)
    # very subtle circuit-board traces like the supplied Ember wallpaper
    for x in range(40,W,210):
        d.line((x,0,x,150,x+55,205,x+55,330),fill=(24,29,38,90),width=3)
        d.line((x,H,x,H-130,x+70,H-210,x+70,H-330),fill=(25,28,36,85),width=3)
    for y in (65,160,910,1000): d.line((0,y,310,y,360,y+35),fill=(20,25,32,80),width=2)
    draw_logo(img,W//2,430,1.1)
    add_gradient_text(img,'Dex OS',650,122)
    # Names / ThowiLabs as in supplied wallpaper
    f=font(FONTB,58); fm=font(FONT,34)
    d=ImageDraw.Draw(img); d.text((625,870),'Gus',font=f,fill=(255,145,25,255)); d.text((1165,870),'Yahir',font=f,fill=(255,135,25,255))
    txt='T h o w i L a b s'; box=d.textbbox((0,0),txt,font=fm); d.text(((W-(box[2]-box[0]))//2,960),txt,font=fm,fill=(230,125,50,255))
    img.convert('RGB').save(OUT/'dexos-wallpaper.jpg','JPEG',quality=94,optimize=True,progressive=True)

if __name__=='__main__': boot(); wallpaper()
