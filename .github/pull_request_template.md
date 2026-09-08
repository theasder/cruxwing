## What changes and why

<!-- One or two sentences. "Why" matters more than "what": the what is visible
     from the diff. -->

## Checks

- [ ] `cd app && swift test`
- [ ] `cd mvp && swift test`
- [ ] `npm test`

If the change touches a workflow, `Package.resolved`, signing, entitlements, the
legal payload or packaging, describe the effect on releases and follow
[`docs/RELEASING.md`](../docs/RELEASING.md). A pull request must not create, move
or publish a tag or release as a side effect of a check.

## Rules pull requests break against most often

In full in [CONTRIBUTING.md](../CONTRIBUTING.md); the same list is repeated here
briefly, so nobody learns it from a rejection.

- [ ] **Do not claim what does not exist.** If I am adding a connector — I checked
      the vendor's method, address, search parameter and response shape, and cited
      the documentation in a comment.
- [ ] **Every function is covered by a test.** Not "there are tests", but: the test
      fails if the function is broken. I checked that — I broke it and looked.
- [ ] **Tests do not go to the network.** HTTP is passed in from outside, keys go
      into `InMemoryKeychain`.
- [ ] **Nothing paid.** No plans, no limits, no pricing screens.
- [ ] **Local stays local.** New network traffic only as an explicit request to a
      provider or a connected service, described in `SECURITY.md`.
- [ ] **Speed is checked by a separate command.** If I changed search, the lexicon
      or the index — I ran
      `cd app && CRUXWING_PERF=1 swift test --filter Performance`.
      An ordinary run skips those tests.
- [ ] **Secrets live only in the Keychain.** Never in `UserDefaults` and never in
      code. An empty string erases the entry rather than saving emptiness.
- [ ] **Check a guard by mutation, and the mutation too.** I damaged the place under
      test with `python3 scripts/mutaciya.py` and saw the suite go red. The script
      refuses to run when there is nothing to damage: a replacement that never
      found its string leaves the run green, and that reads as a strong check.

<!--
Russian is not required: English is accepted, nobody will turn you away.
An item that does not apply to your change — just tick it, or delete the line.
-->
