"""ScrapJaeger: lokale Scrapling-Dashboards (FastAPI, V1: Ad-hoc + Verlauf)."""
from __future__ import annotations

import csv
import io
import json
import os
import time
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse, PlainTextResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

import db
import scraper

BASE = Path(__file__).resolve().parent
load_dotenv(BASE.parent / ".env")
load_dotenv(BASE / ".env")

PORT = int(os.getenv("PORT", "8091"))
HOST = os.getenv("HOST", "0.0.0.0")
DB_PATH = os.getenv("DB_PATH", str(BASE / "data" / "scrapes.db"))
TIMEOUT_MS = int(os.getenv("FETCH_TIMEOUT_MS", "40000"))
VERSION = "0.1.0"

db.open(DB_PATH)

app = FastAPI(title="ScrapJaeger")


class ScrapeReq(BaseModel):
    url: str = Field(min_length=4, max_length=2000)
    selector: str = Field(default="", max_length=1000)
    selector_type: str = Field(default="css", max_length=16)
    fetcher: str = Field(default="auto", max_length=16)


@app.get("/api/health")
def health():
    return {"ok": True, "version": VERSION, "engine": "scrapling"}


@app.post("/api/scrape")
def do_scrape(req: ScrapeReq):
    started = time.time()
    url = req.url.strip()
    if not (url.startswith("http://") or url.startswith("https://")):
        raise HTTPException(status_code=400, detail="url muss mit http(s):// beginnen")
    st = req.selector_type.lower() if req.selector_type.lower() in ("css", "xpath", "text") else "css"
    fx = req.fetcher.lower() if req.fetcher.lower() in scraper.FETCHERS else "auto"
    res = scraper.scrape(url, req.selector, st, fx, TIMEOUT_MS)
    duration = int((time.time() - started) * 1000)
    sid = db.insert_scrape({
        "url": url, "selector": req.selector, "selector_type": st, "fetcher": res["fetcher"],
        "result_count": len(res["items"]), "results_json": json.dumps(res["items"]),
        "duration_ms": duration, "error": "; ".join(res["errors"])[:1000],
    })
    return {"id": sid, "url": url, "selector": req.selector, "selector_type": st,
            "fetcher": res["fetcher"], "count": len(res["items"]),
            "items": res["items"], "errors": res["errors"], "duration_ms": duration}


@app.get("/api/history")
def history(limit: int = 100, q: str = ""):
    return {"history": db.get_history(limit, q)}


@app.get("/api/history/export")
def history_export(format: str = "json"):
    rows = db.get_history(500)
    if format.lower() == "csv":
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(["id", "created_at", "url", "selector", "selector_type",
                    "fetcher", "result_count", "duration_ms", "error"])
        for r in rows:
            w.writerow([r["id"], r["created_at"], r["url"], r["selector"],
                        r["selector_type"], r["fetcher"], r["result_count"],
                        r["duration_ms"], r["error"]])
        return PlainTextResponse(buf.getvalue(), media_type="text/csv")
    return JSONResponse({"history": rows})


@app.get("/api/history/{sid}")
def history_one(sid: int):
    row = db.get_by_id(sid)
    if not row:
        raise HTTPException(status_code=404, detail="nicht gefunden")
    return row


@app.get("/api/crawl")
def crawl_info():
    return {"ok": False, "v2": "Spider-Crawl folgt in V2 (Route reserviert)"}


@app.get("/api/jobs")
def jobs_info():
    return {"ok": False, "v3": "Monitoring/Jobs folgen in V3 (Route reserviert)"}


app.mount("/", StaticFiles(directory=str(BASE / "public"), html=True), name="public")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("server:app", host=HOST, port=PORT)
