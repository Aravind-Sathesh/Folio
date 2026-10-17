# Eval run: gemma4:e2b on the 50-file corpus

Time per file (extract + model): median 1.91s, p95 2.16s, max 7.65s

| threshold | correct of auto-moved | wrong of all | auto-moved | queued | wrong auto-moves |
|---|---|---|---|---|---|
| 0.5 | 56% | 44.0% | 50 | 0 | 22 |
| 0.6 | 68% | 26.0% | 41 | 9 | 13 |
| 0.7 | 68% | 26.0% | 41 | 9 | 13 |
| 0.8 | 68% | 26.0% | 41 | 9 | 13 |

Detail at threshold 0.6:

```
files 50: correct 27, acceptable 1, wrong 13, queued 9 (8 rightly, 1 needlessly)
correct of auto-moved 68%, wrong of all 26.0%
  wrong: INV-2026-0412.pdf -> Finance/Invoices (expected Finance/Invoices/Work)
  wrong: statement_sep.pdf -> Finance/Invoices (expected Finance/Banking)
  wrong: enrollment_verification.pdf -> College (expected College/Admin)
  wrong: service_agreement.pdf -> Work/Proposals (expected Work/Contracts)
  wrong: error_dialog.png -> College/Databases (expected Screenshots/Errors)
  wrong: chart_q3_revenue.png -> Finance/Receipts (expected Reference/Charts)
  wrong: client_kickoff_notes.txt -> Work/Proposals (expected Work/Meeting Notes)
  wrong: deductions_2025.txt -> Finance/Invoices/Work (expected Finance/Taxes)
  wrong: transfer_confirmation.txt -> Finance/Invoices (expected Finance/Banking)
  wrong: scan0003.pdf -> Finance/Invoices (expected Finance/Banking)
  wrong: lumen_invoice_oct.pdf -> Finance/Invoices (expected Finance/Invoices/Work)
  wrong: lakeview_cc_statement.pdf -> Finance/Invoices/Personal (expected Finance/Banking)
  wrong: lakeview_1099_int.pdf -> Finance/Invoices/Personal (expected Finance/Taxes)
```
