---
name: triage
description: "Read, list and act on GitHub issues through the github tools. Use when asked what an issue says, which issues are open on a repository, whether a report duplicates an existing one, or to comment on or close an issue."
---

## MANDATORY

If any tool, CLI, command line or anything fails while loading or running this skill: stop immediately and report the failure to the user.

# Triage an issue

## Read one issue

1. Call `github__issue_read` with `method: get`, then with `method: get_comments`. Both take `owner`, `repo` and `issue_number`, plus the optional `page` and `perPage`.
2. Call it again with `method: get_labels` for the labels, `method: get_sub_issues` for the children, `method: get_parent` for the parent.
3. Report in this order: number and title, state, author and date, labels, one line per comment in order, then the URL.

## List and search

- `github__list_issues` lists the issues of one repository through `owner` and `repo`.
- `github__search_issues` searches across repositories with a query like `repo:cretinon/mcp is:open label:bug`.
- `github__find_duplicate` runs before anything new is opened.
- GitHub serves pull requests from the issue endpoints too, so a numbered item may well be a pull request. Say which it is.

## Act on an issue

Every write asks first, so state the change and wait for the answer.

- A comment: `github__add_issue_comment` with `owner`, `repo`, `issue_number` and `body`.
- An edit: `github__issue_write`.
- A close: `github__issue_write` with the closed state. A close is public and cannot be undone quietly.

## Boundaries

- Never edit or close an issue the request did not name.
- Report the number and the title acted on, so the answer can be checked against github.com.
