#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


class IntakeError(Exception):
    pass


@dataclass(frozen=True)
class Finding:
    commit: str
    path: bytes
    source: str
    line: str
    pattern: bytes


def safe_env(*, owner_config=False):
    env = os.environ.copy()
    for name in (
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_COMMON_DIR",
        "GIT_NAMESPACE",
    ):
        env.pop(name, None)
    env["GIT_NO_REPLACE_OBJECTS"] = "1"
    env["GIT_TERMINAL_PROMPT"] = "0"
    if not owner_config:
        for name in tuple(env):
            if (
                name
                in (
                    "GIT_CONFIG",
                    "GIT_CONFIG_COUNT",
                    "GIT_CONFIG_GLOBAL",
                    "GIT_CONFIG_NOSYSTEM",
                    "GIT_CONFIG_PARAMETERS",
                    "GIT_CONFIG_SYSTEM",
                    "GIT_GLOB_PATHSPECS",
                    "GIT_ICASE_PATHSPECS",
                    "GIT_LITERAL_PATHSPECS",
                    "GIT_NOGLOB_PATHSPECS",
                )
                or name.startswith("GIT_CONFIG_KEY_")
                or name.startswith("GIT_CONFIG_VALUE_")
            ):
                env.pop(name)
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = os.devnull
        env["GIT_CONFIG_SYSTEM"] = os.devnull
        env["GIT_ATTR_NOSYSTEM"] = "1"
    return env


def git(
    repo,
    args,
    *,
    object_repo=False,
    owner_config=False,
    literal_pathspecs=True,
    input_bytes=None,
    ok=(0,),
):
    location = (
        [f"--git-dir={os.fspath(repo)}"]
        if object_repo
        else ["-C", os.fspath(repo)]
    )
    command = [
        "git",
        "--no-replace-objects",
        *(["--literal-pathspecs"] if literal_pathspecs else []),
        *location,
        "-c",
        "core.fsmonitor=false",
        "-c",
        "core.hooksPath=/dev/null",
        *args,
    ]
    try:
        result = subprocess.run(
            command,
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=safe_env(owner_config=owner_config),
            check=False,
        )
    except OSError as error:
        raise IntakeError(f"could not run Git: {error}") from error
    if result.returncode not in ok:
        detail = result.stderr.decode("utf-8", "replace").strip()
        raise IntakeError(f"Git command failed ({' '.join(args)}): {detail or 'no diagnostic'}")
    return result


def fixed_commit(
    repo, revision, label, *, object_repo=False, owner_config=False
):
    result = git(
        repo,
        ["rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"],
        object_repo=object_repo,
        owner_config=owner_config,
    )
    value = result.stdout.strip().decode("ascii", "strict")
    if not value:
        raise IntakeError(f"{label} did not resolve to a commit")
    return value


def require_absolute(path, label):
    candidate = Path(path)
    if not candidate.is_absolute():
        raise IntakeError(f"{label} must be an absolute path")
    return candidate


def validate_repositories(object_repo, policy_repo):
    object_bare = git(
        object_repo,
        ["rev-parse", "--is-bare-repository"],
        object_repo=True,
    ).stdout.strip()
    if object_bare != b"true":
        raise IntakeError("object repository must be bare")
    policy_bare = git(policy_repo, ["rev-parse", "--is-bare-repository"]).stdout.strip()
    if policy_bare != b"false":
        raise IntakeError("policy repository must be a non-bare checkout")
    root = git(policy_repo, ["rev-parse", "--show-toplevel"]).stdout
    if not root.endswith(b"\n"):
        raise IntakeError("malformed policy worktree root")
    return Path(os.fsdecode(root[:-1]))


