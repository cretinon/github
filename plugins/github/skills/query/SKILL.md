---
name: query
description: "Search and read GitHub from the editor through the github tools: repositories, code, commits, files, releases, orgs and users. Use when asked to find code, read a file of a remote repository, list the commits or branches of a repo, or show a release."
---

## MANDATORY

If any tool, CLI, command line or anything fails while loading or running this skill: stop immediately and report the failure to the user.

# Query GitHub

Every tool of this skill is read-only and pre-approved: no call asks. The tool names carry the prefix `github__`.

## Find before reading

1. Call `github__search_repositories` with a query like `org:cretinon mcp in:name`. Take the owner and the repo name from its answer, never from a guess.
2. Call `github__search_code` with a qualified query like `repo:cretinon/mcp my_warp.sh`. GitHub refuses an unqualified code search.
3. Call `github__get_file_contents` with `owner`, `repo` and `path`. Pass `ref` for anything but the default branch.

## Read the history

- `github__list_branches`, `github__list_tags`, `github__get_tag`, `github__list_releases`, `github__get_latest_release` and `github__get_release_by_tag` cover the refs and the releases.
- `github__list_commits` takes a branch or a path, `github__get_commit` takes one `sha`.
- `github__get_repository_tree` takes a `sha` and returns the whole shape of a repository, `github__get_file_blame` names the author of a line range.
- `github__search_commits` takes the same qualified query as the code search.

## Answer

Report in this order: the `owner/repo` and the `ref` used, the value asked for, then the URL of the item on github.com.

## Empty result

An empty answer is not a permission error. Check in order: the query is qualified, the `owner` and `repo` spellings are exact, the `ref` exists, and the token reaches that repository. A classic PAT that lacks a scope makes the server hide the tools of that scope, so a missing `github__` tool is a token question and not a query one.
