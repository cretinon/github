---
name: review
description: "Review a GitHub pull request from the editor through the github tools: diff, changed files, reviews, review threads and CI checks, then a structured report. Use when asked to review a pull request, to explain why its checks are red, or to read the review comments of a PR."
---

# Review a pull request

## Gather

Every call takes `owner`, `repo` and `pullNumber`. `github__pull_request_read` also takes the `method`, one call per view.

1. `method: get` returns the title, the state, the base, the head, the mergeable state and the draft flag.
2. `method: get_diff` returns the patch. This is what a review reads.
3. `method: get_files` returns the changed files with their status and their line counts.
4. `method: get_reviews` returns the verdicts already given, `method: get_review_comments` returns the threads. Page the threads with `perPage` and the `after` cursor of the previous page.
5. `method: get_commits` returns the commits of the branch, `method: get_comments` the conversation.
6. `method: get_check_runs` and `method: get_status` return the CI of the head commit.

For a red check, name the run, then read the failing job.

- `github__actions_list` with `method: list_workflow_runs` and the head branch as `workflow_runs_filter.branch`.
- `github__actions_list` with `method: list_workflow_jobs` and the run id as `resource_id`.
- `github__get_job_logs` with that job id, and `tail_lines` to keep the answer short.

## Report

One section per severity, one line per finding: file, line, what is wrong, what to do. Quote the rule or the convention each finding breaks. Open with the state of the CI and the number of changed files.

## Act on the review

The write tools ask first, so name the change and wait for the answer.

- A review: `github__pull_request_review_write`, or `github__add_comment_to_pending_review` for a line comment in a pending one.
- A reply: `github__add_reply_to_pull_request_comment`.
- A merge: `github__merge_pull_request`. Never merge on your own initiative, and never merge a pull request whose checks are red.

## Boundaries

- A review reads; it never edits the code of the branch.
- Never approve a pull request the owner did not ask you to approve.
