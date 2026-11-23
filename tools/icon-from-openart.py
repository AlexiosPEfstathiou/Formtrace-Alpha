"""Turn OpenArt SVG icon sheets into clean single-colour icons: paint the paths in their original order
(gold adds, near-background colour cuts), optionally thicken thin icons, and emit one even-odd path per icon."""
import re,json
from svgpathtools import parse_path
from shapely.geometry import Polygon, MultiPolygon
from shapely.ops import unary_union
from shapely.validation import make_valid
S="/tmp/claude-0/-home-claude/84abc145-e2df-5522-9407-d813fc713881/scratchpad/tr/"
A="/mnt/user-data/attachments/84abc145-e2df-5522-9407-d813fc713881/"

def polys(d):
    p=parse_path(d); out=[]
    for sub in p.continuous_subpaths():
        pts=[]
        for seg in sub:
            n=max(2,int(seg.length()/3))
            for i in range(n): z=seg.point(i/n); pts.append((z.real,z.imag))
        if len(pts)>=3:
            g=make_valid(Polygon(pts))
            out.append(g)
    if not out: return None
    acc=out[0]
    for g in out[1:]: acc=acc.symmetric_difference(g)   # even-odd within one path
    return make_valid(acc)

def sheet(f):
    s=open(f).read(); res=[]
    for c,d in re.findall(r'<path[^>]*fill="rgb\(([^)]*)\)" d="([^"]*)"',s):
        r,g,b=map(int,c.split(','))
        res.append((r+g+b<120,d))
    return res[1:]  # drop the background rectangle

def region(items,box):
    x0,y0,x1,y1=box; acc=None
    for dark,d in items:
        n=list(map(float,re.findall(r'-?\d+\.?\d*',d))); bx=(min(n[0::2]),min(n[1::2]),max(n[0::2]),max(n[1::2]))
        if bx[2]<x0 or bx[0]>x1 or bx[3]<y0 or bx[1]>y1: continue
        g=polys(d)
        if g is None: continue
        if dark:
            if acc is not None: acc=acc.difference(g)
        else:
            acc=g if acc is None else acc.union(g)
    return make_valid(acc)

def topath(g):
    parts=[]
    geoms=g.geoms if hasattr(g,'geoms') else [g]
    for p in geoms:
        if p.geom_type!='Polygon' or p.area<4: continue
        for ring in [p.exterior,*p.interiors]:
            c=list(ring.coords)
            parts.append("M"+"L".join(f"{x:.0f} {y:.0f}" for x,y in c)+"z")
    return "".join(parts)

def stroke(g):
    return 2*g.area/max(g.length,1)

s1=sheet(A+"58a39e16-image_1795476382745_ea6ff71d.svg"); s2=sheet(A+"1ed2d47b-image_1795476606387_78555edd.svg")
pad=8
boxes={"calendar":(s1,(826,521,1059,745)),"macros":(s1,(2488,531,2790,736)),"checkins":(s1,(3188,548,3424,728)),"pbs":(s1,(507,968,722,1205)),"calls":(s1,(1960,1026,2135,1206)),
       "weight":(s2,(647,546,1143,1285)),"measures":(s2,(1411,523,2074,1307)),"vacation":(s2,(2616,902,3082,1424))}
out={}; ref=[]
for k,(items,(x0,y0,x1,y1)) in boxes.items():
    g=region(items,(x0-pad,y0-pad,x1+pad,y1+pad))
    size=max(x1-x0,y1-y0); rel=stroke(g)/size
    out[k]=[g,size,rel]
    if items is s1: ref.append(rel)
target=sum(ref)/len(ref)
res={}
for k,(g,size,rel) in out.items():
    if rel<target*0.85:
        grow=(target*size-stroke(g))/2
        g=make_valid(g.buffer(grow,join_style=1,cap_style=1).simplify(0.6))
    else: g=g.simplify(0.6)
    b=g.bounds; side=max(b[2]-b[0],b[3]-b[1])*1.06; cx=(b[0]+b[2])/2; cy=(b[1]+b[3])/2
    res[k]=(f"{cx-side/2:.0f} {cy-side/2:.0f} {side:.0f} {side:.0f}",[topath(g)])
    print(k, f"stroke {rel:.3f} -> target {target:.3f}", len(res[k][1][0]))
json.dump(res,open(S+"icons.json","w"))
js="const TR_ICONS={"+",".join(f'{k}:\'<svg class="tr-svg" viewBox="{vb}" aria-hidden="true"><path fill-rule="evenodd" d="{sh[0]}"/></svg>\'' for k,(vb,sh) in res.items())+"};"
open(S+"trjs.txt","w").write(js); print("js",len(js))
