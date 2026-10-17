# AGENTS.md

Instructions for coding agents working in this repo.

## Project

**Folio** is a macOS menu bar app that watches `~/Downloads` and `~/Documents` and, using Gemma running locally through Ollama, renames and moves new files into the right place in Documents on its own. Low-confidence files go to a review queue with a notification. A separate Restructure mode reorganises the whole Documents tree with the user's review.

- **Product spec and source of truth:** [IDEA.md](IDEA.md). Read it before starting any task.
- **Challenge context:** [PROBLEM.md](PROBLEM.md)

## Roles

- **Planner:** Claude Code. Writes the spec and the task breakdown and reviews the work.
- **Implementer:** you. Build exactly the task you were given. If the spec is unclear or seems wrong, stop and ask. Don't invent features.

## Hard rules

1. **Never commit unless the user explicitly says so.** Leave the changes in the working tree.
2. When told to commit, use **one-line Conventional Commits, all lowercase, and no co-author trailer or other trailers.**
   - Good: `feat: add settle queue`, `fix: skip icloud placeholders`, `chore: add app icon`
   - Bad: `Feat: Add Settle Queue`, multi-line bodies, `Co-Authored-By: ...`
3. **Do not use the DevRelay MCP tools** (`devrelay-gateway`, any `mcp__devrelay*` tool, or devrelay skills). The planner owns everything DEV/MLH related.
4. **Filesystem safety. These are non-negotiable:**
   - Never delete a user file. Never overwrite one. A name collision gets ` (2)`, ` (3)`, ...
   - Append the move to `moves.jsonl` **before** the move happens.
   - Only read from the watched folders (default `~/Downloads` and `~/Documents`, user-editable, never outside home, never Library or hidden folders); only write inside `~/Documents` (or the folder chosen for a restructure) plus Folio's own `~/Library/Application Support/Folio/`. Excluded folders are never read, filed into or restructured.
   - Model output is untrusted. Every path and name from Gemma is validated in code (resolved, inside `~/Documents`, no `..`, legal characters, original extension kept) before any filesystem call.
   - When testing, point Folio at a fixture folder (`Tests/Fixtures/`) or a temp directory, **never at the real `~/Downloads` or `~/Documents`**.
5. **Privacy invariants:**
   - The only network traffic is to Ollama on `127.0.0.1:11434`. No cloud LLM calls, analytics or telemetry, ever.
   - Never log file contents. Logs hold paths and decisions only.
6. **No placeholders.** If something is blocked (a model won't load, an API doesn't exist), stop and say so. Don't fake output or numbers.

## Session logging (DevRelay)

Every task conversation may be published on DEV as part of the challenge write-up. The planner handles uploads; you never call DevRelay (see Hard rule 3).

- **One task per conversation.** Start the first message with the task ID and title, e.g. `task 03: settle queue`.
- **Assume it's public.** Never paste real file names or contents from the user's Downloads or Documents. Use fixtures.
- **Explain decisions in the chat, not just in code.** When you pick or reject an approach, say why in one line.
- **End with a summary** in this exact shape, with bad news first:
  `done: <task id> · files: <changed files> · tests: <pass/fail> · notes: <open issues or none>`
- **Keep failed attempts.** Don't restart a conversation to hide a dead end.

## Clean code (priority)

- Swift 6 with strict concurrency. No force unwraps (`!`) outside tests, no `try!`.
- Small, pure functions for the logic (settle rules, path validation, collision naming, confidence decision, undo replay). Keep side effects (FSEvents, FileManager, Ollama, notifications) at the edges, in thin types.
- Comment only the _why_, in one line.
- No speculative abstractions: no protocol with one implementation, no config for values that never change, no "for later" scaffolding.
- **No third-party dependencies** without asking. Ollama is called with `URLSession`; everything else is Apple frameworks.
- Handle errors at the edges. If Ollama is down or a file can't be read, queue it and show one line in the menu. The app must never crash.
- Every non-trivial pure function gets one focused test (Swift Testing). Don't write tests for trivial code.
- Match the code that's already here before inventing a new pattern.

## Stack

- Xcode project, macOS app target, SwiftUI `MenuBarExtra`, `LSUIElement = YES`, not sandboxed.
- FSEvents, PDFKit, Vision, `MDItem` (Spotlight metadata), `UNUserNotificationCenter`, `SMAppService`.
- Ollama: `gemma4:e2b` (autonomous), `gemma4:12b` (restructure), `mxbai-embed-large` (corrections). Use the `format` JSON schema for structured output.

## Prompts (Gemma)

- Code computes the facts (folder tree, metadata, extracted text, similar corrections); Gemma only **chooses a name and a folder** and gives a confidence and a one-line reason.
- Gemma picks from the existing Documents folders, or proposes at most one new folder level under an existing one.
- Prototype prompts with `ollama run` against the fixtures, then check them through the app.

## UI

- Native macOS look: system font, SF Symbols, system colours. Light and dark follow the system.
- Plain words for users ("Filed to Finance › Invoices", "Not sure where this goes"), not "confidence 0.62". Model names and timings live under a "For developers" section.
- Menu bar: status (watching / paused / model offline), recent moves with per-item undo, review queue count, Pause, Restructure…, Settings.
- Every action in a notification is also reachable from the menu bar.
