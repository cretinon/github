# github (ECA plugin)

Personal ECA plugin for GitHub: the hosted GitHub MCP server, five skills and a read-only review sub-agent.

## Components

| Path | Role |
|------|------|
| `eca.json` | MCP server `github`, hosted at `https://api.githubcopilot.com/mcp/` with the token header and `X-MCP-Toolsets: all`, plus the allow list that pre-approves the read tools |
| `skills/query/` | search and read repositories, code, commits, files and releases |
| `skills/triage/` | read, list and act on issues |
| `skills/issue/` | read one issue, its comments, its labels and its hierarchy |
| `skills/review/` | review a pull request, its reviews, its threads and its checks |
| `skills/troubleshoot/` | diagnose the plugin: the verify block, the endpoint probe, the journal, no series |
| `agents/github-reviewer.md` | read-only pull request and issue reviewer |
| `rules/` | empty on purpose: this plugin scopes no file of another service |
| `hooks/hooks.json` | empty on purpose: no hook |

## Usage

- Skills are namespaced: `/github:query`, `/github:triage`, `/github:issue`, `/github:review`, `/github:troubleshoot`.
- `/github:review <owner/name> <number>` reviews a pull request: diff, changed files, review threads, CI.
- `/github:issue <owner/name> <number>` reads one issue: comments, labels, hierarchy, URL.
- Sub-agent: `github-reviewer` in the agent picker.
- Tools: one name per tool of the server, prefixed `github__`, e.g. `github__pull_request_read`, `github__issue_read`, `github__search_code`.
- The read tools run without a prompt. Every write asks: a comment, a review, a merge, an issue write, a file push.
- Three read tools stay out of the allow list, and so out of the prompt: `find_duplicate` needs the `duplicate_detection` feature flag, and `issue_artifact_read` and `issue_dependency_read` have no snapshot upstream. A live `tools/list` adds one of them once the server offers it.

## Requirements

- `GITHUB_PERSONAL_ACCESS_TOKEN` in the environment of the ECA process, read through `${env:GITHUB_PERSONAL_ACCESS_TOKEN}`. A classic PAT is expected: the server hides the tools whose scopes it lacks.
- `api.githubcopilot.com` reachable over HTTPS.
- Nothing to install: the server is hosted, so `install/github_mcp.yaml` verifies the manifest instead of installing a package.

## Egress

Every call carries the token to `api.githubcopilot.com`, and the server calls `api.github.com` on your behalf. A read is a read; a write is public on the repository, which is why the allow list pre-approves none of them.

## Sources

- https://github.com/github/github-mcp-server
- https://docs.github.com/en/copilot/how-tos/provide-context/use-mcp/set-up-the-github-mcp-server
- https://eca.dev/config/tools/
