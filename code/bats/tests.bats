#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# global var (DEBUG/VERBOSE are overridable via env: DEBUG=true VERBOSE=true bats ...)
VERBOSE=${VERBOSE:-false}
DEBUG=${DEBUG:-false}
SYSLOG=${SYSLOG:-false}
DEFAULT=false
YUBIKEY=false
FUNC_LIST=()
unset LIB
CUR_NAME=${FUNCNAME[0]}

# load our shell functions and the library under test
source $MY_GIT_DIR/shell/lib_shell.sh
source $MY_GIT_DIR/github/code/lib_github.sh

CHECK_KO="[KO]"
CHECK_WARN="[WARN]"
CHECK_INFO="[INFO]"

# The suite never reaches the network: every project is a throwaway git
# repository under $BATS_TEST_TMPDIR, its upstream a local bare repository, and
# the OTLP sender is stubbed so no record leaves the machine.

setup() {
    load '/usr/lib/bats/bats-support/load'
    load '/usr/lib/bats/bats-assert/load'
    # no test may reach the real journal: the syslog helper is stubbed for every test
    logger() { cat >> "$BATS_TEST_TMPDIR/journal_entry"; return 0; }
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"
    SENT="$BATS_TEST_TMPDIR/sent"
    SAVED_ROOT="$GITHUB_COMMIT_ROOT"
    SAVED_PROJECTS="${MCP_COMMIT_PROJECTS:-}"
    GITHUB_COMMIT_ROOT="$WORK"
    MCP_COMMIT_PROJECTS=""
    _send_otel_notification() { printf '%s|%s\n' "$2" "$3" >> "$SENT"; return 0; }
}

teardown() {
    GITHUB_COMMIT_ROOT="$SAVED_ROOT"
    MCP_COMMIT_PROJECTS="$SAVED_PROJECTS"
    rm -rf "$WORK" "$SENT"
}

git_make_repo() {
    local __dir="$1"
    mkdir -p "$__dir"
    git -C "$__dir" init -q
    git -C "$__dir" config user.email "test@example.com"
    git -C "$__dir" config user.name "github test"
    printf '%s\n' "initial" > "$__dir/file.txt"
    git -C "$__dir" add file.txt
    git -C "$__dir" commit -q -m "initial"
}

git_make_repo_with_upstream() {
    local __dir="$1"
    local __remote="$2"
    git init -q --bare "$__remote"
    git_make_repo "$__dir"
    git -C "$__dir" remote add origin "$__remote"
    git -C "$__dir" push -q -u origin HEAD
}

git_push_upstream_ahead() {
    local __remote="$1"
    local __work="$2"
    git clone -q "$__remote" "$__work"
    git -C "$__work" config user.email "test@example.com"
    git -C "$__work" config user.name "github test"
    printf '%s\n' "upstream" >> "$__work/file.txt"
    git -C "$__work" commit -q -am "upstream"
    git -C "$__work" push -q origin HEAD
}

####################################################################################################
########################################## PROJECT LIST ############################################
####################################################################################################

@test "_github_projects => echoes the configured list" {
    MCP_COMMIT_PROJECTS="projA projB"
    run _github_projects
    assert_success
    assert_output "projA projB"
}

@test "_github_projects => accepts a comma separated list" {
    MCP_COMMIT_PROJECTS="projA,projB"
    run _github_projects
    assert_success
    assert_output "projA projB"
}

@test "_github_projects => fails when the list is not configured" {
    MCP_COMMIT_PROJECTS=""
    run _github_projects
    assert_failure
    assert_output --partial "MCP_COMMIT_PROJECTS"
}

@test "_github_token => empty without a token" {
    AI_GITHUB_TOKEN=""
    run _github_token
    assert_success
    assert_output ""
}

@test "_github_token => refuses a token that is not shaped like one" {
    AI_GITHUB_TOKEN="bad token\n"
    run _github_token
    assert_success
    assert_output ""
}

####################################################################################################
########################################### COMMIT CELL ############################################
####################################################################################################

@test "_github_commit_cell => clean" {
    git_make_repo "$WORK/projA"
    run _github_commit_cell "$WORK/projA"
    assert_success
    assert_output "clean"
}

@test "_github_commit_cell => counts the changed paths" {
    git_make_repo "$WORK/projA"
    printf '%s\n' "change" >> "$WORK/projA/file.txt"
    printf '%s\n' "new" > "$WORK/projA/new.txt"
    run _github_commit_cell "$WORK/projA"
    assert_success
    assert_output "2 changed path(s)"
}