def linear_commits(object_repo, base, tip):
    output = git(
        object_repo,
        ["rev-list", "--reverse", f"{base}..{tip}"],
        object_repo=True,
    ).stdout
    commits = [item.decode("ascii") for item in output.splitlines() if item]
    if not commits:
        raise IntakeError("BASE..TIP is empty or TIP is not a descendant of BASE")
    previous = base
    for commit in commits:
        parents = (
            git(
                object_repo,
                ["show", "-s", "--format=%P", commit],
                object_repo=True,
            )
            .stdout.strip()
            .decode("ascii")
            .split()
        )
        if parents != [previous]:
            raise IntakeError(
                f"unsupported history at {commit}: every commit must have exactly the previous commit as parent"
            )
        previous = commit
    if previous != tip:
        raise IntakeError("TIP is not the end of a linear BASE..TIP range")
    return commits


def read_optional(path, label, *, required):
    try:
        return path.read_bytes()
    except FileNotFoundError:
        if required:
            raise IntakeError(f"configured {label} does not exist: {path}")
        return None
    except OSError as error:
        raise IntakeError(f"cannot read {label} {path}: {error}") from error


def policy_ignore_case(policy_repo):
    result = git(
        policy_repo,
        ["config", "--type=bool", "--get", "core.ignoreCase"],
        owner_config=True,
        ok=(0, 1),
    )
    if result.returncode == 1:
        return False
    value = result.stdout.strip()
    if value not in (b"true", b"false"):
        raise IntakeError("malformed core.ignoreCase config output")
    return value == b"true"


def policy_files(policy_repo):
    config = git(
        policy_repo,
        ["config", "--null", "--path", "--get", "core.excludesFile"],
        owner_config=True,
        ok=(0, 1),
    )
    if config.returncode == 0:
        if not config.stdout.endswith(b"\0"):
            raise IntakeError("malformed core.excludesFile config output")
        raw = config.stdout[:-1]
        if not raw:
            raise IntakeError("configured core.excludesFile is empty")
        global_path = Path(os.fsdecode(raw))
        if not global_path.is_absolute():
            global_path = policy_repo / global_path
        global_required = True
    else:
        config_home = os.environ.get("XDG_CONFIG_HOME")
        if config_home:
            global_path = Path(config_home) / "git" / "ignore"
        else:
            home = os.environ.get("HOME")
            if not home:
                raise IntakeError("HOME is unset while resolving the default global exclude file")
            global_path = Path(home) / ".config" / "git" / "ignore"
        global_required = False
    global_data = read_optional(
        global_path, "global exclude file", required=global_required
    )

    info_output = git(
        policy_repo,
        ["rev-parse", "--path-format=absolute", "--git-path", "info/exclude"],
    ).stdout
    if not info_output.endswith(b"\n"):
        raise IntakeError("malformed info exclude path output")
    info_output = info_output[:-1]
    if not info_output:
        raise IntakeError("Git returned an empty info exclude path")
    info_path = Path(os.fsdecode(info_output))
    info_data = read_optional(info_path, "info exclude file", required=False)
    return global_path, global_data, info_path, info_data


def safe_tree_path(raw):
    if not raw or raw.startswith(b"/"):
        return False
    parts = raw.split(b"/")
    return all(part not in (b"", b".", b"..", b".git") for part in parts)


def base_ignores(policy_repo, base):
    records = git(
        policy_repo,
        ["ls-tree", "-rz", "--full-tree", base],
    ).stdout.split(b"\0")
    ignores = []
    for record in records:
        if not record:
            continue
        try:
            metadata, path = record.split(b"\t", 1)
            mode, kind, oid = metadata.split(b" ", 2)
        except ValueError as error:
            raise IntakeError("malformed ls-tree output") from error
        if not safe_tree_path(path):
            raise IntakeError(f"unsafe path in trusted BASE tree: {quoted(path)}")
        if path.split(b"/")[-1] != b".gitignore":
            continue
        if kind == b"blob" and mode in (b"100644", b"100755"):
            data = git(policy_repo, ["cat-file", "blob", oid.decode("ascii")]).stdout
            ignores.append((path, data))
    return ignores


