import os
import pty
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HANDOFF = Path(__file__).parents[1] / "chelly-handoff.sh"
CHECKER = Path(__file__).parents[1] / "git_check_new_ignored.py"

# 実機の chelly-agent は sudo と podman を経て同じ引数列を実行する。テストでは
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
        fake = self.bin / "chelly-agent"
        fake.write_text(FAKE_AGENT)
        fake.chmod(0o755)
        checker = self.bin / "git-check-new-ignored"
        checker.write_text(f"#!/bin/sh\nexec {sys.executable} {CHECKER} \"$@\"\n")
        checker.chmod(0o755)
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
        self.repo = self.root / "source"
        self.git("init", "-q", "-b", "main", self.repo)
        self.git("-C", self.repo, "config", "commit.gpgsign", "false")
        self.write(self.repo, ".gitignore", "*.secret\n")
        self.write(self.repo, "tracked", "base\n")
        self.commit(self.repo, "base")
        self.base = self.rev(self.repo)
        self.workspace = self.agent_root / "source" / "fix"

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", "-c", "maintenance.auto=false", *map(str, args)],
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

    def handoff(self, *args, check=True):
        # 本人は端末から起動するので、stdin を擬似端末にして同じ形で動かす。
        leader, follower = pty.openpty()
        try:
            return subprocess.run(
                ["bash", str(HANDOFF), *args], cwd=self.repo, stdin=follower,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env, check=check,
            )
        finally:
            os.close(follower)
            os.close(leader)

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

    def test_harness_cannot_reach_a_repository_outside_the_test_root(self):
        # 専用領域がまだ repo でない状態で git を動かしても、上位の repo に触れないこと。
        stray = self.agent_root / "stray"
        stray.mkdir()
        result = self.git("-C", stray, "rev-parse", "--show-toplevel", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"not a git repository", result.stderr)

    def test_create_defaults_name_to_branch_and_scopes_by_project(self):
        result = self.handoff("create")
        self.assertEqual(result.stdout.decode().strip(), str(self.agent_root / "source" / "main"))
        self.assertEqual(self.rev(self.agent_root / "source" / "main"), self.base)
        self.assertTrue(self.git("-C", self.repo, "config", "remote.handoff-main.url").stdout)
        # 別 project では同じ名前をそのまま使える。
        other = self.root / "other"
        self.git("clone", "-q", self.repo, other)
        result = subprocess.run(
            ["bash", str(HANDOFF), "create"], cwd=other, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env, check=True,
        )
        self.assertEqual(result.stdout.decode().strip(), str(self.agent_root / "other" / "main"))
        self.assertTrue((self.agent_root / "source" / "main").is_dir())
        self.git("-C", self.repo, "switch", "-q", "-c", "feature/x")
        result = self.handoff("create", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"NAME", result.stderr)

    def test_create_rejects_bad_names_and_detached_head(self):
        for name in ("-x", "a/b", "a b", "..", ".hidden"):
            result = self.handoff("create", name, check=False)
            self.assertNotEqual(result.returncode, 0, name)
        self.assertFalse(self.workspace.exists())
        self.git("-C", self.repo, "switch", "-q", "--detach")
        result = self.handoff("create", "fix", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"named branch", result.stderr)

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


if __name__ == "__main__":
    unittest.main()
