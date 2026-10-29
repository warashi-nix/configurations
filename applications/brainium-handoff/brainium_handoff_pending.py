#!/usr/bin/env python3
"""brainium の :handoff: 付き TODO のうち、本人がまだ取り込んでいないものを列挙する。

usage: brainium-handoff-pending REPO NAME

REPO は本人の brainium の clone、NAME は chelly-handoff の handoff 名。専用 clone の HEAD の
tasks.org にあり、見出しの文言が chelly-base の tasks.org にも、本人の tasks.org /
tasks.org_archive にも無い見出しを stdout に並べて exit 1 で終わる。無ければ何も出さずに
exit 0、確かめられなければ理由を stdout に出して exit 2 で終わる。
"""

import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

OPEN = {"TODO", "WIP"}
KEYWORDS = OPEN | {"DONE", "CANCELLED"}
TAG = "handoff"
MAX_BLOB = 4 * 1024 * 1024
MAX_ITEMS = 20
MAX_TITLE = 200

HEADING = re.compile(r"^\*+[ \t]+(.*)$")
TAGS = re.compile(r"[ \t]+:([\w@#%:]+):[ \t]*$")
PRIORITY = re.compile(r"^\[#.\][ \t]+")


class Unverifiable(Exception):
    pass


def headings(text):
    """(キーワード, 見出しの文言, タグ) を順に返す。"""
    for line in text.splitlines():
        match = HEADING.match(line)
        if not match:
            continue
        rest = match[1]
        tags = set()
        tag_match = TAGS.search(rest)
        if tag_match:
            tags = set(tag_match[1].split(":"))
            rest = rest[: tag_match.start()]
        keyword = None
        first, _, after = rest.partition(" ")
        if first in KEYWORDS:
            keyword, rest = first, after
        rest = PRIORITY.sub("", rest.strip())
        yield keyword, " ".join(rest.split()), tags


def requests(text):
    return [title for keyword, title, tags in headings(text) if keyword in OPEN and TAG in tags]


def titles(text):
    return {title for _, title, _ in headings(text)}


def owner_git(repo, *args):
    result = subprocess.run(
        ["git", "-C", repo, *args],
        capture_output=True, encoding="utf-8", errors="replace", check=False,
    )
    if result.returncode != 0:
        raise Unverifiable(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def agent_git(gitdir, *args):
    """専用 clone は agent が書き換えられるので、設定や hook が実行に繋がらない読み方だけをする。

    rev-parse と cat-file blob は hook を起動せず、filter・textconv・pager・fsmonitor も
    通らない。replace ref で読む object をすり替えさせない。clone の所有者は別ユーザーの
    ことがあり、safe.directory はこの呼び出しに限って外す。
    """
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(
        GIT_CONFIG_NOSYSTEM="1",
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_NO_REPLACE_OBJECTS="1",
        GIT_TERMINAL_PROMPT="0",
        GIT_OPTIONAL_LOCKS="0",
    )
    result = subprocess.run(
        ["git", "--no-pager", "-c", "safe.directory=*", f"--git-dir={gitdir}", *args],
        capture_output=True, env=env, stdin=subprocess.DEVNULL, check=False,
    )
    if result.returncode != 0:
        raise Unverifiable(f"agent clone: git {args[0]} failed")
    return result.stdout


def agent_tasks(workspace):
    gitdir = Path(workspace) / ".git"
    if not gitdir.is_dir():
        raise Unverifiable(f"{workspace} に clone が無い")
    head = agent_git(gitdir, "rev-parse", "--verify", "--end-of-options", "HEAD^{commit}")
    spec = f"{head.decode().strip()}:tasks.org"
    size = int(agent_git(gitdir, "cat-file", "-s", "--end-of-options", spec))
    if size > MAX_BLOB:
        raise Unverifiable(f"専用 clone の tasks.org が大きすぎる ({size} bytes)")
    return agent_git(gitdir, "cat-file", "blob", "--end-of-options", spec).decode(
        "utf-8", "replace"
    )


def read_optional(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def pending(repo, name):
    remote = f"remote.handoff-{name}"
    base = owner_git(repo, "config", "--get", f"{remote}.chelly-base").strip()
    workspace = owner_git(repo, "config", "--get", f"{remote}.chelly-workspace").strip()
    try:
        base_tasks = owner_git(repo, "cat-file", "blob", f"{base}:tasks.org")
    except Unverifiable:
        base_tasks = ""
    known = titles(base_tasks)
    for owned in ("tasks.org", "tasks.org_archive"):
        known |= titles(read_optional(Path(repo) / owned))

    found = [("取り込み前", t) for t in requests(agent_tasks(workspace)) if t not in known]
    return list(dict.fromkeys(found))


def clean(title):
    title = "".join(c for c in title if unicodedata.category(c)[0] != "C")
    if len(title) > MAX_TITLE:
        title = title[: MAX_TITLE - 1] + "…"
    return title


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    _, repo, name = argv
    # launchd と systemd の user service は LANG を渡さないので、locale に依らず UTF-8 で書く。
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    try:
        found = pending(repo, name)
    except (Unverifiable, OSError, ValueError) as error:
        print(f"{name} の handoff を確かめられない: {clean(str(error))}")
        return 2
    if not found:
        return 0
    print(f"{name} の handoff の依頼が {len(found)} 件ある")
    for state, title in found[:MAX_ITEMS]:
        print(f"- {state}: {clean(title)}")
    if len(found) > MAX_ITEMS:
        print(f"ほか {len(found) - MAX_ITEMS} 件")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