def additions(object_repo, previous, commit):
    output = git(
        object_repo,
        [
            "diff-tree",
            "-r",
            "--raw",
            "--no-commit-id",
            "--no-renames",
            "--no-ext-diff",
            "--diff-filter=AT",
            "-z",
            previous,
            commit,
            "--",
        ],
        object_repo=True,
    ).stdout
    fields = output.split(b"\0")
    if fields and fields[-1] == b"":
        fields.pop()
    if len(fields) % 2:
        raise IntakeError(f"malformed diff-tree status output for {commit}")
    paths = []
    for index in range(0, len(fields), 2):
        metadata, path = fields[index : index + 2]
        parts = metadata.split(b" ")
        if len(parts) != 5 or not parts[0].startswith(b":") or parts[4] not in (b"A", b"T"):
            raise IntakeError(f"malformed diff-tree status output for {commit}")
        new_mode = parts[1]
        if new_mode == b"160000":
            raise IntakeError(
                f"unsupported gitlink addition in {commit}: {quoted(path)}"
            )
        if new_mode not in (b"100644", b"100755", b"120000"):
            raise IntakeError(
                f"unsupported added path mode {new_mode.decode('ascii', 'replace')}"
                f" in {commit}: {quoted(path)}"
            )
        if not safe_tree_path(path):
            raise IntakeError(f"unsafe candidate tree path in {commit}: {quoted(path)}")
        if parts[4] == b"A":
            paths.append(path)
    return paths


def quoted(value):
    if isinstance(value, bytes):
        value = os.fsdecode(value)
    return json.dumps(value, ensure_ascii=True)


def install_policy(scratch, ignores, global_data, info_data, ignore_case):
    git(scratch, ["config", "core.ignoreCase", "true" if ignore_case else "false"])
    sources = {}
    for raw_path, data in ignores:
        relative = Path(os.fsdecode(raw_path))
        destination = scratch / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        label = f"base:{os.fsdecode(raw_path)}"
        sources[os.path.normpath(os.fspath(destination))] = label
        sources[os.path.normpath(os.fsdecode(raw_path))] = label

    global_snapshot = scratch / ".git/info/global-exclude"
    global_snapshot.parent.mkdir(parents=True, exist_ok=True)
    global_snapshot.write_bytes(global_data or b"")
    git(scratch, ["config", "core.excludesFile", os.fspath(global_snapshot)])
    sources[os.path.normpath(os.fspath(global_snapshot))] = "GLOBAL"

    if info_data is not None:
        info_snapshot = scratch / ".git/info/exclude"
        info_snapshot.parent.mkdir(parents=True, exist_ok=True)
        info_snapshot.write_bytes(info_data)
        sources[os.path.normpath(os.fspath(info_snapshot))] = "INFO"
        sources[os.path.normpath(".git/info/exclude")] = "INFO"
    return sources


def source_label(raw_source, sources, global_path, info_path):
    source = os.fsdecode(raw_source)
    normalized = os.path.normpath(source)
    mapped = sources.get(normalized)
    if mapped == "GLOBAL":
        return os.fspath(global_path)
    if mapped == "INFO":
        return os.fspath(info_path)
    if mapped:
        return mapped
    if not os.path.isabs(normalized):
        mapped = sources.get(os.path.normpath(os.path.abspath(normalized)))
        if mapped:
            return mapped
    raise IntakeError(f"unexpected ignore rule origin: {quoted(raw_source)}")


def inspect_batch(scratch, sources, global_path, info_path, commit, paths):
    if not paths:
        return []
    submitted = {b"./" + path: path for path in paths}
    result = git(
        scratch,
        ["check-ignore", "--no-index", "--verbose", "--stdin", "-z"],
        literal_pathspecs=False,
        input_bytes=b"\0".join(submitted) + b"\0",
        ok=(0, 1),
    )
    if result.returncode == 1:
        if result.stdout:
            raise IntakeError("Git check-ignore returned inconsistent output")
        return []
    fields = result.stdout.split(b"\0")
    if fields and fields[-1] == b"":
        fields.pop()
    if len(fields) % 4:
        raise IntakeError("malformed check-ignore output")
    findings = []
    for index in range(0, len(fields), 4):
        source, line, pattern, path = fields[index : index + 4]
        original_path = submitted.get(path)
        if original_path is None:
            raise IntakeError(
                f"check-ignore returned an unexpected path: {quoted(path)}"
            )
        if pattern.startswith(b"!"):
            continue
        findings.append(
            Finding(
                commit=commit,
                path=original_path,
                source=source_label(source, sources, global_path, info_path),
                line=line.decode("ascii", "replace"),
                pattern=pattern,
            )
        )
    return findings


