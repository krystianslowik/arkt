/* Renders the Arkt window behind the bar and applies the theme from the URL hash:
   index.html#s=empty|search|url|worst|none|small&theme=dark|light */
const H = Object.fromEntries(new URLSearchParams(location.hash.slice(1)));
if (H.s === 'small') document.documentElement.classList.add('small');
if (H.theme === 'light') document.body.classList.add('light');
document.getElementById('win').innerHTML = `
<aside class="side">
  <div class="lights"><i></i><i></i><i></i></div>
  <div class="urlpill" id="pill"><svg viewBox="0 0 12 12"><rect x="2" y="5.5" width="8" height="5.5" rx="1.2" fill="currentColor"/><path d="M4 5.5V4a2 2 0 0 1 4 0v1.5" stroke="currentColor" stroke-width="1.3" fill="none"/></svg>fluidinterfaces.example</div>
  <div class="pins"><div><span class="fav f-mail">M</span></div><div><span class="fav f-cal">31</span></div><div><span class="fav f-fig">F</span></div></div>
  <div class="tabs">
    <div class="space">Work</div>
    <div class="tab"><span class="fav f-lin">L</span>Cycle 42 &middot; Linear</div>
    <div class="tab"><span class="fav f-gh">G</span>acme/atlas &middot; Pull requests</div>
    <div class="tab on"><span class="fav f-blog">D</span>Designing Fluid Interfaces</div>
    <div class="tab"><span class="fav f-doc">D</span>Q4 roadmap</div>
    <div class="tab"><span class="fav f-apple">W</span>WWDC session: AppKit 120Hz</div>
    <div class="tab"><span class="fav f-git">g</span>Git - Branches in a Nutshell</div>
    <div class="sep"></div>
    <div class="tab newtab"><svg class="ico" viewBox="0 0 16 16"><path d="M8 3v10M3 8h10"/></svg>New Tab</div>
  </div>
</aside>
<main class="page">
  <div class="docnav"><span class="logo">fluid.</span><span>Essays</span><span>Talks</span><span>About</span></div>
  <div class="docbody">
    <nav class="toc"><b>On this page</b>Response<br>Direct manipulation<br>Interruptibility<br>Springs<br>Momentum<br>Summary</nav>
    <article class="art">
      <div class="crumb">Essay &middot; 12 min read</div>
      <h1>Designing Fluid Interfaces</h1>
      <p>An interface feels alive when it responds the instant you touch it, moves continuously, and can be redirected at any moment. The moment lag appears, the feeling of directness falls off a cliff.</p>
      <p>Everything that follows is a way to get closer to that: respond on press, not on release; track the pointer one to one; animate from the value on screen, not the target.</p>
      <div class="figure"><i></i><i></i><i></i><i></i></div>
      <p>A spring has no fixed duration. New input just changes the target, and the motion stays continuous.</p>
    </article>
  </div>
</main>`;
