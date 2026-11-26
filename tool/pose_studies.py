"""Build PicPic's illustrated posing cards and their named 2D joint coordinates."""
from pathlib import Path
from html import escape
import json, math

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/studies"
# Left/right elbow and wrist offsets relative to the shoulder, in image space.
ARMS = {
    "理衣领": ((-29,37),(-4,10),(22,42),(7,67)),
    "翻手看表": ((-17,41),(10,48),(19,39),(-11,45)),
    "双手捧花": ((-10,45),(14,60),(10,45),(-14,60)),
    "整理耳饰": ((-33,15),(-7,-14),(17,45),(4,75)),
    "双手插袋": ((-15,39),(0,66),(20,35),(4,65)),
    "单手指路": ((-5,41),(1,68),(42,3),(76,-5)),
    "举手招呼": ((-31,-13),(-34,-47),(8,43),(12,75)),
    "双手比心": ((-30,18),(17,15),(30,18),(-17,15)),
    "手搭肩头": ((-20,38),(33,2),(12,40),(9,73)),
    "轻捏帽檐": ((-36,6),(-8,-24),(13,40),(1,74)),
    "托起相机": ((-19,26),(12,-12),(24,24),(-12,-12)),
    "双手舒展": ((-43,-10),(-68,-28),(43,-10),(68,-28)),
    "手贴脸颊": ((-25,18),(-2,-14),(14,42),(-13,57)),
    "双臂上举": ((-19,-31),(-3,-63),(19,-31),(4,-63)),
    "向前递手": ((-6,41),(-3,72),(22,24),(48,31)),
    "手扶膝盖": ((-9,37),(-18,70),(13,34),(24,63)),
    "摊开手掌": ((-22,37),(-54,22),(22,37),(54,22)),
    "举臂自拍": ((-15,44),(1,70),(35,-18),(58,-43)),
    "抬手比耶": ((-20,42),(1,65),(29,10),(20,-22)),
}
# Hip, knee and ankle positions encode the weight shift / leg arrangement.
LEGS = {
    "重心侧移": ((-12,0),(-20,48),(-34,100),(13,0),(13,49),(10,100)),
    "前脚点地": ((-12,0),(-15,47),(-9,100),(12,0),(32,34),(56,77)),
    "后踢腿": ((-12,0),(-9,46),(-7,100),(12,0),(24,40),(51,9)),
    "交叉脚踝": ((-12,0),(-1,48),(17,100),(12,0),(9,49),(-7,100)),
    "弓步": ((-12,0),(-45,32),(-46,83),(12,0),(43,42),(68,82)),
    "跨步": ((-12,0),(-35,40),(-62,77),(12,0),(44,18),(40,72)),
    "抬膝": ((-12,0),(-14,49),(-10,100),(12,0),(45,-16),(57,31)),
    "椅边并膝": ((-12,0),(20,13),(10,64),(12,0),(42,13),(35,64)),
    "坐姿伸腿": ((-12,0),(-33,14),(-68,44),(12,0),(38,11),(27,63)),
    "侧坐收腿": ((-12,0),(22,21),(55,46),(12,0),(48,12),(63,40)),
    "抱膝坐": ((-12,0),(-37,-27),(-44,20),(12,0),(39,-20),(50,20)),
    "单膝点地": ((-12,0),(-36,6),(-40,59),(12,0),(20,55),(60,53)),
    "背身错步": ((-12,0),(-22,48),(-27,100),(12,0),(20,38),(38,84)),
    "并肩站": ((-12,0),(-17,49),(-20,100),(12,0),(18,49),(22,100)),
}
SINGLES = [
 ("重心侧移","站姿","理衣领 翻手看表 双手捧花 整理耳饰"),
 ("前脚点地","站姿","双手插袋 单手指路 举手招呼 双手比心"),
 ("后踢腿","旅行","手搭肩头 轻捏帽檐 托起相机 双手舒展"),
 ("交叉脚踝","人像","手贴脸颊 双臂上举 向前递手 双手捧花"),
 ("弓步","街拍","单手指路 双手舒展 托起相机 摊开手掌"),
 ("跨步","行走","翻手看表 手搭肩头 向前递手 举手招呼"),
 ("抬膝","旅行","双手舒展 举臂自拍 轻捏帽檐 抬手比耶"),
 ("椅边并膝","坐姿","手扶膝盖 整理耳饰 手贴脸颊 托起相机"),
 ("坐姿伸腿","坐姿","手搭肩头 双手插袋 举手招呼 翻手看表"),
 ("侧坐收腿","坐姿","双手捧花 向前递手 轻捏帽檐 双手比心"),
 ("抱膝坐","人像","手贴脸颊 整理耳饰 摊开手掌 抬手比耶"),
 ("单膝点地","街拍","托起相机 单手指路 双手比心 双臂上举"),
 ("背身错步","背影","举手招呼 单手指路 双手舒展 双臂上举"),
 ("并肩站","自拍","举臂自拍 抬手比耶 双手比心 手贴脸颊"),
]
PAIRS = [
 ("并肩问候","情侣","并肩站","举手招呼","重心侧移","手搭肩头"),
 ("一前一后","情侣","跨步","向前递手","前脚点地","举手招呼"),
 ("坐看远处","情侣","椅边并膝","单手指路","侧坐收腿","手贴脸颊"),
 ("花束合影","情侣","交叉脚踝","双手捧花","并肩站","手搭肩头"),
 ("双人爱心","情侣","前脚点地","双手比心","重心侧移","双手比心"),
 ("海边回望","情侣","背身错步","举手招呼","背身错步","单手指路"),
 ("一高一低","情侣","并肩站","双手插袋","单膝点地","双手捧花"),
 ("长椅自拍","情侣","椅边并膝","举臂自拍","坐姿伸腿","抬手比耶"),
 ("错肩街拍","情侣","跨步","理衣领","交叉脚踝","翻手看表"),
 ("草地约会","情侣","抱膝坐","手贴脸颊","侧坐收腿","双手捧花"),
 ("一起出发","双人","跨步","单手指路","跨步","举手招呼"),
 ("同步踢腿","双人","后踢腿","双手舒展","后踢腿","双臂上举"),
 ("轮流掌镜","双人","前脚点地","托起相机","重心侧移","抬手比耶"),
 ("一起伸展","双人","弓步","双臂上举","抬膝","双手舒展"),
 ("台阶合照","双人","单膝点地","手扶膝盖","坐姿伸腿","手搭肩头"),
 ("招手自拍","双人","并肩站","举臂自拍","交叉脚踝","举手招呼"),
 ("背影指路","双人","背身错步","单手指路","背身错步","双手插袋"),
 ("假日野餐","双人","抱膝坐","双手捧花","侧坐收腿","向前递手"),
 ("街角碰面","双人","重心侧移","翻手看表","弓步","举手招呼"),
 ("同时起跑","双人","弓步","向前递手","跨步","摊开手掌"),
]

