# AGENTS.md — github

> Standalone repository: not a bash library, so it does not inherit the one of the `shell` repository. Read this file first in every session.
> AGENTS.md, this file, is for AI Agents only and is NOT editable by AI Agents without owner's consent.
> README.md, is for any users and is complementary to this file. The information contained in these two files must not be redundant.

## Project Overview

See README.md

## Project Layout

See README.md

## Decisions

Recorded so a later edit does not silently undo them.

| Decision | Why |
|----------|-----|
| The hosted server, not the local `github-mcp-server` binary | `ideas.md` left the choice open; the hosted endpoint installs nothing, pins nothing and upgrades itself, and the token is its only state. The local binary would add a release to download, a sha to verify and a version to bump |
| `url` and `headers` in `plugins/github/eca.json` | ECA starts a remote server natively, and its `plugins` key is the manifest the loader already reads. `mcp-remote` would add a second dependency to reach the same endpoint |
| `X-MCP-Toolsets: all`, as a header | The owner asked for every toolset, and the header says it in one place. The `/mcp/x/all` path would encode the same choice in the url, where a later reader looks for a hostname and not for a scope |
| A classic PAT, not a fine-grained one | The server hides the tools whose scopes a classic token lacks, so an unusable tool never appears and never fails mid-task. A fine-grained token hides nothing and answers the failure at call time |
| Read tools pre-approved, every write leaving the prompt | `ideas.md` fixes the rule for every plugin. A comment, a review, a merge or a push is public on the repository and cannot be undone quietly |
| The `verify` block reads the disk and never the network | The token lives in `.emacs`, so the shell that runs the gate does not carry it. A live probe in the play would fail for a reason that is not the manifest's, and `--tags verify` would stop being runnable anywhere |
| The live check is `/github:troubleshoot` | It runs the same `--tags verify`, then the endpoint probe from a shell that carries the token. The install and the diagnosis cannot drift apart |
| The play asserts the absence of `command` and of `args` | A leftover stdio entry under the same key starts a second server with the same name, and ECA silently loses the hosted one |
| The play asserts the write tools are absent from the allow list | A rule would have to match a file, and no file of the fleet is in scope of this plugin. The play already runs in the gate, so the invariant costs no new file |
| `github` is a code service: `code/lib_github.sh`, `code/bats/tests.bats` and the `my_warp.sh --lib github` gate | The per-project status is logic of our own: four cells, a bounded fetch, a page-bounded issue count and a SKIP row. It replaced the `commit_status` tool of `mcp`, so it needs the tests that tool had. `ideas.md` now classifies `github` as a code service |
| No timer: the status runs by hand | The projects change when the owner commits, not on a clock. A timer would fetch sixteen remotes and spend a call per repository for nothing, and the record of a run nobody asked for reads like noise in the dashboard |
| The record goes through the collector, packed | `_send_otel_notification` posts OTLP to the receiver of the fleet, which re-exports to VictoriaLogs: the record is stored like every other one. It carries a title and a body only, so the four cells travel in the body, joined by a vertical bar, and the dashboard splits them |
| The dashboard shapes the frame itself, in four transforms | The logs frame carries the status inside its `labels` object, so the panel runs `extractFields` (source `labels`, format `json`) to get the four cells as columns, `sortBy` on `last_run` descending, `groupBy` on `notification.title` with the `first` calculation of every cell to keep one row per project, then `organize` to rename the `… (first)` columns. The LogsQL `extract` pipe is what turns the packed body into those four fields in the first place |
| `organize` carries `renameByName` and nothing else | Its `indexByName` empties the whole frame on Grafana 13: the panel then reads `No data`, with no error anywhere. Column order is the query order, so it needs no index, and the colors come from the field overrides keyed on the pre-rename names (`commit (first)`) |
| The project list stays in `mcp/conf/mcp.conf` | The `mcp` tools and this library cover the same projects, and two lists would drift. `MCP_COMMIT_FETCH_TIMEOUT` stays there for the same reason |
| `rules/` stays empty, with its `.gitkeep` | A plugin rule applies once loaded and is scoped by its own `paths`. No file of the fleet belongs to this service, and a pattern matching nothing loads a rule for no reader |
| Skill names equal their directory: `query`, `triage`, `review`, `troubleshoot` | The loader namespaces a skill by its directory, as `skillspector` does. The skills are reached as `/github:<name>` |
| `troubleshoot` answers "no series" for the third step | The scheme makes the three steps mandatory. A service with no series says so instead of dropping the step |
| `github-reviewer` is read-only, through `disabledTools` | A review reports; the owner writes. Disabling the mutating tools makes the sub-agent read-only by construction, not by instruction |
| The global config disables the `github` server for every other sub-agent | The owner's decision: `github-reviewer` stays the only GitHub reader among the sub-agents |
| The plugin is the only GitHub path for an agent | The owner's decision: the `mcp-bash` issue tools are temporary. `mcp` is out of scope, so nothing here edits them, and nothing here names them as the way to work |
| `.env` stays empty | The token comes from `.emacs` through the environment of ECA, so no secret enters a tracked file and the manifest stays publishable |
| `.gitignore` ignores `.env*`, `.ansible/` and `*.retry` | The scanner reads a `.env` line as a PE3 credential access, which is a false positive but a high one; the glob still ignores every local env file. `.ansible/` and `*.retry` are what `ansible-lint` writes, and both siblings ignore them |
| The one accepted finding is baselined, with its reason | The E1 finding of `https://api.githubcopilot.com/mcp/` is the declared endpoint of the service, in the manifest, the play, the readme and the probe. `.skillspector-baseline.yaml` records it, and a scan with `--baseline` then reports only a new finding |
| The linters exclude the baseline file | SkillSpector writes `.skillspector-baseline.yaml` with its sequence at column 0 and rewrites it that way on every run, so an edit by hand is lost. `.ansible-lint` excludes it and `.yamllint` ignores it, so the gate lints the YAML we write and not the file a tool owns |
| The write guard of the play is a deny list | The read tools stay declared in one place, the manifest. The play only refuses a name it knows to mutate, and that list carries the backward-compatible aliases upstream keeps (`create_issue`, `add_sub_issue`, `create_pull_request_review`, the reaction tools) and the remote-only `create_pull_request_with_copilot`, since a guard that knows the current names alone passes the ones a release renames |
| Three read tools stay out of the allow list | `find_duplicate` ships behind the `duplicate_detection` feature flag, and `issue_artifact_read` and `issue_dependency_read` have no snapshot upstream, so none of them registers with `X-MCP-Toolsets: all`. A pre-approval of a name that never appears proves nothing; add one once a live `tools/list` shows it |

