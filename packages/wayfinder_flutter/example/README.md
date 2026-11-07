# Model-free native reader example

The same reader/controller uses an in-memory fixture by default, or a granted
local project selected through a Dart define. No embeddings setup is needed.

The source is runnable on a Linux Flutter host. Generate ignored platform build
scaffolding locally (it is not a supported cross-platform distribution):

```sh
cd packages/wayfinder_flutter/example
flutter create --platforms=linux --project-name wayfinder_reader_example .
flutter pub get
flutter run -d linux
# Or read your own local project without copying it into this repository:
flutter run -d linux --dart-define=WAYFINDER_PROJECT=/absolute/granted/project
```

Keep the supplied pubspec/path overrides when creating platform scaffolding.
Host application teardown closes controller before project. The memory fixture
contains only illustrative content. Local source access is read-only, with
explicit validation-unavailable and no semantic-search control. Widget tests
exercise the actual shared navigation against memory and local backends; they do
not claim interactive/native-window smoke verification.
