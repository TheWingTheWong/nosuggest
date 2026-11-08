// Words your Mac won't suggest: renders the census data in docs/data.
"use strict";

const LANG = "en";
const PAGE = 60;
const SLURS = "slurs";

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const fmt = (n) => n.toLocaleString("en-US");
const pct = (x, d = 1) => (x * 100).toFixed(d) + "%";

const state = { words: [], filtered: [], shown: PAGE, cat: "all", q: "", showSlurs: false, specimens: new Map() };

async function load() {
  const [summary, words, specimens, concepts] = await Promise.all([
    fetch(`data/summary-${LANG}.json`).then((r) => r.json()),
    fetch(`data/words-${LANG}.json`).then((r) => r.json()),
    fetch(`data/specimens-${LANG}.json`).then((r) => r.json()),
    fetch("data/concepts.json").then((r) => r.json()),
  ]);
  renderMatrix(concepts);
  state.words = words.filter((w) => w.v === "suppressed");
  for (const s of specimens) state.specimens.set(s.typo, s);
  renderFacts(summary);
  renderSpecimens(specimens);
  renderChips();
  renderHistogram(summary.control);
  applyFilter();
}

function renderFacts(s) {
  const c = s.census, f = s.final;
  document.querySelectorAll('[data-fill="os"]').forEach((el) => (el.textContent = "macOS " + s.os.replace(/^Version /, "")));
  document.querySelectorAll('[data-fill="generated"]').forEach((el) => (el.textContent = s.generated.slice(0, 10)));
  const avg = Math.round(s.verifyTypos / c.suppressed);
  $("headline-stats").innerHTML =
    `Out of ${fmt(c.tested)} English words that macOS accepts, <strong>${fmt(f.suppressed)}</strong> never come back as a suggestion. ` +
    `Each was tried with every keyboard-plausible one-letter typo, about ${avg} per word. ` +
    `${pct(f.suppressedEmptyListShare, 0)} of those typos got no suggestions at all, ` +
    `and ${fmt(f.suppressedAlsoMissingFromCompletions)} of the words are also missing from word completion.`;
  $("list-text").innerHTML =
    `Every word here passes the spell check when typed correctly. A first pass tried up to eight typos on each of ${fmt(c.tested)} words, stopping at the first hit, and flagged ${fmt(c.suppressed)}; ` +
    `a second pass tried every keyboard-plausible typo on those, ${fmt(s.verifyTypos)} in all, and cleared ${fmt(s.cleared.length)}: ` +
    `${s.cleared.filter((x) => x[1] === "typo").length} came back from some typo (${s.cleared.filter((x) => x[1] === "typo").slice(0, 4).map((x) => `<em>${esc(x[0])}</em> from <em>${esc(x[2])}</em>`).join(", ")}), ` +
    `${s.cleared.filter((x) => x[1] === "related").length} came back only as another form, and ${s.cleared.filter((x) => x[1] === "autocorrect" || x[1] === "completion").length} through autocorrect. ` +
    `Words where the checker offered a different form of the same word instead (<em>Boston's</em> for <em>Bostns</em>) are not counted. ` +
    `The categories are editorial, assigned by hand-written rules in <a href="https://github.com/TheWingTheWong/nosuggest/blob/main/data/categories.tsv"><code>data/categories.tsv</code></a>.`;

  const k = s.control;
  const all = k.perKind.reduce((x, r) => x + r.trials, 0), hits = k.perKind.reduce((x, r) => x + r.hits, 0);
  $("method-text").innerHTML =
    `A spell checker misses the right word sometimes for ordinary reasons. To see how often, eight typos were tried, with no early stop, on ` +
    `${fmt(k.wordsTested)} random lowercase words that macOS accepts. ${pct(k.overallRate)} of all their typos brought the word back; ` +
    `among words that came back at all, ${pct(hits / all)} did.`;
  $("hist-caption").textContent =
    `${fmt(k.wordsTested)} random lowercase words, by how many of their eight typos brought them back (log scale). The bar at zero is words that never came back` +
    (k.controlRelated ? `, or came back only as another form of the word (${k.controlRelated} of these)` : "") + `.`;
  const z = s.auditControlZeros, a = s.auditSample, b = s.auditBaseRate;
  const share = (x) => pct(x.topical / x.size, 0);
  $("fp-text").innerHTML =
    `The middle of the histogram is nearly empty, and the zeros are not random-looking. Three samples were labelled by hand with the same rubric ` +
    `(an obvious sensitive meaning, spelled like one, or no apparent reason):` +
    `<ul class="audit">` +
    (z ? `<li>all ${z.size} control words flagged by the first pass: ${share(z)} sensitive, ${z.none} with no apparent reason;</li>` : "") +
    (a ? `<li>${a.size} words drawn at random from the final list: ${share(a)} sensitive, ${a.lookalike} lookalikes, ${a.none} (${pct(a.noneRate)}, 95% interval ${pct(a.noneLow)} to ${pct(a.noneHigh)}) with no apparent reason: ${a.noneWords.map(esc).join(", ")};</li>` : "") +
    (b ? `<li>for comparison, ${b.size} words drawn at random from the words macOS <em>does</em> suggest: ${share(b)} sensitive.</li>` : "") +
    `</ul>The labels are one person's judgement and are in the repository so you can disagree with them.`;

  const cmp = s.comparison;
  $("ios-text").innerHTML =
    `This week's reporting on Apple's "grey list" was about the iPhone keyboard. Derik Kauffman recovered it from iOS 27.0: ` +
    `${fmt(cmp.iosPhrases)} English entries, every one of them a phrase of two to six words, used to stop predictions and swipe typing. ` +
    `The spell checker's list is a different mechanism: it works on single words, and ` +
    `<strong>${fmt(cmp.suppressedNotInIOS)}</strong> of the ${fmt(cmp.suppressedNotInIOS + cmp.suppressedInIOSPhrase)} words here do not occur in any iOS entry at all.`;
  const hun = Object.entries(cmp.hunspellNoSuggest);
  const count = (v) => hun.filter(([, x]) => x === v).length;
  const hunSug = hun.filter(([, v]) => v === "suggested").map(([w]) => w);
  $("hunspell-text").innerHTML =
    `Open-source spell checkers do something similar, in the open. The Hunspell <code>en_US</code> dictionary used by LibreOffice marks ` +
    `${hun.length} entries <code>NOSUGGEST</code>, all of them profanity or slurs. macOS suppresses ${count("suppressed")} of them` +
    (hunSug.length ? ` and still suggests ${hunSug.length} (${hunSug.map(esc).join(", ")})` : "; it suggests none of them") +
    `. The difference is scope: Hunspell's list is ${hun.length} lines anyone can read; the Mac's covers medicine, religion, crime and history, and is not published.`;
}

