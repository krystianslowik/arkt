/* Synthetic data only. No real browsing data. */
const ICO = {
  search: '<svg class="ico" viewBox="0 0 16 16"><circle cx="7" cy="7" r="4.6"/><path d="M10.5 10.5 14 14"/></svg>',
  clock: '<svg class="ico" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/><path d="M8 4.8V8l2.2 1.5"/></svg>',
  go: '<svg class="ico" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/><path d="M2.4 8h11.2M8 2.2c2 1.7 2.9 3.6 2.9 5.8S10 12.1 8 13.8M8 2.2C6 3.9 5.1 5.8 5.1 8S6 12.1 8 13.8"/></svg>',
  clip: '<svg class="ico" viewBox="0 0 16 16"><rect x="3.5" y="3" width="9" height="10.5" rx="1.8"/><path d="M6 3V2.4h4V3M6 7.5h4M6 10h2.5"/></svg>',
  ret: '<svg class="ico" viewBox="0 0 16 16" style="width:12px;height:12px"><path d="M12.5 4v4.5h-9M6 6l-2.5 2.5L6 11"/></svg>',
};
const fav = (c, ch) => `<span class="fav ${c}">${ch}</span>`;
const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
/* Bold the query match in a title. */
const hl = (t, q) => {
  if (!q) return esc(t);
  const i = t.toLowerCase().indexOf(q.toLowerCase());
  return i < 0 ? esc(t) : esc(t.slice(0, i)) + '<b>' + esc(t.slice(i, i + q.length)) + '</b>' + esc(t.slice(i + q.length));
};

