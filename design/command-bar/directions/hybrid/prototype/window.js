document.getElementById('win').innerHTML = `
<aside class="side">
  <div class="lights"><i></i><i></i><i></i></div>
  <div class="urlpill"><svg viewBox="0 0 12 12"><rect x="2" y="5.5" width="8" height="5.5" rx="1.2" fill="currentColor"/><path d="M4 5.5V4a2 2 0 0 1 4 0v1.5" stroke="currentColor" stroke-width="1.3" fill="none"/></svg>git-scm.com</div>
  <div class="pins">
    <div><span class="fav f-mail">M</span></div>
    <div><span class="fav f-cal">31</span></div>
    <div><span class="fav f-fig">F</span></div>
  </div>
  <div class="space">Work</div>
  <div class="tab"><span class="fav f-lin">L</span>Cycle 42 &middot; Linear</div>
  <div class="tab"><span class="fav f-gh">G</span>krystianslowik/arkt &middot; Pull...</div>
  <div class="tab on"><span class="fav f-git"><b>g</b></span>Git - Branches in a Nutshell</div>
  <div class="tab"><span class="fav f-doc">D</span>Q4 roadmap</div>
  <div class="tab"><span class="fav f-yt">&#9654;</span>WWDC session: AppKit 120Hz</div>
  <div class="sep"></div>
  <div class="tab newtab"><svg class="ico" viewBox="0 0 16 16"><path d="M8 3v10M3 8h10"/></svg>New Tab</div>
  <div class="sidefoot"><i class="on"></i><i></i><i></i></div>
</aside>
<main class="page"><div class="doc">
  <div class="docnav"><span class="logo">git --book</span><span>About</span><span>Documentation</span><span>Downloads</span><span>Community</span></div>
  <div class="docbody">
    <nav class="toc"><b>3. Git Branching</b><span class="cur">3.1 Branches in a Nutshell</span><br>3.2 Basic Branching and Merging<br>3.3 Branch Management<br>3.4 Branching Workflows<br>3.5 Remote Branches<br>3.6 Rebasing<br>3.7 Summary</nav>
    <article class="art">
      <div class="crumb">Chapter 3 &middot; Section 1</div>
      <h1>Branches in a Nutshell</h1>
      <p>To really understand the way Git does branching, we need to take a step back and examine how Git stores its data. Git doesn't store data as a series of changesets or differences, but instead as a series of snapshots.</p>
      <p>When you make a commit, Git stores a commit object that contains a pointer to the snapshot of the content you staged. This object also contains the author's name and email address, the message that you typed, and pointers to the commit or commits that directly came before this commit.</p>
      <pre><em>$</em> git add README test.rb LICENSE
<em>$</em> git commit -m 'Initial commit'
<em>$</em> git branch testing</pre>
      <div class="figure"><i></i><i></i><i class="h"></i><i></i></div>
      <p>A branch in Git is simply a lightweight movable pointer to one of these commits. The default branch name in Git is master.</p>
    </article>
  </div>
</div></main>`;
