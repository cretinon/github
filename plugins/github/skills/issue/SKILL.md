---
name: issue
description: "Read a GitHub issue and the comments of its thread through the github tools, then report it in a fixed order. Use when asked what an issue says, to read or summarise one issue of a repository, or to show its labels, comments and URL."
---

## MANDATORY

If any tool, CLI, command line or anything fails while loading or running this skill: stop immediately and report the failure to the user.

# Read an issue

## Inputs

- `{{repo}}` (required): the repository in `owner/name` form.
- `{{number}}` (required): the number of the issue.

Read the issue `{{number}}` of `{{repo}}`. Load the `github:triage` skill, and change nothing on GitHub.

1. Split `{{repo}}` into `owner` and `repo`, and pass them with `issue_number: {{number}}`.
2. Read `github__issue_read` with `method: get`, then `method: get_comments`, then `method: get_labels`.
3. Read `method: get_sub_issues` and `method: get_parent` when the issue carries a hierarchy.
4. Report in this order: number and title, state, author and date, labels, one line per comment in order, then the URL.
5. Say whether the item is an issue or a pull request, since GitHub serves both from these endpoints.
6. Comment, edit or close nothing: any of those needs a separate request, and it asks before it runs.
