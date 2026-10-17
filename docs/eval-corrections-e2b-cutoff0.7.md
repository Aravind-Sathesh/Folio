# Corrections, before and after (gemma4:e2b, leave-one-out)

14 simulated corrections from the files the model got wrong. Each file was then filed again using only the other files' corrections (similarity cutoff 0.7, up to 5 examples).

| | correct of auto-moved | wrong of all files | wrong auto-moves | queued |
|---|---|---|---|---|
| Before | 68% | 26.0% | 13 | 9 |
| After | 68% | 26.0% | 13 | 9 |

- Fixed by corrections: 1
- Broken by corrections: 1
- Still wrong: 13
- **Repeat mistakes** (same kind of file as an already-corrected one, still wrong): 7 (target 0)

Fixed: INV-2026-0412.pdf

Broken: tax_form_1099.pdf

Repeat mistakes: statement_sep.pdf, deductions_2025.txt, transfer_confirmation.txt, scan0003.pdf, lumen_invoice_oct.pdf, lakeview_cc_statement.pdf, lakeview_1099_int.pdf

Examples injected per file: 1 4 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 3 0 0 0 0 0 2 0 0 0 0 0 0 1 1 2 0 4 3
