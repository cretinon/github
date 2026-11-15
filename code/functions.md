# `lib_github.sh` — Function Reference

This document describes every function defined in `lib_github.sh`.

> **General conventions**
> - Functions whose name starts with a single underscore (e.g. `_github_commit_cell`) are library functions.
> - Every instrumented function calls `_func_start` at its entry point and `_func_end "<code>" ; return <code>` before **every** return, keeping the `FUNC_LIST` telemetry stack balanced.
> - Exit code `0` means success, `1` means generic error/failure, and `10` (`ERROR_ARGV`) means argument/validation error.
> - The library needs the shell runtime (`lib_shell.sh` of the `shell` project) and the `git` helpers it carries.

---

## Globals & Configuration

### `GITHUB_COMMIT_ROOT`
1. **Description:** Directory holding the managed projects, one subdirectory per project name.
2. **Usage:** Default `MCP_COMMIT_ROOT` when it is set, else `$MY_GIT_DIR`; `GITHUB_COMMIT_ROOT` itself wins over both, and each is overridable via the environment.
3. **Returns:** N/A (variable).

### `GITHUB_COMMIT_CONF`
1. **Description:** Configuration file supplying `MCP_COMMIT_PROJECTS` and `MCP_COMMIT_FETCH_TIMEOUT`, sourced at load time. The list stays in one place, shared with the `mcp` tools.
2. **Usage:** Default `$MY_GIT_DIR/mcp/conf/mcp.conf`; overridable via the environment.
3. **Returns:** N/A (variable).

### `GITHUB_OTEL_ENDPOINT`, `GITHUB_OTEL_SERVICE`, `GITHUB_COMMIT_HOST`
1. **Description:** Where the records go: the base URL of the OTLP/HTTP collector, the `service.name` the records carry, and the `host.name` they carry.
2. **Usage:** Defaults are the receiver of the fleet for the endpoint, `commit-status` for the service and the name of the machine for the host; each is overridable via the environment.
3. **Returns:** N/A (variables).
## Commit status helpers

### `_github_projects`
1. **Description:** Echoes the projects the status covers, the space-separated form of `MCP_COMMIT_PROJECTS` (a comma-separated value is accepted too), read from `GITHUB_COMMIT_CONF` at load time.
2. **Usage:**
   - `_github_projects` -> `ma-emacs mcp rc shell`
3. **Returns:**
   - `0` — the list echoed on stdout
   - `1` — `MCP_COMMIT_PROJECTS` is not set

### `_github_token`
1. **Description:** Echoes `AI_GITHUB_TOKEN` when it is shaped like a token, and nothing otherwise, so a malformed value never reaches a fetch nor the REST API.
2. **Usage:**
   - `_github_token` -> `ghp_xxx`
3. **Returns:**
   - `0` — the usable token, or an empty line

### `_github_commit_cell`
1. **Description:** Echoes the commit cell of a git directory: `clean` when `git status --porcelain` prints nothing, else `N changed path(s)`.
2. **Usage:**
   - `_github_commit_cell "/root/git/mcp"` -> `2 changed path(s)`
   - `$1` — directory of the git repository
3. **Returns:**
   - `0` — the cell echoed on stdout
   - `10` (`ERROR_ARGV`) — `DIR` empty

### `_github_push_cell`
1. **Description:** Echoes the push cell of a git directory: `no upstream` when the branch tracks none, else `N commit(s) to push` when the branch is ahead, else `up to date`.
2. **Usage:**
   - `_github_push_cell "/root/git/mcp"` -> `up to date`
   - `$1` — directory of the git repository
3. **Returns:**
   - `0` — the cell echoed on stdout
   - `10` (`ERROR_ARGV`) — `DIR` empty

### `_github_behind_cell`
1. **Description:** Echoes the behind cell of a git directory, after a real bounded `git fetch` of its remote: `up to date`, `N commit(s) behind`, `no upstream`, or `fetch failed` / `fetch failed (timeout)` / `fetch failed (token)` when the remote could not be read.
2. **Usage:**
   - `_github_behind_cell "/root/git/mcp" "$AI_GITHUB_TOKEN"` -> `up to date`
   - `$1` — directory of the git repository
   - `$2` — optional GitHub token authenticating the fetch
3. **Returns:**
   - `0` — the cell echoed on stdout
   - `10` (`ERROR_ARGV`) — `DIR` empty

### `_github_issues_cell`
1. **Description:** Echoes the open-issues cell of a git directory: the count from the GitHub REST API, `-` when the `origin` remote is not a GitHub one, `failed (token)` without a usable token (no request is made then), or `failed` when the count failed.
2. **Usage:**
   - `_github_issues_cell "/root/git/mcp" "$AI_GITHUB_TOKEN"` -> `3`
   - `$1` — directory of the git repository
   - `$2` — optional GitHub token
3. **Returns:**
   - `0` — the cell echoed on stdout
   - `10` (`ERROR_ARGV`) — `DIR` empty

### `_github_status`
1. **Description:** Echoes one `project|commit|push|behind|issues` line per managed project, a missing or non-git directory giving a `SKIP` row whose other cells are `-`.
2. **Usage:**
   - `_github_status "$AI_GITHUB_TOKEN"` -> `mcp|clean|up to date|up to date|3`
   - `$1` — optional GitHub token used by the fetch and the issue count
3. **Returns:**
   - `0` — the lines echoed on stdout, none of them ending with a newline
   - `1` — the project list is not configured

### `_github_send`
1. **Description:** Sends one OTLP log record to the collector of `GITHUB_OTEL_ENDPOINT`: `notification.title` is the project and the body is the four cells, packed as `commit | push | behind | issues`.
2. **Usage:**
   - `_github_send "mcp" "clean | up to date | up to date | 3"`
   - `$1` — project name
   - `$2` — the four cells, already joined
3. **Returns:**
   - `0` — the record was accepted by the collector
   - `10` (`ERROR_ARGV`) — `PROJECT` or `CELLS` empty
   - other — the code `_send_otel_notification` returned

---

## Commit status

### `_commit_status`
1. **Description:** Prints the per-project status as a markdown table, one row per managed project with its commit status, its push status, its behind status (after a real fetch) and its open GitHub issues, then sends one OTLP log record per project so the `Commit status` dashboard shows the same table.
2. **Usage:**
   - `my_warp.sh --lib github commit_status`
3. **Returns:**
   - `0` — the table was printed and every record was accepted
   - `1` — the table was printed but at least one record was refused, or the project list is not configured

### `_process_lib_github`
1. **Description:** Routes the orchestrator calls to the github lib commands. The getopt string puts the options first, then `--`, then the command.
2. **Usage:**
   - `_process_lib_github "-- commit_status"` — what `my_warp.sh --lib github commit_status` calls
3. **Returns:**
   - `0` — the command succeeded
   - `1` — the command failed, is unknown, or none was given
