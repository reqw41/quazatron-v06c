from PIL import Image, ImageDraw, ImageFont
im=Image.open('img.png').convert('RGB'); W,H=im.size; px=im.load()
LV=[round(i*255/7) for i in range(8)]; LB=[0,85,170,255]
def vq(c):
    r,g,b=c
    return (min(LV,key=lambda v:abs(v-r)),min(LV,key=lambda v:abs(v-g)),min(LB,key=lambda v:abs(v-b)))
BLUE,CYAN,BLK,WHT,YEL,RED,MAG=(0,0,255),(0,255,255),(0,0,0),(255,255,255),(255,255,0),(255,0,0),(255,0,255)
norm={(0,205,205):CYAN,(0,0,205):BLUE}
src=[[norm.get(px[x,y],px[x,y]) for x in range(W)] for y in range(H)]
def palette(contrast):
    if contrast:
        P={'bg0':(0,0,85),'bg1':(0,36,170),'bg2':(36,73,255),'cy0':(0,73,85),'cy1':(36,146,170),'cy2':(109,219,255),
           'cy3':(182,255,255),'wh':(255,255,255),'bk':(0,0,0),'ye0':(182,146,0),'ye1':(255,219,85),'re0':(146,0,0),
           're1':(255,36,0),'mg':(219,73,170),'bl':(73,109,255),'gr':(146,146,170)}
    else:
        P={'bg0':(0,36,85),'bg1':(36,73,170),'bg2':(73,109,255),'cy0':(36,109,170),'cy1':(73,182,170),'cy2':(146,219,255),
           'cy3':(219,255,255),'wh':(255,255,255),'bk':(0,0,0),'ye0':(182,182,85),'ye1':(255,219,85),'re0':(146,36,0),
           're1':(219,36,0),'mg':(182,73,170),'bl':(109,146,255),'gr':(146,146,170)}
    return {k:vq(v) for k,v in P.items()}
def base_map(P):  # ZX colour -> palette colour (solid areas)
    return {BLUE:P['bg1'],CYAN:P['cy2'],BLK:P['bk'],WHT:P['wh'],YEL:P['ye1'],RED:P['re1'],MAG:P['mg']}
def mix_map(P):   # unordered pair (checker) -> mid shade
    return {frozenset({CYAN,BLK}):P['cy0'],frozenset({CYAN,WHT}):P['cy3'],frozenset({CYAN,BLUE}):P['cy1'],
            frozenset({BLUE,WHT}):P['bl'],frozenset({BLUE,BLK}):P['bg0'],frozenset({YEL,WHT}):P['ye1'],
            frozenset({YEL,BLUE}):P['ye0'],frozenset({YEL,BLK}):P['ye0'],frozenset({RED,BLK}):P['re0'],
            frozenset({RED,WHT}):P['re1'],frozenset({WHT,BLK}):P['gr'],frozenset({RED,BLUE}):P['re0'],
            frozenset({MAG,BLK}):P['mg'],frozenset({RED,CYAN}):P['re1'],frozenset({YEL,CYAN}):P['cy3']}
def nearest(c,cols):
    return min(cols,key=lambda p:(p[0]-c[0])**2*3+(p[1]-c[1])**2*4+(p[2]-c[2])**2*2)
def C1(P):
    bm=base_map(P); cols=list(P.values()); out=Image.new('RGB',(W,H)); o=out.load()
    for y in range(H):
        for x in range(W):
            c=bm[src[y][x]]; acc=[2*v for v in c]; n=2
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                xx,yy=x+dx,y+dy
                if 0<=xx<W and 0<=yy<H:
                    cc=bm[src[yy][xx]]; acc=[a+b*0.5 for a,b in zip(acc,cc)]; n+=0.5
            o[x,y]=nearest(tuple(a/n for a in acc),cols)
    return out
def checker(x,y):
    c=src[y][x]; nb=[src[yy][xx] for xx,yy in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)) if 0<=xx<W and 0<=yy<H]
    if all(n!=c for n in nb):
        others=set(nb)
        if len(others)==1: return frozenset({c,nb[0]})
    # 2-pixel-wide stripes/dither: diagonal neighbours same, orthogonal different
    return None
def C2(P,grad=False):
    bm=base_map(P); mm=mix_map(P); out=Image.new('RGB',(W,H)); o=out.load()
    bayer=[[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]
    for y in range(H):
        for x in range(W):
            c=src[y][x]; k=checker(x,y)
            if k is not None and k in mm: col=mm[k]
            else: col=bm[c]
            if grad and c==BLUE and k is None:
                t=y/H*2.0   # 0..2 : bg0 -> bg1 -> bg2
                lo,hi,f=(('bg0','bg1',t) if t<1 else ('bg1','bg2',t-1))
                col=P[hi] if f*16>bayer[y&3][x&3]+0.5 else P[lo]
            o[x,y]=col
    return out
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',14)
V=[('ZX',im),('C (было)',Image.open('C.png')),('C1: сглаживание, своя палитра',C1(palette(False))),
   ('C2: только шахматки -> оттенок',C2(palette(False))),('C3: C2 + переход фона',C2(palette(False),True)),
   ('C4: C3 контрастнее',C2(palette(True),True))]
for t,img in V[2:]: print(t, len(set(img.getdata())),'цветов')
cols=3; out=Image.new('RGB',(cols*(W*2+10),2*(H*2+24)),(40,40,40)); d=ImageDraw.Draw(out)
for k,(t,img) in enumerate(V):
    x=(k%cols)*(W*2+10); y=(k//cols)*(H*2+24)
    out.paste(img.resize((W*2,H*2),Image.NEAREST),(x,y+22)); d.text((x+4,y+3),t,fill=(255,255,255),font=font)
    if k>=2: img.save(f'C{k-1}.png')
out.save('/Users/boris/projects/quazatron-v06c/build/splash_c.png')
