/* ============================================================================
 * Cruxwing demo film — timeline engine
 * ----------------------------------------------------------------------------
 * Every visual in the film is a PURE FUNCTION OF TIME. Nothing here starts a
 * transition, sets a timer, or remembers what frame came before: given `t` in
 * seconds, `seek(t)` renders exactly that frame and no other.
 *
 * That constraint is the whole reason this file exists rather than a stack of
 * CSS keyframes. A CSS animation cannot be seeked, so a recorder has to capture
 * it in real time and hope the machine kept up — which is how product films end
 * up with dropped frames and a re-shoot every time a line of copy changes. A
 * seekable film is captured by a loop that can take as long as it likes per
 * frame, and re-cut in one command.
 *
 * The same property makes the motion testable: an assertion about what is on
 * screen at 31.4s is an assertion about a function call.
 * ========================================================================== */
(function (root) {
  'use strict';

  // MARK: - Scalar helpers

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
  function clamp01(v) { return clamp(v, 0, 1); }
  function lerp(a, b, p) { return a + (b - a) * p; }

  /* Linear progress through a window, clamped at both ends. The most used
     function in the film: "how far into this beat are we". */
  function progress(t, start, duration) {
    if (duration <= 0) return t >= start ? 1 : 0;
    return clamp01((t - start) / duration);
  }

  // MARK: - Easing
  //
  // Named for what they are for, not for their curve. `camera` is the only one
  // eased at both ends — a shot that starts and stops abruptly reads as a cut
  // rather than a move.

  var Ease = {
    linear: function (p) { return p; },
    camera: function (p) { return p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2; },
    // Overshoot-free settle. Cards and rows arrive on this: fast, then a long
    // tail, which is what "placed" looks like as opposed to "flung".
    settle: function (p) { return p === 1 ? 1 : 1 - Math.pow(2, -10 * p); },
    out: function (p) { return 1 - Math.pow(1 - p, 3); },
    in: function (p) { return p * p * p; },
    // Pointer travel. A cursor that eases out only looks dragged; a hand
    // accelerates off the mark and decelerates onto the target.
    pointer: function (p) { return p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2; }
  };

  /* A value that rises, holds, and falls — the shape of every toast, caption
     and click in the film. Returns 0..1..0 across `[at, at+dur]`. */
  function pulse(t, at, dur, rise, fall) {
    rise = rise == null ? 0.28 : rise;
    fall = fall == null ? 0.4 : fall;
    if (t < at || t > at + dur) return 0;
    var up = Ease.out(progress(t, at, rise));
    var down = 1 - Ease.in(progress(t, at + dur - fall, fall));
    return Math.min(up, down);
  }

  // MARK: - Deterministic motion
  //
  // Math.random() is banned in this film: two recordings of the same script
  // have to produce the same file. Anything that needs to look alive — an audio
  // meter, a thinking indicator — reads from this instead. Incommensurable
  // frequencies, so the pattern does not visibly repeat inside a 97s film.

  function noise(t, seed) {
    var s = seed || 0;
    return (Math.sin(t * 2.31 + s * 1.7) * 0.5
          + Math.sin(t * 5.77 + s * 3.1) * 0.3
          + Math.sin(t * 11.13 + s * 0.9) * 0.2);
  }

  /* 0..1 height for one bar of the capture level meter. */
  function meterLevel(t, index, active) {
    if (!active) return 0.06;
    return clamp01(0.42 + noise(t + index * 0.37, index) * 0.4);
  }

  // MARK: - Typing
  //
  // Characters, not words: the transcript is a live caption feed, and a caption
  // feed that arrives a word at a time reads as a chat log.

  function typed(text, p) {
    if (p <= 0) return '';
    if (p >= 1) return text;
    return text.slice(0, Math.round(text.length * p));
  }

  /* Progress for item `i` of `count` inside one window, with neighbours
     overlapping by `overlap` (0 = strictly sequential, 1 = all at once). */
  function stagger(p, i, count, overlap) {
    if (count <= 1) return clamp01(p);
    var lap = overlap == null ? 0.55 : overlap;
    var step = 1 / (count - (count - 1) * lap);
    var start = i * step * (1 - lap);
    return clamp01((p - start) / step);
  }

  // MARK: - Camera
  //
  // The film has one camera: a scale plus a translate on the stage wrapper, so
  // every move is a single compositor-friendly transform. Shots are keyframes
  // of (focus point, scale) in STAGE coordinates; the engine interpolates the
  // two that bracket `t` and converts to a transform that puts the focus point
  // in the middle of the viewport.
  //
  // `hold` is how long a shot sits still before the move to the next one
  // begins. Without it every shot would be in permanent slow drift, and a
  // detail the viewer is meant to read would never stop moving under them.

  /* A held shot still breathes. `drift` is how much the scale creeps across the
     hold — two or three percent, linear so it never announces itself. Locked
     off for twenty seconds a frame reads as a screenshot somebody forgot to
     advance; with drift it reads as a camera. It stays small enough that a
     click during the hold still lands on a still frame. */
  function held(shot, t) {
    var drift = shot.drift || 0;
    if (!drift || !shot.hold) return { x: shot.x, y: shot.y, scale: shot.scale };
    return { x: shot.x, y: shot.y, scale: shot.scale + drift * clamp01((t - shot.at) / shot.hold) };
  }

  function shotAt(t, shots) {
    if (!shots.length) return { x: 0, y: 0, scale: 1 };
    var prev = shots[0];
    for (var i = 0; i < shots.length; i++) {
      var s = shots[i];
      if (t < s.at) {
        var from = prev.at + (prev.hold || 0);
        if (t < from) return held(prev, t);
        var a = held(prev, from);
        var p = Ease.camera(progress(t, from, s.at - from));
        return {
          x: lerp(a.x, s.x, p),
          y: lerp(a.y, s.y, p),
          scale: lerp(a.scale, s.scale, p)
        };
      }
      prev = s;
    }
    return held(prev, t);
  }

  /* Transform for a stage whose transform-origin is 0 0, inside `viewport`.
     Rounded: sub-pixel jitter between frames is invisible on screen and
     expensive in an encoded video, where it turns a static region into one the
     codec has to re-send every frame. */
  function cameraTransform(shot, viewport) {
    var x = viewport.width / 2 - shot.x * shot.scale;
    var y = viewport.height / 2 - shot.y * shot.scale;
    return 'translate3d(' + round(x) + 'px,' + round(y) + 'px,0) scale(' + round(shot.scale, 4) + ')';
  }

  function round(v, places) {
    var f = Math.pow(10, places == null ? 2 : places);
    return Math.round(v * f) / f;
  }

  // MARK: - Pointer path
  //
  // The cursor is the only actor in the film. It exists on screen exactly as
  // long as it is doing something: keyframes carry their own visibility, so a
  // pointer never sits parked in a corner between acts.

  function pointerAt(t, path) {
    var visible = 0, x = 0, y = 0, press = 0;
    for (var i = 0; i < path.length; i++) {
      var k = path[i];
      if (t < k.at) break;
      var next = path[i + 1];
      x = k.x; y = k.y; visible = k.show === false ? 0 : 1;
      if (next && next.show !== false && k.show !== false) {
        var p = Ease.pointer(progress(t, k.at, next.at - k.at));
        x = lerp(k.x, next.x, p);
        y = lerp(k.y, next.y, p);
      }
      if (k.click != null) {
        // 340ms down-and-up. Shorter is invisible at 30fps; longer and the
        // button looks stuck rather than pressed.
        press = Math.max(press, pulse(t, k.click, 0.34, 0.06, 0.2));
      }
    }
    return { x: x, y: y, visible: visible, press: press };
  }

  // MARK: - Timeline

  /* An ordered list of acts. Kept as data so the tests can assert the acts tile
     the film with no gap — a hole in the timeline is a frozen second in the
     middle of the video, and the only other way to find one is to watch the
     whole thing. */
  function Timeline(acts) {
    this.acts = acts.slice().sort(function (a, b) { return a.at - b.at; });
  }

  Timeline.prototype.duration = function () {
    var last = this.acts[this.acts.length - 1];
    return last ? last.at + last.dur : 0;
  };

  Timeline.prototype.actAt = function (t) {
    for (var i = this.acts.length - 1; i >= 0; i--) {
      if (t >= this.acts[i].at) return this.acts[i];
    }
    return this.acts[0];
  };

  /* Where the acts fail to tile [0, duration]. Empty means continuous. */
  Timeline.prototype.gaps = function () {
    var out = [], cursor = 0;
    for (var i = 0; i < this.acts.length; i++) {
      var a = this.acts[i];
      if (a.at > cursor + 0.001) out.push({ from: cursor, to: a.at });
      cursor = Math.max(cursor, a.at + a.dur);
    }
    return out;
  };

  root.CruxFilmEngine = {
    clamp: clamp, clamp01: clamp01, lerp: lerp, round: round,
    progress: progress, pulse: pulse, Ease: Ease,
    noise: noise, meterLevel: meterLevel,
    typed: typed, stagger: stagger,
    shotAt: shotAt, cameraTransform: cameraTransform,
    pointerAt: pointerAt, Timeline: Timeline
  };
}(typeof window !== 'undefined' ? window : globalThis));
