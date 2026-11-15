---
description: Read a GitHub issue and the comments of its thread, then report it
arguments:
  - name: repo
    description: the repository in owner/name form, e.g. cretinon/mcp
    required: true
  - name: number
    description: the number of the issue
    required: true
---

Read the issue `{{number}}` of `{{repo}}`. Load the `github:triage` skill, and change nothing on GitHub.

1. Split `{{repo}}` into `owner` and `repo`, and pass them with `issue_number: {{number}}`.
2. Read `github__issue_read` with `method: get`, then `method: get_comments`, then `method: get_labels`.
3. Read `method: get_sub_issues` and `method: get_parent` when the issue carries a hierarchy.
4. Report in this order: number and title, state, author and date, labels, one line per comment in order, then the URL.
5. Say whether the item is an issue or a pull request, since GitHub serves both from these endpoints.
6. Comment, edit or close nothing: any of those needs a separate request, and it asks before it runs.
