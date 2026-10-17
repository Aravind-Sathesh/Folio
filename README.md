# Folio

A macOS menu bar app that files your downloads for you. New files in the folders you watch are read on your Mac, renamed and moved into the right folder in Documents by a local Gemma model running in Ollama. Files it isn't sure about wait for your review. Restructure tidies a folder you pick, after you approve every change. Folio never deletes or overwrites anything, and every move can be undone.

## Requirements

- macOS 14 or later, Apple silicon recommended
- [Ollama](https://ollama.com) running, with the models pulled:

```bash
ollama pull gemma4:12b
ollama pull mxbai-embed-large
```

## Build and install

```bash
xcodebuild -project Folio.xcodeproj -scheme Folio -configuration Release -derivedDataPath build build
ditto build/Build/Products/Release/Folio.app /Applications/Folio.app
open /Applications/Folio.app
```

The build is signed with your own development certificate, so it runs on your Mac. Sharing it with others needs a Developer ID certificate and notarization.

## Try it without touching your real folders

```bash
scripts/run-sandbox.sh
```

This runs Folio against `~/FolioSandbox`, a throwaway copy of the test files.

## Repo map

- `Folio/Core`: pure logic (validation, settle rules, undo plans, prompts)
- `Folio/Edges`: FSEvents, Ollama, file moves, logs, notifications
- `Folio/App`, `Folio/UI`: state and SwiftUI windows
- `Tests/Fixtures`: the 50-file eval corpus and markdown edge cases (all invented)
- `docs/`: eval, performance, safety audit and Restructure results
- `IDEA.md`, `TASKS.md`, `AGENTS.md`: spec, task plan, rules for coding agents
