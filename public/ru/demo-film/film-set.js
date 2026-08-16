/* ============================================================================
 * Cruxwing demo film — building the set
 * ----------------------------------------------------------------------------
 * Constructs the whole app replica ONCE and hands back a map of the elements
 * the timeline mutates. Nothing here reads the clock.
 *
 * The one rule that matters: an element the cursor aims at is never removed
 * from layout. `display: none` collapses `offsetLeft` to zero, and the pointer
 * would then travel to the top-left corner of the window to press a button
 * sitting in the middle of a sheet. Hidden-but-present means opacity 0.
 * ========================================================================== */
(function (root) {
  'use strict';

  var S = root.CruxFilmScene;

  // MARK: - Glyphs
  //
  // Geometric stand-ins for the SF Symbols the app uses, drawn on a 16x16 grid.
  // At 10-14px what carries a glyph is its silhouette, and hand-tracing Apple's
  // outlines would be both worse and not ours to ship.

  var ICONS = {
    waveform: '<rect x="1.5" y="6" width="1.6" height="4" rx=".8"/><rect x="4.7" y="3.5" width="1.6" height="9" rx=".8"/><rect x="7.9" y="1.5" width="1.6" height="13" rx=".8"/><rect x="11.1" y="4.5" width="1.6" height="7" rx=".8"/><rect x="13.9" y="6.5" width="1.6" height="3" rx=".8"/>',
    pause: '<rect x="4" y="3" width="3" height="10" rx="1.2"/><rect x="9" y="3" width="3" height="10" rx="1.2"/>',
    play: '<path d="M4 2.6 13.4 8 4 13.4z"/>',
    calendar: '<rect x="1.6" y="3" width="12.8" height="11.4" rx="2.4" fill="none" stroke="currentColor" stroke-width="1.3"/><rect x="1.6" y="3" width="12.8" height="3.2" rx="1.4"/><rect x="4.4" y="1.2" width="1.4" height="3" rx=".7"/><rect x="10.2" y="1.2" width="1.4" height="3" rx=".7"/>',
    warning: '<path d="M8 1.6 15.2 14H.8z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><rect x="7.25" y="5.6" width="1.5" height="4.4" rx=".75"/><circle cx="8" cy="11.6" r=".95"/>',
    doc: '<path d="M3.4 1.6h5.4l3.8 3.8v9a1.6 1.6 0 0 1-1.6 1.6H3.4a1.6 1.6 0 0 1-1.6-1.6V3.2a1.6 1.6 0 0 1 1.6-1.6z" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M8.6 1.8v3.8h3.8" fill="none" stroke="currentColor" stroke-width="1.3"/>',
    table: '<rect x="1.4" y="2.6" width="13.2" height="10.8" rx="1.8" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M1.4 6.2h13.2M6 6.2v7.2M10.2 6.2v7.2" stroke="currentColor" stroke-width="1.2" fill="none"/>',
    clock: '<circle cx="8" cy="8" r="6.3" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M8 4.6V8l2.6 1.6" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>',
    gear: '<circle cx="8" cy="8" r="5.9" fill="none" stroke="currentColor" stroke-width="1.3"/><circle cx="8" cy="8" r="2.1" fill="none" stroke="currentColor" stroke-width="1.3"/>',
    person: '<circle cx="8" cy="5.6" r="2.9" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M2.9 14c.6-3 2.7-4.5 5.1-4.5s4.5 1.5 5.1 4.5" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>',
    sparkles: '<path d="M6 1.4 7.2 4.9 10.7 6.1 7.2 7.3 6 10.8 4.8 7.3 1.3 6.1 4.8 4.9z"/><path d="M12 8.6 12.7 10.6 14.7 11.3 12.7 12 12 14 11.3 12 9.3 11.3 11.3 10.6z"/>',
    upForward: '<rect x="1.6" y="1.6" width="12.8" height="12.8" rx="3" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M5.8 10.2 10.4 5.6M6.6 5.6h3.8v3.8" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>',
    share: '<path d="M8 1.8v8.6M4.8 5 8 1.8 11.2 5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M3 8.6v4.2a1.6 1.6 0 0 0 1.6 1.6h6.8a1.6 1.6 0 0 0 1.6-1.6V8.6" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>',
    // The refine wand. The first drawing was a hairline diagonal with a 3px
    // star — at 16px it read as a stray slash, not a control ("что за вторая
    // иконка?"). Shorter, thicker handle; a star big enough to be the subject.
    wand: '<path d="M2.8 13.2 8.2 7.8" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M11.2 1.2 12.4 4.1 15.3 5.3 12.4 6.5 11.2 9.4 10 6.5 7.1 5.3 10 4.1z"/><path d="M13.6 9.8 14.1 11 15.3 11.5 14.1 12 13.6 13.2 13.1 12 11.9 11.5 13.1 11z"/>',
    copy: '<rect x="5" y="1.8" width="9.2" height="9.2" rx="2" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M11 13.2a2 2 0 0 1-2 2H3.8a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2" fill="none" stroke="currentColor" stroke-width="1.3"/>',
    downDoc: '<path d="M8 1.8v7.4M5 6.4 8 9.4l3-3" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M2.6 11v1.8a1.6 1.6 0 0 0 1.6 1.6h7.6a1.6 1.6 0 0 0 1.6-1.6V11" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>',
    check: '<path d="M2.8 8.4 6.3 12 13.2 4.6" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
    arrowUpCircle: '<circle cx="8" cy="8" r="6.4" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M8 11.2V5.2M5.6 7.6 8 5.2l2.4 2.4" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>',
    quote: '<path d="M2.6 9.6c0-3 1.6-5.2 4-6l.6 1.4c-1.4.7-2.2 1.8-2.4 3h2v3.6H2.6zm6.4 0c0-3 1.6-5.2 4-6l.6 1.4c-1.4.7-2.2 1.8-2.4 3h2v3.6H9z"/>',
    x: '<path d="M3.6 3.6 12.4 12.4M12.4 3.6 3.6 12.4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
    send: '<path d="M8 13V3.6M4.4 7.2 8 3.6l3.6 3.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>',
    plus: '<path d="M8 3.2v9.6M3.2 8h9.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
    sheet: '<rect x="1.4" y="2.2" width="13.2" height="11.6" rx="1.6" fill="none" stroke="currentColor" stroke-width="1.4"/>'
      + '<path d="M2.1 2.9h11.8v2.6H2.1z"/>'
      + '<path d="M6.1 5.5v8.3M10.1 5.5v8.3M1.4 9.1h13.2" stroke="currentColor" stroke-width="1.1" fill="none"/>',
    n: '<rect x="1.8" y="1.8" width="12.4" height="12.4" rx="2.6" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M5.4 11V5l5.2 6V5" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>'
  };

  function svg(name, cls) {
    return '<svg class="' + (cls || '') + '" viewBox="0 0 16 16" aria-hidden="true">' + ICONS[name] + '</svg>';
  }

  /* Kind tints, from SuggestionCard/FocusRow: the stroke colour plus the 7%
     wash the hypothesis block sits on. */
  var TINTS = {
    accent: ['var(--accent)', 'rgba(154,107,255,0.07)'],
    red: ['var(--record-red)', 'rgba(240,90,106,0.07)'],
    cyan: ['var(--speaker-them)', 'rgba(79,187,234,0.07)'],
    amber: ['var(--amber)', 'rgba(245,166,35,0.09)'],
    magenta: ['var(--speaker-you)', 'rgba(210,75,192,0.07)']
  };

  function el(tag, cls, html) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (html != null) n.innerHTML = html;
    return n;
  }

  function tinted(node, key) {
    var pair = TINTS[key] || TINTS.accent;
    node.style.setProperty('--tint', pair[0]);
    node.style.setProperty('--tint-soft', pair[1]);
    return node;
  }

  function section(id, label, withCount) {
    var sec = el('section', 'section');
    sec.id = id;
    var head = el('div', 'section-head');
    head.appendChild(el('span', 'section-label', label));
    if (withCount) {
      var count = el('span', 'section-count', '0');
      count.dataset.role = 'count';
      head.appendChild(count);
    }
    sec.appendChild(head);
    return sec;
  }

  // MARK: - Sidebar

  function buildSidebar(refs) {
    var bar = el('aside', 'sidebar');

    var brand = el('div', 'brand');
    brand.appendChild(el('span', 'mark', svg('waveform')));
    brand.appendChild(el('span', 'name', 'Cruxwing'));
    bar.appendChild(brand);

    var row = el('div', 'record-row');
    var pill = el('div', 'record-pill');
    pill.appendChild(el('span', 'stop'));
    pill.appendChild(el('span', 'label', S.UI.stopLabel));
    refs.elapsed = el('span', 'elapsed', '12:04');
    pill.appendChild(refs.elapsed);
    row.appendChild(pill);
    row.appendChild(el('div', 'pause-btn', svg('pause')));
    bar.appendChild(row);

    var meta = el('div', 'capture-meta');
    meta.appendChild(el('span', 'source-tag', '<span class="dot them"></span><span>' + S.UI.system + '</span>'));
    meta.appendChild(el('span', 'source-tag', '<span class="dot you"></span><span>' + S.UI.you + '</span>'));
    var meter = el('div', 'meter');
    refs.meterBars = [];
    for (var m = 0; m < 5; m++) {
      var b = el('i');
      meter.appendChild(b);
      refs.meterBars.push(b);
    }
    meta.appendChild(meter);
    bar.appendChild(meta);

    bar.appendChild(el('div', 'rail-divider'));

    // The clip and the thing that moves have to be two elements. Transforming
    // the scroller itself moves its own overflow clip with it, and the rail
    // then spills up over the brand and the record pill.
    var scroll = el('div', 'rail-scroll');
    var content = el('div', 'rail-content');
    scroll.appendChild(content);
    refs.rail = content;

    // Focus
    var focus = section('sec-focus', S.UI.focus, true);
    refs.focusRows = S.FOCUS.items.map(function (item) {
      var wrap = el('div', 'focus-wrap');
      wrap.style.display = 'flex';
      wrap.style.flexDirection = 'column';
      wrap.style.gap = '4px';
      var rowEl = tinted(el('div', 'focus-row'), item.tint);
      rowEl.appendChild(el('span', 'glyph', svg(item.kind === 'risk' ? 'warning' : 'calendar')));
      var body = el('div', 'body');
      body.appendChild(el('span', 't', item.title));
      body.appendChild(el('span', 'd', item.detail));
      rowEl.appendChild(body);
      wrap.appendChild(rowEl);

      var lines = item.brief.map(function (line) {
        var l = el('div', 'brief-line' + (line.overdue ? ' overdue' : ''));
        l.appendChild(el('span', 'bullet'));
        var col = el('div');
        col.appendChild(el('div', 'txt', line.text));
        col.appendChild(el('div', 'src', line.source + ' — ' + line.read));
        l.appendChild(col);
        return l;
      });
      if (lines.length) {
        var brief = el('div', 'brief');
        lines.forEach(function (l) { brief.appendChild(l); });
        wrap.appendChild(brief);
      }
      focus.appendChild(wrap);
      return { wrap: wrap, lines: lines };
    });
    content.appendChild(focus);
    refs.secFocus = focus;

    // Co-pilot: the goal, the watcher, and the blind spots themselves
    var copilot = section('sec-copilot', S.UI.copilot, false);
    refs.goal = el('div', 'goal-chip',
      '<div class="k">' + S.UI.goalKicker + '</div><div class="v">' + S.GOAL.text + '</div>');
    copilot.appendChild(refs.goal);

    refs.watch = el('div', 'watch-head',
      '<span class="h">' + S.UI.watching + '</span><span class="scan"><i></i></span>');
    refs.scanBar = refs.watch.querySelector('.scan i');
    copilot.appendChild(refs.watch);

    refs.spots = S.BLIND_SPOTS.cards.map(function (card, i) {
      var node = tinted(el('article', 'spot'), card.tint);
      node.id = 'spot-' + i;

      var head = el('div', 'head');
      head.innerHTML = svg(card.kind === 'risk' ? 'warning'
        : card.kind === 'missing' ? 'quote' : 'sparkles');
      head.appendChild(el('span', 'title', card.title));
      head.appendChild(el('span', 'x', svg('x')));
      node.appendChild(head);

      var quote = el('div', 'quote');
      quote.appendChild(el('span', 'bar'));
      var q = el('span', 'q');
      quote.appendChild(q);
      node.appendChild(quote);

      node.appendChild(el('p', 'detail', card.detail));

      var parts = { node: node, quote: quote, quoteText: q, card: card };
      if (card.kind === 'hypothesis') {
        var hyp = el('div', 'hyp');
        hyp.appendChild(el('div', 'claim', card.claim));
        var test = el('div', 'test', svg('quote') + '<span>' + card.cheapTest + '</span>');
        hyp.appendChild(test);
        var cost = el('div', 'cost', S.UI.ifWrong + ' ' + card.cost);
        hyp.appendChild(cost);
        node.appendChild(hyp);
        parts.hyp = hyp; parts.test = test; parts.cost = cost;
      }

      var actions = el('div', 'actions');
      if (card.kind === 'hypothesis') {
        actions.appendChild(el('span', 'quiet-btn', svg('copy') + S.UI.copyTest));
      }
      var askBtn = el('span', 'quiet-btn prominent', svg('arrowUpCircle') + S.UI.ask);
      askBtn.id = 'ask-' + i;
      actions.appendChild(askBtn);
      parts.ask = askBtn;
      node.appendChild(actions);

      copilot.appendChild(node);
      return parts;
    });
    content.appendChild(copilot);
    refs.secCopilot = copilot;

    // Context / History / Ledger
    refs.contextRows = [];
    var ctx = section('sec-context', S.UI.context, true);
    S.CONTEXT.items.forEach(function (item) {
      var r = el('div', 'rail-row');
      r.appendChild(el('span', 'ic', svg(item.icon === 'sheet' ? 'table' : item.icon === 'notion' ? 'n' : 'doc')));
      var col = el('div', 'col');
      col.appendChild(el('span', 't', item.name));
      col.appendChild(el('span', 'm', item.meta));
      r.appendChild(col);
      ctx.appendChild(r);
      refs.contextRows.push(r);
    });
    content.appendChild(ctx);
    refs.secContext = ctx;

    refs.historyRows = [];
    var hist = section('sec-history', S.UI.history, true);
    S.HISTORY.items.forEach(function (item) {
      var r = el('div', 'rail-row');
      r.appendChild(el('span', 'ic', svg('clock')));
      var col = el('div', 'col');
      col.appendChild(el('span', 't', item.title));
      col.appendChild(el('span', 'm', item.meta));
      r.appendChild(col);
      hist.appendChild(r);
      refs.historyRows.push(r);
    });
    content.appendChild(hist);
    refs.secHistory = hist;

    refs.ledgerRows = [];
    var led = section('sec-ledger', S.UI.ledger, true);
    S.LEDGER.items.forEach(function (item) {
      var r = el('div', 'rail-row');
      r.appendChild(el('span', 'ledger-dot' + (item.decided ? ' decided' : '')));
      var col = el('div', 'col');
      col.appendChild(el('span', 't', item.title));
      col.appendChild(el('span', 'm', item.meta));
      r.appendChild(col);
      led.appendChild(r);
      refs.ledgerRows.push(r);
    });
    content.appendChild(led);
    refs.secLedger = led;

    bar.appendChild(scroll);
    var foot = el('div', 'rail-foot');
    foot.appendChild(el('span', 'foot-btn', svg('person')));
    refs.gear = el('span', 'foot-btn', svg('gear'));
    refs.gear.id = 'settings-gear';
    foot.appendChild(refs.gear);
    bar.appendChild(foot);
    return bar;
  }

  // MARK: - Centre column

  function buildCentre(refs) {
    var centre = el('section', 'centre');

    var head = el('div', 'meeting-head');
    head.appendChild(el('h1', null, S.MEETING.title));
    head.appendChild(el('div', 'meta',
      '<span>' + S.MEETING.date + '</span><span class="sep"></span><span>' + S.MEETING.contextLabel + '</span>'));
    centre.appendChild(head);

    var bar = el('div', 'transcript-bar');
    bar.appendChild(el('span', 'section-label', S.UI.transcript));
    bar.appendChild(el('span', 'icon-btn', svg('downDoc')));
    bar.appendChild(el('span', 'live-pill', '<span class="dot"></span>' + S.UI.live));
    centre.appendChild(bar);

    var feed = el('div', 'transcript');
    refs.turns = S.TRANSCRIPT.map(function (line) {
      var turn = el('div', 'turn ' + line.source);
      var who = el('div', 'who');
      who.appendChild(el('span', 'n', line.speaker));
      who.appendChild(el('span', 'ts', line.time));
      turn.appendChild(who);
      var said = el('div', 'said');
      turn.appendChild(said);
      feed.appendChild(turn);
      return { turn: turn, said: said, line: line };
    });
    centre.appendChild(feed);
    return centre;
  }

  // MARK: - Assistant

  function buildAssistant(refs) {
    var pane = el('section', 'assistant');

    var head = el('div', 'assistant-head');
    head.appendChild(el('span', 'ttl', svg('sparkles') + '<span>' + S.UI.assistant + '</span>'));
    refs.thinking = el('span', 'dots', '<i></i><i></i><i></i>');
    head.appendChild(refs.thinking);
    var tools = el('div', 'tools');
    refs.writeback = el('span', 'icon-btn', svg('upForward'));
    refs.writeback.id = 'assistant-writeback';
    refs.refine = el('span', 'icon-btn', svg('wand'));
    refs.share = el('span', 'icon-btn', svg('share'));
    refs.share.id = 'assistant-share';
    // Stacked on the share control rather than beside it: the export replaces
    // the button for as long as it runs, which is the app's own behaviour and
    // the only thing on screen that says the click did anything.
    refs.shareSpinner = el('span', 'icon-btn share-busy', '<span class="spinner"></span>');
    tools.appendChild(refs.writeback);
    tools.appendChild(refs.refine);
    var shareSlot = el('span', 'share-slot');
    shareSlot.appendChild(refs.share);
    shareSlot.appendChild(refs.shareSpinner);
    tools.appendChild(shareSlot);
    head.appendChild(tools);
    pane.appendChild(head);

    pane.appendChild(el('div', 'lbl', '<span class="section-label">' + S.UI.prompts + '</span>'));

    var chips = el('div', 'chips');
    refs.chips = {};
    S.PROMPTS.forEach(function (p) {
      var c = el('span', 'chip', '<span class="ico">' + p.icon + '</span>' + p.title);
      c.id = 'prompt-' + p.id;
      chips.appendChild(c);
      refs.chips[p.id] = c;
    });
    chips.appendChild(el('span', 'chip new', svg('plus') + S.UI.newChip));
    pane.appendChild(chips);

    pane.appendChild(el('div', 'budget',
      '<span class="n">' + S.UI.budgetName + '</span><span class="track"><i style="width:38%"></i></span><span class="n">' + S.UI.budgetLeft + '</span>'));

    pane.appendChild(el('div', 'hr'));

    var response = el('div', 'response');
    // The pane is not blank for the first minute of the film. The app has an
    // empty state here for the same reason: a large dark rectangle beside a
    // running transcript reads as a pane that failed to load.
    refs.responseEmpty = el('p', 'response-empty', S.UI.responseEmpty);
    response.appendChild(refs.responseEmpty);

    refs.argue = el('div', 'argue');
    refs.argueLead = el('p', 'answer-lead', '');
    refs.argue.appendChild(refs.argueLead);
    refs.arguePoints = S.ARGUE.points.map(function (point, i) {
      var row = el('div', 'argue-point');
      row.appendChild(el('span', 'n', String(i + 1)));
      row.appendChild(el('span', 'p', point.text));
      refs.argue.appendChild(row);
      return row;
    });
    // The counter-case names its own weakest link. An argument that will not do
    // that is advocacy, and the card above it already made the other case.
    refs.argueWeakest = el('p', 'argue-weakest', S.ARGUE.weakest);
    refs.argue.appendChild(refs.argueWeakest);
    response.appendChild(refs.argue);

    refs.trace = el('div', 'trace');
    refs.traceLines = S.TOOL_TRACE.map(function (line) {
      var l = el('div', 'trace-line', '<span class="tick">' + svg('check') + '</span><span>' + line.text + '</span>');
      refs.trace.appendChild(l);
      return l;
    });
    response.appendChild(refs.trace);

    refs.lead = el('p', 'answer-lead', '');
    response.appendChild(refs.lead);

    refs.table = el('div', 'answer-table');
    var header = el('div', 'tr');
    S.ANSWER.header.forEach(function (h) { header.appendChild(el('span', 'th', h)); });
    refs.table.appendChild(header);
    refs.tableHeader = header;
    refs.tableRows = S.ANSWER.rows.map(function (row) {
      var tr = el('div', 'tr');
      var unassigned = row[0] === S.UI.unassigned;
      tr.appendChild(el('span', 'td owner' + (unassigned ? ' none' : ''), row[0]));
      tr.appendChild(el('span', 'td', row[1]));
      tr.appendChild(el('span', 'td due', row[2]));
      tr.appendChild(el('span', 'td from', row[3]));
      refs.table.appendChild(tr);
      return tr;
    });
    response.appendChild(refs.table);
    pane.appendChild(response);

    pane.appendChild(el('div', 'hr'));
    var composer = el('div', 'composer',
      '<span class="ph">' + S.UI.composer + '</span><span class="send">' + svg('send') + '</span>');
    pane.appendChild(composer);
    refs.composer = composer;

    // The share menu is present from the first frame at opacity 0, so the
    // pointer can measure where its items are before it is ever opened.
    refs.menu = el('div', 'menu');
    refs.menuItems = {};
    S.SHARE_MENU.items.forEach(function (item) {
      if (item.divider) refs.menu.appendChild(el('div', 'sep'));
      var mi = el('div', 'mi',
        svg(item.icon === 'copy' ? 'copy' : item.icon === 'down' ? 'downDoc'
          : item.icon === 'doc' ? 'doc' : item.icon === 'table' ? 'table' : 'n')
        + '<span>' + item.label + '</span>');
      mi.id = 'share-' + item.id;
      refs.menu.appendChild(mi);
      refs.menuItems[item.id] = mi;
    });
    pane.appendChild(refs.menu);

    return pane;
  }

  // MARK: - Write-back sheet

  function buildSheet(refs) {
    var sheet = el('div', 'sheet');
    refs.sheet = sheet;

    var head = el('div', 'sheet-head');
    head.innerHTML = svg('upForward');
    head.appendChild(el('span', 'h', S.UI.sheetTitle));
    refs.sheetDone = el('span', 'quiet-btn done', S.UI.done);
    refs.sheetDone.id = 'writeback-done';
    head.appendChild(refs.sheetDone);
    sheet.appendChild(head);

    var seg = el('div', 'segmented');
    refs.trackers = {};
    S.WRITEBACK.trackers.forEach(function (name) {
      var s = el('span', 'seg', name);
      s.id = 'tracker-' + name.toLowerCase();
      seg.appendChild(s);
      refs.trackers[name] = s;
    });
    sheet.appendChild(seg);

    var list = el('div', 'task-list');
    refs.taskRows = S.WRITEBACK.tasks.map(function (task, i) {
      var r = el('div', 'task-row');
      var col = el('div', 'col');
      col.appendChild(el('span', 't', task.title));
      col.appendChild(el('span', 'm', task.meta));
      r.appendChild(col);

      var file = el('span', 'quiet-btn prominent', S.UI.file);
      file.id = 'file-' + i;
      var spin = el('span', 'spinner');
      var ref = el('span', 'ref', svg('check') + task.ref);
      r.appendChild(file);
      r.appendChild(spin);
      r.appendChild(ref);
      list.appendChild(r);
      return { row: r, file: file, spinner: spin, ref: ref };
    });
    sheet.appendChild(list);
    return sheet;
  }

  // MARK: - Settings
  //
  // Every string here is the app's own, from SettingsView.swift: the five tabs,
  // the section titles, and the sentence about never switching to cloud without
  // being told to. The act answers the two questions a product manager actually
  // asks — what can it reach, and where does my roadmap go — with a real
  // surface rather than a claim.

  function buildSettings(refs) {
    var S2 = S.SETTINGS;
    var win = el('div', 'settings');
    refs.settings = win;

    var head = el('div', 'settings-head');
    var tabs = el('div', 'settings-tabs');
    refs.tabs = {};
    S2.tabs.forEach(function (tab) {
      var node = el('span', 'stab', tab.label);
      node.id = 'tab-' + tab.id;
      tabs.appendChild(node);
      refs.tabs[tab.id] = node;
    });
    head.appendChild(tabs);
    refs.settingsDone = el('span', 'quiet-btn', S.UI.done);
    refs.settingsDone.id = 'settings-done';
    head.appendChild(refs.settingsDone);
    win.appendChild(head);

    var body = el('div', 'settings-body');
    refs.panels = {};

    // Connected Apps
    var apps = el('div', 'spanel');
    apps.appendChild(el('div', 'settings-section', S.UI.workApps));
    var grid = el('div', 'apps-grid');
    refs.appTiles = S2.apps.map(function (app) {
      var tile = el('div', 'app-tile' + (app.on ? ' on' : ''));
      tile.appendChild(el('span', 'dot'));
      tile.appendChild(el('span', 'nm', app.name));
      tile.appendChild(el('span', 'st', app.on ? S.UI.connected : S.UI.connect));
      grid.appendChild(tile);
      return tile;
    });
    apps.appendChild(grid);
    apps.appendChild(el('p', 'settings-note', S2.appsCaption));
    body.appendChild(apps);
    refs.panels.apps = apps;

    // Account & Privacy, and Transcription — same row shape, so one builder.
    function panel(spec) {
      var node = el('div', 'spanel');
      node.appendChild(el('div', 'settings-section', spec.section));
      var rows = spec.rows.map(function (row) {
        var r = el('div', 'srow');
        var col = el('div', 'col');
        col.appendChild(el('span', 'lb', row.label));
        col.appendChild(el('span', 'nt', row.note));
        if (row.terms) {
          var chips = el('div', 'term-chips');
          row.terms.forEach(function (term) { chips.appendChild(el('span', 'term', term)); });
          col.appendChild(chips);
        }
        r.appendChild(col);
        if (row.toggle != null) r.appendChild(el('span', 'switch on'));
        node.appendChild(r);
        return r;
      });
      body.appendChild(node);
      return { node: node, rows: rows };
    }
    var privacy = panel(S2.privacy);
    refs.panels.privacy = privacy.node;
    refs.privacyRows = privacy.rows;
    var transcription = panel(S2.transcription);
    refs.panels.transcription = transcription.node;
    refs.transcriptionRows = transcription.rows;

    win.appendChild(body);
    return win;
  }

  // MARK: - Furniture

  function buildFurniture(refs, viewport) {
    refs.cursor = el('div', 'cursor',
      '<svg viewBox="0 0 26 30" aria-hidden="true">'
      + '<path d="M3 1.6 22.4 16.2h-8.2l-2.4 9.4z" fill="#fff" stroke="#141020" stroke-width="1.6" stroke-linejoin="round"/>'
      + '</svg>');
    refs.ring = el('div', 'click-ring');
    refs.caption = el('div', 'caption', '<span class="box"></span>');
    refs.captionBox = refs.caption.querySelector('.box');

    refs.toastSlot = el('div', 'toast-slot');
    refs.toasts = S.TOASTS.map(function (toast) {
      // Text only. The coloured badge twice escaped the toast's flex row and
      // landed in the middle of the transcript, and a tile approximating another
      // company's icon was never worth that: the sentence already names Asana
      // and Drive, and macOS says this kind of thing in words too.
      var node = el('div', 'toast');
      node.textContent = toast.text;
      refs.toastSlot.appendChild(node);
      return node;
    });
    // The toasts share one grid cell (see .toast-slot): only ever one is
    // visible, and two slots would leave a hole in the frame whenever the
    // other was empty.

    refs.endCard = el('div', 'end-card',
      '<div class="logo"><img class="mark" src="https://cruxwing.ai/assets/brain.png" width="96" height="92" alt="" />'
      + '<span class="name">Cruxwing</span></div>'
      + '<div class="line">' + S.END_CARD.line + '</div>'
      + '<div class="sub">' + S.END_CARD.sub + '</div>'
      + '<div class="url">' + S.END_CARD.url + '</div>');

    refs.safeBand = el('div', 'safe-band');

    [refs.safeBand, refs.cursor, refs.ring, refs.caption, refs.toastSlot, refs.endCard]
      .forEach(function (n) { viewport.appendChild(n); });
  }

  // MARK: - Assembly

  function build(host) {
    var refs = {};

    var fit = el('div', 'film-fit');
    var viewport = el('div', 'film-viewport');
    var stage = el('div', 'film-stage');
    refs.fit = fit; refs.viewport = viewport; refs.stage = stage;

    var win = el('div', 'app-window');
    var titleBar = el('div', 'title-bar',
      '<span class="light red"></span><span class="light amber"></span><span class="light green"></span>');
    titleBar.appendChild(el('span', 'doc-title', S.MEETING.title));
    win.appendChild(titleBar);

    var body = el('div', 'app-body');
    body.appendChild(buildSidebar(refs));
    body.appendChild(buildCentre(refs));
    body.appendChild(buildAssistant(refs));
    win.appendChild(body);

    // Sheet and scrim are children of the WINDOW, so the window's rounded
    // corners clip them exactly as AppKit clips a real sheet.
    refs.scrim = el('div', 'scrim');
    win.appendChild(refs.scrim);
    win.appendChild(buildSheet(refs));
    refs.settingsScrim = el('div', 'scrim settings-scrim');
    win.appendChild(refs.settingsScrim);
    win.appendChild(buildSettings(refs));

    stage.appendChild(win);
    viewport.appendChild(stage);
    buildFurniture(refs, viewport);
    fit.appendChild(viewport);
    // Replace, never stack: a scenario re-mount builds into the same host,
    // and appending would leave the previous film's DOM underneath.
    while (host.firstChild) host.removeChild(host.firstChild);
    host.appendChild(fit);

    refs.window = win;
    return refs;
  }

  root.CruxFilmSet = { build: build, ICONS: ICONS, svg: svg, TINTS: TINTS };
}(typeof window !== 'undefined' ? window : globalThis));
