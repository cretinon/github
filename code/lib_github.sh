#!/bin/bash

# shellcheck source=/dev/null disable=2001,SC2119,SC2120,SC2294,SC2154

# doc-top: > **General conventions**
# doc-top: > - Functions whose name starts with a single underscore (e.g. `_github_commit_cell`) are library functions.
# doc-top: > - Every instrumented function calls `_func_start` at its entry point and `_func_end "<code>" ; return <code>` before **every** return, keeping the `FUNC_LIST` telemetry stack balanced.
# doc-top: > - Exit code `0` means success, `1` means generic error/failure, and `10` (`ERROR_ARGV`) means argument/validation error.
# doc-top: > - The library needs the shell runtime (`lib_shell.sh` of the `shell` project) and the `git` helpers it carries.
# doc-verbatim: ## Globals & Configuration
# doc-verbatim:
# doc-verbatim: ### `GITHUB_COMMIT_ROOT`
# doc-verbatim: 1. **Description:** Directory holding the managed projects, one subdirectory per project name.
# doc-verbatim: 2. **Usage:** Default `MCP_COMMIT_ROOT` when it is set, else `$MY_GIT_DIR`; `GITHUB_COMMIT_ROOT` itself wins over both, and each is overridable via the environment.
# doc-verbatim: 3. **Returns:** N/A (variable).
# doc-verbatim:
# doc-verbatim: ### `GITHUB_COMMIT_CONF`
# doc-verbatim: 1. **Description:** Configuration file supplying `MCP_COMMIT_PROJECTS` and `MCP_COMMIT_FETCH_TIMEOUT`, sourced at load time. The list stays in one place, shared with the `mcp` tools.
# doc-verbatim: 2. **Usage:** Default `$MY_GIT_DIR/mcp/conf/mcp.conf`; overridable via the environment.
# doc-verbatim: 3. **Returns:** N/A (variable).
# doc-verbatim:
# doc-verbatim: ### `GITHUB_OTEL_ENDPOINT`, `GITHUB_OTEL_SERVICE`, `GITHUB_COMMIT_HOST`
# doc-verbatim: 1. **Description:** Where the records go: the base URL of the OTLP/HTTP collector, the `service.name` the records carry, and the `host.name` they carry.
# doc-verbatim: 2. **Usage:** Defaults are the receiver of the fleet for the endpoint, `commit-status` for the service and the name of the machine for the host; each is overridable via the environment.
# doc-verbatim: 3. **Returns:** N/A (variables).

GITHUB_COMMIT_ROOT="${GITHUB_COMMIT_ROOT:-${MCP_COMMIT_ROOT:-$MY_GIT_DIR}}"
GITHUB_COMMIT_CONF="${GITHUB_COMMIT_CONF:-$MY_GIT_DIR/mcp/conf/mcp.conf}"
GITHUB_OTEL_ENDPOINT="${GITHUB_OTEL_ENDPOINT:-http://192.168.2.202:4318}"
GITHUB_OTEL_SERVICE="${GITHUB_OTEL_SERVICE:-commit-status}"
GITHUB_COMMIT_HOST="${GITHUB_COMMIT_HOST:-$(hostname)}"

if [ -e "$GITHUB_COMMIT_CONF" ]; then source "$GITHUB_COMMIT_CONF"; fi

####################################################################################################
###################################### Commit status helpers #######################################
####################################################################################################
# doc-section: Commit status helpers

# call: _github_projects ()
# description: Echoes the projects the status covers, the space-separated form of `MCP_COMMIT_PROJECTS` (a comma-separated value is accepted too), read from `GITHUB_COMMIT_CONF` at load time.
# example: `_github_projects` -> `ma-emacs mcp rc shell`
# return: `0` — the list echoed on stdout
# return: `1` — `MCP_COMMIT_PROJECTS` is not set
_github_projects () {
    _func_start "$@"

    local __result="${MCP_COMMIT_PROJECTS:-}"

    __result="${__result//,/ }"

    if ! _exist "$__result"; then _error "MCP_COMMIT_PROJECTS: not set (define it in $GITHUB_COMMIT_CONF)" ; _func_end "1" ; return 1 ; fi

    echo "$__result"

    _func_end "0" ; return 0
}

