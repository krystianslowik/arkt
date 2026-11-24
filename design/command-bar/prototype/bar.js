/* Rule: the bar shows at most 3 rows per group, in the order Tabs, History, Search.
   A literal row (Paste and Go, Go to a typed address) sits above the groups, no header.
   The selected row is always the first row. Selecting only changes the fill, never animates. */
const S = STATES[H.s || 'search'];
const VERB = { tab: 'Switch to Tab', hist: 'Open', sugg: 'Search', lit: '', url: 'Go', paste: 'Go' };
const trail = (r, sel) => sel ? (VERB[r.k] ? `<span class="verb">${VERB[r.k]}</span>` : '') + RET : (r.k === 'hist' ? r.w : '');
let i = 0;
const row = r => {
  const sel = i++ === 0;
  if (r.k === 'lit') return `<div class="row${sel ? ' sel' : ''}"><span class="slot">${r.ic}</span><span class="t">${r.lead}<b>${esc(r.t)}</b></span><span class="r">${trail(r, sel)}</span></div>`;
  return rowHTML(r, S.q, sel, trail);
};
const html = S.top.map(row).join('') +
  S.g.map(([name, rows]) => `<div class="grp">${name}</div>` + rows.slice(0, 3).map(row).join('')).join('');
document.getElementById('root').innerHTML = `<div class="scrim"></div>
<div class="bar"><div class="field">${ICO.search}${fieldText(S.q)}</div><div class="list">${html}</div>${H.s === 'small' ? '<i class="sb"></i>' : ''}</div>`;

/* Secondary URL is dropped when less than 48 pt of it would remain (the native build measures the same way). */
document.querySelectorAll('.row .u').forEach(u => { if (u.clientWidth < 48) u.style.display = 'none'; });
