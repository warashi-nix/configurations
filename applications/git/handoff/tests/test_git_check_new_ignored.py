import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "git_check_new_ignored.py"


class IntakeTest(unittest.TestCase):
    def setUp(self):
        test_tmp = Path(os.environ.get("TEST_TMPDIR", Path.cwd() / ".test-tmp"))
        test_tmp.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=test_tmp)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.home.mkdir()
        (self.home / ".config/git").mkdir(parents=True)
        self.env = {
            **os.environ,
            "GIT_CONFIG_NOSYSTEM": "1",
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.invalid",
            "GIT_CONFIG_GLOBAL": str(self.home / "gitconfig"),
        }
        for name in tuple(self.env):
            if name == "GIT_CONFIG_COUNT" or name.startswith("GIT_CONFIG_KEY_") or name.startswith(
                "GIT_CONFIG_VALUE_"
            ):
                self.env.pop(name)
        self.policy = self.root / "policy"
        self.candidate = self.root / "candidate"
        self.objects = self.root / "review.git"
        self.git("init", "-q", "-b", "main", str(self.policy))
        self.git("-C", str(self.policy), "config", "commit.gpgSign", "false")
        self.write(self.policy, "tracked", "base\n")
        self.commit(self.policy, "base")
        self.base = self.rev(self.policy, "HEAD")
        self.git("clone", "-q", str(self.policy), str(self.candidate))
        self.git("-C", str(self.candidate), "config", "commit.gpgSign", "false")
        self.git("init", "-q", "--bare", str(self.objects))
        self.git("-C", str(self.policy), "push", "-q", str(self.objects), "HEAD:refs/heads/base")

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, *args, check=True, input=None):
        return subprocess.run(
            ["git", "-c", "maintenance.auto=false", *args],
            env=self.env,
            input=input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=check,
        )

    def write(self, repo, name, content):
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self, repo, message):
        cached = self.git(
            "-C", str(repo), "ls-files", "--cached", "-z"
        ).stdout
        self.git(
            "-C",
            str(repo),
            "update-index",
            "--remove",
            "-z",
            "--stdin",
            input=cached,
        )
        changed = self.git(
            "-C", str(repo), "ls-files", "--modified", "--others", "-z"
        ).stdout
        self.git(
            "-C",
            str(repo),
            "update-index",
            "--add",
            "-z",
            "--stdin",
            input=changed,
        )
        self.git("-C", str(repo), "commit", "-q", "-m", message)
        return self.rev(repo, "HEAD")

    def rev(self, repo, ref):
        return self.git("-C", str(repo), "rev-parse", ref).stdout.decode().strip()

    def push_tip(self):
        tip = self.rev(self.candidate, "HEAD")
        self.git("-C", str(self.candidate), "push", "-q", str(self.objects), f"{tip}:refs/heads/tip")
        return tip

    def check(self, base=None, tip=None, policy=None, objects=None, env=None):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--object-repo",
                str(objects or self.objects),
                "--policy-repo",
                str(policy or self.policy),
                base or self.base,
                tip or self.rev(self.candidate, "HEAD"),
            ],
            env=env or self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def set_base_ignore(self, content, nested=None):
        self.write(self.policy, ".gitignore", content)
        if nested is not None:
            self.write(self.policy, "sub/.gitignore", nested)
        self.commit(self.policy, "policy")
        self.base = self.rev(self.policy, "HEAD")
        self.git("-C", str(self.policy), "push", "-q", str(self.objects), "HEAD:refs/heads/base")
        self.git("-C", str(self.candidate), "fetch", "-q", str(self.policy))
        self.git("-C", str(self.candidate), "switch", "-q", "--detach", self.base)

    def test_clean_addition_passes_and_prints_fixed_range(self):
        self.write(self.candidate, "ok.txt", "ok")
        tip = self.commit(self.candidate, "clean")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"BASE {self.base}", result.stdout.decode())
        self.assertIn(f"TIP {tip}", result.stdout.decode())
        self.assertIn("commits 1", result.stdout.decode())

    def test_owner_git_directory_can_serve_as_object_repository(self):
        self.set_base_ignore("*.secret\n")
        self.write(self.candidate, "leak.secret", "x")
        tip = self.commit(self.candidate, "fetched into owner repo")
        self.git("-C", str(self.policy), "fetch", "-q", str(self.candidate), f"{tip}:refs/remotes/agent/main")
        result = self.check(tip="refs/remotes/agent/main", objects=self.policy / ".git")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('"leak.secret"', result.stdout.decode())

    def test_global_root_nested_and_info_rules_with_negation(self):
        self.set_base_ignore("*.log\n!root.log\nbuild/\n", "*.tmp\n!keep.tmp\n")
        global_ignore = self.home / ".config/git/ignore"
        global_ignore.write_text("global.secret\n")
        info = self.policy / ".git/info/exclude"
        info.write_text("local.secret\n")
        for name in (
            "bad.log",
            "root.log",
            "build/output",
            "sub/bad.tmp",
            "sub/keep.tmp",
            "global.secret",
            "local.secret",
        ):
            self.write(self.candidate, name, "x")
        tip = self.commit(self.candidate, "mixed")
        self.push_tip()
        result = self.check(tip=tip)
        output = result.stdout.decode()
        self.assertEqual(result.returncode, 1, result.stderr)
        for name in (
            "bad.log",
            "build/output",
            "sub/bad.tmp",
            "global.secret",
            "local.secret",
        ):
            self.assertIn(f'"{name}"', output)
        for name in ("root.log", "sub/keep.tmp"):
            self.assertNotIn(f'"{name}"', output)
        self.assertIn("base:.gitignore", output)
        self.assertIn(str(global_ignore), output)
        self.assertIn(str(info), output)

    def test_escaped_bang_pattern_is_respected(self):
        self.set_base_ignore("\\!secret\n")
        self.write(self.candidate, "!secret", "x")
        tip = self.commit(self.candidate, "bang")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1)
        self.assertIn('"!secret"', result.stdout.decode())

    def test_tracked_ignored_modification_is_not_new(self):
        self.write(self.policy, ".gitignore", "tracked\n")
        self.commit(self.policy, "ignore tracked")
        self.base = self.rev(self.policy, "HEAD")
        self.git("-C", str(self.policy), "push", "-q", str(self.objects), "HEAD:refs/heads/base")
        self.git("-C", str(self.candidate), "fetch", "-q", str(self.policy))
        self.git("-C", str(self.candidate), "switch", "-q", "--detach", self.base)
        self.write(self.candidate, "tracked", "changed\n")
        tip = self.commit(self.candidate, "modify")
        self.push_tip()
        self.assertEqual(self.check(tip=tip).returncode, 0)

    def test_add_then_delete_is_still_reported(self):
        self.set_base_ignore("gone\n")
        self.write(self.candidate, "gone", "x")
        first = self.commit(self.candidate, "add")
        (self.candidate / "gone").unlink()
        tip = self.commit(self.candidate, "delete")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1)
        self.assertIn(first, result.stdout.decode())
        self.assertIn('"gone"', result.stdout.decode())

    def test_delete_and_readd_is_a_new_event(self):
        self.write(self.policy, "tracked", "base")
        self.write(self.policy, ".gitignore", "tracked\n")
        self.commit(self.policy, "ignore tracked")
        self.base = self.rev(self.policy, "HEAD")
        self.git("-C", str(self.policy), "push", "-q", str(self.objects), "HEAD:refs/heads/base")
        self.git("-C", str(self.candidate), "fetch", "-q", str(self.policy))
        self.git("-C", str(self.candidate), "switch", "-q", "--detach", self.base)
        (self.candidate / "tracked").unlink()
        self.commit(self.candidate, "delete")
        self.write(self.candidate, "tracked", "again")
        tip = self.commit(self.candidate, "readd")
        self.push_tip()
        self.assertEqual(self.check(tip=tip).returncode, 1)

    def test_rename_to_ignored_name_is_an_addition(self):
        self.set_base_ignore("ignored\n")
        self.write(self.candidate, "visible", "same")
        self.commit(self.candidate, "visible")
        (self.candidate / "visible").rename(self.candidate / "ignored")
        tip = self.commit(self.candidate, "rename")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1)
        self.assertIn('"ignored"', result.stdout.decode())

    def test_directory_only_rule_matches_without_materialized_candidate_tree(self):
        self.set_base_ignore("ignored-dir/\n")
        self.write(self.candidate, "ignored-dir/file.txt", "x")
        tip = self.commit(self.candidate, "directory-only")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('"ignored-dir/file.txt"', result.stdout.decode())

    def test_policy_directory_replaced_by_file_uses_candidate_path_type(self):
        self.write(self.policy, ".gitignore", "policy-dir/\n")
        self.write(self.policy, "policy-dir/.gitignore", "*.secret\n")
        self.commit(self.policy, "nested policy")
        self.base = self.rev(self.policy, "HEAD")
        self.git("-C", str(self.policy), "push", "-q", str(self.objects), "HEAD:refs/heads/base")
        self.git("-C", str(self.candidate), "fetch", "-q", str(self.policy))
        self.git("-C", str(self.candidate), "switch", "-q", "--detach", self.base)
        (self.candidate / "policy-dir/.gitignore").unlink()
        (self.candidate / "policy-dir").rmdir()
        self.write(self.candidate, "policy-dir", "now a file")
        tip = self.commit(self.candidate, "directory to file")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_file_replaced_by_directory_uses_candidate_path_type(self):
        self.write(self.policy, ".gitignore", "transition/\n")
        self.write(self.policy, "transition", "was a file")
        self.commit(self.policy, "file baseline")
        self.base = self.rev(self.policy, "HEAD")
        self.git("-C", str(self.policy), "push", "-q", str(self.objects), "HEAD:refs/heads/base")
        self.git("-C", str(self.candidate), "fetch", "-q", str(self.policy))
        self.git("-C", str(self.candidate), "switch", "-q", "--detach", self.base)
        (self.candidate / "transition").unlink()
        self.write(self.candidate, "transition/file.txt", "x")
        tip = self.commit(self.candidate, "file to directory")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('"transition/file.txt"', result.stdout.decode())

    def test_gitlink_addition_is_rejected_as_unsupported(self):
        self.git(
            "-C",
            str(self.candidate),
            "update-index",
            "--add",
            "--cacheinfo",
            f"160000,{self.base},vendor",
        )
        tip = self.git(
            "-C", str(self.candidate), "commit", "-q", "-m", "gitlink"
        )
        self.assertEqual(tip.returncode, 0)
        tip = self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 2)
        self.assertIn("gitlink", result.stderr.decode().lower())

    def test_file_to_gitlink_is_rejected(self):
        self.set_base_ignore("vendor/\n")
        self.write(self.candidate, "vendor", "regular file")
        self.commit(self.candidate, "add regular file")
        self.git(
            "-C", str(self.candidate), "update-index", "--cacheinfo",
            f"160000,{self.base},vendor",
        )
        self.git("-C", str(self.candidate), "commit", "-q", "-m", "convert to gitlink")
        tip = self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("gitlink", result.stderr.decode().lower())

    def test_existing_ignored_path_type_change_is_not_a_new_path(self):
        self.set_base_ignore("tracked\n")
        (self.candidate / "tracked").unlink()
        (self.candidate / "tracked").symlink_to("target")
        tip = self.commit(self.candidate, "change tracked path type")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_owner_ignore_case_is_preserved(self):
        self.set_base_ignore("secret\n")
        self.git("-C", str(self.policy), "config", "core.ignoreCase", "true")
        self.write(self.candidate, "SECRET", "ignored by owner")
        tip = self.commit(self.candidate, "case variant")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

        self.git("-C", str(self.policy), "config", "core.ignoreCase", "false")
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_relative_global_policy_uses_worktree_root(self):
        self.write(self.policy, "rules", "secret\n")
        self.write(self.policy, "sub/rules", "")
        self.git("-C", str(self.policy), "config", "core.excludesFile", "rules")
        self.write(self.candidate, "secret", "ignored by owner")
        tip = self.commit(self.candidate, "global rule")
        self.push_tip()
        result = self.check(tip=tip, policy=self.policy / "sub")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(str(self.policy / "rules"), result.stdout.decode())

    def test_reports_multiple_commits_and_paths(self):
        self.set_base_ignore("*.secret\n")
        commits = []
        for name in ("one.secret", "two.secret"):
            self.write(self.candidate, name, "x")
            commits.append(self.commit(self.candidate, name))
        tip = self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1)
        for commit, name in zip(commits, ("one.secret", "two.secret")):
            self.assertIn(commit, result.stdout.decode())
            self.assertIn(f'"{name}"', result.stdout.decode())

    def test_candidate_cannot_remove_or_modify_base_ignore(self):
        self.set_base_ignore("secret*\n")
        (self.candidate / ".gitignore").write_text("")
        self.write(self.candidate, "secret-one", "x")
        self.commit(self.candidate, "remove policy")
        (self.candidate / ".gitignore").write_text("!secret-two\n")
        self.write(self.candidate, "secret-two", "x")
        tip = self.commit(self.candidate, "loosen policy")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1)
        self.assertIn('"secret-one"', result.stdout.decode())
        self.assertIn('"secret-two"', result.stdout.decode())

    def test_unusual_filenames_are_json_quoted(self):
        self.set_base_ignore("odd*\n-dash\n")
        names = ("odd line\nname", "-dash")
        for name in names:
            self.write(self.candidate, name, "x")
        tip = self.commit(self.candidate, "odd")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1)
        self.assertIn('"odd line\\nname"', result.stdout.decode())
        self.assertIn('"-dash"', result.stdout.decode())

    def test_pathspec_magic_and_wildcards_are_literal_candidate_names(self):
        self.set_base_ignore("*.secret\n")
        names = (":(glob)magic.secret", "literal*.secret", "[x].secret")
        for name in names:
            self.write(self.candidate, name, "x")
        tip = self.commit(self.candidate, "literal pathspecs")
        self.push_tip()
        polluted = {
            **self.env,
            "GIT_GLOB_PATHSPECS": "1",
            "GIT_CONFIG_PARAMETERS": "'core.bare'='false'",
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "core.worktree",
            "GIT_CONFIG_VALUE_0": str(self.root / "must-not-be-used"),
        }
        result = self.check(tip=tip, env=polluted)
        self.assertEqual(result.returncode, 1, result.stderr)
        for name in names:
            self.assertIn(f'"{name}"', result.stdout.decode())

    def test_owner_config_override_and_newline_in_policy_path_are_preserved(self):
        global_ignore = self.root / "global\nignore"
        global_ignore.write_text("from-override\n")
        self.write(self.candidate, "from-override", "x")
        tip = self.commit(self.candidate, "override")
        self.push_tip()
        overridden = {
            **self.env,
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": "core.excludesFile",
            "GIT_CONFIG_VALUE_0": str(global_ignore),
        }
        result = self.check(tip=tip, env=overridden)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('"from-override"', result.stdout.decode())
        self.assertIn("\\n", result.stdout.decode())

    def test_global_snapshot_does_not_collide_with_trusted_tree(self):
        self.write(
            self.policy,
            ".trusted-global-ignore/.gitignore",
            "*.secret\n",
        )
        self.commit(self.policy, "colliding trusted path")
        self.base = self.rev(self.policy, "HEAD")
        self.git("-C", str(self.policy), "push", "-q", str(self.objects), "HEAD:refs/heads/base")
        self.git("-C", str(self.candidate), "fetch", "-q", str(self.policy))
        self.git("-C", str(self.candidate), "switch", "-q", "--detach", self.base)
        self.write(self.candidate, ".trusted-global-ignore/caught.secret", "x")
        tip = self.commit(self.candidate, "nested ignored file")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('".trusted-global-ignore/caught.secret"', result.stdout.decode())

    def test_invalid_inputs_and_empty_range_exit_two(self):
        self.push_tip()
        cases = [
            self.check(base="f" * 40),
            self.check(tip="e" * 40),
            self.check(tip=self.base),
            self.check(objects=self.policy),
            self.check(policy=self.objects),
        ]
        for result in cases:
            self.assertEqual(result.returncode, 2)
            self.assertTrue(result.stderr)

    def test_base_must_resolve_to_same_commit_in_both_repositories(self):
        self.write(self.candidate, "candidate", "x")
        tip = self.commit(self.candidate, "candidate")
        self.push_tip()
        self.git("-C", str(self.policy), "tag", "anchor", self.base)
        self.git("-C", str(self.objects), "tag", "anchor", tip)
        result = self.check(base="anchor", tip=tip)
        self.assertEqual(result.returncode, 2)
        self.assertIn("different commits", result.stderr.decode())

    def test_merge_and_unrelated_history_exit_two(self):
        self.write(self.candidate, "main", "x")
        self.commit(self.candidate, "main")
        self.git("-C", str(self.candidate), "checkout", "-q", "-b", "side", self.base)
        self.write(self.candidate, "side", "x")
        self.commit(self.candidate, "side")
        self.git("-C", str(self.candidate), "checkout", "-q", "main")
        self.git("-C", str(self.candidate), "merge", "-q", "--no-ff", "-m", "merge", "side")
        merge = self.push_tip()
        self.assertEqual(self.check(tip=merge).returncode, 2)

        unrelated = self.root / "unrelated"
        self.git("init", "-q", str(unrelated))
        self.write(unrelated, "x", "x")
        unrelated_tip = self.commit(unrelated, "root")
        self.git("-C", str(unrelated), "push", "-q", str(self.objects), f"{unrelated_tip}:refs/heads/unrelated")
        self.assertEqual(self.check(tip=unrelated_tip).returncode, 2)

    def test_explicit_missing_global_policy_fails_closed(self):
        self.git("-C", str(self.policy), "config", "core.excludesFile", str(self.root / "missing"))
        self.write(self.candidate, "ok", "x")
        tip = self.commit(self.candidate, "candidate")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 2)
        self.assertIn("exclude", result.stderr.decode().lower())

    def test_unreadable_global_policy_fails_closed(self):
        exclude_directory = self.root / "exclude-directory"
        exclude_directory.mkdir()
        self.git("-C", str(self.policy), "config", "core.excludesFile", str(exclude_directory))
        self.write(self.candidate, "ok", "x")
        tip = self.commit(self.candidate, "candidate")
        self.push_tip()
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 2)
        self.assertIn("cannot read", result.stderr.decode().lower())

    def test_repositories_are_not_modified(self):
        self.write(self.candidate, "ok", "x")
        tip = self.commit(self.candidate, "candidate")
        self.push_tip()
        policy_before = self.git("-C", str(self.policy), "status", "--porcelain=v2", "--branch").stdout
        refs_before = self.git("-C", str(self.objects), "for-each-ref", "--format=%(refname) %(objectname)").stdout
        result = self.check(tip=tip)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(policy_before, self.git("-C", str(self.policy), "status", "--porcelain=v2", "--branch").stdout)
        self.assertEqual(
            refs_before,
            self.git("-C", str(self.objects), "for-each-ref", "--format=%(refname) %(objectname)").stdout,
        )

    def test_symlink_gitignore_is_not_followed(self):
        target = self.policy / "rules"
        target.write_text("blocked\n")
        (self.policy / ".gitignore").symlink_to("rules")
        self.commit(self.policy, "symlink policy")
        self.base = self.rev(self.policy, "HEAD")
        self.git("-C", str(self.policy), "push", "-q", str(self.objects), "HEAD:refs/heads/base")
        self.git("-C", str(self.candidate), "fetch", "-q", str(self.policy))
        self.git("-C", str(self.candidate), "switch", "-q", "--detach", self.base)
        self.write(self.candidate, "blocked", "x")
        tip = self.commit(self.candidate, "allowed")
        self.push_tip()
        self.assertEqual(self.check(tip=tip).returncode, 0)


if __name__ == "__main__":
    unittest.main()
