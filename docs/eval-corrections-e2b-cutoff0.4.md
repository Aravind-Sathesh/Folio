# Corrections, before and after (gemma4:e2b, leave-one-out)

14 simulated corrections from the files the model got wrong. Each file was then filed again using only the other files' corrections (similarity cutoff 0.4, up to 5 examples).

| | correct of auto-moved | wrong of all files | wrong auto-moves | queued |
|---|---|---|---|---|
| Before | 68% | 26.0% | 13 | 9 |
| After | 80% | 16.0% | 8 | 9 |

- Fixed by corrections: 6
- Broken by corrections: 1
- Still wrong: 8
- **Repeat mistakes** (same kind of file as an already-corrected one, still wrong): 5 (target 0)

Fixed: INV-2026-0412.pdf, service_agreement.pdf, chart_q3_revenue.png, client_kickoff_notes.txt, lumen_invoice_oct.pdf, lakeview_1099_int.pdf

Broken: lumen_invoice_home.pdf

Repeat mistakes: statement_sep.pdf, deductions_2025.txt, transfer_confirmation.txt, scan0003.pdf, lakeview_cc_statement.pdf

Examples injected per file: 5 5 5 5 4 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 1 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5
