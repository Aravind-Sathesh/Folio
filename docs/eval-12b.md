# Eval run: gemma4:12b on the 50-file corpus

Time per file (extract + model): median 7.19s, p95 8.09s, max 19.39s

| threshold | correct of auto-moved | wrong of all | auto-moved | queued | wrong auto-moves |
|---|---|---|---|---|---|
| 0.5 | 93% | 6.0% | 44 | 6 | 3 |
| 0.6 | 98% | 2.0% | 42 | 8 | 1 |
| 0.7 | 98% | 2.0% | 42 | 8 | 1 |
| 0.8 | 98% | 2.0% | 42 | 8 | 1 |

Detail at threshold 0.6:

```
files 50: correct 40, acceptable 1, wrong 1, queued 8 (8 rightly, 0 needlessly)
correct of auto-moved 98%, wrong of all 2.0%
  wrong: lakeview_cc_statement.pdf -> Finance/Receipts (expected Finance/Banking)
```
