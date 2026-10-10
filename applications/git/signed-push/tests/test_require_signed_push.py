import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "require-signed-push.sh"


class RequireSignedPushTest(unittest.TestCase):
    def setUp(self):
        test_tmp = Path(os.environ.get("TEST_TMPDIR", Path.cwd() / ".test-tmp"))
        test_tmp.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=test_tmp)
        self.root = Path(self.temporary.name)
        key = self.root / "key"
        subprocess.run(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
            check=True,
        )
        gitconfig = self.root / "gitconfig"
        gitconfig.write_text(
            "[user]\n"
            "\tname = Test\n"
            "\temail = test@example.invalid\n"
            "\tsigningKey = " + str(key) + "\n"
            "[gpg]\n"
            "\tformat = ssh\n"
            "[commit]\n"
            "\tgpgSign = true\n"
            "[maintenance]\n"
            "\tauto = false\n"
            "[hook \"require-signed-push\"]\n"
            "\tevent = pre-push\n"
            "\tcommand = bash " + str(SCRIPT) + "\n"
        )
        self.env = {
            name: value
            for name, value in os.environ.items()
            if not name.startswith("GIT_CONFIG_")
        }
        self.env.update(
            {
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": str(gitconfig),
                "HOME": str(self.root),
            }
        )
        self.remote = self.root / "remote.git"
        self.work = self.root / "work"
        self.git("init", "-q", "--bare", "-b", "main", str(self.remote))
        self.git("init", "-q", "-b", "main", str(self.work))
        self.git("-C", str(self.work), "remote", "add", "origin", str(self.remote))

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, *args, check=True):
        return subprocess.run(
            ["git", *args],
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=check,
        )

    def commit(self, message, signed=True):
        self.git(
            "-C",
            str(self.work),
            "-c",
            f"commit.gpgSign={'true' if signed else 'false'}",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            message,
        )
        return self.git("-C", str(self.work), "rev-parse", "HEAD").stdout.strip()

    def push(self, *args):
        return self.git("-C", str(self.work), "push", "-q", *args, check=False)

    def test_pushes_signed_commits(self):
        self.commit("signed")

        result = self.push("origin", "main")

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_unsigned_commit_and_names_it(self):
        self.commit("signed")
        unsigned = self.commit("unsigned", signed=False)
        self.commit("signed again")

        result = self.push("origin", "main")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(unsigned[:7], result.stderr)
        self.assertEqual(
            self.git("--git-dir", str(self.remote), "show-ref", check=False).stdout, ""
        )

    def test_ignores_unsigned_commits_already_on_remote(self):
        self.commit("unsigned", signed=False)
        self.assertEqual(self.push("--no-verify", "origin", "main").returncode, 0)
        self.commit("signed")

        result = self.push("origin", "main")

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allows_branch_deletion(self):
        self.commit("signed")
        self.assertEqual(self.push("origin", "main", "main:topic").returncode, 0)

        result = self.push("origin", ":topic")

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_runs_alongside_repository_hook(self):
        self.commit("signed")
        marker = self.root / "repository-hook-ran"
        hook = self.work / ".git/hooks/pre-push"
        hook.write_text(f"#!/bin/sh\ntouch {marker}\n")
        hook.chmod(0o755)

        result = self.push("origin", "main")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(marker.exists())


if __name__ == "__main__":
    unittest.main()
