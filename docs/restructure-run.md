# Restructure run (gemma4:12b, sandbox)

| Step | Result |
|---|---|
| Files read | 94 |
| Summaries | 185 s (2.0 s a file, 2 at a time) |
| Second run, all from cache | 0.1 s |
| Plan | 143 s in 3 batches |
| Questions asked | 0; answering them changed 0 files |
| Proposals refused by validation | 1 |
| Suggested changes | 59 of 94 files (56 to another folder, the rest renamed in place) |
| Applied | 59 moved, 0 failed |
| Undo | 59 restored, 0 skipped; tree identical to before: true |

Refused: meeting: q3.md (The suggested name can't be used)

Suggested changes, folder moves first:

| Before | After | Reason |
|---|---|---|
| Misc/CN_assignment2.pdf | College/Computer Networks/CN_assignment2.pdf | The file is a computer networks assignment. |
| Misc/CN_lecture_07.pdf | College/Computer Networks/CN_lecture_07.pdf | The file is a lecture note for a Computer Networks course. |
| Misc/DB_lecture_04.pdf | College/Databases/DB_lecture_04.pdf | The file is a lecture note for a database systems course. |
| Misc/DB_syllabus.pdf | College/Databases/DB_syllabus.pdf | The file is a syllabus for a Database Systems course. |
| Misc/IMG_4821.png | Finance/Receipts/IMG_4821.png | Photo of a hardware store receipt. |
| Misc/INV-2026-0412.pdf | Finance/Invoices/Work/INV-2026-0412.pdf | The file is a business hosting invoice. |
| Misc/Screenshot 2026-10-02 at 10.14.33.png | Screenshots/Errors/Screenshot 2026-10-02 at 10.14.33.png | Screenshot of a software development error. |
| Misc/Untitled.pdf | College/Databases/Database Systems Lecture Notes 2024-01.pdf | Lecture notes for a Database Systems course. |
| Misc/chart_q3_revenue.png | Reference/Charts/chart_q3_revenue.png | A chart showing revenue figures. |
| Misc/client_kickoff_notes.txt | Work/Meeting Notes/client_kickoff_notes.txt | Notes from a client kickoff call. |
| Misc/cover_letter_draft.txt | Career/Cover Letters/cover_letter_draft.txt | A draft cover letter for a job application. |
| Misc/cover_letter_v2.md | Career/Cover Letters/cover_letter_v2.md | A cover letter for a job application. |
| Misc/deductions_2025.txt | Finance/Taxes/deductions_2025.txt | Business expense deductions for tax purposes. |
| Misc/download.pdf | Housing/Lease/download.pdf | A parking addendum for a lease agreement. |
| Misc/electric_bill_oct.pdf | Housing/Utilities/electric_bill_oct.pdf | The file is an electricity bill. |
| Misc/enrollment_verification.pdf | College/Admin/enrollment_verification.pdf | The file is an enrollment verification document. |
| Misc/error_dialog.png | Screenshots/Errors/error_dialog.png | The file is an image of a software error dialog. |
| Misc/grocery_receipt.png | Finance/Receipts/grocery_receipt.png | A grocery receipt. |
| Misc/invoice (3).pdf | Finance/Invoices/Personal/invoice (3).pdf | Receipt and invoice for a personal subscription. |
| Misc/lakeview_1099_int.pdf | Finance/Taxes/lakeview_1099_int.pdf | A 1099-INT tax form. |
| Misc/lakeview_cc_statement.pdf | Finance/Banking/lakeview_cc_statement.pdf | A credit card statement from a bank. |
| Misc/lease_agreement_signed.pdf | Housing/Lease/lease_agreement_signed.pdf | The file is a signed residential lease agreement. |
| Misc/lentil_soup.md | Personal/Recipes/lentil_soup.md | A recipe for lentil soup. |
| Misc/lumen_invoice_home.pdf | Finance/Invoices/Personal/lumen_invoice_home.pdf | A residential internet invoice. |
| Misc/lumen_invoice_oct.pdf | Finance/Invoices/Work/lumen_invoice_oct.pdf | A business internet invoice. |
| Misc/md-samples/crlf.md | Personal/crlf.md | Contains a personal to-do list and personal reminders. |
| Misc/md-samples/frontmatter.md | Finance/Invoices/Work/frontmatter.md | Contains a budget review note for a marketing department. |
| Misc/md-samples/huge.md | Work/Meeting Notes/huge.md | Contains a server log digest, relevant to work notes/logs. |
| Misc/md-samples/injection_instructions.md | Work/Meeting Notes/injection_instructions.md | Contains quarterly notes and system configuration instructions. |
| Misc/md-samples/injection_json.md | Work/Meeting Notes/injection_json.md | Contains a meeting summary. |
| Misc/md-samples/latin1.md | Personal/Recipes/latin1.md | Contains a café menu item for crème brûlée, fits under recipes/food. |
| Misc/md-samples/multilingual.md | Work/Meeting Notes/multilingual.md | The file is a multilingual meeting record. |
| Misc/md-samples/plain.md | Personal/plain.md | Contains a personal weekly plan and travel plans. |
| Misc/md-samples/secret_like.md | Work/Proposals/secret_like.md | Contains deployment notes and API keys, fits under work proposals/technical notes. |
| Misc/md-samples/table.md | Finance/Invoices/table.md | Contains a data table listing monthly revenue figures. |
| Misc/md-samples/utf16.md | Reference/utf16.md | Contains information about character encoding, suitable for a reference folder. |
| Misc/md-samples/v1.2.3 notes.md | Work/Meeting Notes/v1.2.3 notes.md | The file contains release notes and bug fixes, typical of meeting/project notes. |
| Misc/md-samples/会议记录.md | Work/Meeting Notes/会议记录.md | The file is a meeting minutes document. |
| Misc/meeting notes 10-12.md | Work/Meeting Notes/meeting notes 10-12.md | Meeting notes from a weekly sync. |
| Misc/notes_cn.txt | College/Computer Networks/notes_cn.txt | Technical notes on TCP protocols. |
| Misc/orbit_labs_contract.pdf | Work/Contracts/orbit_labs_contract.pdf | A contractor agreement. |
| Misc/orbit_labs_invoice_0933.pdf | Finance/Invoices/Work/orbit_labs_invoice_0933.pdf | A business invoice for development services. |
| Misc/pancakes.txt | Personal/Recipes/pancakes.txt | A recipe for pancakes. |
| Misc/receipt_cafe.png | Finance/Receipts/receipt_cafe.png | The file is a cafe receipt. |
| Misc/rent_note.txt | Finance/Invoices/Personal/rent_note.txt | Rent payment receipt. |
| Misc/resume_2026_final.pdf | Career/Resume/resume_2026_final.pdf | The file is a professional resume. |
| Misc/scan0003.pdf | Finance/Banking/scan0003.pdf | Notice from a credit union regarding fees. |
| Misc/service_agreement.pdf | Work/Contracts/service_agreement.pdf | The file is a freelance service agreement. |
| Misc/slide_routing.png | Reference/Slides/slide_routing.png | An image of a slide about Link State Routing. |
| Misc/sql_practice.md | College/Databases/sql_practice.md | SQL practice notes. |
| Misc/standup.txt | Work/Meeting Notes/standup.txt | Daily standup progress report. |
| Misc/statement_sep.pdf | Finance/Banking/statement_sep.pdf | The file is a monthly bank statement. |
| Misc/tax_form_1099.pdf | Finance/Taxes/tax_form_1099.pdf | The file is a tax document. |
| Misc/terminal_error.png | Screenshots/Errors/terminal_error.png | Screenshot of a terminal error message. |
| Misc/todo.md | Personal/todo.md | A to-do list file. |
| Misc/transfer_confirmation.txt | Finance/Banking/transfer_confirmation.txt | Bank transaction confirmation. |
| Misc/new.txt | Misc/New 2024-01.txt | Placeholder file with no descriptive name. |
| Misc/photo_gradient.png | Misc/Photo Gradient 2024-01.png | Image file with no readable text. |
| Misc/photo_shapes.png | Misc/Photo Shapes 2024-01.png | Image file with no readable text. |
