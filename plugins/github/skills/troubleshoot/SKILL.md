---
name: troubleshoot
description: "Diagnose the github plugin: run the read-only verify block of the install playbook, probe the hosted MCP endpoint with the token, read the journal of the controller, report that GitHub exposes no series here. Use when a github__ tool is missing, answers 401 or 403, or when the plugin loads with no tool."
---

# Troubleshoot github

Three steps, in this order. Stop at the first one that names the fault.

## 1. test

Run the `verify` block of the install playbook. It reads the disk only, so it needs no token and no network.

```shell
ansible-playbook /root/git/github/install/github_mcp.yaml --tags verify
```

- It checks that `plugins/github/eca.json` exists, parses, declares `mcpServers.github` with the hosted url and the two headers, starts no `command`, and pre-approves read tools only.
- A failure names the file and the key that drifted. Fix the manifest, then run the play again.

Then check what the play cannot: the endpoint itself, with the token in the environment.

```shell
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://api.githubcopilot.com/mcp/ -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -H "Authorization: Bearer ${GITHUB_PERSONAL_ACCESS_TOKEN}" -H 'X-MCP-Toolsets: all' -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}'
```

- `200` is the server up and the token accepted.
- `401` is an empty, expired or revoked token: `GITHUB_PERSONAL_ACCESS_TOKEN` is not exported in the shell that started ECA, or `.emacs` no longer sets it.
- `403` is a token without the permission of the call. A classic PAT hides the tools its scopes miss, so the missing tool names the missing scope.

From ECA, the direct check is `github__get_me`: it returns the login of the token, and it proves the start, the header and the endpoint at once.

## 2. logs

Use `mcp-bash__search_logs`, restricted to the controller where ECA runs.

- `query`: the fault, never a wildcard. `401`, `Bad credentials`, `Resource not accessible`, `api.githubcopilot.com`, `github`.
- `host`: the controller. Leave the field empty first if the name is unknown.
- `service`: leave it empty, then try `ansible-ansible.builtin.assert` and `ansible-ansible.builtin.debug`, the module tags of a play that reports.
- `timeframe`: `1h` around the incident, then `1day`.
- `level`: `error,fatal` first, then no filter to see what preceded.

Reading:

- The server is hosted, so nothing of it reaches the journal of this host. A start failure appears in ECA, not in the journal.
- A dead endpoint over the network shows as a timeout in ECA. `curl` above tells the two apart.
- A `verify` run that failed left `Invoked with …` lines tagged by the ansible module. Read the path in the message: it is the manifest the play refused.

## 3. metrics

No series. GitHub exposes no metric to this fleet, and the project ships no dashboard by decision.

- Answer "no series" for github itself. Do not read it as a scrape that is down.
- The only signal left is the host: `grafana-plugin__query_prometheus` on the datasource uid `victoriametrics`, with `max_over_time(…)` over `{system.memory.utilization, host.name="<the controller>"}`.
- A slow `github__search_code` across a large organisation is the one call that moves that line. A wrong answer from a healthy endpoint is not worth that check.
