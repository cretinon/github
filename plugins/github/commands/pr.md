---
description: Review a GitHub pull request through the github tools and report its findings
arguments:
  - name: repo
    description: the repository in owner/name form, e.g. cretinon/mcp
    required: true
  - name: number
    description: the number of the pull request
    required: true
---

Review the pull request `{{number}}` of `{{repo}}`. Load the `github:review` skill, and change no file and no pull request.

1. Split `{{repo}}` into `owner` and `repo`, and pass them with `pullNumber: {{number}}`.
2. Read `github__pull_request_read` with `method: get`, then `get_diff`, then `get_files`.
3. Read `method: get_reviews` and `method: get_review_comments`, then `method: get_check_runs` and `method: get_status`.
4. For a red check, name the run through `github__actions_list` with `method: list_workflow_runs`, then the job with `method: list_workflow_jobs`, then the log through `github__get_job_logs`.
5. Report one section per severity, one line per finding: file, line, the problem, the fix. Open with the state of the CI, the number of changed files and the verdicts already given.
6. Write nothing to GitHub: a comment, a review or a merge needs a separate request.
