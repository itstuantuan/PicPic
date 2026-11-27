"""PicPic stage-five service. Run exactly one worker per persistent database."""
import asyncio
import base64
from contextlib import asynccontextmanager, closing
import io
import json
import os
from pathlib import Path
import sqlite3
import time
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
import httpx
from PIL import Image, ImageOps, UnidentifiedImageError

DB = Path(os.getenv("PICPIC_DB", "data/picpic.sqlite"))
LIMIT = 8 * 1024 * 1024
STYLES = ("Golden Hour", "Editorial Film", "Soft Flash", "VHS Camcorder", "Vintage",
          "Cinematic", "Portrait", "Fashion Editorial", "Film Photography", "Travel Photography")
SCENES = ("海滩", "台阶", "墙壁", "咖啡馆", "公园", "街道", "建筑", "长椅", "镜子", "室内", "其他")
FIELDS = "id,kind,style,prompt,state,scene,error,attempt,created"
SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs(
 id TEXT NOT NULL, owner TEXT NOT NULL, kind TEXT NOT NULL, style TEXT NOT NULL, prompt TEXT NOT NULL,
 state TEXT NOT NULL, source BLOB NOT NULL, result BLOB, scene TEXT, error TEXT,
 attempt INTEGER NOT NULL DEFAULT 1, created INTEGER NOT NULL, PRIMARY KEY(owner,id));
