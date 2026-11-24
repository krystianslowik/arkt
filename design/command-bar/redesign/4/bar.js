const S = STATES[H.s || 'search'];
const verb = { tab: 'Switch to Tab', hist: 'Open', sugg: 'Search', url: 'Go', paste: 'Paste and Go' };
const [a, ...rest] = S.rows.slice(0, 6);
const sub = a.k === 'url' ? 'Go to site' : (a.u || (a.k === 'sugg' ? 'Search the web' : ''));
const answer = `<div class="ans"><span class="slot">${a.ic}</span><div class="tx"><span class="t">${a.k === 'url' || a.k === 'paste' ? esc(a.t) : hl(a.t, S.q)}</span><span class="u">${esc(sub)}</span></div>
<span class="go">${verb[a.k]}${ICO.ret}</span></div>`;
const list = rest.map(r => rowHTML(r, S.q, false, (r2) => r2.k === 'hist' ? r2.w : '')).join('');
document.getElementById('root').innerHTML = `<div class="bar"><div class="field">${ICO.search}${fieldText(S.q)}</div><div class="list">${answer}${list}</div></div>`;
