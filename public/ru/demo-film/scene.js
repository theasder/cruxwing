/* ============================================================================
 * Cruxwing demo film — the script
 * ----------------------------------------------------------------------------
 * Data only. Every string, every timestamp, every camera move lives here, and
 * nothing in this file touches the DOM — so re-cutting the film is editing a
 * list, not rewriting a renderer.
 *
 * WHOSE MEETING THIS IS: a product manager at a venture-backed startup, in the
 * Q3 roadmap review, eleven working days from a board update. That choice is
 * the whole script. The four things that actually go wrong in that room are:
 *
 *   1. a date is agreed while the step that gates it has no owner;
 *   2. a bet is committed to with no definition of it working;
 *   3. the loudest four accounts get mistaken for the market;
 *   4. all of it is re-argued three weeks later because nobody wrote down
 *      what was decided or why.
 *
 * The film shows the product catching 1-3 while the call is still running, and
 * closing 4 on the way out. A demo about a generic "meeting" would show none of
 * them, which is why this is a roadmap review and not a sales call.
 *
 * HONESTY RULES, asserted by demoFilm.test.js:
 *
 *   * No real company and no real person. The footage carries no on-screen
 *     disclaimer — the interface in it is the real product, and a badge over
 *     the frame was reading as a caveat about the UI rather than the cast.
 *     The page's hidden description still says the meeting is scripted.
 *   * Every blind spot carries a quote that appears verbatim in this file's
 *     transcript. That is the product's own rule — a card that cannot quote the
 *     call is discarded rather than shown — and a demo that breaks it is
 *     advertising a feature the app refuses to ship.
 *   * Menu labels, button titles and status strings are the app's actual
 *     strings. When the app renames something the film is wrong, and a test
 *     that pins the copy is how that gets noticed.
 *
 Coordinates are STAGE pixels, and the app window now fills all 1920x1080 of
 * them — so a stage coordinate is a window coordinate.
 * ========================================================================== */
