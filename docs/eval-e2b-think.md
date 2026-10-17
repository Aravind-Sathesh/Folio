# Eval run: gemma4:e2b-think on the 50-file corpus

Time per file (extract + model): median 15.76s, p95 19.32s, max 19.82s

| threshold | correct of auto-moved | wrong of all | auto-moved | queued | wrong auto-moves |
|---|---|---|---|---|---|
| 0.5 | 83% | 16.0% | 46 | 4 | 8 |
| 0.6 | 90% | 8.0% | 42 | 8 | 4 |
| 0.7 | 90% | 8.0% | 42 | 8 | 4 |
| 0.8 | 90% | 8.0% | 42 | 8 | 4 |

Detail at threshold 0.6:

```
files 50: correct 36, acceptable 2, wrong 4, queued 8 (8 rightly, 0 needlessly)
correct of auto-moved 90%, wrong of all 8.0%
  wrong: enrollment_verification.pdf -> College (expected College/Admin)
  wrong: transfer_confirmation.txt -> Finance/Receipts (expected Finance/Banking)
  wrong: scan0003.pdf -> Finance/Invoices (expected Finance/Banking)
  wrong: lumen_invoice_oct.pdf -> Finance/Invoices (expected Finance/Invoices/Work)
```
