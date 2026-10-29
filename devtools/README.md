# flutter_ai_whisper_devtools

DevTools extension panel for live state inspection and primitive field writes
over the VM Service connection DevTools already holds.

## Enable in an app

1. Add a path `dev_dependency` on this package.
2. Create `devtools_options.yaml` with `flutter_ai_whisper_devtools: true`.
3. Run the app in debug mode and open DevTools → **Extensions**.

See the main [README](../README.md#devtools-extension-panel) for YAML samples.

## Develop

```console
flutter pub get
flutter analyze
flutter test
```

## Ship build output

DevTools loads the precompiled web app from `extension/devtools/build/`:

```console
dart run devtools_extensions build_and_copy --source=. --dest=extension/devtools
```

Commit `extension/devtools/build/` when you want consumers of the path package
to see the panel without rebuilding.
