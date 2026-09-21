# `git-check-new-ignored`

`git-check-new-ignored` checks objects received from an isolated agent before an
owner reviews or signs them. It reports paths that become newly tracked while
matching the owner's trusted ignore policy. It does not approve exceptions,
run hooks, sign commits, publish refs, or change either repository.

## Trust and policy

The object repository must be an independently initialized, trusted bare
receiver. This command is not a sandbox for an attacker-created `.git`
directory. The policy repository must be the owner's trusted non-bare checkout.

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
