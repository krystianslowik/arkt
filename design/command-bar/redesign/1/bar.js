const S = STATES[H.s || 'search'];
const label = { tab: 'Tab', sugg: 'Search', url: 'Open', hist: null, paste: null };
const trail = (r, sel) => sel ? RET : (r.k === 'hist' ? r.w : r.k === 'tab' ? 'Tab' : label[r.k] || '');
document.getElementById('root').innerHTML = `<div class="scrim"></div>
<div class="bar"><div class="field">${ICO.search}${fieldText(S.q)}</div>
<div class="list">${S.rows.map((r, i) => rowHTML(r, S.q, i === 0, trail)).join('')}
${S.rows.length > 9 ? '<i class="sb" style="top:10px;height:96px"></i>' : ''}</div></div>`;
