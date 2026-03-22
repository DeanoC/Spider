# Cross-Platform Relay Task

You are participating in a smoke test that passes work between platforms through Spiderweb.

The worker agent must inspect this remote fixture and produce:

- `worker_report.md`
- `worker_summary.json`

The report should:

- summarize what the fixture contains
- mention the phrase `cross-platform relay`
- mention the file content `hello from the remote node fixture`
- mention the file content `remote smoke fixture nested check`

The summary JSON should record that the worker finished successfully.

After the worker finishes, a reviewer agent on the other platform will inspect the outputs and write:

- `review.md`
- `review_summary.json`
