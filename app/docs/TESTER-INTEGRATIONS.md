# Integrations: handing over a test build safely

Current as of the test branch of 2026-08-16. This document describes the
boundaries actually implemented in the macOS application. It does not promise
imports the code does not have, and it does not assume secrets are stored in Git.

## The main rule of handing over

A branch or a fork must contain **zero working keys**. "A fork with the keys
already set up" is unsafe and does not technically solve the problem:

- the WEEEK, YouGile, Yandex Tracker, Pachca and Telegram tokens belong to the
  test user or bot and are entered on their Mac in the application's interface;
- the user OAuth tokens for Asana and Google are issued to each tester in the
  browser and saved only in their macOS Keychain;
- only the OAuth client identifier and secret for Asana and Google are needed at
  local build time. They are read from an ignored `app/.env`, not from the branch;
- a built test application carrying such OAuth clients is a controlled artifact
  too. It needs separate test applications at the vendors, a limited set of
  recipients, and rotation after the test.

Values must not be added to `app/.env.example`, the documentation, test fixtures
or commits. Testers must not be handed someone else's Keychain or employees'
personal tokens.

## What is implemented today

| Integration | Implemented scenario | What is required | Where the secret lives |
|---|---|---|---|
| WEEEK | Task search; task creation after confirmation | Access token; numeric project ID for writing only | The tester's Keychain |
| YouGile | Task search; task creation after confirmation | API key; column ID for writing only | The tester's Keychain |
| Yandex Tracker | Task search; task creation after confirmation | OAuth token, organisation ID; queue key for writing only | The tester's Keychain |
| Pachca | Full-text message search, no sending | Personal token with `search:messages` | The tester's Keychain |
| Telegram — supergroups | Receiving new messages and edits, a local archive and search; no sending | A separate bot's token and an allowlist of numeric supergroup IDs | Token and allowlist in the Keychain; messages in the application's local archive |
| Asana | Task search through the official MCP V2; creation after confirmation | The test build's OAuth client and the user's consent in the browser | Client ID/secret only in `app/.env` at build time; OAuth token in the Keychain |
| Google Sheets | Importing a spreadsheet by an explicit link; creating a new spreadsheet from an answer | A Google Desktop OAuth client and the selected Sheets permissions | Client ID/secret only in `app/.env` at build time; OAuth token in the Keychain |
| Google Slides | Reading a presentation by an explicit link | A Google Desktop OAuth client and the Slides permission | As for Sheets |
| Google Forms | Reading questions and responses by an explicit editor link | A Google Desktop OAuth client and two read-only Forms permissions | As for Sheets |
| Jitsi | Detecting a live call and ordinary system-audio/microphone recording | No key needed; macOS permissions | No secret |
| TrueConf | An acoustic heuristic while the official client is running, plus ordinary recording of a live call | No key needed; macOS permissions | No secret |

## Preparing a test build

For Asana and Google the build operator creates **separate test OAuth
applications**. In a disposable or private checkout:

```sh
cd app
umask 077
cp .env.example .env
chmod 600 .env
```

Only the necessary fields are filled in `app/.env`, without quotes, and the file
itself is not sent to testers:

```dotenv
ASANA_CLIENT_ID=<id of the test Asana MCP app>
ASANA_CLIENT_SECRET=<secret of the test Asana MCP app>
GOOGLE_CLIENT_ID=<id of the Google Desktop OAuth client>
GOOGLE_CLIENT_SECRET=<secret of that same Desktop OAuth client>
```

Building the artifact without installing into `/Applications`:

```sh
MEETGPT_NO_INSTALL=1 ./build.sh
open "$PWD/build/cruxwing.app"
```

An ordinary distribution build with `MEETGPT_DIST=1` deliberately scrubs those
four values and is unsuitable for this integration run. A local test build embeds
the OAuth clients in the binary, so it must not be published as a general release.

`build.sh` generates an ignored
`app/Sources/MeetGPT/LocalSecrets.generated.swift`; it does not modify the tracked
`Secrets.swift`. Do not `git add -f` the generated file. It is safer to build such
an artifact in a disposable checkout and then delete the checkout together with
`app/.env`.

WEEEK, YouGile, Yandex Tracker, Pachca and Telegram do not read keys from `.env`.
They cannot be "baked" into a shared build in advance: each tester connects their
own test account through **Settings → Work applications**.

## Telegram — supergroups

### Access

1. Create a **separate test bot** through BotFather. Do not use a bot that already
   has a webhook or another `getUpdates` consumer.
2. Add the bot only to test supergroups.
3. To read ordinary messages, either disable Privacy Mode in BotFather or make the
   bot an administrator of every allowed supergroup.
4. Obtain each supergroup's `message.chat.id` from your own `getUpdates` response
   or from an internal administrative tool. Do not hand a private group's contents
   to a third-party bot just to determine an ID. A supergroup ID usually has the
   negative form `-100…`.

