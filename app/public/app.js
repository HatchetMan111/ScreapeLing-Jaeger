"use strict";
let lastItems = [], lastMeta = null;
const $ = (id) => document.getElementById(id);

function tabs() {
  const map = { "tab-scrape": "view-scrape", "tab-history": "view-history", "tab-roadmap": "view-roadmap" };
  for (const [b, v] of Object.entries(map)) {
    $(b).onclick = () => {
      for (const x of Object.keys(map)) $(x).classList.remove("active");
      $(b).classList.add("active");
      for (const y of Object.values(map)) $(y).classList.add("hidden");
      $(v).classList.remove("hidden");
      if (v === "view-history") loadHistory();
    };
  }
}

function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function renderRows(items) {
  const f = $("filter").value.toLowerCase();
  const rows = items.filter((r) => !f || (r.text + " " + r.tag + " " + r.href).toLowerCase().includes(f));
  $("count").textContent = `${rows.length}/${items.length} Treffer · ${lastMeta ? lastMeta.fetcher + " · " + lastMeta.duration_ms + " ms" : ""}`;
  $("rows").innerHTML = rows.slice(0, 300).map((r) => `<tr><td>${r.i}</td><td>${esc(r.tag)}</td><td class="t" title="${esc(r.text)}">${esc(r.text.slice(0, 220))}</td><td>${r.href ? `<a href="${esc(r.href)}" target="_blank" rel="noopener">Link</a>` : ""}</td><td>${esc(lastMeta ? lastMeta.fetcher : "")}</td></tr>`).join("");
}

async function scrape(ev) {
  ev.preventDefault();
  $("status").textContent = "Scrape läuft …";
  $("errs").textContent = "";
  try {
    const res = await fetch("/api/scrape", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url: $("url").value.trim(), selector: $("sel").value, selector_type: $("seltype").value, fetcher: $("fetcher").value }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || data.error || "Fehler");
    lastItems = data.items || []; lastMeta = data;
    renderRows(lastItems);
    $("status").textContent = `#${data.id} · ${data.count} Treffer`;
    $("errs").textContent = (data.errors || []).join(" | ");
  } catch (e) { $("status").textContent = "Fehler: " + e.message; }
}

async function loadHistory() {
  const q = $("hq").value;
  const res = await fetch("/api/history?limit=100&q=" + encodeURIComponent(q));
  const data = await res.json();
  $("hrows").innerHTML = (data.history || []).map((r) => `<tr><td><a href="#" data-id="${r.id}">${r.id}</a></td><td>${new Date(r.created_at).toLocaleString()}</td><td class="t">${esc(r.url)}</td><td class="t">${esc(r.selector || "(Seite)")}</td><td>${r.result_count}</td><td>${r.duration_ms} ms</td><td class="t">${esc(r.error || "")}</td></tr>`).join("");
  $("hrows").querySelectorAll("a").forEach((a) => a.onclick = async (ev) => {
    ev.preventDefault();
    const d = await (await fetch("/api/history/" + a.dataset.id)).json();
    lastItems = d.results || []; lastMeta = { fetcher: d.fetcher, duration_ms: d.duration_ms };
    $("detail").classList.remove("hidden");
    $("detail").innerHTML = `<b>#${d.id}</b> ${esc(d.url)} · ${d.results.length} Treffer <button id="take">In Scrape übernehmen</button>`;
    $("take").onclick = () => { renderRows(lastItems); document.getElementById("tab-scrape").click(); };
    renderRows(lastItems);
  });
}

function download(name, text, type) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type })); a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

tabs();
$("f").onsubmit = scrape;
$("filter").oninput = () => renderRows(lastItems);
$("hgo").onclick = loadHistory;
$("exp-json").onclick = () => download("scrape.json", JSON.stringify(lastItems, null, 2), "application/json");
$("exp-csv").onclick = () => {
  const rows = [["i", "tag", "text", "href"]];
  for (const r of lastItems) rows.push([r.i, r.tag, (r.text || "").replace(/"/g, '""'), r.href]);
  download("scrape.csv", rows.map((r) => r.map((v) => `"${v}"`).join(",")).join("\n"), "text/csv");
};
loadHistory();