function renderSpecimens(list) {
  $("specimens").innerHTML = list
    .map((s) => `<span class="typo specimen${s.guesses.some((g) => g.toLowerCase() === s.word.toLowerCase()) ? " ok" : ""}" tabindex="0" role="button" aria-haspopup="menu" data-word="${esc(s.typo)}">${esc(s.typo)}</span>`)
    .join("");
  document.querySelectorAll(".typo").forEach((el) => {
    el.tabIndex = 0;
    el.addEventListener("click", (e) => { e.stopPropagation(); openMenu(el); });
    el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openMenu(el); }
    });
  });
}

let menuOwner = null;
function openMenu(el) {
  const menu = $("menu");
  if (menuOwner === el && !menu.hidden) return closeMenu();
  closeMenu();
  const s = state.specimens.get(el.dataset.word);
  if (!s) return;
  const items = s.guesses.length
    ? s.guesses.slice(0, 6).map((g) => `<div class="item guess${g.toLowerCase() === s.word.toLowerCase() ? " hit" : ""}" role="menuitem">${esc(g)}</div>`).join("")
    : `<div class="item none" role="menuitem" aria-disabled="true">No Guesses Found</div>`;
  const found = s.guesses.some((g) => g.toLowerCase() === s.word.toLowerCase());
  menu.innerHTML = items +
    `<div class="sep"></div><div class="item dim">Ignore Spelling</div><div class="item dim">Learn Spelling</div>` +
    `<div class="sep"></div><div class="meta">${found ? "Suggests" : "Accepts but never suggests"} <em>${esc(s.word)}</em></div>`;
  const r = el.getBoundingClientRect();
  menu.hidden = false;
  menu.style.left = Math.min(window.scrollX + r.left, window.scrollX + document.documentElement.clientWidth - menu.offsetWidth - 8) + "px";
  menu.style.top = window.scrollY + r.bottom + 4 + "px";
  el.setAttribute("aria-expanded", "true");
  menuOwner = el;
}
function closeMenu() {
  $("menu").hidden = true;
  if (menuOwner) menuOwner.setAttribute("aria-expanded", "false");
  menuOwner = null;
}
document.addEventListener("click", closeMenu);
document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeMenu(); });