Only a Bot API token and a list of IDs are required; there are no OAuth scopes and
no redirect. The contract: [Telegram Bot API](https://core.telegram.org/bots/api).

### Connecting and the smoke test

1. Open **Settings → Work applications → Work messengers → Telegram —
   supergroups**.
2. Paste the bot token and the allowed supergroup IDs separated by commas, then
   press **Check and save**. The check rejects a wrong token, a webhook
   already in use, an unknown chat, and a bot that cannot see messages because of
   Privacy Mode.
3. After connecting, send a new text message with a unique marker to an allowed
   supergroup. Do not use an old message as the test.
4. Wait for the poll and ask a question about the marker. Check the group name, the
   author and, where applicable, the topic ID.
5. Edit the message and confirm that the local result was updated rather than
   duplicated.

The limitations are substantial:

- the Bot API does not hand over old history and cannot search it; the archive
  begins after connecting and fills up while the application receives updates;
- only `supergroup` chats count, not private chats, ordinary groups or channels;
- text and media captions are read, but the files themselves are not downloaded;
- cruxwing does not send messages;
- the allowlist applies both on receipt and in local search.

The token and the allowlist live in the Keychain. The local archive is in the
application's Application Support directory
(`ai.cruxwing.desktop/Telegram/messages.json`) and does not contain the token. The
**Disconnect** button stops polling, deletes the Keychain entries and erases that
archive. The former product's `MeetGPT` directory is not read or imported
automatically.

## Asana MCP V2

### The build's OAuth application

1. Create a separate test **Asana MCP app**.
2. Register the redirect **exactly** as `http://127.0.0.1:52703/callback`.
3. Put the client ID and client secret into `ASANA_CLIENT_ID` and
   `ASANA_CLIENT_SECRET` in the local `app/.env` and rebuild the application.

The official endpoint `https://mcp.asana.com/v2/mcp` and the OAuth resource
`https://mcp.asana.com/v2` are used. The live OAuth metadata advertises the
`default` scope, so the SDK's standard selector usually sends `scope=default`; the
server also tolerates the parameter being absent. This contract offers no granular
Asana scopes. If either half of the build credential is empty, Asana is hidden from
the catalogue rather than showing a button that does not work.

The official contract:
[Integrating with Asana's MCP server](https://developers.asana.com/docs/integrating-with-asanas-mcp-server).

### Connecting and the smoke test

1. Open **Settings → Work applications → Work applications → Asana** and press
   **Connect**.
2. In the browser choose the test workspace and confirm access. The user's OAuth
   token is saved in the Keychain under the versioned namespace `asana-v2`; the
   client secret is not carried there.
3. Check search for a unique test task. The application prefers `search_objects`,
   which is more widely available; `search_tasks` may depend on the workspace's
   plan.
4. In the confirmed creation scenario choose Asana, review the task list, confirm
   creation explicitly and find the result in the test workspace. cruxwing's settings
   have no separate fixed project choice: the permitted fields and the destination
   are determined by the live `create_tasks` schema and the Asana context.

Limitation: the tool list and schema belong to Asana's live MCP server. If a
required tool or field is absent from the test workspace, the application must not
substitute an invented REST contract for it.

## Google Sheets, Slides and Forms

### The build's OAuth application

1. In a separate test Google Cloud project enable **Google Sheets API**,
   **Google Slides API**, **Google Forms API** and **Google Drive API**. The Drive
   API is needed by the scenario that creates a new spreadsheet, but broad Drive
   reading is not granted.
2. Configure the OAuth consent screen. For an External application in Testing
   status, add the testers' addresses to **Test users**.
3. Create an OAuth client of type **Desktop app** and record its values in
   `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` of the local `app/.env`.
4. No fixed redirect is registered in the Google Cloud Console. On each attempt the
   application raises a local callback of the form
   `http://127.0.0.1:<random port 49500–64500>/callback` and uses PKCE.

Before connecting, enable only the switches you need under **Settings → Work
applications → Google**. A full run needs:

| Service | Requested OAuth scopes | The actual boundary |
|---|---|---|
| Sheets | `spreadsheets.readonly`, `drive.file` | Read the specified spreadsheet; create and maintain only files the application created |
| Slides | `presentations.readonly` | Read only the presentation whose ID was explicitly pasted |
| Forms | `forms.body.readonly`, `forms.responses.readonly` | Read the structure and responses of the explicitly specified form only |

`drive.readonly` and `drive.metadata.readonly` are not requested. There is no
global search or enumeration of files on Drive. After changing the switches, or
after updating an old build, press **Reconnect**, otherwise the old refresh
token will not receive the new permissions.

### Sheets smoke test

1. Connect Google in the browser.
2. In the side panel choose **Context → Add → Google Sheet…** and paste the
   link to a test spreadsheet.
3. Check the title and the values from the first sheet in the range `A1:Z1000`.
4. Get an answer containing a Markdown table, confirm the export to a new Google
   Sheet, check the created file, and then check the undo action, which moves the
   application-created file to the trash.

### Slides smoke test

1. Choose **Context → Add → Google Slides…** and paste an explicit
   `/presentation/d/<id>/…` link.
2. Check slide boundaries, visible text, tables and speaker notes.

Slides imports at most 80,000 characters. OCR of images, video, diagrams with no
textual representation, and writing into a presentation are not implemented.

### Forms smoke test

1. Create a synthetic form and a few synthetic responses. Do not use real
   questionnaires or real feedback on the first run.
2. Choose **Context → Add → Google Form + responses…** and paste an editor link
   of the form `/forms/d/<formId>/edit`.
3. Check question titles, answers and submission times. The service field
   `respondentEmail` must be removed before the model context; an email remains
   only if the respondent typed it themselves as an answer to a visible question on
   the form.
4. Separately check that a public link of the form `/forms/d/e/…` is rejected: it
   contains no API form ID.

Forms imports at most 100 responses by default with pagination; the internal hard
limit is 500 and the overall text limit is 80,000 characters. For a File upload
answer only the filenames are taken; the files themselves are not downloaded. A
Forms import may include personal data, so the test must use a permitted synthetic
form.

Google's OAuth access and refresh tokens live in the Keychain. Only non-secret
flags for the selected and granted services remain in `UserDefaults`.

## Jitsi and TrueConf: live calls only

These are not meeting-history connectors. What is implemented is
platform-independent recording of system audio and the microphone, plus a heuristic
detection of a live call:

- Jitsi is recognised when the official native client `org.jitsi.jitsi-meet`
  activates, and by a `Jitsi Meet` marker in a supported browser's window;
- TrueConf goes only through an acoustic heuristic: the official client
  `org.trueconf.client` must be running, and macOS must report that the system
  microphone is in use. Simply bringing the client to the foreground is not enough;
- after detection the application offers to start recording. Starting a recording
  by hand remains the fallback and the control path.

No API key, OAuth scopes or redirect are needed for this feature. On first launch
macOS must be granted **Screen Recording** and **Microphone** permissions; after
changing permissions the application usually has to be restarted.

The smoke test for each service:

1. Open a test call with two audio sources.
2. Confirm that a recording notification/offer appears with the correct service
   name.
3. Start recording, say a unique phrase into the local microphone and a second one
   from the remote side.
4. Stop the recording and confirm both fragments are in the transcript. This tests
   the integration boundary better than the window detector alone.

Jitsi and TrueConf history, the list of past conferences, participants and
server-side recordings are not imported at present. For TrueConf a shared cloud
endpoint must not be guessed: before such work the owner has to supply the URL of
**their own TrueConf Server**, after which the contract and available methods are
verified in that specific server's documentation at `<server-url>/api/v4/docs`.
Only then can a read-only account be chosen and history implemented. Until that
point there is nowhere — and no need — to enter a TrueConf server token in cruxwing.

## The shared acceptance checklist

- [ ] `git status` and `git diff` contain no `.env`, no tokens and no filled-in
  values; `LocalSecrets.generated.swift` stays ignored.
- [ ] Every test runs on synthetic data and separate test
  users/projects/chats.
- [ ] A connection survives an application restart: the runtime token is read from
  the Keychain, not from the branch.
- [ ] The read-only configuration works without a destination field on the
  trackers.
- [ ] Every write to WEEEK, YouGile, Yandex Tracker or Asana requires an explicit
  confirmation and lands only in the test destination.
- [ ] The Telegram check and a confirmed write to a tracker show an authorization
  error on a wrong or revoked token.
- [ ] A known limitation is recorded in the report: read-side grounding skips a
  failed source, so a revoked tracker/messenger token can currently produce a
  missing snippet. That must not be written down as a confirmed "nothing was found
  in the service".
- [ ] Disconnecting an integration removes the local token; for Telegram it also
  erases the local archive.
- [ ] After disconnection, a repeated search no longer uses the source.

## Revocation and cleanup after the test

First press **Disconnect** on each integration in cruxwing. That deletes the local
Keychain entries; for Google a best-effort revocation of the refresh token is
additionally performed, and for Telegram the archive is erased. Then finish the
cleanup at the vendor:

- **WEEEK:** delete the access token and the synthetic tasks/project.
- **YouGile:** delete the API key through `DELETE /api-v2/auth/keys/{key}` and
  delete the test tasks.
- **Yandex Tracker:** revoke the OAuth token / test OAuth application and delete
  the test queue's tasks.
- **Pachca:** delete the personal API token and the test messages, if the
  workspace's policy allows it.
- **Telegram:** remove the bot from the supergroups; in BotFather revoke the token
  or delete the test bot.
- **Asana:** remove the application's authorization from the tester's account,
  remove the test users' access to the workspace and rotate the test MCP app's
  secret.
- **Google:** remove the application's access in the Google Account, remove the
  test users, delete the synthetic Sheets/Slides/Forms and rotate the Desktop
  client secret.
- **Jitsi/TrueConf:** there are no keys; delete the test recordings from cruxwing. On
  a dedicated test Mac, remove the Screen Recording and Microphone permissions in
  System Settings if needed.

Finally, delete `app/.env` and the disposable checkout. Deleting `.env` does not
scrub an already-built binary: the test `.app`, the zip/dmg and every copy of them
must also be deleted or replaced by a build without the OAuth clients.