CREATE INDEX IF NOT EXISTS queue ON jobs(state,created);
CREATE TABLE IF NOT EXISTS usage(owner TEXT, at INTEGER);
CREATE INDEX IF NOT EXISTS usage_time ON usage(at);
"""


def connect():
    db = sqlite3.connect(DB, timeout=15)
    db.row_factory = sqlite3.Row
    return db


def ready(kind):
    return bool(os.getenv("GEMINI_API_KEY") and os.getenv(
        "GEMINI_EDIT_MODEL" if kind == "edit" else "GEMINI_SCENE_MODEL"))


def jpeg(data):
    try:
        with Image.open(io.BytesIO(data)) as im:
            if im.width * im.height > 24_000_000:
                raise ValueError("图片分辨率太大")
            im = ImageOps.exif_transpose(im)
            im.thumbnail((2048, 2048))
            buf = io.BytesIO()
            im.convert("RGB").save(buf, format="JPEG", quality=93)
            return buf.getvalue()
    except (OSError, ValueError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
        raise ValueError("不支持这张图片，请选择 JPEG 或 PNG 照片") from exc


async def owner(req: Request):
    auth = req.headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(401, "请重新登录")
    url, key = os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_PUBLISHABLE_KEY")
    if not url or not key:
        raise HTTPException(503, "服务端尚未配置身份验证")
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            res = await client.get(url.rstrip("/") + "/auth/v1/user",
                                   headers={"apikey": key, "Authorization": auth})
        if res.status_code in (401,403):
            raise HTTPException(401, "会话已失效")
        res.raise_for_status()
        return str(UUID(res.json()["id"]))
    except (httpx.HTTPError, ValueError, KeyError) as exc:
        raise HTTPException(503, "身份服务暂不可用") from exc


def select(db, uid, job):
    row = db.execute(f"SELECT {FIELDS} FROM jobs WHERE owner=? AND id=?", (uid, str(job))).fetchone()
    if not row:
        raise HTTPException(404, "找不到任务")
    return dict(row)


def quota(db, uid):
    now = int(time.time())
    db.execute("DELETE FROM usage WHERE at < ?", (now - 86400,))
    count, personal = db.execute("SELECT count(*),count(CASE WHEN owner=? THEN 1 END) FROM usage", (uid,)).fetchone()
    if count >= int(os.getenv("GLOBAL_DAILY_LIMIT","100")) or personal >= int(os.getenv("USER_DAILY_LIMIT","10")):
        raise HTTPException(429, "已达到今日用量上限")
    db.execute("INSERT INTO usage VALUES(?,?)", (uid, now))


async def generate(row):
    edit = row["kind"] == "edit"
    model = os.environ["GEMINI_EDIT_MODEL" if edit else "GEMINI_SCENE_MODEL"]
    instruction = (f"Restyle this photograph in {row['style']} style. Preserve the person's identity, facial "
                   "features, clothing, pose, composition and number of people. Return an edited photograph. "
                   f"Additional photographic direction: {row['prompt']}") if edit else (
                   "Identify the most useful visible setting for posing. Choose 其他 if uncertain. "
                   "Respond with one enum value only.")
    config = {"responseModalities":["TEXT","IMAGE"]} if edit else {
        "responseMimeType":"application/json","responseSchema":{"type":"STRING","enum":list(SCENES)}}
    payload = {"contents":[{"parts":[{"text":instruction},{"inlineData":{
        "mimeType":"image/jpeg","data":base64.b64encode(row["source"]).decode()}}]}],"generationConfig":config}
    async with httpx.AsyncClient(timeout=150) as client:
        resp = await client.post(f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
                                 json=payload,headers={"x-goog-api-key":os.environ["GEMINI_API_KEY"]})
    if resp.status_code != 200:
        raise ValueError(f"模型请求失败（HTTP {resp.status_code}）")
    candidates = resp.json().get("candidates") or []
    parts = candidates[0].get("content",{}).get("parts",[]) if candidates else []
    for part in parts:
        if part.get("thought"):
            continue
        if edit and "inlineData" in part:
            return jpeg(base64.b64decode(part["inlineData"]["data"], validate=True)), None
        if not edit and "text" in part:
            scene = json.loads(part["text"])
            if scene in SCENES:
                return None, scene
    raise ValueError("模型未返回可用结果")


async def worker():
    next_cleanup = 0.0
    while True:
        with closing(connect()) as db, db:
            if time.monotonic() >= next_cleanup:
                cutoff = int(time.time()) - 86400 * max(1, int(os.getenv("RETENTION_DAYS","30")))
                db.execute("DELETE FROM jobs WHERE state IN ('failed','done') AND created < ?", (cutoff,))
                next_cleanup = time.monotonic() + 3600
            row = db.execute("SELECT * FROM jobs WHERE state='queued' ORDER BY created LIMIT 1").fetchone()
            if row:
                db.execute("UPDATE jobs SET state='running' WHERE owner=? AND id=?", (row["owner"],row["id"]))
        if not row:
            await asyncio.sleep(.5)
            continue
        try:
            result,scene = await generate(row)
            values = ("done",result,scene,None)
        except Exception as exc:
            message = str(exc) if isinstance(exc,ValueError) else "模型服务暂时不可用，请稍后重试"
            values = ("failed",None,None,message[:180])
        with closing(connect()) as db, db:
            db.execute("UPDATE jobs SET state=?,result=?,scene=?,error=? WHERE owner=? AND id=?",
                       (*values,row["owner"],row["id"]))


@asynccontextmanager
async def lifespan(app):
    DB.parent.mkdir(parents=True, exist_ok=True)
    with closing(connect()) as db, db:
        db.execute("PRAGMA journal_mode=WAL")
        db.executescript(SCHEMA)
        db.execute("UPDATE jobs SET state='failed',error='处理被中断，可手动重试' WHERE state='running'")
    task=asyncio.create_task(worker())
    try:
        yield
    finally:
        task.cancel()
        await asyncio.gather(task,return_exceptions=True)


app=FastAPI(lifespan=lifespan,docs_url=None,redoc_url=None)


@app.get("/jobs")
def history(uid: str=Depends(owner)):
    with closing(connect()) as db:
        return [dict(r) for r in db.execute(f"SELECT {FIELDS} FROM jobs WHERE owner=? ORDER BY created DESC,rowid DESC LIMIT 100",(uid,))]


@app.post("/jobs/{job}")
async def submit(job: UUID,request: Request,kind: str, style: str="",prompt: str=Query("",max_length=600),uid: str=Depends(owner)):
    if kind not in ("scene","edit") or (kind=="edit" and style not in STYLES):
        raise HTTPException(422,"无效的任务类型或风格")
    with closing(connect()) as db:
        if db.execute("SELECT 1 FROM jobs WHERE owner=? AND id=?",(uid,str(job))).fetchone():
            return select(db,uid,job)
    if not ready(kind):
        raise HTTPException(503,"服务端尚未配置此模型")
    data=bytearray()
    async for chunk in request.stream():
        if len(data)+len(chunk)>LIMIT:
            raise HTTPException(413,"照片超过 8 MB")
        data.extend(chunk)
    try:
        source=await asyncio.to_thread(jpeg,data)
    except ValueError as exc:
        raise HTTPException(422,str(exc)) from exc
    with closing(connect()) as db, db:
        db.execute("BEGIN IMMEDIATE")
        if not db.execute("SELECT 1 FROM jobs WHERE owner=? AND id=?",(uid,str(job))).fetchone():
            quota(db,uid)
            db.execute("INSERT INTO jobs(id,owner,kind,style,prompt,state,source,created) VALUES(?,?,?,?,?,'queued',?,?)",
                       (str(job),uid,kind,style,prompt,source,int(time.time())))
        return select(db,uid,job)


@app.get("/jobs/{job}")
def detail(job:UUID,uid:str=Depends(owner)):
    with closing(connect()) as db:
        return select(db,uid,job)


@app.post("/jobs/{job}/retry")
def retry(job:UUID,attempt:int,uid:str=Depends(owner)):
    with closing(connect()) as db, db:
        db.execute("BEGIN IMMEDIATE")
        row=select(db,uid,job)
        if row["state"]=="failed" and row["attempt"]==attempt:
            if not ready(row["kind"]):
                raise HTTPException(503,"服务端尚未配置此模型")
            quota(db,uid)
            db.execute("UPDATE jobs SET state='queued',error=NULL,attempt=attempt+1 WHERE id=? AND owner=?",(str(job),uid))
        return select(db,uid,job)


@app.get("/jobs/{job}/image/{which}")
def image(job:UUID,which:str,uid:str=Depends(owner)):
    if which not in ("source","result"):
        raise HTTPException(404)
    with closing(connect()) as db:
        row=db.execute(f"SELECT {which} FROM jobs WHERE id=? AND owner=?",(str(job),uid)).fetchone()
    if not row or not row[0]:
        raise HTTPException(404,"图片不存在")
    return Response(row[0],media_type="image/jpeg",headers={"Cache-Control":"private, no-store"})