function renderChips() {
  const counts = new Map();
  for (const w of state.words) counts.set(w.cat, (counts.get(w.cat) || 0) + 1);
  const cats = [...counts.entries()].sort((a, b) => b[1] - a[1]);
  const all = [["all", state.words.length], ...cats];
  $("chips").innerHTML = all
    .map(([c, n]) => `<button type="button" class="chip" data-cat="${esc(c)}" aria-pressed="${c === state.cat}">${c === "all" ? "All" : esc(c)}<span class="n">${fmt(n)}</span></button>`)
    .join("");
  $("chips").addEventListener("click", (e) => {
    const b = e.target.closest(".chip");
    if (!b) return;
    state.cat = b.dataset.cat;
    document.querySelectorAll(".chip").forEach((x) => x.setAttribute("aria-pressed", x === b));
    state.shown = PAGE;
    applyFilter();
  });
}

function applyFilter() {
  const q = state.q.trim().toLowerCase();
  state.filtered = state.words.filter((w) => (state.cat === "all" || w.cat === state.cat) && (!q || w.w.toLowerCase().includes(q)));
  renderRows();
}

function renderRows() {
  const rows = state.filtered.slice(0, state.shown).map((w) => {
    const hide = w.cat === SLURS && !state.showSlurs;
    const ex = w.ex[0] || [];
    const offered = (ex.length > 1 ? ex.slice(1, 5).map(esc).join(", ") : "no guesses") + ` <span class="n">(0 of ${w.n} typos)</span>`;
    const word = hide ? `<span class="blur" title="Click to reveal">${esc(w.w)}</span>` : esc(w.w);
    const typo = hide ? `<span class="blur">${esc(ex[0] || "")}</span>` : `<span class="t">${esc(ex[0] || "")}</span>`;
    return `<tr><td class="w">${word}</td><td class="cat">${esc(w.cat)}</td><td class="ex">${typo}: ${hide ? "" : offered}</td><td class="ios">${w.ios ? "yes" : ""}</td></tr>`;
  });
  $("rows").innerHTML = rows.join("");
  $("count").textContent = `${fmt(state.filtered.length)} word${state.filtered.length === 1 ? "" : "s"}` + (state.filtered.length > state.shown ? `, showing ${fmt(state.shown)}` : "");
  $("more").hidden = state.filtered.length <= state.shown;
}

$("rows").addEventListener("click", (e) => { if (e.target.classList.contains("blur")) e.target.classList.remove("blur"); });
$("more").addEventListener("click", () => { state.shown += PAGE * 4; renderRows(); });
$("q").addEventListener("input", (e) => {
  state.q = e.target.value;
  state.shown = PAGE;
  // A search looks through every category.
  if (state.q && state.cat !== "all") {
    state.cat = "all";
    document.querySelectorAll(".chip").forEach((x) => x.setAttribute("aria-pressed", x.dataset.cat === "all"));
  }
  applyFilter();
});
$("show-slurs").addEventListener("change", (e) => { state.showSlurs = e.target.checked; renderRows(); });

