# github

## Project overview

Two goals.

1. **Reach GitHub from the editor**, through the ECA plugin `github`: the hosted GitHub MCP server, its skills, its commands and its review sub-agent.
2. **Prove the plugin from outside**, through `install/github_mcp.yaml`, whose `verify` block reads the manifest the plugin starts.

No installation and no monitoring: the server is hosted by GitHub, so nothing lands on the controller, and GitHub exposes no series to this fleet. The project ships no dashboard and no telemetry playbook.

## Project layout

| Path | Edit it to... |
|------|---------------|
| `install/github_mcp.yaml` | change the verified url, the headers, the toolsets, or the list of write tools that must stay unapproved |
| `.ansible-lint` | change the lint profile of the playbook |
| `.yamllint` | change the YAML style |
| `.env` | nothing: it stays git-ignored and holds no secret |
| `plugins/github/eca.json` | change the server, its headers, or the allow list of pre-approved read tools |
| `plugins/github/skills/<s>/SKILL.md` | change a skill |
| `plugins/github/agents/` | change the review sub-agent |
| `plugins/github/commands/` | change a slash command |
| `.skillspector-baseline.yaml` | change the accepted finding, and its reason |
| `.eca-plugin/marketplace.json` | declare a plugin of this source |
| `~/.config/eca/config.json` | the registration that loads the plugin |

One playbook, `install/github_mcp.yaml`. The service is a remote endpoint, so there is no package, no binary and no version to pin: the play verifies the manifest instead of installing anything. `ideas.md` classifies this project as a thin service, with no `code/`, no BATS suite and no wrapper.

## Prerequisites

On the controller:

- `ansible-core` 2.19 or later, with `ansible-lint` and `yamllint` for the gate
- a GitHub classic PAT with the scopes `repo`, `read:org`, `read:packages`, `workflow`, `project`, `gist` and `notifications`
- that token exported as `GITHUB_PERSONAL_ACCESS_TOKEN` in the environment of the ECA process, which reads it from `.emacs`
- HTTPS access to `api.githubcopilot.com`

A classic token is what makes a tool disappear instead of failing: the server hides every tool whose scope the token lacks. A fine-grained token hides nothing and fails at call time.

## Install

Nothing to install: GitHub hosts the server, and ECA dials it with `url` and `headers`.

```shell
ansible-playbook install/github_mcp.yaml
```

- The run reports the endpoint, the toolsets and the token variable, then executes the `verify` block.
- It changes nothing: every task of this play reads.

## Verify the installation

The playbook carries one block, tagged `verify`, and every task of it reads the disk. It needs no token and no network, so it runs from any shell.

```shell
ansible-playbook install/github_mcp.yaml --tags verify
```

- It checks `plugins/github/eca.json` present and parseable.
- It checks `mcpServers.github` for the url, the `Authorization` header naming `GITHUB_PERSONAL_ACCESS_TOKEN`, `X-MCP-Toolsets: all`, and the absence of a `command` and of `args`.
- It checks that the allow list holds `github__` read tools only and none of the published write tools.
- It reports whether the token is set in the running shell, and it fails on none of it.
- The same block is step 1 of `/github:troubleshoot`: the install and the diagnosis cannot drift apart.

## Use the ECA plugin

| Component | Name |
|-----------|------|
| Skills | `github:query`, `github:triage`, `github:review`, `github:troubleshoot` |
| Commands | `github:pr`, `github:issue` |
| Sub-agent | `github-reviewer` |
| MCP server | `github`, tools prefixed `github__` |
| Rules | none: this plugin scopes no file |

1. Declare the source in the top-level `plugins` key of `~/.config/eca/config.json`: `"github-local": {"source": "/root/git/github"}`, and add `"github"` to its `install` list.
2. Restart ECA.
3. `/plugins` shows `github`, and `/github:` lists its skills and its commands.

- Read tools run without a prompt. A comment, a review, a merge, an issue write or a file push asks first.
- Ask in plain words: "review PR 12 of cretinon/mcp", "what does issue 7 say on cretinon/shell", "which issues are open on cretinon/github".

## Testing

| File type | Check |
|-----------|-------|
| every playbook | `ansible-playbook --syntax-check`, then `--list-tasks`, then `ansible-lint .` and `yamllint -c .yamllint .` |
| `install/github_mcp.yaml` | `--tags verify` passes and changes nothing |
| every `.json` | `jq empty` |
| each skill, agent and command | its frontmatter keys are present |
| the plugin content | `skillspector scan . --no-llm --baseline .skillspector-baseline.yaml` reports no issue, and a file scanned alone stays inside the `SAFE` band |

- The `verify` block of `install/github_mcp.yaml` is the only place the checks of the service live.
- `.skillspector-baseline.yaml` records the one accepted finding: the declared endpoint, an E1 "external transmission" on every file that names it. Scan a single file with its own path and that finding reappears, since a fingerprint carries the path of the scan. Add a new finding to the baseline only with its reason.
- No BATS suite and no coverage gate: a thin service carries no library.

### Probes

The endpoint, from a shell that carries the token. Expect `200`; `401` is a token the shell does not export, `403` a token without the permission of the call.

```shell
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://api.githubcopilot.com/mcp/ -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" -H 'X-MCP-Toolsets: all' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'
```

From ECA, `github__get_me` answers the login of the token: the start, the header and the endpoint proven in one call.
