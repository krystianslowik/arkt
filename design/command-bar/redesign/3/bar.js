const S = STATES[H.s || 'search'];
const by = k => S.rows.filter(r => k.includes(r.k));
const groups = [['', by(['paste'])], ['Tabs', by(['tab'])], ['History', by(['hist'])], ['Search', [...by(['url']), ...by(['sugg'])]]]
  .filter(g => g[1].length).map(g => [g[0], g[1].slice(0, 3)]);
let i = 0;
const trail = (r, sel) => sel ? RET : (r.k === 'hist' ? r.w : '');
const html = groups.map(([name, rows]) => (name ? `<div class="grp">${name}</div>` : '') +
  rows.map(r => rowHTML(r, S.q, i++ === 0, trail)).join('')).join('');
document.getElementById('root').innerHTML = `<div class="scrim"></div><div class="bar"><div class="field">${ICO.search}${fieldText(S.q)}</div><div class="list">${html}</div></div>`;
