"""SQLite-Verlauf fuer ScrapJaeger (V1: Ad-hoc Scrapes, V2/V3: Tabellen vorbereitet)."""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path

_handle: sqlite3.Connection | None = None


def open(path: str) -> sqlite3.Connection:
    global _handle
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    _handle = sqlite3.connect(path, check_same_thread=False)
    _handle.row_factory = sqlite3.Row
    _handle.execute(
        """CREATE TABLE IF NOT EXISTS scrapes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at INTEGER NOT NULL,
          url TEXT NOT NULL,
          selector TEXT NOT NULL DEFAULT '',
          selector_type TEXT NOT NULL DEFAULT 'css',
          fetcher TEXT NOT NULL DEFAULT 'auto',
          result_count INTEGER NOT NULL DEFAULT 0,
          results_json TEXT NOT NULL DEFAULT '[]',
          duration_ms INTEGER NOT NULL DEFAULT 0,
          error TEXT NOT NULL DEFAULT ''
        )"""
    )
    _handle.execute(
        "CREATE INDEX IF NOT EXISTS idx_scrapes_created ON scrapes(created_at DESC)"
    )
    _handle.execute(
        """CREATE TABLE IF NOT EXISTS crawls(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at INTEGER NOT NULL,
          start_url TEXT NOT NULL,
          max_pages INTEGER NOT NULL DEFAULT 20,
          result_count INTEGER NOT NULL DEFAULT 0,
          results_json TEXT NOT NULL DEFAULT '[]',
          duration_ms INTEGER NOT NULL DEFAULT 0,
          error TEXT NOT NULL DEFAULT ''
        )"""
    )
    _handle.execute(
        """CREATE TABLE IF NOT EXISTS jobs(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          created_at INTEGER NOT NULL,
          name TEXT NOT NULL DEFAULT '',
          url TEXT NOT NULL DEFAULT '',
          selector TEXT NOT NULL DEFAULT '',
          cron TEXT NOT NULL DEFAULT '',
          enabled INTEGER NOT NULL DEFAULT 1,
          last_run INTEGER NOT NULL DEFAULT 0,
          last_count INTEGER NOT NULL DEFAULT 0
        )"""
    )
    _handle.commit()
    return _handle


def handle() -> sqlite3.Connection:
    assert _handle is not None, "db.open() wurde nicht aufgerufen"
    return _handle


def insert_scrape(row: dict) -> int:
    db = handle()
    cur = db.execute(
        """INSERT INTO scrapes(created_at,url,selector,selector_type,fetcher,
           result_count,results_json,duration_ms,error)
           VALUES(?,?,?,?,?,?,?,?,?)""",
        (
            int(time.time() * 1000),
            row.get("url", ""),
            row.get("selector", ""),
            row.get("selector_type", "css"),
            row.get("fetcher", "auto"),
            row.get("result_count", 0),
            row.get("results_json", "[]"),
            row.get("duration_ms", 0),
            row.get("error", ""),
        ),
    )
    db.commit()
    return int(cur.lastrowid)


def get_history(limit: int = 100, q: str = "") -> list[dict]:
    db = handle()
    try:
        lim = max(1, min(int(limit or 100), 500))
    except (TypeError, ValueError):
        lim = 100
    if q:
        cur = db.execute(
            """SELECT id,created_at,url,selector,selector_type,fetcher,
               result_count,duration_ms,error FROM scrapes
               WHERE url LIKE ? OR selector LIKE ? ORDER BY id DESC LIMIT ?""",
            (f"%{q}%", f"%{q}%", lim),
        )
    else:
        cur = db.execute(
            """SELECT id,created_at,url,selector,selector_type,fetcher,
               result_count,duration_ms,error FROM scrapes
               ORDER BY id DESC LIMIT ?""",
            (lim,),
        )
    return [dict(r) for r in cur.fetchall()]


def get_by_id(scrape_id: int) -> dict | None:
    db = handle()
    cur = db.execute("SELECT * FROM scrapes WHERE id=?", (scrape_id,))
    row = cur.fetchone()
    if not row:
        return None
    out = dict(row)
    try:
        out["results"] = json.loads(out.get("results_json") or "[]")
    except (ValueError, TypeError):
        out["results"] = []
    return out