# call: _github_token ()
# description: Echoes `AI_GITHUB_TOKEN` when it is shaped like a token, and nothing otherwise, so a malformed value never reaches a fetch nor the REST API.
# example: `_github_token` -> `ghp_xxx`
# return: `0` — the usable token, or an empty line
_github_token () {
    _func_start ""

    local __result="${AI_GITHUB_TOKEN:-}"

    if ! _git_token_check "$__result"; then __result="" ; fi

    echo "$__result"

    _func_end "0" ; return 0
}

# call: _github_commit_cell ($1:dir)
# description: Echoes the commit cell of a git directory: `clean` when `git status --porcelain` prints nothing, else `N changed path(s)`.
# example: `_github_commit_cell "/root/git/mcp"` -> `2 changed path(s)`
# example: `$1` — directory of the git repository
# return: `0` — the cell echoed on stdout
# return: `10` (`ERROR_ARGV`) — `DIR` empty
_github_commit_cell () {
    _func_start "$@"

    # Check argv
    if ! _exist "$1"; then _error "DIR EMPTY" ; _func_end "$ERROR_ARGV" ; return "$ERROR_ARGV" ; fi

    local __dir="$1"
    local __status
    local __count
    local __result

    __status=$(_git_porcelain_status "$__dir")

    if [ -z "$__status" ]; then
        __result="clean"
    else
        __count=$(printf '%s\n' "$__status" | wc -l | tr -d ' ')
        __result="$__count changed path(s)"
    fi

    echo "$__result"

    _func_end "0" ; return 0
}

# call: _github_push_cell ($1:dir)
# description: Echoes the push cell of a git directory: `no upstream` when the branch tracks none, else `N commit(s) to push` when the branch is ahead, else `up to date`.
# example: `_github_push_cell "/root/git/mcp"` -> `up to date`
# example: `$1` — directory of the git repository
# return: `0` — the cell echoed on stdout
# return: `10` (`ERROR_ARGV`) — `DIR` empty
_github_push_cell () {
    _func_start "$@"

    # Check argv
    if ! _exist "$1"; then _error "DIR EMPTY" ; _func_end "$ERROR_ARGV" ; return "$ERROR_ARGV" ; fi

    local __dir="$1"
    local __upstream
    local __ahead
    local __result

    __upstream=$(_git_upstream "$__dir")

    if [ -z "$__upstream" ]; then
        __result="no upstream"
    else
        __ahead=$(_git_commits_ahead "$__dir")
        if _exist "$__ahead" && [ "$__ahead" -gt 0 ]; then
            __result="$__ahead commit(s) to push"
        else
            __result="up to date"
        fi
    fi

    echo "$__result"

    _func_end "0" ; return 0
}

# call: _github_behind_cell ($1:dir) ($2:token)
# description: Echoes the behind cell of a git directory, after a real bounded `git fetch` of its remote: `up to date`, `N commit(s) behind`, `no upstream`, or `fetch failed` / `fetch failed (timeout)` / `fetch failed (token)` when the remote could not be read.
# example: `_github_behind_cell "/root/git/mcp" "$AI_GITHUB_TOKEN"` -> `up to date`
# example: `$1` — directory of the git repository
# example: `$2` — optional GitHub token authenticating the fetch
# return: `0` — the cell echoed on stdout
# return: `10` (`ERROR_ARGV`) — `DIR` empty
_github_behind_cell () {
    # No argument is logged : `$2` is a GitHub token.
    _func_start ""

    # Check argv
    if ! _exist "$1"; then _error "DIR EMPTY" ; _func_end "$ERROR_ARGV" ; return "$ERROR_ARGV" ; fi

    local __dir="$1"
    local __token="${2:-}"
    local __upstream
    local __behind
    local __result
    local __return=0

    __upstream=$(_git_upstream "$__dir")

    if ! _exist "$__upstream"; then
        __result="no upstream"
    else
        _git_fetch "$__dir" "$__token" "${MCP_COMMIT_FETCH_TIMEOUT:-5}" || __return=$?

        if [ "$__return" -eq 2 ]; then
            __result="fetch failed (timeout)"
        elif [ "$__return" -ne 0 ]; then
            if [ -z "$__token" ] && [ "$__return" -eq 1 ]; then
                __result="fetch failed (token)"
            else
                __result="fetch failed"
            fi
        else
            __behind=$(_git_commits_behind "$__dir")

            if ! _exist "$__behind"; then
                __result="fetch failed"
            elif [ "$__behind" -gt 0 ]; then
                __result="$__behind commit(s) behind"
            else
                __result="up to date"
            fi
        fi
    fi

    echo "$__result"

    _func_end "0" ; return 0
}