@test "_github_commit_cell => empty" {
    run _github_commit_cell
    assert_failure
}

####################################################################################################
############################################ PUSH CELL #############################################
####################################################################################################

@test "_github_push_cell => no upstream" {
    git_make_repo "$WORK/projA"
    run --separate-stderr _github_push_cell "$WORK/projA"
    assert_success
    assert_output "no upstream"
}

@test "_github_push_cell => up to date" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    run _github_push_cell "$WORK/projA"
    assert_success
    assert_output "up to date"
}

@test "_github_push_cell => ahead of its upstream" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    printf '%s\n' "local" >> "$WORK/projA/file.txt"
    git -C "$WORK/projA" commit -q -am "local"
    run _github_push_cell "$WORK/projA"
    assert_success
    assert_output "1 commit(s) to push"
}

@test "_github_push_cell => empty" {
    run _github_push_cell
    assert_failure
}

####################################################################################################
########################################### BEHIND CELL ############################################
####################################################################################################

@test "_github_behind_cell => no upstream" {
    git_make_repo "$WORK/projA"
    run --separate-stderr _github_behind_cell "$WORK/projA"
    assert_success
    assert_output "no upstream"
}

@test "_github_behind_cell => up to date" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    run _github_behind_cell "$WORK/projA"
    assert_success
    assert_output "up to date"
}

@test "_github_behind_cell => behind its upstream" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    git_push_upstream_ahead "$WORK/remoteA" "$WORK/workA"
    run _github_behind_cell "$WORK/projA"
    assert_success
    assert_output "1 commit(s) behind"
}

@test "_github_behind_cell => an unreachable remote is a fetch failure" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    mv "$WORK/remoteA" "$WORK/remoteA.gone"
    run --separate-stderr _github_behind_cell "$WORK/projA"
    assert_success
    assert_output --partial "fetch failed"
}

@test "_github_behind_cell => a hanging fetch is reported as a timeout" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    _git_fetch() { return 2 ; }
    run --separate-stderr _github_behind_cell "$WORK/projA"
    assert_success
    assert_output "fetch failed (timeout)"
}

@test "_github_behind_cell => a token that cannot read the remote is a plain fetch failure" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    _git_fetch() { return 1 ; }
    run --separate-stderr _github_behind_cell "$WORK/projA" "dummy_token"
    assert_success
    assert_output "fetch failed"
}

@test "_github_behind_cell => an unreadable behind count is a fetch failure" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    _git_fetch() { return 0 ; }
    _git_commits_behind() { return 1 ; }
    run --separate-stderr _github_behind_cell "$WORK/projA"
    assert_success
    assert_output "fetch failed"
}

@test "_github_behind_cell => empty" {
    run _github_behind_cell
    assert_failure
}

####################################################################################################
########################################### ISSUES CELL ############################################
####################################################################################################

@test "_github_issues_cell => no GitHub origin is a dash" {
    git_make_repo_with_upstream "$WORK/projA" "$WORK/remoteA"
    run --separate-stderr _github_issues_cell "$WORK/projA"
    assert_success
    assert_output -- "-"
}

@test "_github_issues_cell => without a token the cell says so, without a request" {
    git_make_repo "$WORK/projA"
    git -C "$WORK/projA" remote add origin "https://github.com/owner/name.git"
    run _github_issues_cell "$WORK/projA"
    assert_success
    assert_output "failed (token)"
}

@test "_github_issues_cell => empty" {
    run _github_issues_cell
    assert_failure
}

@test "_github_issues_cell => counts the issues of a GitHub origin" {
    git_make_repo "$WORK/projA"
    git -C "$WORK/projA" remote add origin "https://github.com/owner/name.git"
    _git_issue_count() { echo "3" ; }
    run --separate-stderr _github_issues_cell "$WORK/projA" "dummy_token"
    assert_success
    assert_output "3"
}

@test "_github_issues_cell => an ssh origin is understood too" {
    git_make_repo "$WORK/projA"
    git -C "$WORK/projA" remote add origin "git@github.com:owner/name.git"
    _git_issue_count() { echo "7" ; }
    run --separate-stderr _github_issues_cell "$WORK/projA" "dummy_token"
    assert_success
    assert_output "7"
}

@test "_github_issues_cell => a scheme, a port and a trailing slash do not hide the repository" {
    git_make_repo "$WORK/projA"
    git -C "$WORK/projA" remote add origin "https://github.com:443/owner/name/"
    _git_issue_count() { echo "12" ; }
    run --separate-stderr _github_issues_cell "$WORK/projA" "dummy_token"
    assert_success
    assert_output "12"
}

