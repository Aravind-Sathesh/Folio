# Safety audit (task 23)

| Check | Result |
|---|---|
| Delete, trash, replace APIs in app code | None. Only `Mover` calls `moveItem` and `createDirectory` (non-intermediate, validated). Other writes are atomic JSON or the append-only logs inside Folio's support folder. |
| Network | Only `OllamaClient`, hard-coded to 127.0.0.1:11434 and checked on every request. |
| Logging | No `print`, `Logger` or `NSLog` in the app. |
| Force unwraps and `try!` | None in the app. |
| Hostile input | 50+ names and folders (traversal, symlinks, NUL, RTL override, control and zero-width characters, 300-byte names, 1,000-deep folders, absolute and `~` paths, normalisation, case-only collisions) in `HostileInputTests`. All rejected or kept inside Documents. |
| Crash recovery | 20 rounds of 1,500 moves with 59 `kill -9`: no file lost or duplicated, the log always matched the disk. |
| Pause | Checked right before the move; a Pause pressed while the model is thinking holds the file (tested). |
| Prompt injection | Data fenced and neutralised in the prompt; with the real model, e2b followed the injection but validation blocked it. |

## Findings fixed

1. Cached `URL` resource values hid file growth and deletion, so the settle queue emitted files too early. Fixed by reading through a fresh URL.
2. `resolvingSymlinksInPath` strips `/private`, which broke matching with FSEvents paths. Replaced by `realpath`.
3. A crash between "log" and "move" left an intent for a file that never moved, which undo then reported as unrecoverable, and an interrupted undo hid the original from the undo list. Added `MoveLog.reconcile()` at launch and made `failed` entries cancel any kind of intent.
4. The unit tests ran inside the real app, which started watching the real Downloads and Documents. No file was touched (checked), but the app is now inert when it is a test host.
5. Cancelling a request was reported as "model offline"; it is now a cancellation.

## Known limits

- No reliable way to detect another app holding a file open for writing without `lsof`; Folio relies on the 60 s settle and the partial-download rules.
- A name containing a zero-width joiner (for example some emoji sequences) is refused.
- Empty folders left by a restructure are never removed, by design.
