// Shared code of the cover gallery pages: page nav, the Title text toggle, card grids and the lightbox.
// Each page loads cover.js and mods.js, then calls Gallery.page({ current, sections }).
//   section: { title, intro (HTML), items: [{ mod, title, note, sub }] }
(function () {
  // The pages, in nav order. `filter` picks the page's mods from Square.MODS (for the nav counts too).
  const PAGES = [
    { href: 'index.html', label: 'Mods', filter: m => !m.series },
    { href: 'states.html', label: 'State series', filter: m => m.series === 'state' },
    { href: 'forks.html', label: 'SQ Opt forks', filter: m => m.series === 'fork' },
    { href: 'dev.html', label: 'DEV mods', filter: m => m.series === 'dev' },
    { href: 'options.html', label: 'Logo options' },
    { href: 'slide_options.html', label: 'Slide options' },
    { href: 'photo_mode.html', label: 'Photo Mode launch' },
  ];
  const card = (key, it) => `
      <div class="card">
        <div class="cover" data-k="${key}">${Square.render(it.mod, Gallery.opts())}</div>
        <div class="title">${it.title || it.mod.name}</div>
        ${it.note ? `<div class="note">${it.note}</div>` : ''}
        <div class="id">${it.sub || it.mod.id}</div>
      </div>`;
  const cards = mods => mods.map(mod => ({ mod }));

  function page({ current, sections }) {
    const state = { text: true };
    Gallery.opts = () => ({ text: state.text });
    const main = document.querySelector('main');
    main.insertAdjacentHTML('afterbegin', `<nav>${PAGES.map(p => `<a href="${p.href}"${p.href === current ? ' aria-current="page"' : ''}>${p.label}${p.filter ? `<span class="n">${Square.MODS.filter(p.filter).length}</span>` : ''}</a>`).join('')}</nav>`);
    main.insertAdjacentHTML('beforeend', `
      <div class="bar"><label><input type="checkbox" id="optText" checked> Title text</label></div>
      ${sections.map((s, i) => `<h2>${s.title}</h2>${s.intro ? `<p>${s.intro}</p>` : ''}<div class="browser" id="sec${i}"></div>`).join('')}`);
    document.body.insertAdjacentHTML('beforeend', '<dialog id="lb"></dialog>');
    const render = () => sections.forEach((s, i) => {
      document.getElementById('sec' + i).innerHTML = s.items.map((it, j) => card(`${i}.${j}`, it)).join('');
    });
    document.addEventListener('click', e => {
      const c = e.target.closest('.cover');
      if (!c) return;
      const [i, j] = c.dataset.k.split('.').map(Number);
      const lb = document.getElementById('lb');
      lb.innerHTML = Square.render(sections[i].items[j].mod, Gallery.opts());
      lb.showModal();
    });
    document.getElementById('lb').addEventListener('click', e => e.currentTarget.close());
    document.getElementById('optText').onchange = e => { state.text = e.target.checked; render(); };
    render();
  }

  const Gallery = { PAGES, page, cards, mods: href => Square.MODS.filter(PAGES.find(p => p.href === href).filter) };
  window.Gallery = Gallery;
})();