@test "_github_issues_cell => a failed count is a cell, not a failure" {
    git_make_repo "$WORK/projA"
    git -C "$WORK/projA" remote add origin "https://github.com/owner/name.git"
    _git_issue_count() { return 1 ; }
    run --separate-stderr _github_issues_cell "$WORK/projA" "dummy_token"
    assert_success
    assert_output "failed"
}

####################################################################################################
########################################## STATUS LINES ############################################
####################################################################################################

@test "_github_status => one line per project" {
    git_make_repo "$WORK/projA"
    git_make_repo "$WORK/projB"
    MCP_COMMIT_PROJECTS="projA projB"
    run --separate-stderr _github_status ""
    assert_success
    assert_line --index 0 "projA|clean|no upstream|no upstream|-"
    assert_line --index 1 "projB|clean|no upstream|no upstream|-"
}

@test "_github_status => a missing directory is a SKIP row" {
    MCP_COMMIT_PROJECTS="ghost"
    run _github_status ""
    assert_success
    assert_output "ghost|SKIP (no such directory)|-|-|-"
}

@test "_github_status => a non git directory is a SKIP row" {
    mkdir -p "$WORK/plain"
    MCP_COMMIT_PROJECTS="plain"
    run --separate-stderr _github_status ""
    assert_success
    assert_output "plain|SKIP (not a git repository)|-|-|-"
}

@test "_github_status => fails without a project list" {
    MCP_COMMIT_PROJECTS=""
    run _github_status ""
    assert_failure
}

####################################################################################################
############################################ SENDING ###############################################
####################################################################################################

@test "_github_send => packs the project as title and the four cells as body" {
    run _github_send "projA" "clean | up to date | up to date | 3"
    assert_success
    run cat "$SENT"
    assert_output "projA|clean | up to date | up to date | 3"
}

@test "_github_send => a refused record is an error" {
    _send_otel_notification() { return 1 ; }
    run _github_send "projA" "clean | up to date | up to date | 3"
    assert_failure
}

@test "_github_send => empty" {
    run _github_send
    assert_failure
}

####################################################################################################
############################################ CLI ENTRY #############################################
####################################################################################################

@test "_commit_status => prints the table and sends one record per project" {
    git_make_repo "$WORK/projA"
    MCP_COMMIT_PROJECTS="projA"
    run --separate-stderr _commit_status
    assert_success
    assert_line --index 0 "| Project | Commit | Push | Behind | Git open issues |"
    assert_line --index 1 "| --- | --- | --- | --- | --- |"
    assert_line --index 2 "| projA | clean | no upstream | no upstream | - |"
    run cat "$SENT"
    assert_output "projA|clean | no upstream | no upstream | -"
}

@test "_commit_status => the table is printed even when a record is refused" {
    git_make_repo "$WORK/projA"
    MCP_COMMIT_PROJECTS="projA"
    _send_otel_notification() { return 1 ; }
    run --separate-stderr _commit_status
    assert_failure
    assert_output --partial "| projA | clean | no upstream | no upstream | - |"
}

@test "_commit_status => fails without a project list" {
    MCP_COMMIT_PROJECTS=""
    run _commit_status
    assert_failure
}

@test "_process_lib_github => dispatches commit_status" {
    git_make_repo "$WORK/projA"
    MCP_COMMIT_PROJECTS="projA"
    run --separate-stderr _process_lib_github "-- commit_status"
    assert_success
    assert_output --partial "| projA |"
}

@test "_process_lib_github => skips the options getopt leaves before the command" {
    git_make_repo "$WORK/projA"
    MCP_COMMIT_PROJECTS="projA"
    run --separate-stderr _process_lib_github "--lib github -- commit_status"
    assert_success
    assert_output --partial "| projA |"
}

@test "_process_lib_github => unknown command" {
    run _process_lib_github "-- nope"
    assert_failure
    assert_output --partial "command nope not found"
}

@test "_process_lib_github => no command is an error" {
    run _process_lib_github ""
    assert_failure
    assert_output --partial "none given"
}

@test "_doc => documented mode regenerates functions.md (github)" {
    local __out="$BATS_TEST_TMPDIR/functions_doc.md"
    LIB=github
    run _doc "$__out"
    LIB=""
    assert_success
    diff "$MY_GIT_DIR/github/code/functions.md" "$__out"
    assert_success
}
