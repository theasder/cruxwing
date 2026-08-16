/* ============================================================================
 * Cruxwing demo film — projection
 * ----------------------------------------------------------------------------
 * Binds the timeline to the set. `render(t)` is the whole film: it reads only
 * `t` and the scene data, and writes only inline styles and text — no state
 * carried between frames, so seeking backwards is exactly as correct as playing
 * forwards. That is what lets the recorder step frame by frame, and what lets
 * the scrubber land anywhere.
 *
 * The public surface is `window.__film`:
 *   seek(t)     render that frame
 *   duration    seconds
 *   ready       resolves once fonts are loaded and geometry is measured
 * scripts/record-demo-film.mjs drives exactly those three.
 * ========================================================================== */
(function (root) {
  'use strict';

  var E = root.CruxFilmEngine;
  var S = root.CruxFilmScene;
  /* Output formats. `safeBottom` is frame the film deliberately does not use:
     on a Story that band is where the invite sticker goes, and content under a
     sticker is content nobody reads. The camera is told a SHORTER viewport than
     the frame really is, so everything composes into the top of it and the band
     stays clean. */
  var FORMATS = {
    wide: { w: 1920, h: 1080, safeBottom: 0, track: 'CAMERA' },
    reel: { w: 1080, h: 1920, safeBottom: 300, track: 'CAMERA_VERTICAL' },
    story: { w: 1080, h: 1920, safeBottom: 470, track: 'CAMERA_VERTICAL' }
  };
  var format = FORMATS.wide;
  var VIEWPORT = { width: format.w, height: format.h - format.safeBottom };
  var CAMERA_TRACK = S.CAMERA;

  var refs = null;
  var scope = null;   // document, or the shadow root the film is mounted in
  var timeline = new E.Timeline(S.ACTS);
  var DURATION = timeline.duration();
  var points = {};          // pointer target -> stage coordinate, measured once

  // MARK: - Small helpers

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  /* m:ss, or h:mm:ss past an hour — formatElapsed() from Theme.swift. */
  function formatElapsed(total) {
    total = Math.floor(total);
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    var mm = (h > 0 && m < 10 ? '0' : '') + m;
    return (h > 0 ? h + ':' : '') + mm + ':' + (s < 10 ? '0' : '') + s;
  }

  /* Fade-and-rise, the film's one arrival gesture. Everything that lands —
     a focus row, a blind spot, a table row — lands the same way, because five
     different entrances would read as five different products. */
  function arrive(node, t, at, dur, rise) {
    var p = E.Ease.settle(E.progress(t, at, dur == null ? 0.5 : dur));
    node.style.opacity = p;
    node.style.transform = 'translate3d(0,' + E.round((1 - p) * (rise == null ? 10 : rise)) + 'px,0)';
    return p;
  }

  function show(node, on) { node.style.display = on ? '' : 'none'; }

  /* Position in STAGE coordinates, by walking offsetParents rather than reading
     a rect: getBoundingClientRect() is measured AFTER the camera transform, so
     it would report where the element appears on screen this frame rather than
     where it lives in the set. No pointer target sits inside the rail, so the
     rail's own scroll transform never enters this. */
  function stagePoint(node) {
    var x = 0, y = 0, el = node;
    while (el && el !== refs.stage) {
      x += el.offsetLeft;
      y += el.offsetTop;
      el = el.offsetParent;
    }
    return { x: x + node.offsetWidth / 2, y: y + node.offsetHeight / 2 };
  }

  function measure() {
    points = {};
    S.POINTER.forEach(function (key) {
      if (!key.target || points[key.target]) return;
      var node = scope.querySelector(key.target);
      if (node) points[key.target] = stagePoint(node);
    });
  }

  // MARK: - Chrome: the pill clock and the capture meter

  function renderChrome(t) {
    refs.elapsed.textContent = formatElapsed(S.MEETING.elapsedAtStart + t);
    // LevelMeter scales between a 3.5pt floor and a 17pt peak.
    var floor = 3.5 / 17;
    refs.meterBars.forEach(function (bar, i) {
      var level = E.meterLevel(t, i, true);
      bar.style.transform = 'scaleY(' + E.round(floor + (1 - floor) * level, 3) + ')';
    });
  }

  // MARK: - Transcript

  function renderTranscript(t) {
    refs.turns.forEach(function (turn) {
      var line = turn.line;
      if (t < line.at) { show(turn.turn, false); return; }
      show(turn.turn, true);
      var p = E.progress(t, line.at, line.dur);
      turn.said.innerHTML = esc(E.typed(line.text, p)) + (p < 1 ? '<span class="caret"></span>' : '');
      turn.turn.classList.toggle('partial', p < 1);
    });
  }

  // MARK: - The left rail

  function railOffset(t) {
    var keys = S.RAIL_SCROLL, prev = keys[0];
    for (var i = 0; i < keys.length; i++) {
      if (t < keys[i].at) {
        var p = E.Ease.camera(E.progress(t, prev.at, keys[i].at - prev.at));
        return E.lerp(prev.y, keys[i].y, p);
      }
      prev = keys[i];
    }
    return prev.y;
  }

  function countUpTo(items, t) {
    return items.filter(function (i) { return t >= i.at; }).length;
  }

  function setCount(section, n) {
    var node = section.querySelector('[data-role="count"]');
    if (node) node.textContent = String(n);
  }

  function renderRail(t) {
    refs.rail.style.transform = 'translate3d(0,' + E.round(-railOffset(t)) + 'px,0)';

    show(refs.secFocus, t >= S.FOCUS.at);
    setCount(refs.secFocus, countUpTo(S.FOCUS.items, t));
    refs.focusRows.forEach(function (row, i) {
      var item = S.FOCUS.items[i];
      show(row.wrap, t >= item.at);
      if (t < item.at) return;
      arrive(row.wrap, t, item.at, 0.5);
      row.lines.forEach(function (node, j) {
        var line = item.brief[j];
        show(node, t >= line.at);
        if (t >= line.at) arrive(node, t, line.at, 0.45, 6);
      });
    });

    show(refs.secCopilot, t >= S.GOAL.at);
    if (t >= S.GOAL.at) arrive(refs.goal, t, S.GOAL.at, 0.5);

    [[refs.secContext, S.CONTEXT, refs.contextRows],
     [refs.secHistory, S.HISTORY, refs.historyRows],
     [refs.secLedger, S.LEDGER, refs.ledgerRows]].forEach(function (group) {
      var section = group[0], data = group[1], nodes = group[2];
      show(section, t >= data.at);
      setCount(section, countUpTo(data.items, t));
      nodes.forEach(function (node, i) {
        var item = data.items[i];
        show(node, t >= item.at);
        if (t >= item.at) arrive(node, t, item.at, 0.45, 8);
      });
    });
  }

  // MARK: - Blind spots

  function renderSpots(t) {
    var B = S.BLIND_SPOTS;
    show(refs.watch, t >= B.headingAt);
    if (t >= B.headingAt) {
      arrive(refs.watch, t, B.headingAt, 0.4, 4);
      // The scanner sweeps its track. It is the only thing on screen saying the
      // watcher is running between cards, which can be several seconds apart.
      refs.scanBar.style.transform =
        'translate3d(' + E.round((0.5 + 0.5 * Math.sin(t * 1.7)) * 26) + 'px,0,0)';
    }

    refs.spots.forEach(function (spot) {
      var card = spot.card;
      show(spot.node, t >= card.at);
      if (t < card.at) return;
      arrive(spot.node, t, card.at, 0.55, 14);

      var quoteAt = card.quoteAt == null ? card.at + 0.35 : card.quoteAt;
      var quoteDur = card.quoteDur == null ? 1.1 : card.quoteDur;
      var qp = E.progress(t, quoteAt, quoteDur);
      spot.quoteText.innerHTML = esc('“' + E.typed(card.evidence, qp) + (qp >= 1 ? '”' : ''))
        + (qp > 0 && qp < 1 ? '<span class="caret"></span>' : '');
      spot.quote.style.opacity = qp > 0 ? 1 : 0;

      if (spot.hyp) {
        spot.test.style.opacity = E.Ease.out(E.progress(t, card.testAt, 0.4));
        spot.cost.style.opacity = E.Ease.out(E.progress(t, card.costAt, 0.4));
      }
    });
  }

  // MARK: - The assistant

  function renderAssistant(t, pointer) {
    var A = S.ANSWER;
    var G = S.ARGUE;

    // The Ask beat: the hypothesis card's cheap test sits in the composer
    // from the card's Ask click until the first prompt run takes the stage.
    if (refs.composer && S.ASK_BEAT) {
      var ph = refs.composer.querySelector('.ph');
      var asked = t >= S.ASK_BEAT.at && t < S.PROMPT_RUNS[0].click;
      if (ph) {
        ph.textContent = asked
          ? (S.BLIND_SPOTS.cards[S.ASK_BEAT.cardIndex].cheapTest || '')
          : S.UI.composer;
      }
      refs.composer.classList.toggle('composer-filled', asked);
    }
    // Two answers share the pane. Between them the assistant is working again,
    // which is why "streaming" spans from the first prompt's click to the last
    // answer finishing rather than tracking one run.
    var streaming = (t >= G.startAt - 0.6 && t < G.doneAt)
      || (t >= S.TOOL_TRACE[0].at - 0.4 && t < A.doneAt);

    // Each chip lights on hover, dips under the click, and stays lit while the
    // prompt it launched is still running.
    S.PROMPT_RUNS.forEach(function (run) {
      var chip = refs.chips[run.id];
      var hovering = t >= run.hover.from && t < run.hover.to;
      var active = t >= run.active.from && t < run.active.to;
      chip.classList.toggle('hot', hovering || active);
      var pressing = hovering && pointer.press > 0.02;
      chip.style.transform = pressing
        ? 'scale(' + E.round(1 - 0.03 * pointer.press, 3) + ')'
        : 'scale(1)';
    });

    refs.thinking.style.opacity = streaming ? 1 : 0;
    if (streaming) {
      // Three dots breathing out of phase — BreathingDots, but seekable.
      Array.prototype.forEach.call(refs.thinking.children, function (dot, i) {
        dot.style.opacity = E.round(0.35 + 0.65 * (0.5 + 0.5 * Math.sin(t * 5 - i * 0.9)), 3);
      });
    }

    refs.responseEmpty.style.opacity = 1 - E.Ease.out(E.progress(t, G.startAt - 0.8, 0.4));
    show(refs.responseEmpty, t < G.startAt - 0.4);

    // Argue Against. Cleared when the next prompt runs — the app replaces the
    // response rather than stacking answers, and a pane that grew forever would
    // be showing a chat log the product does not have.
    var argueOut = E.Ease.out(E.progress(t, G.clearAt, 0.35));
    show(refs.argue, t >= G.startAt && argueOut < 1);
    if (t >= G.startAt && argueOut < 1) {
      refs.argue.style.opacity = 1 - argueOut;
      var gp = E.progress(t, G.startAt, G.leadDur);
      refs.argueLead.innerHTML = esc(E.typed(G.lead, gp))
        + (gp > 0 && gp < 1 ? '<span class="caret"></span>' : '');
      refs.arguePoints.forEach(function (node, i) {
        var point = G.points[i];
        show(node, t >= point.at);
        if (t >= point.at) arrive(node, t, point.at, 0.42, 8);
      });
      show(refs.argueWeakest, t >= G.weakestAt);
      if (t >= G.weakestAt) arrive(refs.argueWeakest, t, G.weakestAt, 0.4, 6);
    }

    refs.traceLines.forEach(function (node, i) {
      var line = S.TOOL_TRACE[i];
      show(node, t >= line.at);
      if (t >= line.at) arrive(node, t, line.at, 0.35, 5);
    });

    var lp = E.progress(t, A.startAt, A.leadDur);
    refs.lead.innerHTML = esc(E.typed(A.lead, lp)) + (lp > 0 && lp < 1 ? '<span class="caret"></span>' : '');

    show(refs.table, t >= A.tableAt);
    if (t >= A.tableAt) {
      arrive(refs.tableHeader, t, A.tableAt, 0.35, 6);
      refs.tableRows.forEach(function (row, i) {
        var at = A.tableAt + 0.35 + i * A.tableRowDur;
        show(row, t >= at);
        if (t >= at) arrive(row, t, at, 0.4, 8);
      });
    }

    // Dimmed before there is an answer, never absent. AIStudioView hides these
    // until content exists, and the replica used to match it — but a film is
    // scrubbed to arbitrary instants, and 79 seconds of empty header read as a
    // missing icon rather than as a state ("иконки всё ещё нет"). Dim-to-lit
    // keeps the app's meaning and the film's legibility. The export spinner
    // still REPLACES share while it runs — a 45% dim of a 14px glyph is
    // invisible, which is how the Sheets click once looked like a miss.
    var actionable = t >= A.doneAt;
    var busy = t >= S.EXPORT_BUSY.from && t < S.EXPORT_BUSY.to;
    refs.writeback.style.opacity = actionable ? 1 : 0.3;
    refs.refine.style.opacity = actionable ? 1 : 0.3;
    refs.share.style.opacity = actionable ? (busy ? 0 : 1) : 0.3;
    refs.shareSpinner.style.opacity = busy ? 1 : 0;
    refs.shareSpinner.firstChild.style.transform = 'rotate(' + E.round(t * 520 % 360) + 'deg)';

    var M = S.SHARE_MENU;
    var open = E.clamp01(E.progress(t, M.openAt, 0.16) - E.progress(t, M.closeAt, 0.14));
    refs.menu.style.opacity = open;
    refs.menu.style.transform = 'scale(' + E.round(0.94 + 0.06 * open, 3) + ')';
    Object.keys(refs.menuItems).forEach(function (id) {
      refs.menuItems[id].classList.toggle('hot',
        id === M.picked && t >= M.pickAt - 0.5 && t < M.closeAt);
    });
  }

  // MARK: - Write-back sheet

  function renderSheet(t) {
    var W = S.WRITEBACK;
    var open = E.clamp01(E.progress(t, W.openAt, 0.24) - E.progress(t, W.closeAt, 0.2));
    refs.scrim.style.opacity = open;
    refs.sheet.style.opacity = open;
    refs.sheet.style.transform = 'scale(' + E.round(0.965 + 0.035 * E.Ease.settle(open), 3) + ')';

    // The tracker is already chosen; the picker is on screen so the choice is
    // visible, not so the film can spend a beat making it.
    Object.keys(refs.trackers).forEach(function (name) {
      refs.trackers[name].classList.toggle('on', name === W.selected);
    });

    refs.taskRows.forEach(function (row, i) {
      var task = W.tasks[i];
      var filing = t >= task.fileAt && t < task.doneAt;
      var done = t >= task.doneAt;
      row.file.style.opacity = done || filing ? 0 : 1;
      row.spinner.style.opacity = filing ? 1 : 0;
      row.spinner.style.transform = 'rotate(' + E.round(t * 520 % 360) + 'deg)';
      row.ref.style.opacity = done ? E.Ease.out(E.progress(t, task.doneAt, 0.3)) : 0;
    });
  }

  // MARK: - Settings

  function renderSettings(t) {
    var S2 = S.SETTINGS;
    var open = E.clamp01(E.progress(t, S2.openAt, 0.26) - E.progress(t, S2.closeAt, 0.22));
    refs.settingsScrim.style.opacity = open;
    refs.settings.style.opacity = open;
    refs.settings.style.transform = 'scale(' + E.round(0.968 + 0.032 * E.Ease.settle(open), 3) + ')';
    if (open <= 0) return;

    // Which panel is up is a lookup on time, not a variable the renderer keeps:
    // seeking backwards has to land on the same tab as playing forwards did.
    var active = S2.panels[0];
    S2.panels.forEach(function (panel) { if (t >= panel.from) active = panel; });
    Object.keys(refs.panels).forEach(function (id) {
      show(refs.panels[id], id === active.id);
      if (id === active.id) refs.panels[id].style.opacity = E.Ease.out(E.progress(t, active.from, 0.22));
    });
    Object.keys(refs.tabs).forEach(function (id) {
      refs.tabs[id].classList.toggle('on', id === active.id);
    });

    refs.appTiles.forEach(function (tile, i) {
      var app = S2.apps[i];
      show(tile, t >= app.at);
      if (t >= app.at) arrive(tile, t, app.at, 0.34, 7);
    });
    [[refs.privacyRows, S2.privacy.rows], [refs.transcriptionRows, S2.transcription.rows]]
      .forEach(function (pair) {
        pair[0].forEach(function (row, i) {
          var spec = pair[1][i];
          show(row, t >= spec.at);
          if (t >= spec.at) arrive(row, t, spec.at, 0.4, 9);
        });
      });
  }

  // MARK: - Furniture

  function renderFurniture(t, shot, pointer) {
    // Stage coordinates -> viewport coordinates under the current camera, so
    // the cursor tracks a button that is itself being zoomed.
    var vx = VIEWPORT.width / 2 + (pointer.x - shot.x) * shot.scale;
    var vy = VIEWPORT.height / 2 + (pointer.y - shot.y) * shot.scale;

    refs.cursor.style.opacity = pointer.visible;
    refs.cursor.style.transform = 'translate3d(' + E.round(vx) + 'px,' + E.round(vy) + 'px,0)';

    refs.ring.style.opacity = E.round(pointer.press * 0.7, 3);
    refs.ring.style.transform = 'translate3d(' + E.round(vx) + 'px,' + E.round(vy) + 'px,0) scale('
      + E.round(0.3 + 0.9 * (1 - pointer.press), 3) + ')';

    var caption = null, captionOpacity = 0;
    S.CAPTIONS.forEach(function (c) {
      var v = E.pulse(t, c.at, c.dur, 0.4, 0.5);
      if (v > captionOpacity) { captionOpacity = v; caption = c; }
    });
    if (caption) refs.captionBox.textContent = caption.text;
    refs.caption.style.opacity = E.round(captionOpacity, 3);
    refs.caption.style.transform = 'translate3d(0,' + E.round((1 - captionOpacity) * 12) + 'px,0)';

    refs.toasts.forEach(function (node, i) {
      var toast = S.TOASTS[i];
      var v = E.pulse(t, toast.at, toast.dur, 0.32, 0.5);
      node.style.opacity = E.round(v, 3);
      node.style.transform = 'translate3d(0,' + E.round((1 - v) * 16) + 'px,0)';
    });

    refs.endCard.style.opacity = E.round(E.Ease.out(E.progress(t, S.END_CARD.at, 0.7)), 3);
  }

  // MARK: - One frame

  function render(t) {
    t = E.clamp(t, 0, DURATION);
    var shot = E.shotAt(t, CAMERA_TRACK);
    refs.stage.style.transform = E.cameraTransform(shot, VIEWPORT);

    var pointer = E.pointerAt(t, S.POINTER.map(function (key) {
      var base = points[key.target] || { x: 0, y: 0 };
      return {
        at: key.at, click: key.click, show: key.show,
        x: base.x + (key.dx || 0), y: base.y + (key.dy || 0)
      };
    }));

    renderChrome(t);
    renderTranscript(t);
    renderRail(t);
    renderSpots(t);
    renderAssistant(t, pointer);
    renderSheet(t);
    renderSettings(t);
    renderFurniture(t, shot, pointer);
  }

  // MARK: - Fitting the film into whatever box it was dropped in

  function fit() {
    var box = refs.fit.getBoundingClientRect();
    var scale = Math.min(box.width / VIEWPORT.width, box.height / VIEWPORT.height);
    // The translate is what centres it; see .film-viewport in film.css for why
    // the parent's alignment cannot be trusted to do it.
    refs.viewport.style.transform = 'translate(-50%, -50%) scale(' + scale + ')';
  }

  // MARK: - Player
  //
  // Browser only. The recorder never starts it: it calls seek() itself, one
  // frame at a time, so a slow machine produces the same file as a fast one.

  var stopActivePlayer = null;

  function startPlayer(ui, speed, endAt) {
    // A re-mount (the landing's scenario tabs) must silence the previous
    // loop first: render() reads module-level refs, so an orphaned RAF loop
    // from the old mount would double-drive the new stage.
    if (stopActivePlayer) stopActivePlayer();
    // Vertical embeds stop where the exported vertical cuts stop: the acts
    // beyond are composed for the wide frame only.
    var stopAt = endAt > 0 ? Math.min(endAt, DURATION) : DURATION;
    var playing = false;
    var startedAt = 0;
    var offset = 0;

    function frame(now) {
      if (!playing) return;
      // `speed` advances the film's clock, not the frame rate — the browser
      // still renders every frame it can, so a fast cut is smooth rather than
      // the stutter you get from dropping frames.
      var t = offset + ((now - startedAt) / 1000) * speed;
      if (t >= stopAt) { offset = 0; startedAt = now; t = 0; }   // loop
      render(t);
      if (ui.bar) ui.bar.style.width = (t / stopAt * 100) + '%';
      requestAnimationFrame(frame);
    }

    function play() {
      if (playing) return;
      playing = true;
      startedAt = performance.now();
      if (ui.play) ui.play.hidden = true;
      requestAnimationFrame(frame);
    }

    function pause() {
      if (!playing) return;
      offset += ((performance.now() - startedAt) / 1000) * speed;
      playing = false;
      if (ui.play) ui.play.hidden = false;
    }

    stopActivePlayer = function () { playing = false; };

    // Whether the viewer stopped the film themselves. Without this the observer
    // below wins every argument: tap to pause on a phone, scroll one pixel, and
    // the frame is ≥45% visible again so it resumes — which reads as a video
    // that cannot be paused at all. An explicit pause has to outrank visibility
    // until the viewer asks for play again.
    var userPaused = false;

    if (ui.play) ui.play.addEventListener('click', function () { userPaused = false; play(); });
    refs.viewport.addEventListener('click', function () {
      if (playing) { userPaused = true; pause(); }
      else { userPaused = false; play(); }
    });

    // Autoplay only while it is actually on screen. A film looping in a tab
    // nobody is looking at is a battery bug with a marketing budget.
    var reduced = root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (!reduced && 'IntersectionObserver' in root) {
      new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          // Scrolling out still pauses — a film playing off screen is the
          // battery bug this observer exists to prevent — but scrolling back in
          // does NOT undo a pause the viewer asked for.
          if (!entry.isIntersecting) pause();
          else if (!userPaused) play();
        });
      }, { threshold: 0.45 }).observe(refs.viewport);
    }
    return { play: play, pause: pause };
  }

  // MARK: - Boot

  /* Mount into any element. `host` is where the set is built; `where` is what
     the film queries against — the document for the standalone page, a shadow
     root when it is embedded in another page.

     Embedding it this way rather than in an <iframe> is not a preference: the
     site sends `X-Frame-Options: DENY`, which refuses framing from every origin
     including its own, so a same-origin frame renders empty. A shadow root has
     no such rule, costs no extra bytes, and keeps film.css — which claims very
     ordinary names like .sidebar and .chip — from touching the host page. */
  function mount(host, where, options) {
    var opts = options || {};
    scope = where || document;
    refs = root.CruxFilmSet.build(host);

    var params = new URLSearchParams(root.location.search);
    var recording = opts.record != null ? opts.record : params.get('record') === '1';
    // `?speed=1.5` is what the embeds use. On a page, 128 seconds is a long ask
    // of someone deciding whether to keep scrolling; opened on its own the film
    // runs at 1x, where the card paragraphs are readable.
    var speed = E.clamp(Number(opts.speed || params.get('speed')) || 1, 0.5, 3);

    // Format before anything measures itself: the viewport's real size and the
    // shorter box the camera composes into both come from here.
    format = FORMATS[opts.format || params.get('format')] || FORMATS.wide;
    VIEWPORT = { width: format.w, height: format.h - format.safeBottom };
    CAMERA_TRACK = S[format.track] || S.CAMERA;
    // On a page the story's sticker band is 470px of dead black — an export
    // needs it, an embed does not. Trimming cuts the frame at the composed
    // area; fit() already scales by that area, so the crop is exact.
    var trimBand = format.safeBottom > 0
      && (opts.trimBand || params.get('band') === 'trim');
    refs.viewport.style.width = format.w + 'px';
    refs.viewport.style.height = (trimBand ? format.h - format.safeBottom : format.h) + 'px';
    refs.viewport.setAttribute('data-format', opts.format || params.get('format') || 'wide');
    if (trimBand) refs.viewport.setAttribute('data-band', 'trim');

    var ui = {
      root: scope.querySelector('.player-ui'),
      play: scope.querySelector('.play-btn'),
      bar: scope.querySelector('.scrub i')
    };
    // The standalone page ships this control in its markup; an EMBED had none,
    // so the film on the landing page offered no play affordance at all. That
    // is invisible while the film autoplays and total when it does not —
    // someone who asked for reduced motion saw a still frame with no way to
    // know it was a film. Build it when it is missing.
    if (!ui.play && !recording) {
      var playerUi = document.createElement('div');
      playerUi.className = 'player-ui';
      playerUi.innerHTML = '<button class="play-btn" type="button" aria-label="Play the product film">'
        + '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M4 2.6 13.4 8 4 13.4z"/></svg>'
        + '</button><div class="scrub"><i style="width:0"></i></div>';
      refs.viewport.appendChild(playerUi);
      ui.root = playerUi;
      ui.play = playerUi.querySelector('.play-btn');
      ui.bar = playerUi.querySelector('.scrub i');
    }
    if (recording && ui.root) ui.root.hidden = true;

    fit();
    root.addEventListener('resize', fit);

    var ready = (document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve())
      .then(function () {
        // Geometry is measured with the film in its opening state and AFTER the
        // fonts land: a chip measured in the fallback face is the wrong width,
        // and the cursor would then press just past its edge.
        render(0);
        measure();
        render(Number(opts.t || params.get('t')) || 0);
        if (!recording) startPlayer(ui, speed, Number(opts.endAt || params.get('to')) || 0);
        if (document.documentElement) document.documentElement.setAttribute('data-film-ready', '1');
        // Tell a parent page the film actually rendered. Silence is the signal
        // that matters: if X-Frame-Options blocked the frame this never
        // arrives, and the embed swaps itself for a poster rather than sitting
        // there as an empty box. It also self-heals — the day the header is
        // fixed the message lands and the fallback never shows.
        try {
          if (root.parent && root.parent !== root) {
            root.parent.postMessage({ cruxwingFilm: 'ready' }, '*');
          }
        } catch (e) { /* a parent we cannot reach is a parent we cannot help */ }
        return true;
      });

    root.__film = {
      seek: function (t) { render(t); },
      duration: DURATION,
      acts: S.ACTS,
      ready: ready
    };
  }

  root.CruxFilm = { mount: mount };

  // The standalone page mounts itself. An embedding page calls mount() with its
  // own host and shadow root instead.
  /* `cruxwing-film`, not `film`. The landing's own section is id="film", and
     this ran on every page that loaded the scripts — building a second, unstyled
     copy of the whole app into the landing's light DOM, where film.css (which
     lives in the shadow root) could not reach it. The result measured tens of
     thousands of pixels tall, fit() computed a 24x scale from it, and the film
     painted over the hero. An id this specific cannot be claimed by accident. */
  function bootStandalone() {
    var host = document.getElementById('cruxwing-film');
    if (host) mount(host, document);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', bootStandalone);
  } else {
    bootStandalone();
  }
}(typeof window !== 'undefined' ? window : globalThis));