## Invariants

- **Valid JSON everywhere**: `jq empty` passes on every `.json` of the repository. A broken manifest resolves the whole plugin source to nothing.
- **The playbook lint passes**: `ansible-lint .` exits `0` under the `safety` profile of `.ansible-lint`, and `yamllint -c .yamllint .` prints nothing. Both skip `.skillspector-baseline.yaml`, which no ansible tool wrote.
- **`--syntax-check` passes**: `ansible-playbook --syntax-check install/github_mcp.yaml` and `--syntax-check install/github_dashboards.yaml` before every run.
- **`--tags verify` passes and changes nothing**: every task of that block reads, and no task of the play writes.
- **The library gate passes**: `/root/git/shell/my_warp.sh --lib github -s` prints nothing, and its suite runs through `-b '<filter>'`, never a raw binary.
- **The dashboard stays valid**: `jq empty install/dashboards/github.json` passes, every panel id is non-zero and unique, and no panel overlaps another on the 24-column grid.
- **The manifest declares the hosted server alone**: `mcpServers.github` carries the url, the two headers and no `command` and no `args`.
- **The allow list holds read tools only**: every name is prefixed `github__`, and none of the published mutation tools appears. A new read tool is added by name once it answers.
- **The token variable has one spelling**: `GITHUB_PERSONAL_ACCESS_TOKEN`, read as `${env:GITHUB_PERSONAL_ACCESS_TOKEN}` in `eca.json` and named by `github_mcp_token_variable` in the play, which asserts the header of the manifest.
- **No secret in a tracked file**: `.gitignore` ignores every `.env*` file, and a token found in a tracked file is a defect, not a convenience.
- **The agent content scans `SAFE`**: no file of the repository scores above the `SAFE` band, and the only finding left is the E1 of the declared endpoint, recorded in the baseline with its reason. `skillspector scan . --no-llm --baseline .skillspector-baseline.yaml` reports no issue at all.
- **The rules directory stays empty**: the plugin scopes no file of the fleet.

