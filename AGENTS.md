# This is NOT the Flutter you remember

Flutter, Dart, and every package below move fast, and this project is on the current stable — APIs,
required parameters, and defaults may all differ from your training data.

**Before writing code against a package, read that package's own docs from the resolved version:**

```
~/.pub-cache/hosted/pub.dev/<package>-<version>/     # README.md, CHANGELOG.md, example/
```

`pubspec.lock` tells you which version resolved. `CHANGELOG.md` is the fastest place to see what
broke. Heed deprecation warnings from `flutter analyze` — they are the SDK telling you your habit
is stale.

Packages where remembered APIs are most likely to be wrong:

- **`supabase_flutter`** — auth state stream shape, session persistence, Realtime channel and
  `setAuth` API, and PostgREST filter/`rpc` builders have all changed across majors.
- **`riverpod` / `flutter_riverpod`** — provider syntax, codegen, and `Notifier` vs the old
  `StateNotifier` differ substantially by major version. Check which style this project resolved to
  before writing a provider.
- **`drift`** — table DSL, migration strategy, and generated-code layout change between majors.
  Never hand-edit a `.g.dart`; run the generator.
- **`go_router`** — redirect and route-builder signatures change often.

Do not guess a version constraint into `pubspec.yaml`. Use `flutter pub add <package>`, let it
resolve, then read what it gave you.