/* Row: k = tab | hist | sugg | url | paste, ic = slot html, t, u (secondary), w (when) */
const R = {
  lin:  { k: 'tab', ic: fav('f-lin', 'L'), t: 'Cycle 42 · Linear', u: 'linear.app/acme/cycle/42', w: '2 min' },
  gh:   { k: 'tab', ic: fav('f-gh', 'G'), t: 'acme/atlas · Pull requests', u: 'github.com/acme/atlas/pulls', w: '12 min' },
  road: { k: 'tab', ic: fav('f-doc', 'D'), t: 'Q4 roadmap', u: 'docs.example.com/q4-roadmap', w: '1 h' },
  wwdc: { k: 'tab', ic: fav('f-apple', 'W'), t: 'WWDC session: AppKit 120Hz', u: 'developer.example.com/videos/play/wwdc', w: '3 h' },
  git:  { k: 'tab', ic: fav('f-git', 'g'), t: 'Git - Branches in a Nutshell', u: 'git-scm.com/book/en/v2/Git-Branching-Branches-in-a-Nutshell', w: '1 h' },
  mail: { k: 'hist', ic: ICO.clock, t: 'Inbox (3)', u: 'mail.example.com/u/0', w: 'Yesterday' },
  hbook:{ k: 'hist', ic: ICO.clock, t: 'Git - Book', u: 'git-scm.com/book/en/v2', w: 'Yesterday' },
  cheat:{ k: 'hist', ic: ICO.clock, t: 'Git Cheat Sheet', u: 'training.example.com/downloads/git-cheat-sheet.pdf', w: 'Monday' },
  hmaps:{ k: 'hist', ic: ICO.clock, t: 'Trail map · Lake District', u: 'maps.example.com/trails/lake-district', w: 'Sunday' },
  s1:   { k: 'sugg', ic: ICO.search, t: 'git rebase onto' },
  s2:   { k: 'sugg', ic: ICO.search, t: 'git stash pop' },
  url:  { k: 'url', ic: ICO.go, t: 'git-scm.com', u: 'Go to site' },
  paste:{ k: 'paste', ic: ICO.clip, t: 'Paste and Go', u: 'example.com/notes/2026/launch-checklist' },
};
const LONG_T = 'A very long page title that keeps going well past the width of any sensible results list: Part 2 of 14, notes on layout, measurement and the cost of reflow in large documents · The Engineering Blog';
const LONG_U = 'https://www.example-engineering-blog.com/2026/11/24/a-very-long-path/with/many/segments/and-a-query?utm_source=newsletter&utm_medium=email&utm_campaign=autumn-digest&ref=sidebar#section-reflow-cost';
const W = (k, ic, t, u, w) => ({ k, ic, t, u, w });
/* Worst case, query "layout": long titles and URLs, short ones, CJK, many rows. */
const WORST = [
  W('tab', fav('f-blog', 'E'), LONG_T, LONG_U, '4 min'),
  W('tab', fav('f-doc', 'D'), 'Layout', 'docs.example.com/layout', '1 h'),
  W('tab', fav('f-lin', 'L'), 'レイアウトエンジンの設計と実装 – 第3章 リフローのコスト', 'ドコス.example.jp/book/3', '3 h'),
  W('tab', fav('f-apple', 'A'), 'Auto Layout Guide: Anatomy of a Constraint, Priorities and Content Hugging', 'developer.example.com/library/archive/documentation/UserExperience', '5 h'),
  W('hist', ICO.clock, 'CSS Grid layout: a complete guide with live examples and 40 patterns', 'css-tricks.example.com/snippets/css/complete-guide-grid', 'Yesterday'),
  W('hist', ICO.clock, LONG_T.replace('Part 2', 'Part 3'), LONG_U.replace('autumn', 'winter'), 'Yesterday'),
  W('hist', ICO.clock, 'Layout shift: why it happens and how to stop it', 'web.example.dev/articles/cls', 'Monday'),
  W('hist', ICO.clock, 'Flexbox layout cheat sheet', 'flexbox.example.com', 'Monday'),
  W('hist', ICO.clock, 'Masonry layout without JavaScript', 'example.com/blog/masonry', 'Sunday'),
  W('hist', ICO.clock, 'Layout engines compared', 'example.org/wiki/Layout_engine', 'Last week'),
  W('sugg', ICO.search, 'layout engine internals and how browsers compute style, layout and paint for very large documents'),
  W('sugg', ICO.search, 'layout thrashing'),
  W('sugg', ICO.search, 'layout shift score'),
  W('sugg', ICO.search, 'layoutsubviews not called'),
  W('url', ICO.go, 'layout.example.com', 'Go to site'),
  W('hist', ICO.clock, 'Layout · Guide', 'example.com/guide/layout', 'Last week'),
  W('hist', ICO.clock, 'The Layout Anatomy Poster', 'posters.example.com/layout', 'Oct 28'),
  W('hist', ICO.clock, 'Layout inspector', 'tools.example.com/inspect', 'Oct 21'),
  W('hist', ICO.clock, 'Layout.md', 'git.example.com/acme/atlas/blob/main/docs/Layout.md', 'Oct 19'),
  W('hist', ICO.clock, 'Responsive layout patterns', 'patterns.example.com/responsive', 'Oct 12'),
  W('hist', ICO.clock, 'Layout · Wiki', 'wiki.example.com/layout', 'Oct 3'),
];
const STATES = {
  empty:  { q: '', rows: [R.paste, R.lin, R.gh, R.road, R.mail, R.hmaps] },
  search: { q: 'git', rows: [R.git, R.gh, R.hbook, R.cheat, R.s1, R.s2, R.url] },
  worst:  { q: 'layout', rows: WORST },
};

/* One row. trail(r, selected) returns the right-hand html. */
function rowHTML(r, q, sel, trail) {
  const t = r.k === 'url' || r.k === 'paste' ? esc(r.t) : hl(r.t, q);
  return `<div class="row${sel ? ' sel' : ''}"><span class="slot">${r.ic}</span><span class="t">${t}</span>` +
    (r.u && r.k !== 'url' ? `<span class="u">${esc(r.u)}</span>` : '') +
    `<span class="r">${trail(r, sel)}</span></div>`;
}
const RET = '<span class="kbd">' + ICO.ret + '</span>';
const FIELD_PH = 'Search or enter address';
const fieldText = q => `<span class="ft">` + (q ? `<span class="qt">${esc(q)}</span><span class="caret"></span>` : `<span class="caret"></span><span class="ph">${FIELD_PH}</span>`) + `</span>`;
const page = (cls) => `<div class="win" id="win"></div>`;
