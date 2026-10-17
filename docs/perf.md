# Performance (M3 Pro, 18 GB, macOS 27)

| Metric | Target | Measured |
|---|---|---|
| Ready to filed, warm model, e2b (extract + model) | under 10 s | median 1.4 to 1.9 s, p95 2.2 s |
| Ready to filed, warm model, 12b | under 10 s | median 7.2 s, p95 8.1 s (first file 19 s while loading) |
| Folio idle memory, nothing processed | under 50 MB | 17 MB footprint |
| Folio memory right after OCR and PDF work on 6 files | n/a | 97 MB peak |
| Folio memory one minute after that | under 50 MB | 31 MB |
| CPU while idle | about 0% | 0.0%, 5 threads, 0 idle wakeups per second shown by top |

The 97 MB peak is Vision and PDFKit working; macOS reclaims it within a minute. Model memory belongs to Ollama (e2b about 4.6 GB on disk, 12b 8 GB).
Settle time (60 s) is excluded from the timings. The only periodic work is the 5 s settle poll (only when files are pending), a 15 s Ollama check, and a 2 min correction check.
