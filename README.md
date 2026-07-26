# ExtraHelper Mobile

Native staff app (iOS + Android) for the ExtraHelper restaurant SaaS. One client of an existing
system — the web app, schema, and RLS policies live in `../extrahelper/`.

**Read first:** `PLANNING.md` (architecture, roadmap) · `CLAUDE.md` (working rules, design system) ·
`TASKS.md` (what's done, what's next) · `AGENTS.md` (package APIs differ from training data).

## Setup

```bash
cp env.example.json env.json     # then fill in the Supabase project values
flutter pub get
```

`env.json` is gitignored. It holds the Supabase URL and the **publishable** key only — RLS is the
gate, and the service role key must never reach a client.

## Run

Config is passed at build time, so **every** run/build command needs the define file:

```bash
flutter run   --dart-define-from-file=env.json                 # attached device
flutter run   --dart-define-from-file=env.json -d <device-id>  # pick a device
flutter build apk    --dart-define-from-file=env.json
flutter build ios    --dart-define-from-file=env.json
```

Omit it and the app throws at startup naming the command it wanted — deliberate, so a missing
config never surfaces later as an opaque network error.

```bash
flutter devices        # list simulators, emulators, attached phones
flutter doctor         # toolchain health
```

## Checks

```bash
dart format .
flutter analyze
flutter test
```

## Toolchain notes

- **CocoaPods is required for iOS.** Without it `supabase_flutter` will not build, and the failure
  doesn't say so plainly. `brew install cocoapods`.
- **Android** needs `cmdline-tools` plus accepted licenses (`flutter doctor --android-licenses`).
  `ANDROID_HOME` is exported from `~/.zshrc`.
- **Offline behaviour must be tested on a real device in airplane mode.** A simulator's network
  stubbing is not the same thing.

## Identifiers

Bundle / application id: `com.extrahelper.app` (both platforms). Changing it later means a new Play
listing and a new iOS app record.
