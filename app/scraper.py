"""Scrapling-Wrapper: auto/http/stealth/dynamic + CSS/XPath-Auswahl."""
from __future__ import annotations

import time

FETCHERS = ("auto", "http", "stealthy", "dynamic")


def _page_text(el) -> str:
    try:
        txt = el.text
        if callable(txt):
            txt = txt()
        return (txt or "").strip()
    except Exception:
        return ""


def _page_html(el, limit: int = 2000) -> str:
    try:
        html = el.html
        if callable(html):
            html = html()
        return str(html or "")[:limit]
    except Exception:
        return ""


def _attrs(el) -> dict:
    try:
        attribs = el.attribs if isinstance(el.attribs, dict) else dict(el.attribs or {})
        return {k: str(v) for k, v in attribs.items()}
    except Exception:
        return {}


def _select(page, selector: str, selector_type: str):
    st = (selector_type or "css").lower()
    if not selector:
        return [page]
    if st == "xpath":
        return page.xpath(selector)
    if st == "text":
        try:
            return page.find_by_text(selector)
        except Exception:
            return page.css(f":contains('{selector}')")
    return page.css(selector)


def _row(el, idx: int) -> dict:
    href = ""
    try:
        href = el.css("a::attr(href)").get() or el.attrib.get("href", "") or ""
    except Exception:
        href = ""
    return {
        "i": idx,
        "tag": getattr(el, "tag", "") or "",
        "text": _page_text(el),
        "html": _page_html(el),
        "href": href,
        "attrs": _attrs(el),
    }


def scrape(url: str, selector: str = "", selector_type: str = "css",
           fetcher: str = "auto", timeout_ms: int = 40000) -> dict:
    started = time.time()
    errors: list[str] = []
    items: list[dict] = []
    used = fetcher if fetcher in FETCHERS else "auto"
    timeout_s = max(5, min(int(timeout_ms or 40000) // 1000, 120))

    def run(kind: str):
        from scrapling.fetchers import DynamicFetcher, Fetcher, StealthyFetcher

        if kind == "http":
            return Fetcher.get(url, timeout=timeout_s * 1000)
        if kind == "stealthy":
            return StealthyFetcher.fetch(url, headless=True, timeout=timeout_s * 1000)
        if kind == "dynamic":
            return DynamicFetcher.fetch(url, headless=True, timeout=timeout_s * 1000)
        raise ValueError(f"unbekannter Fetcher: {kind}")

    order = [used] if used != "auto" else ["http", "stealthy", "dynamic"]
    page = None
    for kind in order:
        try:
            page = run(kind)
            used = kind if used == "auto" else used
            break
        except Exception as exc:  # volle Kette sammeln, nicht nur letzte Zeile
            errors.append(f"{kind}: {type(exc).__name__}: {exc}")
            page = None
    if page is None:
        return {"items": [], "fetcher": used, "errors": errors,
                "duration_ms": int((time.time() - started) * 1000)}

    try:
        found = _select(page, selector, selector_type)
    except Exception as exc:
        errors.append(f"selector: {type(exc).__name__}: {exc}")
        found = []
    try:
        items = [_row(el, i) for i, el in enumerate(list(found)[:500])]
    except Exception as exc:
        errors.append(f"extract: {type(exc).__name__}: {exc}")
        items = []
    return {"items": items, "fetcher": used, "errors": errors,
            "duration_ms": int((time.time() - started) * 1000)}
