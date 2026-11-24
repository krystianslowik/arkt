const S = STATES[H.s || 'search'];
document.getElementById('pill').style.visibility = 'hidden';
const trail = (r, sel) => sel ? RET : (r.k === 'hist' ? r.w : '');
document.getElementById('root').innerHTML = `<div class="bar"><div class="field">${ICO.search}${fieldText(S.q)}</div>
<div class="list">${S.rows.map((r, i) => rowHTML(r, S.q, i === 0, trail)).join('')}
${S.rows.length > 8 ? '<i class="sb" style="top:8px;height:80px"></i>' : ''}</div></div>`;