def inspect(scratch, sources, global_path, info_path, commit, paths):
    ordinary = []
    collisions = []
    for path in paths:
        if (scratch / Path(os.fsdecode(path))).is_dir():
            collisions.append(path)
        else:
            ordinary.append(path)

    findings = inspect_batch(
        scratch, sources, global_path, info_path, commit, ordinary
    )
    backup = scratch / ".git/policy-path-type-backup"
    for path in collisions:
        policy_directory = scratch / Path(os.fsdecode(path))
        if backup.exists():
            raise IntakeError("internal scratch policy backup already exists")
        os.replace(policy_directory, backup)
        try:
            findings.extend(
                inspect_batch(
                    scratch,
                    sources,
                    global_path,
                    info_path,
                    commit,
                    [path],
                )
            )
        finally:
            os.replace(backup, policy_directory)
    return findings


def run(arguments):
    object_repo = require_absolute(arguments.object_repo, "--object-repo")
    policy_repo = require_absolute(arguments.policy_repo, "--policy-repo")
    policy_repo = validate_repositories(object_repo, policy_repo)

    policy_base = fixed_commit(policy_repo, arguments.base, "BASE in policy repository")
    object_base = fixed_commit(
        object_repo,
        arguments.base,
        "BASE in object repository",
        object_repo=True,
    )
    if policy_base != object_base:
        raise IntakeError("BASE resolves to different commits in policy and object repositories")
    tip = fixed_commit(
        object_repo,
        arguments.tip,
        "TIP in object repository",
        object_repo=True,
    )
    commits = linear_commits(object_repo, object_base, tip)

    ignores = base_ignores(policy_repo, policy_base)
    global_path, global_data, info_path, info_data = policy_files(policy_repo)
    ignore_case = policy_ignore_case(policy_repo)
    findings = []
    with tempfile.TemporaryDirectory(prefix="git-check-new-ignored-") as temporary:
        scratch = Path(temporary) / "policy"
        template = Path(temporary) / "empty-template"
        template.mkdir()
        scratch.mkdir()
        git(scratch, ["init", "--quiet", f"--template={template}"])
        sources = install_policy(scratch, ignores, global_data, info_data, ignore_case)
        previous = object_base
        for commit in commits:
            paths = additions(object_repo, previous, commit)
            findings.extend(
                inspect(
                    scratch,
                    sources,
                    global_path,
                    info_path,
                    commit,
                    paths,
                )
            )
            previous = commit

    if findings:
        for finding in findings:
            print(
                "ignored addition:"
                f" commit={finding.commit}"
                f" path={quoted(finding.path)}"
                f" source={quoted(finding.source)}"
                f" line={finding.line}"
                f" pattern={quoted(finding.pattern)}"
            )
        return 1
    print(f"BASE {object_base}")
    print(f"TIP {tip}")
    print(f"commits {len(commits)}")
    return 0


def parser():
    result = argparse.ArgumentParser(
        prog="git-check-new-ignored",
        description="Reject newly tracked paths ignored by a trusted BASE policy.",
    )
    result.add_argument("--object-repo", required=True)
    result.add_argument("--policy-repo", required=True)
    result.add_argument("base", metavar="BASE")
    result.add_argument("tip", metavar="TIP")
    return result


def main():
    try:
        return run(parser().parse_args())
    except (IntakeError, OSError, UnicodeError, ValueError) as error:
        print(f"git-check-new-ignored: error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
