/* ============================================================================
 * Mount the product film INSIDE a page — no iframe.
 * ----------------------------------------------------------------------------
 *   <div class="film-frame" data-film-embed data-speed="1.5"></div>
 *   <script src="/demo-film/embed.js" defer></script>
 *
 * WHY NOT AN IFRAME. The site sends `X-Frame-Options: DENY`, which refuses
 * framing from every origin INCLUDING its own, so a same-origin frame renders
 * empty. That header is set in internal/deploy and cannot be changed from this
 * repository — see ops/internal-deploy-frame-options.patch.DO-NOT-APPLY. A
 * shadow root has no equivalent rule.
 *
 * WHY A SHADOW ROOT rather than dropping the markup straight in. film.css
 * claims very ordinary names — .sidebar, .chip, .toast, .settings, .switch —
 * because it is replicating an app, and the landing has opinions about most of
 * them. A shadow root keeps each side's CSS to itself, in both directions.
 *
 * WHY LAZY. Five files and a stylesheet is not much, but it is not nothing, and
 * a visitor who never scrolls past the hero should not pay for it. Nothing
 * loads until the section is within a screen of the viewport — the behaviour
 * `loading="lazy"` gave the iframe this replaces.
 * ========================================================================== */
(function (root) {
  'use strict';

  // Resolve beside this loader so the bundle works at both cruxwing.ai/ru/
  // and the Orakul GitHub Pages preview (/orakul/ru/).
  var BASE = new URL('./', (document.currentScript && document.currentScript.src) || document.baseURI).href;
  var PARTS = ['engine.js', 'scene.js', 'film-set.js', 'film.js'];

  /* nginx serves this docroot with NO Cache-Control, so browsers cache by
     heuristic — a fraction of the file's age. That is why every mutable script
     on the landing carries ?v=<hash>; without it a returning visitor keeps a
     stale copy for hours after a deploy, which is exactly how a fixed page
     looks unfixed. This script is loaded with the bundle's stamp and passes it
     on to the film's own files, so one query string versions all six. */
  var STAMP = (function () {
    var self = document.currentScript;
    var m = self && self.src && self.src.match(/[?&]v=([\w.-]+)/);
    return m ? '?v=' + m[1] : '';
  }());

  var loading = null;
  var loadedScenario;   // undefined = nothing yet; '' = base; 'ru' etc.

  /* The scripts, in dependency order. A scenario is an overlay layer between
     scene and set (scene.ru.js is the first; ICP variants follow the same
     shape). Overlays mutate the scene in place, so SWITCHING scenarios
     re-runs the whole chain: scene.js rebuilds CruxFilmScene from scratch and
     the overlay — or no overlay — applies to a pristine scene. That is what
     keeps overlays one-way and simple. */
  function loadFilm(scenario) {
    var key = scenario || '';
    if (loading && loadedScenario === key) return loading;
    var parts = ['engine.js', 'scene.js']
      .concat(key ? ['scene.' + key + '.js'] : [])
      .concat(['film-set.js', 'film.js']);
    loadedScenario = key;
    loading = parts.reduce(function (chain, name) {
      return chain.then(function () {
        return new Promise(function (resolve, reject) {
          var script = document.createElement('script');
          script.src = BASE + name + STAMP;
          script.onload = resolve;
          script.onerror = function () { reject(new Error('could not load ' + name)); };
          document.head.appendChild(script);
        });
      });
    }, Promise.resolve());
    return loading;
  }

  function mountInto(host) {
    if (host.shadowRoot) return;
    // A narrow screen may ask for the vertical cut: data-format-mobile plus
    // its own speed and loop point, chosen once at mount. The story loops at
    // the same 104.5s the exported story ends on — the acts past it compose
    // for the wide frame only.
    var mobile = host.hasAttribute('data-format-mobile')
      && root.matchMedia && root.matchMedia('(max-width: 720px)').matches;
    var pick = function (name) {
      return (mobile && host.getAttribute(name + '-mobile')) || host.getAttribute(name);
    };
    var format = pick('data-format') || undefined;
    var trimBand = pick('data-band') === 'trim';
    var endAt = Number(pick('data-to')) || undefined;
    var speed = Number(pick('data-speed')) || 1;
    var shadow = host.attachShadow({ mode: 'open' });

    // Geometry first, and stated here rather than inherited. film.css lays the
    // film out inside `.film-fit { position: absolute; inset: 0 }`, which needs
    // a sized, positioned box to resolve against. Left to chance it resolved
    // against the page: fit() then measured a container tens of thousands of
    // pixels tall, computed a 24x scale, and the film grew the section that was
    // supposed to contain it — a runaway that painted over the hero.
    var frame = document.createElement('style');
    // isolation: the film's own chrome carries z-index (scrub bar at 70), and
    // a host that creates no stacking context lets that paint over the page's
    // sticky header while the section scrolls under it.
    frame.textContent = ':host { position: relative; display: block; overflow: hidden; isolation: isolate; }'
      + '#cruxwing-film { position: absolute; inset: 0; }';
    shadow.appendChild(frame);

    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = BASE + 'film.css' + STAMP;
    shadow.appendChild(link);

    var stage = document.createElement('div');
    stage.id = 'cruxwing-film';
    shadow.appendChild(stage);

    // The player's own chrome. The button is visually hidden until focused —
    // the film autoplays once on screen and the whole frame is the pause
    // target — but it stays for anyone driving by keyboard.
    var ui = document.createElement('div');
    ui.className = 'player-ui';
    ui.innerHTML = '<button class="play-btn" type="button" aria-label="Воспроизвести демо продукта">'
      + '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M4 2.6 13.4 8 4 13.4z" /></svg>'
      + '</button><div class="scrub"><i style="width:0"></i></div>';
    shadow.appendChild(ui);

    // Mount only once the stylesheet has applied. The film measures itself on
    // mount — the fit scale, and where every pointer target sits — and geometry
    // read against unstyled markup is geometry that is wrong everywhere.
    var scenario = pick('data-scenario') || '';
    var start = function () {
      loadFilm(scenario).then(function () {
        root.CruxFilm.mount(stage, shadow, { speed: speed, format: format, endAt: endAt, trimBand: trimBand });
      }).catch(function () {
        // Findable in a console, and never a broken page.
        host.setAttribute('data-film-failed', '1');
      });
    };
    host.__cruxfilmRemount = function (nextScenario) {
      loadFilm(nextScenario || '').then(function () {
        root.CruxFilm.mount(stage, shadow, { speed: speed, format: format, endAt: endAt, trimBand: trimBand });
      }).catch(function () {
        host.setAttribute('data-film-failed', '1');
      });
    };
    if (link.sheet) start();
    else {
      link.addEventListener('load', start);
      link.addEventListener('error', start);
    }
  }

  function boot() {
    var hosts = document.querySelectorAll('[data-film-embed]');
    if (!hosts.length) return;

    var canShadow = !!(root.Element && Element.prototype.attachShadow);
    if (!canShadow) return;                 // leave the written fallback in place

    if (!('IntersectionObserver' in root)) {
      Array.prototype.forEach.call(hosts, mountInto);
      return;
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        observer.unobserve(entry.target);
        mountInto(entry.target);
      });
    }, { rootMargin: '100% 0px' });         // a screen ahead, so it is ready on arrival
    Array.prototype.forEach.call(hosts, function (host) { observer.observe(host); });
  }

  /* The landing's scenario tabs. A tab names the overlay it wants
     (data-scenario="" for the base film, "ru" for the Russian track); the
     film re-mounts in place, same speed and format choices as the original
     mount. */
  root.CruxFilmEmbed = {
    switchScenario: function (host, scenario) {
      if (host && host.__cruxfilmRemount) host.__cruxfilmRemount(scenario);
    }
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
}(window));
