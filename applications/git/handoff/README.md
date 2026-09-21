# `git-check-new-ignored`

`git-check-new-ignored` checks objects received from an isolated agent before an
owner reviews or signs them. It reports paths that become newly tracked while
matching the owner's trusted ignore policy. It does not approve exceptions,
run hooks, sign commits, publish refs, or change either repository.

## Trust and policy

The object repository must be a trusted Git directory that the owner controls,
such as the owner's own `.git` after fetching the candidate objects into it, or
an independently initialized bare receiver. This command is not a sandbox for
an attacker-created `.git` directory. The policy repository must be the owner's
trusted non-bare checkout.

Policy is fixed before checking:

- regular `.gitignore` blobs come from `BASE` in the policy repository;
- `.git/info/exclude` comes from the current policy repository;
- the global exclude comes from the policy repository's effective
  `core.excludesFile`, or the standard XDG/HOME default when it is unset.

Relative exclude paths resolve against the policy worktree root, even when a
subdirectory is supplied. Matching preserves the owner's effective
`core.ignoreCase` setting rather than the temporary repository's default.

An explicitly configured missing or unreadable global exclude is an error.
Candidate `.gitignore` changes therefore cannot relax policy. Trusted-base
`.gitignore` symlinks are not followed, matching Git's behavior.

## Usage

```console
git-check-new-ignored \
  --object-repo /absolute/trusted/review.git \
  --policy-repo /absolute/trusted/owner/repo \
  BASE TIP
```

`BASE` must resolve to the same trusted commit in both repositories. `TIP`
resolves only in the object repository. Both are fixed to commit IDs before
inspection, and replace objects are disabled. Bare-repository reads use an
explicit `--git-dir`; unrelated Git configuration and pathspec-mode environment
variables are removed from object and scratch operations. Owner configuration
is consulted only while resolving the effective global exclude file. Candidate
names are passed literally through NUL-delimited plumbing.

The supported range is deliberately narrow: `BASE..TIP` must be nonempty and
linear, and each commit must have exactly the preceding commit as its sole
parent. Empty ranges, merges, and unrelated histories are rejected rather than
flattened or partially checked. Every commit is inspected, including files
added and later deleted. Renames are treated as delete/add pairs.
Directory-only rules are evaluated against the incoming path type even when a
trusted nested `.gitignore` requires a conflicting directory in the policy
snapshot. New gitlinks/submodules, including conversions from tracked files,
are currently unsupported and cause a
fail-closed status `2`, rather than bypassing directory-only rules.

Exit status is `0` after a clean complete check, `1` after printing all ignored
additions, and `2` for invalid input, unsupported history, unreadable policy, or
Git errors. Findings include the fixed candidate commit, JSON-quoted path,
trusted rule origin, line, and pattern. A successful check prints fixed
`BASE`/`TIP` IDs and the checked commit count.

## `chelly-handoff`

`chelly-handoff` moves Git bundles between the owner's repository and a named
clone owned by the dedicated `chelly-agent` account. Review and integration are
ordinary Git operations on a remote-tracking branch, so Magit or any Git client
can show the diff, cherry-pick, or merge with the owner's usual signing
configuration. The command keeps no state file: the remote `handoff-NAME` in
the owner's repository is the only record.

```console
cd /absolute/project            # on the branch the agent should start from
chelly-handoff create [fix-issue-123]
chelly-handoff fetch [fix-issue-123]
chelly-handoff remove [fix-issue-123] [--force]
```

`create` bundles the current `HEAD` and lets `chelly-agent` clone it into
`/srv/chelly-workspaces/PROJECT/NAME` on a branch with the owner's current
branch name, without `origin`, hooks, or the owner's Git configuration.
`PROJECT` is the directory name of the owner's repository, so the same `NAME`
can be in use for different projects at once. `NAME` defaults to the current
branch name; pass it explicitly to run several workspaces from one branch or
when the branch name contains `/`. It starts with an ASCII letter or digit and
then contains only ASCII letters, digits, `.`, `_`, or `-`. `create` then adds
the remote `handoff-NAME` whose URL is a bundle file under
`.git/chelly-handoff/`, and records the fixed base and workspace path in
`remote.handoff-NAME.chelly-base` and `remote.handoff-NAME.chelly-workspace`.
An existing remote or workspace is rejected without changes. Uncommitted owner
changes are not transferred.

`fetch` requires the agent workspace to be clean, on the expected branch, and
ahead of the base. It streams `BASE..branch` back as a bundle, verifies it,
fetches it into `refs/remotes/handoff-NAME/branch`, and finally runs
`git-check-new-ignored` with the owner's own Git directory as the object
repository. The exit status is the checker's, so findings return `1` while the
fetched ref stays available for inspection. Repeat `fetch` after the agent
adds commits.

`remove` deletes the agent workspace, the remote, its remote-tracking refs, and
the bundle. Without `--force` it refuses when the workspace has uncommitted
changes or a `HEAD` that this repository has not fetched yet.

The owner's SSH agent and Git identity variables are not passed to the
transport, and nothing is ever pushed. `chelly-agent` must be on the host
`PATH`; it is started from `/srv/chelly-workspaces` so candidate development
shells are never evaluated for transport. `CHELLY_HANDOFF_WORKSPACES` overrides
that directory for tests only.