const LANG_NAMES = { en: "English", de: "German", fr: "French", es: "Spanish", it: "Italian", pt_BR: "Portuguese", nl: "Dutch" };

function renderMatrix(m) {
  const head = `<thead><tr>${m.languages.map((l) => `<th scope="col">${esc(LANG_NAMES[l] || l)}</th>`).join("")}</tr></thead>`;
  const body = m.rows.map((r) => {
    const cells = m.languages.map((l) => {
      const c = r.cells[l];
      const cls = c.verdict === "suppressed" ? "no" : c.verdict === "suggested" ? "" : "maybe";
      const ex = c.example && c.example.length ? `${c.example[0]} \u2192 ${c.example.slice(1, 4).join(", ") || "no guesses"}` : "";
      const label = c.verdict === "suppressed" ? "never suggested" : c.verdict === "suggested" ? "suggested" : c.verdict.replace("related", "only another form suggested");
      return `<td class="${cls}" title="${esc(`${label}: ${c.hits}/${c.trials} typos. ${ex}`)}">${esc(c.word)}</td>`;
    }).join("");
    return `<tr>${cells}</tr>`;
  }).join("");
  $("matrix").innerHTML = head + `<tbody>${body}</tbody>`;
  const sup = m.rows.flatMap((r) => m.languages.map((l) => r.cells[l])).filter((c) => c.verdict === "suppressed").length;
  const all = m.rows.length * m.languages.length;
  const everywhere = m.rows.filter((r) => m.languages.every((l) => r.cells[l].verdict === "suppressed")).map((r) => r.concept);
  $("matrix-note").textContent =
    `${sup} of ${all} cells are suppressed. Suppressed in every language: ${everywhere.join(", ")}. ` +
    `Each cell tried every keyboard-plausible typo of the word, ${Math.round(m.rows.flatMap((r) => m.languages.map((l) => r.cells[l].trials)).reduce((x, y) => x + y, 0) / all)} on average. ` +
    `Italic cells were inconclusive (too few genuine typos, or only another form came back). Hover a cell for the evidence.`;
}

function renderHistogram(k) {
  const h = k.histogram, max = Math.max(1, ...h);
  const W = 640, H = 220, padL = 44, padB = 34, padT = 14;
  const bw = (W - padL - 10) / h.length;
  const y = (v) => padT + (H - padT - padB) * (1 - Math.log10(v + 1) / Math.log10(max + 1));
  let svg = `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Histogram of typos recovered out of eight">`;
  for (const t of [1, 10, 100, 1000].filter((t) => t <= max * 1.2)) {
    svg += `<line x1="${padL}" x2="${W - 10}" y1="${y(t)}" y2="${y(t)}" stroke="#e3e5e9"/>` +
      `<text x="${padL - 8}" y="${y(t) + 4}" text-anchor="end" font-size="11" fill="#5d636e" font-family="-apple-system,sans-serif">${fmt(t)}</text>`;
  }
  h.forEach((v, i) => {
    const x = padL + i * bw + 4, top = y(v);
    svg += `<rect x="${x}" y="${top}" width="${bw - 8}" height="${H - padB - top}" rx="2" fill="${i === 0 ? "#e0352b" : "#9aa1ad"}"/>` +
      `<text x="${x + (bw - 8) / 2}" y="${top - 4}" text-anchor="middle" font-size="11" fill="#1d1f23" font-family="-apple-system,sans-serif">${fmt(v)}</text>` +
      `<text x="${x + (bw - 8) / 2}" y="${H - padB + 16}" text-anchor="middle" font-size="12" fill="#5d636e" font-family="-apple-system,sans-serif">${i}</text>`;
  });
  svg += `<text x="${padL + (W - padL) / 2}" y="${H - 2}" text-anchor="middle" font-size="11" fill="#5d636e" font-family="-apple-system,sans-serif">typos out of 8 that brought the word back (log scale)</text></svg>`;
  $("histogram").innerHTML = svg;
}

load().catch((err) => {
  $("headline-stats").textContent = "The census data did not load (" + err.message + "). Serve this folder over HTTP rather than opening the file directly.";
});