## Prerequisites

See README.md

## Configuration

| Variable | Read by | Purpose |
|----------|---------|---------|
| `GITHUB_PERSONAL_ACCESS_TOKEN` | the ECA process, through `plugins/github/eca.json` | the bearer of the hosted server, and the identity every tool answers with |

- The token is exported by `.emacs` in the account that runs ECA.
- `.env` is sourced from `.bashrc`, git-ignored, and holds no secret.
- The toolsets are configuration, not a variable: they live in the `X-MCP-Toolsets` header of `eca.json`.

## External Access

| Component | Reaches | Through |
|-----------|---------|---------|
| the `github` MCP server | `api.githubcopilot.com` | HTTPS, with the token of `GITHUB_PERSONAL_ACCESS_TOKEN` as a bearer |
| the hosted server | `api.github.com`, on the owner's behalf | the token the bearer carries |
| `install/github_mcp.yaml` | nothing | no network: the verify block reads the disk |
| `install/github_dashboards.yaml` | the `grafana_server` guest | SSH, `ansible.builtin.copy` |
| `code/lib_github.sh` | the remote of each managed project, `api.github.com`, the OTLP receiver of the fleet | `git fetch` with `AI_GITHUB_TOKEN`, `_curl`, `_send_otel_notification` |
| `github__get_job_logs` | the logs of a workflow job, which is the largest body this plugin downloads | the hosted server, with `tail_lines` to bound it |

- The plugin itself reaches no endpoint: only the server dials GitHub.
- A read sends the token and the query. A write sends the content the owner approved.
- The status command reads the projects and sends one record per project: it stages, commits and pushes nothing.

## Documentation

- When editing any md file, NEVER explain how something works but explain HOW TO USE it.
- `README.md` explains the verification and the plugin usage.
- `plugins/github/README.md` lists the components and their requirements.
- The information contained in AGENTS.md and README.md must not be redundant.
- A new plugin component gets a row in the table of `plugins/github/README.md`.
- The playbook carries no comment header: a design decision gets a row in the table above, not a paragraph of YAML comments.
- A skill that acts on GitHub names the tool it calls, as `review` names `github__pull_request_read`.

## Testing

See README.md

## Git Workflow

- Commit only when asked. Never push.
- Stage only the changed files. No `git add .`.
- `.env` is ignored: if it shows up in `git status`, the `.gitignore` regressed.

## Recommendations

1. First run after the registration: `/doctor` reports an `mcpServers` key ECA does not read, and `github__get_me` proves the start, the header and the endpoint at once. Add `"type": "http"` to `eca.json` only if `/doctor` asks for it — nothing in this repository proves that ECA accepts a `url` entry without it.
2. Re-check the tool names after a server release: the hosted endpoint is upgraded by GitHub, and a renamed tool leaves its old name in the allow list as an alias for a while. `github__get_me` plus a `tools/list` from `/github:troubleshoot` settles it.
2. Add a read tool to the allow list only once it answers, and never add a write tool to it: a pre-approved merge is one prompt away from an accident.
3. Check the global ECA config before renaming the plugin or the server: the server name prefixes every tool name quoted by a skill, a command and the sub-agent.
4. Keep the token a classic PAT: a fine-grained one hides nothing, so a missing permission turns into a failure in the middle of a task instead of a tool that is not there.
