# Folio — PRD

Oct 13, 2026 · @Aravind

## Overview

Folio is a macOS menu bar app that files your downloads for you. It watches `~/Downloads` and `~/Documents` (including subfolders, plus any folders you add; you can exclude folders), reads each new file, and renames and moves it into the right place in your Documents tree. Nobody has to approve it. When it isn't sure, it leaves the file alone and sends you a notification asking for review.

It runs Gemma locally through Ollama. Your contracts, invoices, bank statements and IDs never leave the Mac, it costs nothing per file, and because the model is open, Folio learns from your corrections instead of guessing the same way forever.

Built for the DEV Hacktoberfest week 2 challenge, theme "Side Hustle": open-source AI at the core, and something people would pay for.

## Why someone pays for it

Existing AI renamers (Zush and similar) are tools you run: you select files, you click rename. Folio does the work while you're not looking. That's what people pay for: a Downloads folder that stays empty and a Documents tree that stays organised, with no effort and no uploads.

## Goals and non-goals

**Goals**

- A new download ends up correctly named and in the right Documents folder within about 2 minutes, with no clicks.
- Every action can be undone, from the menu bar, in one click.
- Nothing is ever deleted or overwritten.
- Folio gets measurably better after you correct it.
- Fully offline once the models are pulled.

**Non-goals**

- Deleting duplicates or cleaning up junk. Folio only renames and moves.
- Cloud sync, accounts, or anything with a server.
- Windows or Linux.
- Filing folders, app bundles or packages. Single files only.

## Target users and scenarios

| User                | Need                                                   | Scenario                                                                                                    |
| ------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Freelancer          | Invoices, contracts and client files findable at tax time | Downloads `invoice (3).pdf` from Stripe; a minute later it's `Documents/Finance/Invoices/Stripe Invoice 2026-10.pdf` |
| Student             | Coursework sorted by course                            | Downloads `lec7.pdf`; Folio reads it and files it under `Documents/College/Computer Networks/Lecture 7 - Routing.pdf` |
| Anyone with a Mac   | Downloads folder that doesn't rot                      | Takes 20 screenshots in a week; they're named by what's on screen and filed                                  |

## Two modes

### Autonomous (always on)

1. FSEvents reports a new or changed file in `~/Downloads` or the top level of `~/Documents`.
2. **Settle:** wait until the file hasn't changed for 60 s. Skip hidden files, partial downloads (`.crdownload`, `.download`, `.part`), iCloud placeholders (`.icloud`), folders and packages.
3. **Extract context:**
   - Text: PDFKit for PDFs, plain read for text and Markdown, Vision OCR for images and scanned PDFs. Capped at the first ~2,000 characters.
   - Spotlight metadata: `kMDItemWhereFroms` (the URL it was downloaded from), content type, creation date.
   - The Documents folder tree (folders only, 3 levels deep).
   - The 5 most similar past corrections (see below).
4. **Ask `gemma4:e2b`** for structured JSON: `{ name, folder, confidence, reason }`. `folder` must be an existing folder or a new one at most one level below an existing folder.
5. **Validate in code:** folder is inside `~/Documents`; the name is legal and keeps the original extension; on a name collision, add ` (2)`.
6. **Decide:**
   - Confidence ≥ threshold → append to the move log, then rename and move.
   - Below threshold → leave the file where it is and add it to the review queue.
7. **Notify:** one batched notification ("4 files need review") at most every 30 minutes, with **Review** and **Undo last** actions.

### Restructure (on demand)

Started from the menu bar. Uses `gemma4:12b`, because the user is waiting for it.

1. Scan the whole Documents tree and summarise each file (cached by content hash, so a rerun is fast).
2. The model proposes a target tree and where each file goes.
3. **Questions:** where the model is unsure, it asks the user instead of guessing ("Is `Networks/` coursework or work?"). Answers are added to the context for the remaining files.
4. **Review window:** a list of `before → after` with a reason per file. The user can edit or uncheck any row.
5. Apply only what was approved. The whole session is one undo step.

## Learning from corrections

If the user moves or renames a file Folio placed within 7 days, Folio records a correction: `{ summary of the file, Folio's choice, the user's choice }`. Files are tracked by their file resource identifier, which survives a move on the same volume.