(function (root) {
  'use strict';

  // MARK: - Stage geometry
  //
  // Mirrors ContentView: sidebar 264pt, assistant 340–460pt, transcript takes
  // the rest. Holding the app's real proportions is what makes the zoom read as
  // a screen recording rather than an illustration of one.

  var STAGE = {
    width: 1920, height: 1080,
    // Full bleed: the app is the frame. See .app-window in film.css.
    window: { x: 0, y: 0, width: 1920, height: 1080 },
    titleBar: 38,
    sidebarWidth: 264,
    assistantWidth: 392
  };

  // MARK: - The meeting

  var MEETING = {
    title: 'Q3 roadmap review — the cut list',
    date: 'Wednesday, Aug 12 · 10:30 AM',
    contextLabel: '3 context sources',
    // The call started at 10:30, so the pill's clock opens at 12:04 and every
    // transcript timestamp below is 10:42:04 plus that line's `at`.
    elapsedAtStart: 724,
    speakers: ['Daniel · CEO', 'Ana · Eng', 'You']
  };

  /* The transcript. `at` is when the line starts arriving; negative values are
     lines already on screen when the film opens. `dur` is how long the caption
     takes to land — roughly speech rate, so the feed keeps pace with a call
     rather than dumping paragraphs.
     `source` is the capture track: 'them' is system audio (cyan), 'you' is the
     microphone (magenta), matching Theme.speakerThem / Theme.speakerYou. Two
     names share the 'them' track because that is what diarization does to one
     stream of remote audio. */
  var TRANSCRIPT = [
    { at: -92, dur: 2.4, source: 'them', speaker: 'Daniel · CEO', time: '10:40:32',
      text: 'Give me two minutes, I am closing the investor update tab.' },
    { at: -85, dur: 2.2, source: 'them', speaker: 'Ana · Eng', time: '10:40:39',
      text: 'No rush. I have the cycle board open if we need issue numbers.' },
    { at: -78, dur: 2.6, source: 'you', speaker: 'You', time: '10:40:46',
      text: 'One hour. The aim is a cut list we all stand behind before the board update.' },
    { at: -72, dur: 2.6, source: 'them', speaker: 'Daniel · CEO', time: '10:40:52',
      text: 'Agreed. I want to be able to say we shipped something that moved activation.' },
    { at: -66, dur: 2.8, source: 'them', speaker: 'Ana · Eng', time: '10:40:58',
      text: 'Flagging early that the platform migration is still in the same cycle as everything else.' },
    { at: -59, dur: 2.6, source: 'you', speaker: 'You', time: '10:41:05',
      text: 'Noted. Let us take the three big asks first and see what survives.' },
    { at: -52, dur: 3.0, source: 'them', speaker: 'Daniel · CEO', time: '10:41:12',
      text: 'The workflow builder is the one I keep hearing about. Three customers raised it last month.' },
    { at: -45, dur: 2.2, source: 'them', speaker: 'Ana · Eng', time: '10:41:19',
      text: 'Four, if you count the one that emailed support.' },
    { at: -38, dur: 3.0, source: 'you', speaker: 'You', time: '10:41:26',
      text: 'Which four? I want to know whether they are in the segment the board deck describes.' },
    { at: -31, dur: 2.2, source: 'them', speaker: 'Daniel · CEO', time: '10:41:33',
      text: 'They are all design partners. I would have to look.' },
    { at: -24, dur: 3.0, source: 'them', speaker: 'Ana · Eng', time: '10:41:40',
      text: 'Either way it is a big build. Six weeks of one engineer, more if the migration slips.' },
    { at: -17, dur: 2.4, source: 'you', speaker: 'You', time: '10:41:47',
      text: 'And the migration still has no owner, right?' },
    { at: -9, dur: 2.8, source: 'them', speaker: 'Ana · Eng', time: '10:41:55',
      text: 'Not formally. I have been doing it around other work.' },

    { at: 1.4, dur: 3.0, source: 'you', speaker: 'You', time: '10:42:05',
      text: 'Before we commit to it — what does success look like for the workflow builder?' },
    { at: 5.2, dur: 3.0, source: 'them', speaker: 'Daniel · CEO', time: '10:42:09',
      text: "we'll know it's working when people are using it" },
    { at: 9.4, dur: 2.8, source: 'you', speaker: 'You', time: '10:42:13',
      text: 'That is the part I want pinned down before it goes on the roadmap.' },
    { at: 13.2, dur: 3.4, source: 'them', speaker: 'Ana · Eng', time: '10:42:17',
      text: 'There is also the design review. It has not been scheduled and it gates the launch.' },
    { at: 18.0, dur: 3.2, source: 'them', speaker: 'Daniel · CEO', time: '10:42:22',
      text: 'We can move fast on that. I would rather not lose the quarter arguing about process.' },
    { at: 22.6, dur: 3.4, source: 'you', speaker: 'You', time: '10:42:27',
      text: 'Understood. And the three asks — all design partners, none from the ICP in the deck?' },
    { at: 27.0, dur: 3.6, source: 'them', speaker: 'Daniel · CEO', time: '10:42:31',
      text: "they're the customers who shout the loudest, and honestly that's who I hear from" },
    { at: 32.2, dur: 3.4, source: 'them', speaker: 'Ana · Eng', time: '10:42:36',
      text: 'Which is fine, but that is four accounts. The activation number comes from everyone else.' },
    { at: 37.6, dur: 3.2, source: 'you', speaker: 'You', time: '10:42:42',
      text: 'Let me pull the commitments together so we are not re-arguing this in three weeks.' }
  ];

  // MARK: - The left rail
  //
  // Act 2. Each entry carries the moment it lands; the section counters read
  // off the same times, so a header count can never disagree with the rows
  // under it. The calendar row and its brief are there before the film opens —
  // they exist before the call does. Everything the CALL produces arrives on
  // camera.

  var FOCUS = {
    at: -1,
    items: [
      { at: -1, kind: 'reminder', tint: 'accent', icon: 'calendar',
        title: 'Q3 roadmap review', detail: 'Now · 4 attendees · board update Aug 27',
        brief: [
          { at: 12.2, text: 'Activation flat six weeks — 11.4% to 11.6%', source: 'Amplitude', read: 'read 2m ago', overdue: true },
          { at: 12.9, text: 'Q3 cycle is 46 issues over capacity', source: 'Linear', read: 'read 2m ago', overdue: false }
        ] },
      { at: 13.4, kind: 'risk', tint: 'red', icon: 'triangle',
        title: 'Design review unbooked', detail: 'Gates the launch they just dated', brief: [] }
    ]
  };

  var CONTEXT = {
    at: 15.4,
    items: [
      { at: 15.6, icon: 'doc', name: 'Board deck v3.pdf', meta: '22 slides · attached' },
      { at: 16.4, icon: 'notion', name: 'Q3 roadmap draft', meta: 'Notion · synced 2m ago' },
      { at: 17.2, icon: 'sheet', name: 'Activation funnel — Aug', meta: 'Amplitude · synced 2m ago' }
    ]
  };

  var HISTORY = {
    at: 17.8,
    items: [
      { at: 18.0, title: 'Customer discovery — wave 3', meta: '4d ago · 268 segments' },
      { at: 18.7, title: 'Sprint 24 planning', meta: '8d ago · 191 segments' },
      { at: 19.4, title: 'Design partner sync', meta: '2w ago · 143 segments' },
      { at: 20.1, title: 'Board prep — dry run', meta: '3w ago · 226 segments' }
    ]
  };

  var LEDGER = {
    at: 20.6,
    items: [
      { at: 20.9, title: 'Activation is the H2 north star', meta: '2026-07-14 · decided', decided: true },
      { at: 21.7, title: 'Mobile app cut from Q3', meta: '2026-07-28 · decided', decided: true },
      { at: 22.5, title: 'Workflow builder — owner unnamed', meta: '2026-08-12 · open', decided: false }
    ]
  };

  var GOAL = {
    at: 13.8,
    text: 'A cut list all three of us stand behind, with a named owner on every bet.'
  };

  // MARK: - Blind spots
  //
  // Act 3, and the reason the film exists. Each card is one of the failures
  // this room produces: a date resting on an unbooked dependency, a bet with no
  // definition of working, and a roadmap set by whoever emails most.
  //
  // `evidence` MUST appear verbatim in TRANSCRIPT above — the app discards a
  // card whose quote is not in the recognised text, and the film holds itself
  // to the same rule. demoFilm.test.js checks every one.

  var BLIND_SPOTS = {
    headingAt: 26.4,
    cards: [
      {
        at: 27.6, kind: 'risk', tint: 'red', label: 'Risk',
        title: 'The launch date rests on a review nobody has booked.',
        evidence: 'It has not been scheduled and it gates the launch.',
        detail: 'Six weeks was named for the build. The one step in it sitting on somebody else’s calendar still has no date.'
      },
      {
        at: 32.7, kind: 'missing', tint: 'cyan', label: 'Missing info',
        title: 'Nothing said so far distinguishes this bet working from it shipping.',
        evidence: "we'll know it's working when people are using it",
        detail: 'Usage cannot fail. No number, no cohort, no date to check it on — and the board update is in eleven working days.'
      },
      {
        at: 38.0, kind: 'hypothesis', tint: 'amber', label: 'Hypothesis',
        title: 'The roadmap is being set by four accounts, not by the market.',
        evidence: "they're the customers who shout the loudest, and honestly that's who I hear from",
        detail: 'All three asks on the table came from design partners. Nobody has checked them against the segment the board deck describes.',
        claim: 'The cohort you hear from and the cohort the activation number comes from are not the same people.',
        cheapTest: '“How many of those four are in the ICP we put in the deck?”',
        cost: 'A quarter spent building for four accounts that were never the market.',
        quoteAt: 39.0, quoteDur: 2.2, testAt: 41.4, costAt: 42.4
      }
    ]
  };

  // MARK: - The assistant
  //
  // Act 4-5. The chips are QuickPrompts.all, in the app's own order, so the
  // grid the viewer sees is the grid they get.

  var PROMPTS = [
    { id: 'agenda', icon: '🗓️', title: 'Current Agenda' },
    { id: 'brainstorm', icon: '💡', title: 'Brainstorm Ideas' },
    { id: 'unresolved', icon: '❓', title: 'Unresolved Issues' },
    { id: 'ask', icon: '🎯', title: 'What To Ask' },
    { id: 'factcheck', icon: '🔎', title: 'Fact Check' },
    { id: 'rhetoric', icon: '🎭', title: 'Rhetoric Check' },
    { id: 'answer-last', icon: '🙋', title: 'Answer Last Question' },
    { id: 'dispute', icon: '🤝', title: 'Resolve Dispute' },
    { id: 'risk', icon: '⚠️', title: 'Risk Assessment' },
    { id: 'advice', icon: '🧭', title: 'Give Advice' },
    { id: 'tasks', icon: '📋', title: 'Tasks Follow-Up' },
    { id: 'decision', icon: '📌', title: 'Log Decision' },
    { id: 'summarize', icon: '📝', title: 'Summarize Call' },
    { id: 'argue', icon: '⚔️', title: 'Argue Against' },
    { id: 'commitments', icon: '🔗', title: 'Open Commitments' }
  ];

  /* Two prompts are run, in this order. Argue Against first, because a co-pilot
     that will attack its OWN finding on request is the thing a product manager
     has never seen a meeting tool do — and because a demo whose only click is
     "make me a task list" is a demo of a to-do app.
     Tasks Follow-Up second, because that is the one whose output can be filed:
     the write-back button exists only when the answer carries task items.

     `hover` has to bracket the POINTER keyframes below — a hover that outlives
     the cursor is a chip lit by nothing — and `active` is how long the chip
     stays lit while the answer it launched is still arriving. */
  var PROMPT_RUNS = [
    { id: 'argue', click: 53.5, hover: { from: 52.4, to: 56.6 }, active: { from: 53.5, to: 70.4 } },
    { id: 'tasks', click: 70.3, hover: { from: 69.6, to: 72.4 }, active: { from: 70.3, to: 79.4 } }
  ];

  /* Argue Against, run on the co-pilot's own conclusion. Deliberately the
     strongest version of the case the blind spots argued against: a tool that
     only ever agrees with itself is a tool nobody checks their thinking with.
     No connector trace here, and that is honest — this prompt reads the call
     and nothing else. */
  var ARGUE = {
    startAt: 58.0,
    lead: 'The strongest case for building it anyway — the three arguments, in the order they would be made.',
    leadDur: 2.4,
    points: [
      { at: 61.0, text: 'Design partners are not noise. They are the only accounts using this deeply enough to know what is missing.' },
      { at: 62.4, text: 'Activation is flat because there is nothing new to activate on. The build is the intervention, not the distraction.' },
      { at: 63.8, text: 'Six weeks of one engineer is recoverable. A quarter of small bets that move nothing is not.' }
    ],
    weakestAt: 65.4,
    weakest: 'Weakest link: all three collapse if those four accounts are outside the ICP — which is still unchecked.',
    doneAt: 66.4,
    // The pane clears when the next prompt runs, exactly as it does in the app.
    clearAt: 70.4
  };

  /* What the assistant does before it writes anything. Grounding is the part
     buyers do not believe, so it is shown running rather than claimed — and
     both apps named here are in MCPCatalog. */
  var TOOL_TRACE = [
    { at: 71.0, text: 'Reading this call — 38 turns' },
    { at: 71.7, text: 'Linear — Q3 cycle, 46 issues' },
    { at: 72.4, text: 'Jira — project “Q3 roadmap”' }
  ];

  var ANSWER = {
    startAt: 73.2,
    lead: 'Four commitments, each tied to the moment it was made. “Unassigned” means nobody was named.',
    leadDur: 2.4,
    tableAt: 76.2,
    tableRowDur: 0.55,
    header: ['Owner', 'Commitment', 'Due', 'Said at'],
    rows: [
      ['Ana', 'Book the design review', 'Aug 19', '10:42:17'],
      ['Unassigned', 'Own the platform migration', 'Aug 15', '10:41:55'],
      ['Daniel', 'Check the four asks against the deck ICP', 'Aug 14', '10:42:31'],
      ['You', 'Define what “working” means before it ships', 'Aug 15', '10:42:13']
    ],
    doneAt: 79.4
  };

  // MARK: - Where it lands
  //
  // Act 6. Two real write paths: the tracker write-back sheet (Linear / Jira /
  // Asana over MCP) and the Sheets export off the share menu. The point of the
  // act is that the commitments leave the call — a decision that lives only in
  // a transcript gets re-argued in three weeks, which is the pain this whole
  // scenario is built around.

  var WRITEBACK = {
    openAt: 85.0,
    trackers: ['Linear', 'Jira', 'Asana'],
    // Jira, already selected. Between the two the film could land on, Jira has
    // the larger installed base in the room this is aimed at — past about fifty
    // people a startup runs Jira or Linear, and Asana skews to marketing and ops
    // rather than to a roadmap. Preselected rather than clicked: the picker
    // still shows all three, so the choice is visible without the film spending
    // a beat making it.
    selected: 'Jira',
    tasks: [
      { title: 'Book the design review', meta: 'Ana · Aug 19', fileAt: 87.8, doneAt: 88.3, ref: 'Created · ROAD-418' },
      { title: 'Own the platform migration', meta: 'Unassigned · Aug 15', fileAt: 89.1, doneAt: 89.6, ref: 'Created · ROAD-419' },
      { title: 'Check the four asks against the deck ICP', meta: 'Daniel · Aug 14', fileAt: 90.3, doneAt: 90.8, ref: 'Created · ROAD-420' },
      { title: 'Define what “working” means before it ships', meta: 'You · Aug 15', fileAt: 91.4, doneAt: 91.9, ref: 'Created · ROAD-421' }
    ],
    doneAt: 93.2,
    closeAt: 93.4
  };

  var SHARE_MENU = {
    openAt: 96.0,
    closeAt: 98.0,
    items: [
      { id: 'copy', icon: 'copy', label: 'Copy this answer' },
      { id: 'dialog', icon: 'copy', label: 'Copy whole dialog' },
      { id: 'docx', icon: 'down', label: 'Word document (.docx)', divider: true },
      { id: 'gdocs', icon: 'doc', label: 'Google Docs' },
      // The app builds this label from the table it found in the answer:
      // GoogleFileExport.Proposal.createSpreadsheet.summary.
      { id: 'sheets', icon: 'table', label: 'Create a spreadsheet “Q3 roadmap — commitments” with 4 rows' },
      { id: 'notion', icon: 'n', label: 'Notion page' }
    ],
    pickAt: 97.6,
    picked: 'sheets'
  };

  var TOASTS = [
    { at: 93.6, dur: 4.2, icon: 'asana', text: '4 tasks created in Jira · Q3 roadmap' },
    { at: 100.4, dur: 5.4, icon: 'sheet', text: 'Sheet created in Drive · “Q3 roadmap — commitments”' }
  ];

  // Long enough to read as work happening. The spinner is the whole answer to
  // "I clicked it and nothing happened".
  var EXPORT_BUSY = { from: 97.8, to: 100.4 };

  /* The rail scrolls, because in the app it is a ScrollView and the sections
     below Co-pilot are genuinely below the fold at 862px of window. Scripted as
     a transform on the rail content rather than a real scrollTop: a transform
     is seekable and stays on the compositor, and a scrollTop would have to be
     re-applied every frame anyway.
     Keyframes are (time, offset in px). It runs down to reach History and the
     Ledger, then back up to park the Co-pilot section under the camera before
     the first blind spot lands, then follows the cards as they stack. */
  var RAIL_SCROLL = [
    { at: 0, y: 0 },
    { at: 15.0, y: 0 },
    { at: 18.6, y: 180 },
    { at: 22.0, y: 380 },
    { at: 23.6, y: 380 },
    { at: 26.0, y: 236 },
    { at: 30.8, y: 236 },
    { at: 36.2, y: 340 },
    { at: 40.0, y: 880 },
    { at: 132, y: 880 }
  ];

  /* Act 7 — Settings. Everything here is the app's own copy, lifted from
     SettingsView.swift: the five tabs, the section titles, and the sentence
     about never switching to cloud without being told to. This act exists
     because the two objections a product manager at a venture-backed startup
     actually raises are "what can it reach" and "where does my roadmap go",
     and both are answered by a real surface rather than a claim. */
  var SETTINGS = {
    openAt: 105.8,
    closeAt: 120.1,
    tabs: [
      { id: 'general', label: 'General' },
      { id: 'transcription', label: 'Transcription' },
      { id: 'ai', label: 'AI' },
      { id: 'apps', label: 'Connected Apps' },
      { id: 'privacy', label: 'Account & Privacy' }
    ],
    // Which panel is up, and from when. The pointer clicks the tab a beat
    // earlier; these are the times the panel actually changes.
    panels: [
      { id: 'apps', from: 105.8 },
      { id: 'privacy', from: 111.2 },
      { id: 'transcription', from: 115.6 }
    ],
    // MCPCatalog.swift, in its own order. `on` is what this workspace has
    // connected — a grid where everything is lit is a screenshot, not a setup.
    apps: [
      { at: 106.2, name: 'Google Calendar', on: true },
      { at: 106.3, name: 'Google Drive', on: true },
      { at: 106.5, name: 'Linear', on: true },
      { at: 106.6, name: 'Atlassian · Jira', on: true },
      { at: 106.8, name: 'Notion', on: true },
      { at: 106.9, name: 'Amplitude', on: true },
      { at: 107.1, name: 'Attio', on: false },
      { at: 107.2, name: 'Asana', on: false },
      { at: 107.4, name: 'Fireflies', on: false },
      { at: 107.5, name: 'HubSpot', on: false },
      { at: 107.7, name: 'Intercom', on: false },
      { at: 107.8, name: 'PostHog', on: false },
      { at: 108.0, name: 'Sentry', on: false },
      { at: 108.1, name: 'Mixpanel', on: false },
      { at: 108.3, name: 'Zoom', on: false },
      { at: 108.4, name: 'Gmail', on: false }
    ],
    appsCaption: '6 connected · every request needs the app you point it at',
    privacy: {
      section: 'Remove secrets before sending',
      rows: [
        { at: 111.6, label: 'Filter outbound requests', toggle: true,
          note: 'Card numbers, API keys and labelled credentials are stripped from anything sent to a provider. The request is never blocked — the secret is removed and the rest is sent.' },
        { at: 112.6, label: 'Also remove these terms', toggle: null,
          note: 'Project code names, client names — one per line. Removed wherever they appear.',
          terms: ['Northwind', 'Project Halyard', 'workflow builder'] }
      ]
    },
    transcription: {
      section: 'On-device model',
      rows: [
        { at: 116.0, label: 'Whisper Large v3 Turbo', toggle: null,
          note: 'Sized to this Mac. Model changes apply on your next recording.' },
        { at: 117.0, label: 'Adaptive performance', toggle: true,
          note: 'If captions repeatedly fall behind, Cruxwing selects the next lighter validated local model for the next recording. At Base, it can offer Deepgram, but never switches to cloud without your choice.' },
        { at: 118.2, label: 'Custom vocabulary', toggle: null,
          note: '12 terms active',
          terms: ['RICE', 'ARR', 'ICP', 'activation', 'north star', 'design partner'] }
      ]
    }
  };

  // MARK: - Camera
  //
  // `hold` is how long a shot sits still before the move to the next begins.
  // Shots are chosen so nothing the viewer has to READ is ever moving: the rail
  // stops before the first card lands, and the answer stops before it streams.

  /* One camera, two tracks, and a hard rule about EDGES: a frame edge lands
     in a gap, never through a control, and never off the stage. The bands, in
     stage pixels, measured:

       title bar          0..38    (traffic lights 13..25)
       capture meta     134..180   (System / You / level meter — sidebar only)
       hairline + gap   180..197   (edge target: 186)
       prompt chips     118..414   (rows every 37px; gaps at 147, 184, 221…)

     The test recomputes every edge below from this data, so a shot that slices
     a control or hangs off the stage fails the build. Both regressions that
     forced the rule were found by watching an export — the slowest possible
     test suite. */
  var CAMERA = [
    { at: 0,    x: 960,  y: 540, scale: 1.00, hold: 8.4, drift: 0.05 },
    // top 186: the gap between the capture meta and the Focus label
    { at: 10.6, x: 520,  y: 478, scale: 1.85, hold: 13.0, drift: 0.05 },
    { at: 26.0, x: 540,  y: 486, scale: 1.80, hold: 21.2, drift: 0.06 },
    // Ask payoff: the cheap test sitting in the composer. x 1484 pins the
    // right edge at 1920 (halfW 436 at 2.2); y 835 pins the bottom at 1080.
    { at: 46.9, x: 1484, y: 835, scale: 2.20, hold: 2.6 },
    // top 40, under the title bar; right edge exactly the stage's
    { at: 50.6, x: 1440, y: 310, scale: 2.00, hold: 5.0, drift: 0.04 },
    // top 223, riding the 8px gap between chip rows three and four — drift
    // held to 0.02 so the edge stays inside the gap across the whole hold
    { at: 57.6, x: 1400, y: 515, scale: 1.85, hold: 22.0, drift: 0.02 },
    { at: 83.0, x: 960,  y: 540, scale: 1.65, hold: 11.0, drift: 0.04 },
    // Pull back BEFORE the lateral sweep, and not for style: at 1.90 mid-move
    // the frame's right edge lands at 1794 and slices the chip column, which
    // ends at 1905. At 1.30 the edge reaches 1918 and the column survives the
    // move. Removing this as a "whip" put half-words on screen — the rendered
    // frame at 94.8s showed "Brainstorm", "Give Advi", "Argue Agai" all cut.
    { at: 94.6, x: 1180, y: 420, scale: 1.30, hold: 0 },
    // x 1440, not 1470: the share menu runs to stage 1905, and at 1470 the
    // frame's right edge sat at 1740 — a menu shown half-clipped
    { at: 95.4, x: 1440, y: 310, scale: 2.00, hold: 3.2, drift: 0.02 },
    { at: 100.6, x: 960, y: 540, scale: 1.00, hold: 6.0, drift: 0.03 },
    // y 520: at 1.35 the left edge reaches into the sidebar, so the top edge
    // has to clear the capture meta band there too — 120 does, 140 sliced it
    { at: 108.0, x: 960, y: 520, scale: 1.35, hold: 12.4, drift: 0.04 },
    { at: 122.4, x: 960, y: 540, scale: 1.00, hold: 9.6 }
  ];

  /* The same film for 9:16 — Reels and Stories. Same at/hold grid, so every
     beat lands on the same second; only the framing changes.

     The camera composes into the area ABOVE the format's safe band (film.js
     shortens the viewport), and the two formats compose to different heights —
     so every held shot has TWO top edges to clear: reel = y - 810/scale,
     story = y - 725/scale. The test checks both.

     This works at all because the app is columns: at 1.85 the frame is 584
     stage-pixels wide, a pane rather than a squeezed landscape. The transcript
     is the one pane wider than that, so vertical formats wrap its lines at
     460px (film.css) and the wide shots centre on exactly that block — names
     288..400, text 412..872. The share menu also moves down to 150 in vertical
     formats: at the scale that fits its width, no y clears the title bar in
     both composed heights while reaching a menu that starts at stage 46.

     No Settings act here. Its window is 1180 wide — 0.92x, black bands — and
     ending after the filing act keeps a Reel inside 90 seconds. */
  var CAMERA_VERTICAL = [
    // x 575: the text block is 288..862, and 580 put the frame's left edge
    // exactly on the first glyph — TRANSCRIPT rendered as RANSCRIPT
    { at: 0,    x: 582,  y: 478, scale: 1.85, hold: 8.4, drift: 0.04 },
    // x 246/252: halfW is 540/2.20 = 245.5 and 540/2.15 = 251.2, and the
    // sidebar's first glyphs (КОНТЕКСТ label, card titles) start at stage
    // x≈12 — 260/270 put the left edge at 14.5/18.8 and sliced the К. These
    // hold the edge at 0.5/0.8, inside the window border, left of the text.
    { at: 10.6, x: 246,  y: 410, scale: 2.20, hold: 13.0, drift: 0.05 },
    { at: 26.0, x: 252,  y: 430, scale: 2.15, hold: 21.2, drift: 0.05 },
    // Ask payoff close-up; y 712 = 1080 - 810/2.2 (reel half), composer at
    // stage ~1010 sits inside both composed heights.
    { at: 46.9, x: 1670, y: 712, scale: 2.2, hold: 2.6 },
    // tops: reel 77, story 115 — above the chips, clear of the PROMPTS label
    { at: 50.6, x: 1670, y: 445, scale: 2.20, hold: 5.0 },
    // reel top 186 and story top 227 both land in gaps between chip rows, so
    // no drift here: three percent would walk the edge into a row of pills
    { at: 57.6, x: 1660, y: 572, scale: 2.10, hold: 22.0 },
    { at: 83.0, x: 960,  y: 500, scale: 2.00, hold: 11.0, drift: 0.03 },
    { at: 94.6, x: 1300, y: 478, scale: 1.85, hold: 0 },
    { at: 95.4, x: 1645, y: 470, scale: 2.00, hold: 3.2 },
    { at: 100.6, x: 582, y: 478, scale: 1.85, hold: 6.0, drift: 0.03 }
  ];

  // MARK: - The cursor
  //
  // Keyframes name a DOM target rather than a coordinate: the film's layout is
  // CSS, and a hard-coded pixel would drift the moment a chip changed width and
  // put the pointer beside the button it is supposed to be pressing.

  var POINTER = [
    // The hypothesis card's own Ask: its cheap test goes to the assistant
    // before any prompt chip is touched — the card is not just prose.
    { at: 45.6, target: '#ask-2', dx: -220, dy: 120 },
    { at: 46.2, target: '#ask-2', click: 46.6 },
    { at: 47.4, target: '#ask-2', dx: 12, dy: 26, show: false },

    { at: 50.9, target: '#prompt-argue', dx: -300, dy: 150 },
    { at: 52.9, target: '#prompt-argue', click: 53.5 },
    { at: 55.4, target: '#prompt-argue', dx: 14, dy: 30 },
    { at: 56.6, target: '#prompt-argue', dx: 14, dy: 30, show: false },

    { at: 69.0, target: '#prompt-tasks', dx: -140, dy: 90 },
    { at: 70.0, target: '#prompt-tasks', click: 70.3 },
    { at: 71.6, target: '#prompt-tasks', dx: 14, dy: 30 },
    { at: 72.4, target: '#prompt-tasks', dx: 14, dy: 30, show: false },

    { at: 83.2, target: '#assistant-writeback', dx: -170, dy: 200 },
    { at: 84.6, target: '#assistant-writeback', click: 84.9 },
    { at: 87.6, target: '#file-0', click: 87.8 },
    { at: 88.9, target: '#file-1', click: 89.1 },
    { at: 90.1, target: '#file-2', click: 90.3 },
    { at: 91.2, target: '#file-3', click: 91.4 },
    { at: 93.0, target: '#writeback-done', click: 93.2 },
    { at: 95.8, target: '#assistant-share', click: 96.0 },
    { at: 97.4, target: '#share-sheets', click: 97.6 },
    { at: 98.6, target: '#share-sheets', dx: -60, dy: 140 },
    { at: 99.4, target: '#share-sheets', dx: -60, dy: 140, show: false },

    { at: 104.8, target: '#settings-gear', dx: -70, dy: -170 },
    { at: 105.4, target: '#settings-gear', click: 105.6 },
    { at: 110.9, target: '#tab-privacy', click: 111.2 },
    { at: 115.3, target: '#tab-transcription', click: 115.6 },
    { at: 119.7, target: '#settings-done', click: 119.9 },
    { at: 120.6, target: '#settings-done', dx: -40, dy: 80, show: false }
  ];

  // MARK: - Captions
  //
  // Silent film by design: it plays in an iframe on a landing page, where sound
  // is a liability. The captions carry the argument, one sentence per act, and
  // each one names a thing that goes wrong in a roadmap review.

  var CAPTIONS = [
    { at: 1.2,  dur: 6.0, text: 'A live call. Both sides captured on this Mac.' },
    { at: 11.0, dur: 6.5, text: 'The rail arrives first — Linear, Amplitude, the last four calls.' },
    { at: 27.2, dur: 6.5, text: 'It speaks first — and every card quotes your transcript.' },
    { at: 51.6, dur: 5.0, text: 'One click. No prompt to write.' },
    { at: 58.6, dur: 6.4, text: 'And it will argue against its own finding, if you ask it to.' },
    { at: 73.8, dur: 6.0, text: 'Commitments with owners, dates, and the line each came from.' },
    { at: 84.2, dur: 6.0, text: 'Filed where the work lives, before anyone leaves the call.' },
    { at: 101.2, dur: 3.4, text: 'Nothing here gets re-argued in three weeks.' },
    { at: 106.6, dur: 4.2, text: 'Everything it can reach — and nothing it reaches without you.' },
    { at: 111.8, dur: 4.4, text: 'Your code names never leave this Mac.' },
    { at: 116.2, dur: 6.4, text: 'Transcribed on this Mac. It never switches to cloud on its own.' }
  ];

  var END_CARD = {
    at: 123.4, dur: 8.6,
    line: 'The question nobody in the room asked.',
    // One concrete thing to do, not a slogan. A film that ends on a tagline
    // leaves the viewer with nothing to press.
    sub: 'Free tier on macOS. Runs on your next roadmap review.',
    url: 'cruxwing.ai/download'
  };

  // MARK: - Acts
  //
  // These tile [0, duration] exactly. A gap here is a frozen second in the
  // middle of the film; demoFilm.test.js fails on one.

  var ACTS = [
    { id: 'establish',  at: 0,  dur: 9,  label: 'The call, as it runs' },
    { id: 'rail',       at: 9,  dur: 16, label: 'The left rail fills' },
    { id: 'blindspots', at: 25, dur: 24, label: 'Blind spots' },
    { id: 'prompt',     at: 49, dur: 8,  label: 'One click' },
    { id: 'assistant',  at: 57, dur: 26, label: 'The assistant works' },
    { id: 'actions',    at: 83, dur: 22, label: 'Jira, then Sheets' },
    { id: 'settings',   at: 105, dur: 27, label: 'What it can reach, and what it keeps' }
  ];

  /* Every word of CHROME the set builds — extracted so a translation is one
     file overriding strings, never a fork of the DOM builder. film-set.js has
     no words of its own; when a key is missing here the set renders
     'undefined', which is exactly the loud failure a missing translation
     deserves. */
  var UI = {
    stopLabel: 'Stop',
    system: 'System', you: 'You',
    focus: 'Focus', copilot: 'Co-pilot', context: 'Context',
    history: 'History', ledger: 'Decision Ledger',
    goalKicker: 'Goal', watching: 'Watching for blind spots',
    transcript: 'Transcript', live: 'Live',
    assistant: 'Assistant', prompts: 'Prompts', newChip: 'New',
    budgetName: 'Copilot', budgetLeft: '6.2 h left',
    responseEmpty: 'Pick a prompt, or ask anything about this call.',
    composer: 'Ask about this call…',
    ifWrong: 'If wrong:', copyTest: 'Copy the test', ask: 'Ask',
    sheetTitle: 'Send tasks to a tracker', done: 'Done', file: 'File',
    workApps: 'Work apps', connected: 'Connected', connect: 'Connect',
    unassigned: 'Unassigned'
  };

  root.CruxFilmScene = {
    STAGE: STAGE, MEETING: MEETING, TRANSCRIPT: TRANSCRIPT,
    FOCUS: FOCUS, CONTEXT: CONTEXT, HISTORY: HISTORY, LEDGER: LEDGER, GOAL: GOAL,
    BLIND_SPOTS: BLIND_SPOTS, PROMPTS: PROMPTS, PROMPT_RUNS: PROMPT_RUNS,
    ARGUE: ARGUE, TOOL_TRACE: TOOL_TRACE, ANSWER: ANSWER, WRITEBACK: WRITEBACK,
    SHARE_MENU: SHARE_MENU, TOASTS: TOASTS, EXPORT_BUSY: EXPORT_BUSY,
    SETTINGS: SETTINGS,
    // Ask-beat: at `at` the hypothesis card's cheap test lands in the
    // composer, cleared when the first prompt run starts.
    ASK_BEAT: { at: 46.6, cardIndex: 2 },
    CAMERA: CAMERA, CAMERA_VERTICAL: CAMERA_VERTICAL,
    RAIL_SCROLL: RAIL_SCROLL, POINTER: POINTER,
    CAPTIONS: CAPTIONS, END_CARD: END_CARD,
    ACTS: ACTS,
    UI: UI
  };
}(typeof window !== 'undefined' ? window : globalThis));
