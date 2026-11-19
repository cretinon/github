# github

## Project overview

Three goals.

1. **Reach GitHub from the editor**, through the ECA plugin `github`: the hosted GitHub MCP server, its skills and its review sub-agent.
2. **Prove the plugin from outside**, through `install/github_mcp.yaml`, whose `verify` block reads the manifest the plugin starts.
3. **Watch the local projects from one table**, through the `commit_status` command of `code/lib_github.sh`: it prints the commit, push, behind and open-issue status of every managed project, and sends one record per project to VictoriaLogs, which the `Commit status` dashboard of the fleet reads.

The server itself installs nothing: GitHub hosts it. The dashboard reaches Grafana through `install/github_dashboards.yaml`, and the table is filled only when the command is run by hand — nothing schedules it.

## Project layout

| Path | Edit it to... |
|------|---------------|
| `code/lib_github.sh` | change a cell of the status table, the project list source, or where the records are sent |
| `code/bats/tests.bats` | change a test of the library |
| `code/functions.md` | nothing: it is generated from `code/lib_github.sh` |
| `install/github_mcp.yaml` | change the verified url, the headers, the toolsets, or the list of write tools that must stay unapproved |
| `install/github_dashboards.yaml` | change the dashboard path, the folder it lands in, or the checks of the `verify` block |
| `install/dashboards/github.json` | change a panel, a query or a column of the `Commit status` dashboard |
| `.ansible-lint` | change the lint profile of the playbook |
| `.yamllint` | change the YAML style |
| `.env` | nothing: it stays git-ignored and holds no secret |
| `plugins/github/eca.json` | change the server, its headers, or the allow list of pre-approved read tools |
| `plugins/github/skills/<s>/SKILL.md` | change a skill |
| `plugins/github/agents/` | change the review sub-agent |
| `.eca-plugin/marketplace.json` | declare a plugin of this source |
| `~/.config/eca/config.json` | the registration that loads the plugin |

Two playbooks: `install/github_mcp.yaml` verifies the plugin manifest, `install/github_dashboards.yaml` installs the dashboard. The service is a remote endpoint, so the first one has no package, no binary and no version to pin. `/root/git/agents/readfirst/archi.md` classifies this project as a code service: `code/` carries the library and its suite, and the gate is `my_warp.sh --lib github`.

## Prerequisites

On the controller:

- `ansible-core` 2.19 or later, with `ansible-lint` and `yamllint` for the gate
- a GitHub classic PAT with the scopes `repo`, `read:org`, `read:packages`, `workflow`, `project`, `gist` and `notifications`
- that token exported as `GITHUB_PERSONAL_ACCESS_TOKEN` in the environment of the ECA process, which reads it from `.emacs`
- HTTPS access to `api.githubcopilot.com`
- for the status command: `git`, `curl` and `jq` on the machine holding the projects, and `AI_GITHUB_TOKEN` in its environment, the token the fetch and the issue count use

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

## Commit status: the table and the dashboard

The `commit_status` command prints one row per managed project and sends one record per project to the log database of the fleet.

```shell
/root/git/shell/my_warp.sh --lib github commit_status
```

- The project list is not in this repository: the command reads `MCP_COMMIT_PROJECTS` from `mcp/conf/mcp.conf`, so the table and the `mcp` tools cover the same projects.
- Each row holds four cells: the commit status (`clean`, `N changed path(s)`, or `SKIP`), the push status (`up to date`, `N commit(s) to push`, `no upstream`), the behind status after a real `git fetch` (`up to date`, `N commit(s) behind`, `no upstream`, `fetch failed ...`), and the open issues of the GitHub repository (`N`, `N+`, `-` without a GitHub origin, `failed ...`).
- It stages, commits and pushes nothing.
- The records carry `service.name=commit-status`, the project in `notification.title`, and the four cells in the body joined by ` | `.
- The token is `AI_GITHUB_TOKEN`, read from the environment, with `Contents: Read-only` on the repositories it must fetch. A private repository without it reports `fetch failed`, and the issue column says `failed (token)` when the variable is unset.
- A refused record makes the command exit non-zero, after the table has been printed.

The dashboard is called `Commit status`, lives in the `Services` folder, and reads the newest record of each project inside its own time range, one hour back by default.

```shell
ansible-playbook -i /root/git/ansible_old/inventory/tofu/ansible_hosts install/github_dashboards.yaml
```

- Run `/root/git/grafana/install/grafana.yaml` first: it creates the directory and the provider the dashboard is read from.
- The dashboard is served at `http://<grafana guest>:3000/d/commit-status`, within a minute of the copy.
- A table with no row means no run fell inside the time range: run the command, then refresh.
- `--tags verify` checks the installed file alone, on the guest, with no network.

## Use the ECA plugin

| Component | Name |
|-----------|------|
| Skills | `github:query`, `github:triage`, `github:issue`, `github:review`, `github:troubleshoot` |
| Sub-agent | `github-reviewer` |
| MCP server | `github`, tools prefixed `github__` |
| Rules | none: this plugin scopes no file |

1. Declare the source in the top-level `plugins` key of `~/.config/eca/config.json`: `"github-local": {"source": "/root/git/github"}`, and add `"github"` to its `install` list.
2. Restart ECA.
3. `/plugins` shows `github`, and `/github:` lists its skills.

- A skill invoked with arguments expands them into its body: `/github:review owner/repo 42` and `/github:issue owner/repo 42`.
- Read tools run without a prompt. A comment, a review, a merge, an issue write or a file push asks first.
- Ask in plain words: "review PR 12 of cretinon/mcp", "what does issue 7 say on cretinon/shell", "which issues are open on cretinon/github".

## Testing

| File type | Check |
|-----------|-------|
| every playbook | `ansible-playbook --syntax-check`, then `--list-tasks`, then `ansible-lint .` and `yamllint -c .yamllint .` |
| `install/github_mcp.yaml` | `--tags verify` passes and changes nothing |
| `install/github_dashboards.yaml` | `--tags verify` passes on the guest and changes nothing |
| `code/lib_github.sh` | `/root/git/shell/my_warp.sh --lib github -s`, then `-b '<filter>'` |
| every `.json` | `jq empty` |
| each skill and agent | its frontmatter keys are present |
| the plugin content | `skillspector scan . --no-llm` reports no issue, and a file scanned alone stays inside the `SAFE` band |

- The `verify` blocks of the two playbooks are the only place the installation checks live.
- The library gate is the wrapper of the `shell` project, never the raw `bats`, `shellcheck` or `kcov` binary. The full suite and the coverage belong to the review.
- Run the command by hand once after a change: it is the only end-to-end proof that the table and the records agree.

### Probes

The endpoint, from a shell that carries the token. Expect `200`; `401` is a token the shell does not export, `403` a token without the permission of the call.

```shell
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://api.githubcopilot.com/mcp/ -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" -H 'X-MCP-Toolsets: all' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'
```

From ECA, `github__get_me` answers the login of the token: the start, the header and the endpoint proven in one call.