For each new file, the 5 most similar corrections (embedding similarity, `mxbai-embed-large`) go into the prompt as examples. No fine-tuning: the prompt is the memory. This is the "why open" story: a closed API could do this too, but only by sending every file summary to a server.

## Safety requirements

Folio moves your files without asking, so these are hard rules:

- **Never delete. Never overwrite.** Collisions get a suffix.
- **Write the log before moving.** If the app crashes mid-move, the log still shows what happened.
- Only touch files inside `~/Downloads` and `~/Documents`. Destinations are always inside `~/Documents`.
- Never touch a file that's still changing or that another app has open for writing.
- Model output is untrusted: code validates every path and name before any filesystem call.
- Undo: last move, last N, everything since a time, or a whole restructure session.
- A **Pause** toggle in the menu bar stops all autonomous moves immediately.

## Technical architecture

```
FSEvents ──► settle queue ──► extract (PDFKit / Vision / Spotlight) ──► Gemma via Ollama ──► validate ──► move + log
                                                                         ▲                       │
                                                       corrections (embeddings)                  └─► review queue ──► notification
```

| Layer         | Choice                                                                                       |
| ------------- | -------------------------------------------------------------------------------------------- |
| App           | Swift 6, SwiftUI `MenuBarExtra`, `LSUIElement` (no Dock icon), not sandboxed                  |
| Watching      | FSEvents (`FSEventStreamCreate`) on Downloads and Documents                                    |
| Extraction    | PDFKit, Vision (`VNRecognizeTextRequest`), `MDItem` for Spotlight metadata                    |
| Model         | Ollama on `127.0.0.1:11434`: `gemma4:e2b` (autonomous), `gemma4:12b` (restructure), JSON schema via `format` |
| Embeddings    | Ollama `mxbai-embed-large`                                                                    |
| Notifications | `UNUserNotificationCenter` with action buttons                                               |
| Launch        | `SMAppService.mainApp` (start at login)                                                       |
| Storage       | `~/Library/Application Support/Folio/`: `moves.jsonl`, `corrections.jsonl`, `review.json`, summary cache |

## Success metrics

| Metric                                                 | Target                     |
| ------------------------------------------------------ | -------------------------- |
| Correct folder on a 50-file test set                   | ≥ 80% of auto-moved files  |
| Wrong auto-moves (moved, but to a wrong place)         | ≤ 5%                       |
| Time from download to filed (excluding settle)         | < 10 s on M3 Pro           |
| Idle memory with no model loaded                       | < 50 MB                    |
| Repeat mistake after a correction (same kind of file)  | 0 on the test set          |
| Data loss                                              | 0                          |

## Milestones

Submissions are due Oct 18, 2026, 11:59 PM PDT.

1. **Oct 13–14, spike + core:** menu bar app, FSEvents + settle queue, extraction, one Gemma call returning valid JSON, move + log + undo. Go/no-go on E2B accuracy against a 50-file test set.
2. **Oct 15, autonomous:** confidence threshold, review queue, batched notifications, pause, launch at login.
3. **Oct 16, corrections:** detect user moves, store corrections, retrieve by similarity, show the before/after on the test set.
4. **Oct 17, restructure:** scan, proposal, questions, review window, session undo. Cut the questions step first if behind.
5. **Oct 18, ship:** run it on a real Downloads folder for a day, record the demo, write the post.

## Risks and open questions

| Risk                                                         | Mitigation                                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Model's self-reported confidence is unreliable               | Also lower confidence in code when text is empty or the folder is new; tune the threshold on the test set |
| E2B too weak to file correctly                               | Fall back to `gemma4:12b` for autonomous and accept slower filing              |
| Moving a file the user just opened breaks the app using it   | 60 s settle and skip files open for writing                                    |
| Restructure on a big Documents folder is slow                | Summary cache by content hash; cap the first run at N files                    |
| Ollama not running                                           | Menu bar shows "Model offline"; files queue until it's back                    |

- [ ] Confirm the deadline and partner categories on the challenge page.
- [x] Naming convention: date last, `Stripe Invoice 2026-10.pdf` (decided Oct 14).
- [x] Confidence threshold: start at 0.6, tune on the test set (decided Oct 14).
- [ ] Who pays and how much (one-time licence? $X)? Needed for the post.
