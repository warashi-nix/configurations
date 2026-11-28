import json
import os
import pty
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HANDOFF = Path(__file__).parents[1] / "chelly-handoff.sh"
CHECKER = Path(__file__).parents[1] / "git_check_new_ignored.py"

# 実機の chelly は sudo と podman を経て同じ引数列を実行する。テストでは
# 引数の script をそのまま bash に渡し、専用領域だけをテスト用ディレクトリへ向ける。
# 端末を stdin のまま渡すと実機の podman が終了しなくなるため、その形も拒否する。
FAKE_AGENT = """#!/bin/sh
if [ -n "${SSH_AUTH_SOCK-}" ] || [ -n "${GIT_AUTHOR_NAME-}" ]; then
  echo "owner environment leaked into transport" >&2
  exit 1
fi
if [ -t 0 ]; then
  echo "owner terminal reached transport" >&2
  exit 1
fi
test "$1" = run && test "$2" = -- || exit 90
shift 2
exec "$@"
"""


@unittest.skipUnless(sys.platform.startswith("linux"), "Chelly handoff targets Linux")
class HandoffTest(unittest.TestCase):
    def setUp(self):
        test_tmp = Path(os.environ.get("TEST_TMPDIR", Path.cwd() / ".test-tmp"))
        test_tmp.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=test_tmp)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.agent_root = self.root / "agent"
        self.bin = self.root / "bin"
        for path in (self.home, self.agent_root, self.bin):
            path.mkdir()
        fake = self.bin / "chelly"
        fake.write_text(FAKE_AGENT)
        fake.chmod(0o755)
        checker = self.bin / "git-check-new-ignored"
        checker.write_text(f"#!/bin/sh\nexec {sys.executable} {CHECKER} \"$@\"\n")
        checker.chmod(0o755)
        self.ghq = self.root / "ghq"
        self.write_gitconfig(f"[ghq]\n\troot = {self.ghq}\n")
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": str(self.home / "gitconfig"),
            "GIT_AUTHOR_NAME": "Owner",
            "GIT_AUTHOR_EMAIL": "owner@example.invalid",
            "GIT_COMMITTER_NAME": "Owner",
            "GIT_COMMITTER_EMAIL": "owner@example.invalid",
            "SSH_AUTH_SOCK": str(self.root / "owner-agent.sock"),
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "CHELLY_HANDOFF_WORKSPACES": str(self.agent_root),
            # テスト用の root より上にある repo を git が見つけないようにする。
            "GIT_CEILING_DIRECTORIES": str(self.root),
        }
        self.project = Path("example.com", "owner", "source")
        self.repo = self.ghq / self.project
        self.git("init", "-q", "-b", "main", self.repo)
        self.git("-C", self.repo, "config", "commit.gpgsign", "false")
        self.write(self.repo, ".gitignore", "*.secret\n")
        self.write(self.repo, "tracked", "base\n")
        self.commit(self.repo, "base")
        self.base = self.rev(self.repo)
        self.workspace = self.agent_root / self.project / "fix"

    def tearDown(self):
        self.temporary.cleanup()

    def write_gitconfig(self, extra=""):
        # 裏で走る repack が tearDown の削除と競合するので、本人側の git でも起こさない。
        (self.home / "gitconfig").write_text("[maintenance]\n\tauto = false\n" + extra)

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", *map(str, args)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env, check=check,
        )

    def write(self, repo, name, content):
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self, repo, message):
        self.git("-C", repo, "add", "--all")
        self.git("-C", repo, "commit", "-q", "--no-verify", "-m", message)
        return self.rev(repo)

    def rev(self, repo, revision="HEAD"):
        return self.git("-C", repo, "rev-parse", "--verify", revision).stdout.decode().strip()

    def handoff(self, *args, check=True, cwd=None):
        # 本人は端末から起動するので、stdin を擬似端末にして同じ形で動かす。
        leader, follower = pty.openpty()
        try:
            return subprocess.run(
                ["bash", str(HANDOFF), *args], cwd=cwd or self.repo, stdin=follower,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env, check=check,
            )
        finally:
            os.close(follower)
            os.close(leader)

    def add_submodule(self, path):
        upstream = self.root / f"{path}-upstream"
        self.git("init", "-q", "-b", "main", upstream)
        self.git("-C", upstream, "commit", "-q", "--allow-empty", "-m", "first")
        self.git("-C", self.repo, "-c", "protocol.file.allow=always", "submodule", "add", "-q", upstream, path)
        return self.commit(self.repo, f"add {path}")

    def bump_submodule(self, path):
        upstream = self.root / f"{path}-upstream"
        self.git("-C", upstream, "commit", "-q", "--allow-empty", "-m", "next")
        self.git("-C", self.repo / path, "pull", "-q", "--ff-only")
        return self.commit(self.repo, f"bump {path}")

    def agent_commit(self, name, content, message="agent work"):
        self.write(self.workspace, name, content)
        # ignore 対象を故意に追跡させる場合もあるので、個別に強制追加する。
        self.git("-C", self.workspace, "add", "--force", name)
        return self.commit(self.workspace, message)

    def test_create_makes_isolated_clone_and_bundle_remote(self):
        result = self.handoff("create", "fix")
        self.assertEqual(result.stdout.decode().strip(), str(self.workspace))
        self.assertEqual(self.rev(self.workspace), self.base)
        self.assertEqual(
            self.git("-C", self.workspace, "symbolic-ref", "--short", "HEAD").stdout.decode().strip(),
            "main",
        )
        self.assertEqual(self.git("-C", self.workspace, "remote").stdout, b"")
        self.assertEqual(self.git("-C", self.workspace, "status", "--porcelain").stdout, b"")
        self.assertFalse((self.workspace / ".git" / "hooks" / "pre-commit").exists())
        url = self.git("-C", self.repo, "config", "remote.handoff-fix.url").stdout.decode().strip()
        self.assertEqual(url, str(self.repo / ".git" / "chelly-handoff" / "fix.bundle"))
        self.assertEqual(
            self.git("-C", self.repo, "config", "remote.handoff-fix.chelly-base").stdout.decode().strip(),
            self.base,
        )
        self.assertEqual(
            self.git("-C", self.repo, "config", "remote.handoff-fix.chelly-workspace").stdout.decode().strip(),
            str(self.workspace),
        )
        duplicate = self.handoff("create", "fix", check=False)
        self.assertEqual(duplicate.returncode, 1)
        self.assertIn(b"already exists", duplicate.stderr)

    def test_create_fills_an_empty_directory_prepared_as_a_mount_source(self):
        self.workspace.mkdir(parents=True)
        self.handoff("create", "fix")
        self.assertEqual(self.rev(self.workspace), self.base)

    def test_create_rejects_a_non_empty_directory_or_a_symlink(self):
        self.workspace.mkdir(parents=True)
        self.write(self.workspace, "stray", "x\n")
        result = self.handoff("create", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"already exists", result.stderr)
        self.assertTrue((self.workspace / "stray").exists())

        (self.workspace / "stray").unlink()
        self.workspace.rmdir()
        target = self.root / "elsewhere"
        target.mkdir()
        self.workspace.symlink_to(target)
        result = self.handoff("create", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"already exists", result.stderr)
        self.assertEqual(list(target.iterdir()), [])

    def test_empty_directory_left_as_a_mount_source_counts_as_a_missing_clone(self):
        self.handoff("create", "fix")
        subprocess.run(["rm", "-rf", str(self.workspace)], check=True)
        self.workspace.mkdir()
        result = self.handoff("update", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"missing; run create", result.stderr)
        self.handoff("remove", "fix")
        self.assertEqual(self.git("-C", self.repo, "remote").stdout, b"")

    def test_harness_cannot_reach_a_repository_outside_the_test_root(self):
        # 専用領域がまだ repo でない状態で git を動かしても、上位の repo に触れないこと。
        stray = self.agent_root / "stray"
        stray.mkdir()
        result = self.git("-C", stray, "rev-parse", "--show-toplevel", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"not a git repository", result.stderr)

    def test_create_defaults_name_to_branch_and_scopes_by_project(self):
        result = self.handoff("create")
        self.assertEqual(result.stdout.decode().strip(), str(self.agent_root / self.project / "main"))
        self.assertEqual(self.rev(self.agent_root / self.project / "main"), self.base)
        self.assertTrue(self.git("-C", self.repo, "config", "remote.handoff-main.url").stdout)
        # 別 project では同じ名前をそのまま使える。
        other = self.ghq / "example.com" / "owner" / "other"
        self.git("clone", "-q", self.repo, other)
        result = subprocess.run(
            ["bash", str(HANDOFF), "create"], cwd=other, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env, check=True,
        )
        self.assertEqual(result.stdout.decode().strip(), str(self.agent_root / "example.com" / "owner" / "other" / "main"))
        self.assertTrue((self.agent_root / self.project / "main").is_dir())
        # '/' を含む branch 名も、path に使える ID に置き換えて名前にする。
        self.git("-C", self.repo, "switch", "-q", "-c", "feature/x")
        result = self.handoff("create")
        self.assertEqual(
            result.stdout.decode().strip(),
            str(self.agent_root / self.project / ("x-" + b"feature/x".hex())),
        )

    def test_create_places_clone_under_the_ghq_path_of_the_repository(self):
        # ghq.root は複数書け、~ は git が展開する。未設定なら ~/ghq。
        second = self.home / "ghq"
        self.write_gitconfig(f"[ghq]\n\troot = {self.ghq}\n\troot = ~/ghq\n")
        repo = second / "example.org" / "group" / "sub" / "deep"
        self.git("clone", "-q", self.repo, repo)
        result = self.handoff("create", "fix", cwd=repo)
        expected = self.agent_root / "example.org" / "group" / "sub" / "deep" / "fix"
        self.assertEqual(result.stdout.decode().strip(), str(expected))
        self.write_gitconfig()
        self.handoff("remove", "fix", cwd=repo)
        result = self.handoff("create", "fix", cwd=repo)
        self.assertEqual(result.stdout.decode().strip(), str(expected))

    def test_where_prints_the_directory_holding_the_clones_of_the_repository(self):
        worktree = self.root / "wit-1234"
        self.git("-C", self.repo, "worktree", "add", "-q", "--detach", worktree)
        for cwd in (self.repo, worktree):
            result = self.handoff("where", cwd=cwd)
            self.assertEqual(result.stdout.decode(), f"{self.agent_root / self.project}\n")
        self.assertEqual(list(self.agent_root.iterdir()), [])
        loose = self.root / "loose"
        self.git("init", "-q", loose)
        result = self.handoff("where", check=False, cwd=loose)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"ghq", result.stderr)

    def test_id_prints_the_id_of_a_name_outside_any_repository(self):
        outside = self.root / "outside"
        outside.mkdir()
        for name, expected in (("fix", "fix"), ("feature/x", "x-" + b"feature/x".hex())):
            result = self.handoff("id", name, cwd=outside)
            self.assertEqual(result.stdout.decode(), f"{expected}\n")
        for args in (("id",), ("id", ""), ("id", "a\tb")):
            result = self.handoff(*args, check=False, cwd=outside)
            self.assertNotEqual(result.returncode, 0, args)

    def test_name_turns_an_id_back_into_its_name(self):
        outside = self.root / "outside"
        outside.mkdir()
        for name in ("fix", "feature/x", "ログイン"):
            id_ = self.handoff("id", name, cwd=outside).stdout.decode().strip()
            result = self.handoff("name", id_, cwd=outside)
            self.assertEqual(result.stdout.decode(), f"{name}\n")

    def test_name_rejects_what_id_never_produces(self):
        # x-666978 は fix に戻るが、fix の ID は fix なので、その名前の clone ではない。
        outside = self.root / "outside"
        outside.mkdir()
        for args in (("name",), ("name", ""), ("name", "x-666978"), ("name", "x-0a"),
                     ("name", "x-6"), ("name", "x-zz"), ("name", "-fix"), ("name", "fix", "more")):
            result = self.handoff(*args, check=False, cwd=outside)
            self.assertNotEqual(result.returncode, 0, args)
            self.assertEqual(result.stdout, b"", args)

    def test_create_rejects_a_repository_outside_ghq_root(self):
        loose = self.root / "loose"
        self.git("clone", "-q", self.repo, loose)
        result = self.handoff("create", "fix", check=False, cwd=loose)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"ghq", result.stderr)
        self.assertEqual(list(self.agent_root.iterdir()), [])
        self.assertEqual(self.git("-C", loose, "remote").stdout, b"origin\n")

    def test_remove_cleans_empty_parents_up_to_the_workspace_root(self):
        self.handoff("create", "fix")
        self.handoff("create", "other")
        self.handoff("remove", "fix")
        self.assertTrue((self.agent_root / self.project / "other").is_dir())
        self.handoff("remove", "other")
        self.assertEqual(list(self.agent_root.iterdir()), [])

    def test_create_from_linked_worktree_scopes_by_repository_name(self):
        # git-wit などの worktree はディレクトリ名が repo 名と無関係な ID になる。
        worktree = self.root / "wit-1234"
        self.git("-C", self.repo, "worktree", "add", "-q", "-b", "topic", worktree)
        result = self.handoff("create", "fix", cwd=worktree)
        self.assertEqual(result.stdout.decode().strip(), str(self.workspace))
        self.assertEqual(self.rev(self.workspace), self.base)

    def test_name_outside_the_ascii_rule_is_handed_off_under_a_hex_id(self):
        name = "ログイン 修正"
        workspace = self.agent_root / self.project / ("x-" + name.encode().hex())
        result = self.handoff("create", name)
        self.assertEqual(result.stdout.decode().strip(), str(workspace))
        remote = "handoff-x-" + name.encode().hex()
        self.assertEqual(
            self.git("-C", self.repo, "config", f"remote.{remote}.chelly-workspace").stdout.decode().strip(),
            str(workspace),
        )
        self.handoff("update", name)
        self.write(workspace, "feature", "done\n")
        self.commit(workspace, "agent work")
        self.handoff("fetch", name)
        self.assertEqual(self.rev(self.repo, f"refs/remotes/{remote}/main"), self.rev(workspace))
        self.handoff("remove", name, "--force")
        self.assertFalse(workspace.exists())
        self.assertEqual(self.git("-C", self.repo, "remote").stdout, b"")

    def test_names_that_would_be_unsafe_as_paths_or_refs_get_hex_ids(self):
        # 先頭の記号、'/'、ref に使えない並び、ID の接頭辞と紛れる名前は、そのまま使わない。
        for name in ("-x", "a/b", "a..b", ".hidden", "x-foo", "a.lock"):
            result = self.handoff("create", name)
            self.assertEqual(
                result.stdout.decode().strip(),
                str(self.agent_root / self.project / ("x-" + name.encode().hex())),
                name,
            )

    def test_create_rejects_unusable_names_and_unnamed_detached_head(self):
        for name in ("a\tb", "a\nb", "あ" * 34):
            result = self.handoff("create", name, check=False)
            self.assertEqual(result.returncode, 1, name)
            self.assertIn(b"NAME", result.stderr, name)
        self.assertEqual(list(self.agent_root.iterdir()), [])
        self.git("-C", self.repo, "switch", "-q", "--detach")
        result = self.handoff("create", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"NAME", result.stderr)
        self.assertFalse(self.workspace.exists())

    def test_create_from_a_commit_leaves_the_owner_checkout_alone(self):
        # PR の head のように、どの ref からも届かない commit から作る。
        tree = self.rev(self.repo, "HEAD^{tree}")
        commit = self.git(
            "-C", self.repo, "commit-tree", "-p", self.base, "-m", "pull request", tree,
        ).stdout.decode().strip()
        result = self.handoff("create", "fix", commit)
        self.assertEqual(result.stdout.decode().strip(), str(self.workspace))
        self.assertEqual(self.rev(self.workspace), commit)
        self.assertEqual(
            self.git("-C", self.workspace, "symbolic-ref", "--short", "HEAD").stdout.decode().strip(),
            "fix",
        )
        self.assertEqual(self.git("-C", self.workspace, "status", "--porcelain").stdout, b"")
        self.assertEqual(self.rev(self.repo), self.base)
        self.assertEqual(
            self.git("-C", self.repo, "symbolic-ref", "--short", "HEAD").stdout.decode().strip(),
            "main",
        )
        self.assertEqual(
            self.git("-C", self.repo, "config", "remote.handoff-fix.chelly-base").stdout.decode().strip(),
            commit,
        )
        self.assertEqual(
            self.git("-C", self.repo, "config", "remote.handoff-fix.chelly-branch", check=False).returncode,
            1,
        )
        self.assertEqual(self.git("-C", self.repo, "for-each-ref", "refs/chelly-handoff/").stdout, b"")
        self.assertEqual(
            self.git("-C", self.workspace, "for-each-ref", "--format=%(refname)").stdout.decode().split(),
            ["refs/heads/fix"],
        )
        self.handoff("remove", "fix")
        self.assertFalse(self.workspace.exists())

    def test_create_from_a_commit_sends_no_submodules(self):
        # COMMIT は本人の checkout と無関係なので、その gitlink の commit が本人の
        # submodule に無いこともあり、あっても送る相手として扱わない。
        self.add_submodule("sub")
        missing = "0" * 39 + "1"
        self.git("-C", self.repo, "update-index", "--cacheinfo", f"160000,{missing},sub")
        tree = self.git("-C", self.repo, "write-tree").stdout.decode().strip()
        self.git("-C", self.repo, "reset", "-q")
        commit = self.git(
            "-C", self.repo, "commit-tree", "-p", self.rev(self.repo), "-m", "bump sub", tree,
        ).stdout.decode().strip()
        self.handoff("create", "fix", commit)
        self.assertEqual(self.rev(self.workspace), commit)
        self.assertEqual(list((self.workspace / "sub").iterdir()), [])
        self.assertEqual(self.git("-C", self.workspace, "status", "--porcelain").stdout, b"")

    def test_create_rejects_an_unknown_commit(self):
        result = self.handoff("create", "fix", "0" * 40, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.workspace.exists())
        self.assertEqual(self.git("-C", self.repo, "remote").stdout, b"")

    def test_create_delivers_initialized_submodules_without_their_remotes(self):
        self.add_submodule("deps/sub")
        self.handoff("create", "fix")
        submodule = self.workspace / "deps" / "sub"
        self.assertEqual(self.rev(submodule), self.rev(self.repo / "deps" / "sub"))
        self.assertEqual(self.git("-C", self.workspace, "status", "--porcelain").stdout, b"")
        self.assertTrue((self.workspace / ".git" / "modules" / "deps" / "sub").is_dir())
        self.assertEqual(self.git("-C", submodule, "remote").stdout, b"")
        # 本人側の submodule には受け渡し用の ref を残さない。
        self.assertEqual(self.git("-C", self.repo / "deps" / "sub", "for-each-ref", "refs/chelly-handoff/").stdout, b"")

    def test_create_skips_uninitialized_submodules_and_rejects_missing_commits(self):
        self.add_submodule("sub")
        self.git("-C", self.repo, "submodule", "deinit", "-q", "sub")
        result = self.handoff("create", "fix")
        self.assertIn(b"submodule sub is not initialized", result.stderr)
        self.assertEqual(list((self.workspace / "sub").iterdir()), [])
        self.handoff("remove", "fix")
        self.git("-C", self.repo, "submodule", "update", "-q", "--init")
        missing = "0" * 39 + "1"
        self.git("-C", self.repo, "update-index", "--cacheinfo", f"160000,{missing},sub")
        self.git("-C", self.repo, "commit", "-q", "--no-verify", "-m", "dangling gitlink")
        result = self.handoff("create", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"git submodule update", result.stderr)
        self.assertFalse(self.workspace.exists())

    def test_detached_worktree_hands_off_and_follows_its_own_head(self):
        # git-wit の worktree は detached HEAD のまま作業し、そこで取り込みも行う。
        worktree = self.root / "wit-1234"
        self.git("-C", self.repo, "worktree", "add", "-q", "--detach", worktree)
        self.write(worktree, "tracked", "wit\n")
        wit_base = self.commit(worktree, "wit work")
        self.handoff("create", "fix", cwd=worktree)
        self.assertEqual(self.rev(self.workspace), wit_base)
        self.assertEqual(
            self.git("-C", self.workspace, "symbolic-ref", "--short", "HEAD").stdout.decode().strip(),
            "fix",
        )
        self.assertEqual(
            self.git("-C", self.repo, "config", "remote.handoff-fix.chelly-branch", check=False).returncode,
            1,
        )

        tip = self.agent_commit("feature", "done\n")
        result = self.handoff("fetch", "fix", cwd=worktree)
        self.assertEqual(self.rev(self.repo, "refs/remotes/handoff-fix/fix"), tip)
        self.assertIn(b"handoff-fix/fix", result.stdout)
        # agent が detached にしても、handoff の名前で受ける。
        self.git("-C", self.workspace, "switch", "-q", "--detach")
        tip = self.agent_commit("more", "x\n")
        self.handoff("fetch", "fix", cwd=worktree)
        self.assertEqual(self.rev(self.repo, "refs/remotes/handoff-fix/fix"), tip)

        self.git("-C", worktree, "cherry-pick", f"{wit_base}..refs/remotes/handoff-fix/fix")
        self.git("-C", worktree, "commit", "-q", "--amend", "--no-verify", "-m", "integrated")
        integrated = self.rev(worktree)
        # 本人の branch は動かさず、update を実行した worktree の HEAD に追従する。
        self.write(self.repo, "tracked", "owner\n")
        self.commit(self.repo, "owner work")
        result = self.handoff("update", "fix", cwd=worktree)
        self.assertIn(b"updated", result.stdout)
        self.assertEqual(self.rev(self.workspace), integrated)
        self.assertEqual(
            self.git("-C", self.workspace, "branch", "--list", "--format=%(refname:short)").stdout.decode().split(),
            ["fix"],
        )
        self.assertEqual(
            self.git("-C", self.repo, "config", "remote.handoff-fix.chelly-base").stdout.decode().strip(),
            integrated,
        )
        result = self.handoff("update", "fix", cwd=worktree)
        self.assertIn(b"up to date", result.stdout)

    def test_fetch_exposes_agent_commits_and_checks_new_paths(self):
        self.handoff("create", "fix")
        tip = self.agent_commit("feature", "done\n")
        result = self.handoff("fetch", "fix")
        self.assertEqual(self.rev(self.repo, "refs/remotes/handoff-fix/main"), tip)
        self.assertIn(b"handoff-fix/main", result.stdout)
        self.assertIn(b"commits 1", result.stdout.replace(b"\n", b" "))
        self.assertEqual(self.rev(self.repo), self.base)

        ignored_tip = self.agent_commit("token.secret", "x\n", "leak")
        result = self.handoff("fetch", "fix", check=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b"token.secret", result.stdout)
        self.assertEqual(self.rev(self.repo, "refs/remotes/handoff-fix/main"), ignored_tip)

    def test_fetch_follows_agent_head_on_another_branch(self):
        self.handoff("create", "fix")
        self.git("-C", self.workspace, "switch", "-q", "-c", "feat/topic")
        tip = self.agent_commit("feature", "done\n")
        result = self.handoff("fetch", "fix")
        self.assertEqual(self.rev(self.repo, "refs/remotes/handoff-fix/feat/topic"), tip)
        self.assertIn(b"handoff-fix/feat/topic", result.stdout)
        self.assertEqual(
            self.git("-C", self.repo, "rev-parse", "--verify", "-q", "refs/remotes/handoff-fix/main",
                     check=False).returncode,
            1,
        )

    def test_fetch_uses_recorded_branch_name_for_detached_head(self):
        self.handoff("create", "fix")
        self.git("-C", self.workspace, "switch", "-q", "--detach")
        tip = self.agent_commit("feature", "done\n")
        result = self.handoff("fetch", "fix")
        self.assertEqual(self.rev(self.repo, "refs/remotes/handoff-fix/main"), tip)
        self.assertIn(b"handoff-fix/main", result.stdout)
        # detached のままでも update は記録 branch に載せ直す。
        self.git("-C", self.repo, "merge", "-q", "--ff-only", "refs/remotes/handoff-fix/main")
        self.handoff("update", "fix")
        self.assertEqual(
            self.git("-C", self.workspace, "symbolic-ref", "--short", "HEAD").stdout.decode().strip(),
            "main",
        )
        self.assertEqual(self.rev(self.workspace), tip)

    def test_fetch_drops_remote_tracking_refs_from_earlier_branches(self):
        self.handoff("create", "fix")
        self.git("-C", self.workspace, "switch", "-q", "-c", "feat/topic")
        self.agent_commit("feature", "done\n")
        self.handoff("fetch", "fix")
        # 本人側に feat/topic が残ったままだと feat は directory と衝突して作れないので、先に消す必要がある。
        self.git("-C", self.workspace, "switch", "-q", "main")
        self.git("-C", self.workspace, "branch", "-q", "-D", "feat/topic")
        self.git("-C", self.workspace, "switch", "-q", "-c", "feat")
        tip = self.agent_commit("more", "x\n")
        self.handoff("fetch", "fix")
        self.assertEqual(
            self.git("-C", self.repo, "for-each-ref", "--format=%(refname)", "refs/remotes/handoff-fix/")
            .stdout.decode().split(),
            ["refs/remotes/handoff-fix/feat"],
        )
        self.assertEqual(self.rev(self.repo, "refs/remotes/handoff-fix/feat"), tip)

    def test_fetch_requires_a_clean_committed_workspace(self):
        self.handoff("create", "fix")
        result = self.handoff("fetch", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"no commits", result.stderr)
        self.agent_commit("feature", "done\n")
        self.write(self.workspace, "feature", "edited\n")
        result = self.handoff("fetch", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"not clean", result.stderr)
        self.assertEqual(
            self.git("-C", self.repo, "rev-parse", "--verify", "-q", "refs/remotes/handoff-fix/main",
                     check=False).returncode,
            1,
        )

    def test_fetch_rejects_unknown_remote(self):
        self.git("-C", self.repo, "remote", "add", "handoff-fix", "/nonexistent")
        result = self.handoff("fetch", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"not created by chelly-handoff", result.stderr)

    def test_remove_protects_unfetched_work_unless_forced(self):
        self.handoff("create", "fix")
        self.agent_commit("feature", "done\n")
        result = self.handoff("remove", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"run fetch first", result.stderr)
        self.assertTrue(self.workspace.exists())

        self.handoff("fetch", "fix")
        self.write(self.workspace, "scratch", "x\n")
        result = self.handoff("remove", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"uncommitted", result.stderr)

        self.handoff("remove", "fix", "--force")
        self.assertFalse(self.workspace.exists())
        self.assertFalse(self.workspace.parent.exists())
        self.assertEqual(self.git("-C", self.repo, "remote").stdout, b"")
        self.assertFalse((self.repo / ".git" / "chelly-handoff" / "fix.bundle").exists())
        self.assertEqual(
            self.git("-C", self.repo, "rev-parse", "--verify", "-q", "refs/remotes/handoff-fix/main",
                     check=False).returncode,
            1,
        )

    def test_update_moves_workspace_to_owner_branch_tip(self):
        self.handoff("create", "fix")
        self.write(self.repo, "tracked", "owner\n")
        owner_tip = self.commit(self.repo, "owner work")
        result = self.handoff("update", "fix")
        self.assertIn(b"updated", result.stdout)
        self.assertEqual(self.rev(self.workspace), owner_tip)
        self.assertEqual(
            self.git("-C", self.repo, "config", "remote.handoff-fix.chelly-base").stdout.decode().strip(),
            owner_tip,
        )
        self.assertEqual(self.git("-C", self.workspace, "status", "--porcelain").stdout, b"")
        # 取得済みの agent commit は捨ててよく、本人側で取り込んだ形に揃う。
        self.agent_commit("feature", "done\n")
        self.handoff("fetch", "fix")
        self.git("-C", self.repo, "cherry-pick", "refs/remotes/handoff-fix/main")
        # 同じ親・tree・時刻だと cherry-pick が同一 SHA になるので、取り込み側で書き換わった形にする。
        self.git("-C", self.repo, "commit", "-q", "--amend", "--no-verify", "-m", "integrated")
        integrated = self.rev(self.repo)
        self.assertNotEqual(integrated, self.rev(self.repo, "refs/remotes/handoff-fix/main"))
        # 本人が別 branch にいても、記録した branch の先端に追従する。
        self.git("-C", self.repo, "switch", "-q", "-c", "elsewhere")
        result = self.handoff("update", "fix")
        self.assertEqual(self.rev(self.workspace), integrated)
        self.assertEqual((self.workspace / "feature").read_text(), "done\n")
        self.assertEqual(
            self.git("-C", self.repo, "rev-parse", "--verify", "-q", "refs/remotes/handoff-fix/main",
                     check=False).returncode,
            1,
        )
        result = self.handoff("update", "fix")
        self.assertIn(b"up to date", result.stdout)

    def test_update_returns_workspace_to_recorded_branch_and_drops_agent_branch(self):
        self.handoff("create", "fix")
        self.git("-C", self.workspace, "switch", "-q", "-c", "feat/topic")
        self.agent_commit("feature", "done\n")
        self.handoff("fetch", "fix")
        self.git("-C", self.repo, "cherry-pick", "refs/remotes/handoff-fix/feat/topic")
        self.git("-C", self.repo, "commit", "-q", "--amend", "--no-verify", "-m", "integrated")
        integrated = self.rev(self.repo)
        result = self.handoff("update", "fix")
        self.assertIn(b"updated", result.stdout)
        self.assertEqual(self.rev(self.workspace), integrated)
        self.assertEqual(
            self.git("-C", self.workspace, "symbolic-ref", "--short", "HEAD").stdout.decode().strip(),
            "main",
        )
        self.assertEqual(
            self.git("-C", self.workspace, "branch", "--list", "--format=%(refname:short)").stdout.decode().split(),
            ["main"],
        )
        self.assertEqual(
            self.git("-C", self.repo, "for-each-ref", "refs/remotes/handoff-fix/").stdout,
            b"",
        )

    def test_update_returns_to_recorded_branch_even_when_tip_is_unchanged(self):
        # ff-only で取り込むと SHA が変わらず先端は一致するが、clone は agent の branch に居る。
        self.handoff("create", "fix")
        self.git("-C", self.workspace, "switch", "-q", "-c", "feat/topic")
        tip = self.agent_commit("feature", "done\n")
        self.handoff("fetch", "fix")
        self.git("-C", self.repo, "merge", "-q", "--ff-only", "refs/remotes/handoff-fix/feat/topic")
        result = self.handoff("update", "fix")
        self.assertIn(b"updated", result.stdout)
        self.assertEqual(self.rev(self.workspace), tip)
        self.assertEqual(
            self.git("-C", self.workspace, "branch", "--list", "--format=%(refname:short)").stdout.decode().split(),
            ["main"],
        )
        self.assertEqual(
            self.git("-C", self.repo, "config", "remote.handoff-fix.chelly-base").stdout.decode().strip(),
            tip,
        )
        # 本人側も先端も動いていないが agent が branch だけ切った場合も、記録 branch に戻す。
        self.git("-C", self.workspace, "switch", "-q", "-c", "feat/idle")
        result = self.handoff("update", "fix")
        self.assertIn(b"updated", result.stdout)
        self.assertEqual(
            self.git("-C", self.workspace, "branch", "--list", "--format=%(refname:short)").stdout.decode().split(),
            ["main"],
        )
        result = self.handoff("update", "fix")
        self.assertIn(b"up to date", result.stdout)

    def test_update_does_not_fetch_submodules_from_their_remotes(self):
        # 本人が共有領域で手動 init した submodule は、transport から届かない remote を向いている。
        self.add_submodule("sub")
        self.handoff("create", "fix")
        self.git("-C", self.workspace, "submodule", "init", "-q")
        self.git("-C", self.workspace / "sub", "remote", "add", "origin", self.root / "unreachable")
        owner_tip = self.bump_submodule("sub")
        self.handoff("update", "fix")
        self.assertEqual(self.rev(self.workspace), owner_tip)

    def test_update_moves_submodules_to_the_recorded_commits(self):
        self.add_submodule("one")
        self.add_submodule("two")
        self.handoff("create", "fix")
        self.bump_submodule("one")
        self.bump_submodule("two")
        self.add_submodule("three")
        owner_tip = self.rev(self.repo)
        self.handoff("update", "fix")
        self.assertEqual(self.rev(self.workspace), owner_tip)
        for path in ("one", "two", "three"):
            self.assertEqual(self.rev(self.workspace / path), self.rev(self.repo / path))
        self.assertEqual(self.git("-C", self.workspace, "status", "--porcelain").stdout, b"")
        # 次の受け渡しが clean な workspace を前提に続けられる。
        self.agent_commit("feature", "done\n")
        self.handoff("fetch", "fix")

    def test_handoff_git_starts_no_background_maintenance(self):
        trace = self.root / "trace.json"
        self.env["GIT_TRACE2_EVENT"] = str(trace)
        self.add_submodule("sub")
        self.handoff("create", "fix")
        self.agent_commit("feature", "done\n")
        self.handoff("fetch", "fix")
        self.bump_submodule("sub")
        self.handoff("update", "fix")
        events = [json.loads(line) for line in trace.read_text().splitlines()]
        self.assertEqual(
            [e["argv"] for e in events if e["event"] == "start" and "maintenance" in e["argv"]],
            [],
        )

    def test_handoff_git_drops_the_untracked_cache_an_agent_enabled(self):
        self.handoff("create", "fix")
        self.git("-C", self.workspace, "config", "core.untrackedCache", "true")
        self.agent_commit("feature", "done\n")
        self.git("-C", self.workspace, "status", "--porcelain")
        index = self.workspace / ".git" / "index"
        self.assertTrue(b"UNTR" in index.read_bytes())
        self.handoff("fetch", "fix")
        self.assertFalse(b"UNTR" in index.read_bytes())

    def test_workspace_left_behind_by_a_failed_submodule_send_is_recreated(self):
        self.add_submodule("sub")
        self.handoff("create", "fix")
        owner_tip = self.bump_submodule("sub")
        # 本体だけ先端に進み、submodule の送信前に止まった状態。
        self.git("-C", self.workspace, "fetch", "-q", "--recurse-submodules=no", self.repo, "main")
        self.git("-C", self.workspace, "switch", "-q", "--force", "-C", "main", owner_tip)
        result = self.handoff("update", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.handoff("remove", "fix", "--force")
        self.handoff("create", "fix")
        self.assertEqual(self.rev(self.workspace / "sub"), self.rev(self.repo / "sub"))
        self.assertEqual(self.git("-C", self.workspace, "status", "--porcelain").stdout, b"")

    def test_update_refuses_unfetched_or_uncommitted_agent_work(self):
        self.handoff("create", "fix")
        self.agent_commit("feature", "done\n")
        self.write(self.repo, "tracked", "owner\n")
        self.commit(self.repo, "owner work")
        result = self.handoff("update", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"run fetch first", result.stderr)
        self.handoff("fetch", "fix")
        self.write(self.workspace, "scratch", "x\n")
        result = self.handoff("update", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"uncommitted", result.stderr)
        self.assertNotEqual(self.rev(self.workspace), self.rev(self.repo))

    def test_remove_cleans_up_after_fetch_without_force(self):
        self.handoff("create", "fix")
        self.agent_commit("feature", "done\n")
        self.handoff("fetch", "fix")
        self.handoff("remove", "fix")
        self.assertFalse(self.workspace.exists())
        self.assertEqual(self.git("-C", self.repo, "remote").stdout, b"")
        # 二度目は clone が無くても remote の残りを消して成功する。
        self.git("-C", self.repo, "remote", "add", "handoff-fix", "/nonexistent")
        self.handoff("remove", "fix")
        self.assertEqual(self.git("-C", self.repo, "remote").stdout, b"")

    def config(self, key):
        return self.git("-C", self.repo, "config", "--get-all", key, check=False).stdout.decode().split()

    def test_send_lets_the_agent_rebase_onto_the_owner_tip(self):
        self.handoff("create", "fix")
        self.agent_commit("tracked", "agent\n")
        self.write(self.repo, "tracked", "owner\n")
        owner_tip = self.commit(self.repo, "owner work")
        agent_head = self.rev(self.workspace)
        # agent が作業中でも送れて、clone の HEAD と作業ツリーには触れない。
        self.write(self.workspace, "scratch", "x\n")
        result = self.handoff("send", "fix")
        self.assertIn(b"upstream/main", result.stdout)
        self.assertEqual(self.rev(self.workspace, "refs/remotes/upstream/main"), owner_tip)
        self.assertEqual(self.rev(self.workspace), agent_head)
        self.assertEqual((self.workspace / "scratch").read_text(), "x\n")
        self.assertEqual(self.config("remote.handoff-fix.chelly-sent"), [owner_tip])
        (self.workspace / "scratch").unlink()

        # rebase しないままでも従来どおり base から受け取れる。
        self.handoff("fetch", "fix")
        self.assertEqual(self.config("remote.handoff-fix.chelly-fetched-base"), [self.base])

        rebase = self.git("-C", self.workspace, "rebase", "-q", "refs/remotes/upstream/main", check=False)
        self.assertNotEqual(rebase.returncode, 0)
        self.write(self.workspace, "tracked", "owner\nagent\n")
        self.git("-C", self.workspace, "add", "tracked")
        self.git("-C", self.workspace, "-c", "core.editor=true", "rebase", "--continue")
        tip = self.rev(self.workspace)

        result = self.handoff("fetch", "fix")
        self.assertIn(f"{owner_tip}..handoff-fix/main".encode(), result.stdout)
        self.assertEqual(self.config("remote.handoff-fix.chelly-fetched-base"), [owner_tip])
        self.assertEqual(self.config("remote.handoff-fix.chelly-base"), [self.base])
        self.assertEqual(self.rev(self.repo, "refs/remotes/handoff-fix/main"), tip)
        self.git("-C", self.repo, "cherry-pick", f"{owner_tip}..refs/remotes/handoff-fix/main")
        self.assertEqual((self.repo / "tracked").read_text(), "owner\nagent\n")
        self.git("-C", self.repo, "commit", "-q", "--amend", "--no-verify", "-m", "integrated")
        result = self.handoff("update", "fix")
        self.assertIn(b"updated", result.stdout)
        self.assertEqual(self.rev(self.workspace), self.rev(self.repo))

    def test_send_lets_the_agent_replay_unpushed_commits_onto_origin(self):
        self.git("-C", self.repo, "switch", "-q", "-c", "elsewhere")
        self.write(self.repo, "tracked", "origin\n")
        origin_tip = self.commit(self.repo, "pushed elsewhere")
        self.git("-C", self.repo, "update-ref", "refs/remotes/origin/main", origin_tip)
        self.git("-C", self.repo, "switch", "-q", "main")
        self.git("-C", self.repo, "branch", "-q", "-D", "elsewhere")
        self.write(self.repo, "tracked", "owner\n")
        self.commit(self.repo, "unpushed")
        self.handoff("create", "fix")

        self.handoff("send", "fix", "main", "origin/main")
        self.assertEqual(self.rev(self.workspace, "refs/remotes/upstream/origin/main"), origin_tip)
        rebase = self.git("-C", self.workspace, "rebase", "-q", "refs/remotes/upstream/origin/main", check=False)
        self.assertNotEqual(rebase.returncode, 0)
        self.write(self.workspace, "tracked", "origin\nowner\n")
        self.git("-C", self.workspace, "add", "tracked")
        self.git("-C", self.workspace, "-c", "core.editor=true", "rebase", "--continue")

        result = self.handoff("fetch", "fix")
        self.assertIn(f"{origin_tip}..handoff-fix/main".encode(), result.stdout)
        self.git("-C", self.repo, "reset", "-q", "--hard", "origin/main")
        self.git("-C", self.repo, "cherry-pick", f"{origin_tip}..refs/remotes/handoff-fix/main")
        self.assertEqual((self.repo / "tracked").read_text(), "origin\nowner\n")

    def test_fetch_checks_from_the_base_when_the_agent_forges_upstream(self):
        self.handoff("create", "fix")
        self.write(self.repo, "tracked", "owner\n")
        self.commit(self.repo, "owner work")
        self.handoff("send", "fix")
        # agent は upstream の ref を書き換えられるので、検査の起点は本人が送った記録だけから選ぶ。
        self.agent_commit("token.secret", "x\n", "leak")
        self.git("-C", self.workspace, "update-ref", "refs/remotes/upstream/main", "HEAD")
        self.agent_commit("feature", "done\n")
        result = self.handoff("fetch", "fix", check=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn(b"token.secret", result.stdout)
        self.assertEqual(self.config("remote.handoff-fix.chelly-fetched-base"), [self.base])

    def test_fetch_requires_commits_on_top_of_what_was_sent(self):
        self.handoff("create", "fix")
        self.write(self.repo, "tracked", "owner\n")
        self.commit(self.repo, "owner work")
        self.handoff("send", "fix")
        self.git("-C", self.workspace, "reset", "-q", "--hard", "refs/remotes/upstream/main")
        result = self.handoff("fetch", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"no commits", result.stderr)

    def test_send_rejects_refs_it_cannot_name_or_trust(self):
        self.handoff("create", "fix")
        self.agent_commit("feature", "done\n")
        self.handoff("fetch", "fix")
        # 受け取っただけで未検査の agent の commit を、検査の起点にさせない。
        for ref in ("handoff-fix/main", "v1", "nonexistent"):
            if ref == "v1":
                self.git("-C", self.repo, "tag", "v1")
            result = self.handoff("send", "fix", ref, check=False)
            self.assertEqual(result.returncode, 1, ref)
        self.assertEqual(self.config("remote.handoff-fix.chelly-sent"), [])
        self.assertEqual(
            self.git("-C", self.workspace, "for-each-ref", "refs/remotes/upstream/").stdout, b"",
        )

    def test_send_delivers_a_ref_the_workspace_already_has(self):
        self.handoff("create", "fix")
        self.handoff("send", "fix")
        self.assertEqual(self.rev(self.workspace, "refs/remotes/upstream/main"), self.base)


if __name__ == "__main__":
    unittest.main()
