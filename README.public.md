# Cruxwing

**Meeting notes that never leave your Mac.** Records the call, transcribes it on
your machine, and lets you find the exact sentence someone said — with the
timestamp — weeks later.

No bot joins the room. No account. No server. **This build makes no network
request to anything but `127.0.0.1`**, and that is not a promise you have to take
on trust: point a network monitor at it and watch.

---

## Why

Every meeting tool in this category is cloud-first by architecture. Your audio
goes to their servers because that is where the transcription runs. They can
promise care; they cannot promise absence.

Cruxwing transcribes on-device with WhisperKit, stores everything in a local
database, and — if you want answers rather than a search box — talks to a model
you are running yourself. There is no code path to a cloud provider in this
repository. That is the whole point of it.

And the thing it is actually for: when someone says *"I never agreed to that,"*
you find the line, with the time, and play it back. Not a summary. The sentence.

---

## What it does

- **Captures system audio and your microphone** without joining the call.
  Works over Zoom, Meet, Teams, or a conversation in a room —
  `ScreenCaptureKit` for system audio, `AVAudioEngine` for the mic, no virtual
  audio device to install.
- **Transcribes on your machine.** WhisperKit and FluidAudio, with a term
  dictionary you can extend so the words specific to your work stop coming out
  mangled.
- **Searches across every call you have recorded**, and answers with the quote,
  the speaker and the timestamp rather than a paraphrase.
- **Answers questions using a local model, if you run one.** Point it at
  [LM Studio](https://lmstudio.ai) or anything else serving an OpenAI-compatible
  API on loopback. The system prompt is one deliberately boring line — *answer
  from the transcript below and cite the timestamps* — and you can read it in the
  source and change it. There is nothing clever hidden there.

---

## Install

macOS 14 or later, Apple Silicon or Intel. Signed with a Developer ID and
notarized.

```bash
git clone <this repository> cruxwing && cd cruxwing
swift build -c release
```

Swift 6.0+ (Xcode 16+). Optional, for the ask box: LM Studio running with a model
loaded and its local server on — the default address is `http://127.0.0.1:1234`
and you can change it.

Tests: `swift test`. Some measurement checks skip unless real models, recordings
or a quiet machine are available; the reason is printed, and a skip is never
counted as a pass.

---

## What is not true yet

This project has a rule: never claim what you cannot show on screen in thirty
seconds. Applied to itself, that produces this section — read it before you
decide the tool fits your work.

- **Speaker separation is off.** Best measured accuracy is 88.3% against the 90%
  bar we set ourselves, so it ships disabled rather than confidently wrong. Three
  people in a meeting room currently merge into one voice.
- **English accuracy is not measured.** We benchmarked off-the-shelf engines on
  our own fixtures and picked the best one; there is no published English number,
  and we are not going to invent one.
- **Spanish is not supported.** No work has been scoped on it.
- **The language must be set before the call starts.** Switching language
  mid-call breaks the transcript.
- **macOS only.** No Windows build, no mobile app.
- **No certifications.** No SOC 2, HIPAA, SSO or SCIM. If procurement requires
  them, this is not usable for you today, and it is cheaper for both of us to say
  so on the first screen.
- **Not a stealth recorder.** The window is not visible on the other party's
  screen, and that is not permission to hide that you are recording. Several US
  states require all-party consent; in the EU a recording is personal-data
  processing under GDPR. Telling people is on you, and the app will not help you
  avoid it.

---

## Open core, stated on day one

**This repository is the private half, and it is complete.** Capture,
transcription, storage, search, local-model answers — all of it works with
nothing installed but this app and, optionally, a local model. Nothing here
degrades into an upsell, and nothing phones home to check whether you paid.

**The assistant is the commercial half**, and it is not in this repository:
blind-spot scans that tell you what the call is avoiding, agenda and framing
checks, fact-checking against sources, contradiction search across past calls,
decision extraction, drafted follow-ups, connectors to your tracker and wiki, and
managed model access so you do not have to run one yourself. That is
[Cruxwing](https://cruxwing.com) the product, it runs against a backend that
stays closed, and it is how the work here gets paid for.

We are saying this on the first day rather than letting you discover it in three
months. If the open half is all you need, use the open half — that is a fine
outcome and it is why the boundary is drawn here.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues through
[SECURITY.md](SECURITY.md) rather than a public issue — for a program that
listens to meetings, that is the first question anyone should ask, and it
deserves a written answer rather than a paragraph about how seriously we take it.

## Licence

[Mozilla Public License 2.0](LICENSE). File-level copyleft: improvements to this
project's files come back, while your own code beside them can stay closed. MPL
2.0 also carries an express patent grant (section 2.1).