# call: _github_issues_cell ($1:dir) ($2:token)
# description: Echoes the open-issues cell of a git directory: the count from the GitHub REST API, `-` when the `origin` remote is not a GitHub one, `failed (token)` without a usable token (no request is made then), or `failed` when the count failed.
# example: `_github_issues_cell "/root/git/mcp" "$AI_GITHUB_TOKEN"` -> `3`
# example: `$1` — directory of the git repository
# example: `$2` — optional GitHub token
# return: `0` — the cell echoed on stdout
# return: `10` (`ERROR_ARGV`) — `DIR` empty
_github_issues_cell () {
    # No argument is logged : `$2` is a GitHub token.
    _func_start ""

    # Check argv
    if ! _exist "$1"; then _error "DIR EMPTY" ; _func_end "$ERROR_ARGV" ; return "$ERROR_ARGV" ; fi

    local LC_ALL=C
    local __dir="$1"
    local __token="${2:-}"
    local __url
    local __repo=""
    local __count
    local __result

    __url=$(_git_remote_url "$__dir" "origin" 2>/dev/null) || __url=""
    __url="${__url%/}"
    __url="${__url%.git}"

    if [[ "$__url" =~ ^[a-z+]*://([^@/]+@)?github\.com(:[0-9]+)?/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)$ ]]; then
        __repo="${BASH_REMATCH[3]}"
    elif [[ "$__url" =~ ^([^@/]+@)?github\.com:([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)$ ]]; then
        __repo="${BASH_REMATCH[2]}"
    fi

    if ! _exist "$__repo"; then
        __result="-"
    elif ! _git_token_check "$__token"; then
        __result="failed (token)"
    else
        __count=$(_git_issue_count "$__repo" "$__token") || __count=""

        if ! _exist "$__count"; then
            __result="failed"
        else
            __result="$__count"
        fi
    fi

    echo "$__result"

    _func_end "0" ; return 0
}

# call: _github_status ($1:token)
# description: Echoes one `project|commit|push|behind|issues` line per managed project, a missing or non-git directory giving a `SKIP` row whose other cells are `-`.
# example: `_github_status "$AI_GITHUB_TOKEN"` -> `mcp|clean|up to date|up to date|3`
# example: `$1` — optional GitHub token used by the fetch and the issue count
# return: `0` — the lines echoed on stdout, none of them ending with a newline
# return: `1` — the project list is not configured
_github_status () {
    # No argument is logged : `$1` is a GitHub token.
    _func_start ""

    local __token="${1:-}"
    local __projects
    local __project
    local __dir
    local __commit
    local __push
    local __behind
    local __issues
    local __return=0
    local __result=""

    __projects=$(_github_projects)
    __return=$?
    if [ "$__return" -ne 0 ]; then _func_end "$__return" ; return "$__return" ; fi

    for __project in $__projects; do
        __dir="$GITHUB_COMMIT_ROOT/$__project"

        if [ ! -d "$__dir" ]; then
            __result="$__result$__project|SKIP (no such directory)|-|-|-"$'\n'
            continue
        fi
        if ! _git_is_work_tree "$__dir"; then
            __result="$__result$__project|SKIP (not a git repository)|-|-|-"$'\n'
            continue
        fi

        __commit=$(_github_commit_cell "$__dir")
        __behind=$(_github_behind_cell "$__dir" "$__token")
        __push=$(_github_push_cell "$__dir")
        __issues=$(_github_issues_cell "$__dir" "$__token")

        __result="$__result$__project|$__commit|$__push|$__behind|$__issues"$'\n'
    done

    echo "${__result%$'\n'}"

    _func_end "0" ; return 0
}

# call: _github_send ($1:project) ($2:cells)
# description: Sends one OTLP log record to the collector of `GITHUB_OTEL_ENDPOINT`: `notification.title` is the project and the body is the four cells, packed as `commit | push | behind | issues`.
# example: `_github_send "mcp" "clean | up to date | up to date | 3"`
# example: `$1` — project name
# example: `$2` — the four cells, already joined
# return: `0` — the record was accepted by the collector
# return: `10` (`ERROR_ARGV`) — `PROJECT` or `CELLS` empty
# return: other — the code `_send_otel_notification` returned
_github_send () {
    _func_start ""

    # Check argv
    if ! _exist "$1"; then _error "PROJECT EMPTY" ; _func_end "$ERROR_ARGV" ; return "$ERROR_ARGV" ; fi
    if ! _exist "$2"; then _error "CELLS EMPTY" ; _func_end "$ERROR_ARGV" ; return "$ERROR_ARGV" ; fi

    local __project="$1"
    local __cells="$2"
    local __return=0

    _send_otel_notification "$GITHUB_OTEL_ENDPOINT" "$__project" "$__cells" "INFO" "$GITHUB_OTEL_SERVICE" "$GITHUB_COMMIT_HOST" || __return=$?

    if [ "$__return" -ne 0 ]; then _error "OTEL: the record of $__project was refused" ; _func_end "$__return" ; return "$__return" ; fi

    _func_end "0" ; return 0
}

####################################################################################################
############################################ Commit status ##########################################
####################################################################################################
# doc-section: Commit status

# usage: _commit_status
# description: Prints the per-project status as a markdown table, one row per managed project with its commit status, its push status, its behind status (after a real fetch) and its open GitHub issues, then sends one OTLP log record per project so the `Commit status` dashboard shows the same table.
# example: `my_warp.sh --lib github commit_status`
# return: `0` — the table was printed and every record was accepted
# return: `1` — the table was printed but at least one record was refused, or the project list is not configured
_commit_status () {
    _func_start "$@"

    local __token
    local __lines
    local __line
    local __project
    local __commit
    local __push
    local __behind
    local __issues
    local __return=0

    __token=$(_github_token)

    __lines=$(_github_status "$__token")
    __return=$?
    if [ "$__return" -ne 0 ]; then _func_end "$__return" ; return "$__return" ; fi

    echo "| Project | Commit | Push | Behind | Git open issues |"
    echo "| --- | --- | --- | --- | --- |"

    while IFS= read -r __line; do
        __project="${__line%%|*}"
        __line="${__line#*|}"
        __commit="${__line%%|*}"
        __line="${__line#*|}"
        __push="${__line%%|*}"
        __line="${__line#*|}"
        __behind="${__line%%|*}"
        __line="${__line#*|}"
        __issues="$__line"

        echo "| $__project | $__commit | $__push | $__behind | $__issues |"

        if ! _github_send "$__project" "$__commit | $__push | $__behind | $__issues"; then __return=1 ; fi
    done <<< "$__lines"

    if [ "$__return" -ne 0 ]; then _error "OTEL: the table was printed but a record was not accepted by $GITHUB_OTEL_ENDPOINT" ; _func_end "1" ; return 1 ; fi

    _func_end "0" ; return 0
}

# call: _process_lib_github ($@:args)
# description: Routes the orchestrator calls to the github lib commands. The getopt string puts the options first, then `--`, then the command.
# example: `_process_lib_github "-- commit_status"` — what `my_warp.sh --lib github commit_status` calls
# return: `0` — the command succeeded
# return: `1` — the command failed, is unknown, or none was given
_process_lib_github () {
    _func_start "$@"

    eval set -- "$@"

    local __return=0

    # the getopt string of the orchestrator puts the options first, then `--`,
    # then the command
    while true; do
        case "$1" in
            -- )  break ;;
            "" )  break ;;
            * )   shift ;;
        esac
    done

    while true ; do
        case "$1" in
            -- )            shift ;;
            commit_status ) _commit_status ; __return=$? ; break ;;
            "" )            _error "command: none given (expected: commit_status)" ; __return=1 ; break ;;
            * )             _error "command $1 not found" ; __return=1 ; break ;;
        esac
    done

    _func_end "$__return" ; return "$__return"
}