def joints(legs, arms):
    hip_l,knee_l,ankle_l,hip_r,knee_r,ankle_r=LEGS[legs]
    lean=-7 if legs in ("重心侧移","侧坐收腿","背身错步") else 3
    ls=(lean-23,-57); rs=(lean+23,-57)
    def plus(a,b):return (a[0]+b[0],a[1]+b[1])
    el,wl,er,wr=ARMS[arms]
    return dict(head=(lean,-79),ls=ls,rs=rs,le=plus(ls,el),lw=plus(ls,wl),
                re=plus(rs,er),rw=plus(rs,wr),lh=hip_l,rh=hip_r,lk=knee_l,
                rk=knee_r,la=ankle_l,ra=ankle_r)

def figure(points):
    def xy(k):return ' '.join(map(str,points[k]))
    def chain(keys,thick):
        return f'<polyline points="{" ".join(xy(k) for k in keys)}" stroke="url(#pearl)" fill="none" stroke-width="{thick}" stroke-linecap="round" stroke-linejoin="round"/>'
    body=''
    for leg in ('l','r'):
        body+=chain([leg+'h',leg+'k'],16)+chain([leg+'k',leg+'a'],12)
        x,y=points[leg+'a'];body+=f'<ellipse cx="{x+2}" cy="{y+3}" rx="8" ry="4" fill="#b8b8ba"/>'
    body+=f'<polygon points="{xy("ls")} {xy("rs")} {xy("rh")} {xy("lh")}" fill="url(#pearl)" stroke="#a2a2a4" stroke-width="5" stroke-linejoin="round"/>'
    x,y=points['head'];body+=f'<ellipse cx="{x}" cy="{y}" rx="11" ry="15" fill="url(#pearl)"/>'
    for arm in ('l','r'):
        body+=chain([arm+'s',arm+'e'],10)+chain([arm+'e',arm+'w'],8)
    return body

def write(i,title,cat,people,steps):
    skeletons=[joints(l,a) for l,a in people]
    if len(people)==2:
        for j,pts in enumerate(skeletons):
            xshift=(-66,66)[j]
            ground=max(pts['la'][1],pts['ra'][1])
            skeletons[j]={k:(x+xshift,y-ground) for k,(x,y) in pts.items()}
    coords=[p for pts in skeletons for p in pts.values()]
    x0=min(x for x,y in coords)-18;y0=min(y for x,y in coords)-20
    w=max(x for x,y in coords)-x0+18;h=max(y for x,y in coords)-y0+14
    name=f'study_{i:02}'
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{x0} {y0} {w} {h}"><defs><linearGradient id="pearl"><stop stop-color="#a2a2a4"/><stop offset=".48" stop-color="#e8e8e8"/><stop offset="1" stop-color="#aaa9ad"/></linearGradient></defs>'+''.join(map(figure,skeletons))+'</svg>'
    (OUT/f'{name}.svg').write_text(svg)
    records[name]=dict(title=title,category=cat,people=len(people),steps=steps,aspect=w/h,
                        joints=[{k:[round((x-x0)/w,5),round((y-y0)/h,5)] for k,(x,y) in pts.items()} for pts in skeletons])

records={}
for legs,category,actions in SINGLES:
    for arms in actions.split():
        write(len(records)+1,legs+' · '+arms,category,[(legs,arms)],[legs,arms,'放松肩膀，保持这个动作'])
for title,category,l1,a1,l2,a2 in PAIRS:
    write(len(records)+1,title,category,[(l1,a1),(l2,a2)],['两个人分别站在画面左右','左侧：'+l1+'，'+a1,'右侧：'+l2+'，'+a2])
(OUT/'landmarks.json').write_text(json.dumps(records,ensure_ascii=False,indent=1)+'\n')
