import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "brainium_handoff_pending.py"

TASKS = """\
* Next
** TODO 既存の作業
** TODO 前からある依頼 :handoff:
"""
# 前からある依頼は本人が処理済みで、作業ツリーでは DONE になっている。
PROCESSED = TASKS.replace("TODO 前から", "DONE 前から")


class PendingTest(unittest.TestCase):
    def setUp(self):
        test_tmp = Path(os.environ.get("TEST_TMPDIR", Path.cwd() / ".test-tmp"))
        test_tmp.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=test_tmp)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.home.mkdir()
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
            # テスト用の root より上にある repo を git が見つけないようにする。
            "GIT_CEILING_DIRECTORIES": str(self.root),
        }
        self.owner = self.root / "owner" / "brainium"
        self.git("init", "-q", "-b", "main", self.owner)
        self.git("-C", self.owner, "config", "commit.gpgsign", "false")
        self.write(self.owner, "tasks.org", TASKS)
        self.commit(self.owner, "base")
        base = self.git("-C", self.owner, "rev-parse", "HEAD").stdout.strip()
        self.write(self.owner, "tasks.org", PROCESSED)
        self.clone = self.root / "agent" / "brainium" / "brainium"
        self.git("clone", "-q", self.owner, self.clone)
        self.git("-C", self.clone, "config", "commit.gpgsign", "false")
        self.git("-C", self.owner, "config", "remote.handoff-brainium.chelly-base", base)
        self.git("-C", self.owner, "config", "remote.handoff-brainium.chelly-workspace", self.clone)
        self.marker = self.root / "pwned"

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, *args):
        return subprocess.run(
            ["git", "-c", "maintenance.auto=false", *map(str, args)],
            capture_output=True, text=True, env=self.env, check=True,
        )

    def write(self, repo, name, text):
        (repo / name).write_text(text)

    def commit(self, repo, message):
        self.git("-C", repo, "add", "-A")
        self.git("-C", repo, "commit", "-q", "-m", message)

    def agent_writes(self, text):
        self.write(self.clone, "tasks.org", text)
        self.commit(self.clone, "agent work")

    def pending(self, name="brainium", env=None):
        return subprocess.run(
            [sys.executable, SCRIPT, self.owner, name],
            capture_output=True, text=True, encoding="utf-8", env=env or self.env, timeout=60,
        )

    def assertPending(self, *lines):
        result = self.pending()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout.splitlines()[1:], list(lines))
        self.assertEqual(
            result.stdout.splitlines()[0], f"brainium の handoff の依頼が {len(lines)} 件ある"
        )

    def assertNothingPending(self):
        result = self.pending()
        self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)

    def test_nothing_pending_when_only_processed_requests_exist(self):
        self.assertNothingPending()

    def test_new_request_in_agent_clone_is_pending_before_fetch(self):
        self.agent_writes(TASKS + "** TODO 鍵を替える :chelly:handoff:\n")
        self.assertPending("- 取り込み前: 鍵を替える")

    def test_request_already_in_base_is_not_pending_again(self):
        self.agent_writes(TASKS + "** TODO 普通の作業\n")
        self.assertNothingPending()

    def test_request_without_handoff_tag_is_not_pending(self):
        self.agent_writes(TASKS + "** TODO 鍵を替える :chelly:\n")
        self.assertNothingPending()

    def test_closed_request_in_agent_clone_is_not_pending(self):
        self.agent_writes(TASKS + "** DONE 鍵を替える :handoff:\n")
        self.assertNothingPending()

    def test_imported_request_is_not_pending_before_update(self):
        self.agent_writes(TASKS + "** TODO 鍵を替える :handoff:\n")
        for imported in (
            "** TODO 鍵を替える :handoff:\n",
            "** WIP [#A] 鍵を替える :handoff:\n",
            "** DONE 鍵を替える :handoff:\n",
        ):
            with self.subTest(imported=imported):
                self.write(self.owner, "tasks.org", PROCESSED + imported)
                self.assertNothingPending()

    def test_open_request_only_in_owner_tasks_is_not_pending(self):
        self.write(self.owner, "tasks.org", TASKS + "** TODO 鍵を替える :handoff:\n")
        self.assertNothingPending()

    def test_archived_request_is_not_pending_before_update(self):
        self.agent_writes(TASKS + "** TODO 鍵を替える :handoff:\n")
        self.write(self.owner, "tasks.org_archive", "* DONE 鍵を替える :handoff:\n")
        self.assertNothingPending()

    def test_renamed_request_is_pending_again_until_update(self):
        self.agent_writes(TASKS + "** TODO 鍵を替える :handoff:\n")
        self.write(self.owner, "tasks.org", PROCESSED + "** DONE 鍵を新しくする\n")
        self.assertPending("- 取り込み前: 鍵を替える")

    def test_reads_and_reports_utf8_without_a_utf8_locale(self):
        # launchd と systemd の user service は LANG を渡さない。
        self.agent_writes(TASKS + "** TODO 鍵を替える :handoff:\n")
        env = {**self.env, "LC_ALL": "C", "PYTHONUTF8": "0", "PYTHONCOERCECLOCALE": "0"}
        env.pop("LANG", None)
        result = self.pending(env=env)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(result.stdout.splitlines()[1:], ["- 取り込み前: 鍵を替える"])

    def test_agent_branch_head_is_read(self):
        self.git("-C", self.clone, "switch", "-q", "-c", "feat")
        self.agent_writes(TASKS + "** TODO 鍵を替える :handoff:\n")
        self.assertPending("- 取り込み前: 鍵を替える")

    def test_lists_are_bounded_and_titles_are_cleaned(self):
        requests = "".join(f"** TODO 依頼 {i:02} :handoff:\n" for i in range(25))
        self.agent_writes(TASKS + requests + "** TODO 長い" + "あ" * 300 + "\x1b[31m :handoff:\n")
        result = self.pending()
        self.assertEqual(result.returncode, 1)
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], "brainium の handoff の依頼が 26 件ある")
        self.assertEqual(len(lines), 1 + 20 + 1)
        self.assertEqual(lines[-1], "ほか 6 件")
        self.assertTrue(all(len(line) <= 220 for line in lines))
        self.assertNotIn("\x1b", result.stdout)

    def test_hooks_and_config_in_agent_clone_do_not_run(self):
        (self.clone / ".gitattributes").write_text("* filter=evil diff=evil\n")
        self.agent_writes(TASKS + "** TODO 鍵を替える :handoff:\n")
        payload = self.root / "payload"
        payload.write_text(f"#!/bin/sh\ntouch {self.marker}\n")
        payload.chmod(0o755)
        hooks = self.clone / ".git" / "hooks"
        for hook in (
            "pre-commit", "post-checkout", "post-index-change", "reference-transaction",
            "pre-auto-gc", "fsmonitor-watchman", "post-rewrite",
        ):
            (hooks / hook).write_text(payload.read_text())
            (hooks / hook).chmod(0o755)
        for key, value in (
            ("core.fsmonitor", payload),
            ("core.pager", payload),
            ("pager.cat-file", payload),
            ("pager.rev-parse", payload),
            ("core.hooksPath", hooks),
            ("core.sshCommand", payload),
            ("core.alternateRefsCommand", payload),
            ("filter.evil.smudge", payload),
            ("diff.evil.textconv", payload),
            ("alias.cat-file", f"!{payload}"),
        ):
            self.git("-C", self.clone, "config", key, value)
        self.assertPending("- 取り込み前: 鍵を替える")
        self.assertFalse(self.marker.exists())

    def test_replace_refs_in_agent_clone_do_not_change_what_is_read(self):
        self.agent_writes(TASKS + "** TODO 鍵を替える :handoff:\n")
        real = self.git("-C", self.clone, "rev-parse", "HEAD:tasks.org").stdout.strip()
        fake = subprocess.run(
            ["git", "-C", self.clone, "hash-object", "-w", "--stdin"],
            input=TASKS, capture_output=True, text=True, env=self.env, check=True,
        ).stdout.strip()
        self.git("-C", self.clone, "replace", real, fake)
        self.assertPending("- 取り込み前: 鍵を替える")

    def test_missing_workspace_is_reported_as_failure(self):
        self.git("-C", self.owner, "config", "remote.handoff-brainium.chelly-workspace",
                 self.root / "missing")
        result = self.pending()
        self.assertEqual(result.returncode, 2)
        self.assertTrue(result.stdout.startswith("brainium の handoff を確かめられない: "))

    def test_unknown_handoff_is_reported_as_failure(self):
        result = self.pending("unknown")
        self.assertEqual(result.returncode, 2)
        self.assertTrue(result.stdout.startswith("unknown の handoff を確かめられない: "))

    def test_oversized_tasks_in_agent_clone_is_reported_as_failure(self):
        self.agent_writes(TASKS + "x" * (5 * 1024 * 1024))
        result = self.pending()
        self.assertEqual(result.returncode, 2)
        self.assertIn("大きすぎる", result.stdout)


if __name__ == "__main__":
    unittest.main()
