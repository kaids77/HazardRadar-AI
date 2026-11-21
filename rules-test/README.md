# Firestore rules tests

Automated tests for `../firestore.rules`, run against the local Firestore emulator.
Nothing here touches the live `hazardradarai` project: the emulator uses the demo
project id `demo-hazardradar`.

## Requirements
- Node 20 or newer
- Java 11 or newer (the emulator runs on Java)

`firebase-tools` is installed locally in this folder, so no global install is needed.

## Run
From `hazardradarai/rules-test`:

```powershell
npm install
npm run emulator:test
```

The first run downloads the Firestore emulator (about 60 MB) into
`%USERPROFILE%\.cache\firebase\emulators`.

## Layout
- `test/helpers.js` creates the test environment, signed-in contexts (guest or
  Google-linked), seed data, and a valid incident.
- `test/*.test.js` one file per area: users, incidents, votes.

Every rules change should come with allowed and denied cases here.
