import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SESSION = Path(__file__).parents[1] / "handoff-session.sh"
HANDOFF = Path(os.environ.get(
    "CHELLY_HANDOFF_SCRIPT", Path(__file__).parents[3] / "git" / "handoff" / "chelly-handoff.sh"))

# 本体の chelly の代わりに、受け取った引数と mount の指定を記録する。
FAKE_CHELLY = """#!/bin/sh
python3 -c 'import json, os, sys; json.dump({"args": sys.argv[1:], "cwd": os.getcwd(), "mounts": os.environ.get("CHELLY_ADDITIONAL_MOUNTS"), "leaked": sorted(k for k in os.environ if k.startswith("HANDOFF_SESSION_"))}, open(os.environ["CHELLY_LOG"], "w"))' "$@"
"""

# 動いているコンテナの mount 元を、テストが書いたファイルから返す。
FAKE_PODMAN = """#!/bin/sh
case "$1" in
ps) cat "$PODMAN_CONTAINERS" ;;
inspect) cat "$PODMAN_SOURCES" ;;
*) exit 90 ;;
esac
"""

BASE = "/nix:/nix:ro,claude-state:/home/warashi/.claude"


class HandoffSessionTest(unittest.TestCase):
    def setUp(self):
        test_tmp = Path(os.environ.get("TEST_TMPDIR", Path.cwd() / ".test-tmp"))
        test_tmp.mkdir(parents=True, exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=test_tmp)
        self.root = Path(self.temporary.name)
        self.workspaces = self.root / "workspaces"
        self.workspaces.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name, text in (
            ("chelly", FAKE_CHELLY),
            ("podman", FAKE_PODMAN),
            ("chelly-handoff", f'#!/bin/sh\nexec bash {HANDOFF} "$@"\n'),
        ):
            path = self.bin / name
            path.write_text(text)
            path.chmod(0o755)
        self.log = self.root / "chelly.json"
        self.containers = self.root / "containers"
        self.sources = self.root / "sources"
        self.containers.write_text("")
        self.sources.write_text("")
        self.fixed = self.clone("github.com/Warashi/brainium/brainium")
        self.env = {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HANDOFF_SESSION_WORKSPACES": str(self.workspaces),
            "HANDOFF_SESSION_MOUNTS": BASE,
            "HANDOFF_SESSION_FIXED": str(self.fixed),
            "HANDOFF_SESSION_DIRECTORY": str(self.fixed),
            "HANDOFF_SESSION_CHELLY": str(self.bin / "chelly"),
            "CHELLY_LOG": str(self.log),
            "PODMAN_CONTAINERS": str(self.containers),
            "PODMAN_SOURCES": str(self.sources),
        }

    def tearDown(self):
        self.temporary.cleanup()

    def clone(self, path):
        clone = self.workspaces / path
        (clone / ".git").mkdir(parents=True)
        return clone

    def session(self, *args, cwd=None, check=True):
        if self.log.exists():
            self.log.unlink()
        return subprocess.run(
            ["bash", str(SESSION), *args], cwd=cwd or self.root, env=self.env,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check,
        )

    def launched(self):
        return json.loads(self.log.read_text()) if self.log.exists() else None

    def mounts(self):
        mounts = self.launched()["mounts"]
        self.assertTrue(mounts.startswith(BASE + ","), mounts)
        return sorted(mounts[len(BASE) + 1:].split(","))

    def test_other_commands_and_single_runs_go_straight_to_chelly(self):
        self.session("__complete", "run", "")
        self.assertEqual(self.launched(), {"args": ["__complete", "run", ""], "cwd": str(self.root),
                                           "mounts": None, "leaked": []})
        self.session("run", "--", "claude")
        self.assertEqual(self.launched(), {"args": ["run", "--", "claude"], "cwd": str(self.root),
                                           "mounts": None, "leaked": []})

    def test_handoff_starts_in_the_session_directory_from_anywhere(self):
        # 計画は brainium の task で立てるので、横断セッションは cwd に関わらず brainium で動かす。
        lib = self.clone("github.com/acme/lib/fix")
        app = self.clone("github.com/Warashi/app/fix")
        for cwd in (self.root, lib, app):
            self.session("--handoff", "fix", "run", cwd=cwd)
            self.assertEqual(self.launched()["cwd"], str(self.fixed), cwd)
            self.assertEqual(len(self.mounts()), 2, cwd)
        # 既定 branch の名前で単独起動に落ちても、起動場所は同じにする。
        self.session("--handoff", "main", "run", cwd=lib)
        self.assertEqual(self.launched()["cwd"], str(self.fixed))

    def test_handoff_mounts_every_clone_of_the_name_at_its_ghq_path(self):
        lib = self.clone("github.com/acme/lib/fix")
        app = self.clone("github.com/Warashi/app/fix")
        deep = self.clone("gitlab.com/group/sub/tool/fix")
        self.clone("github.com/Warashi/app/other")
        # clone の中の submodule や、.git の無い mount 元は clone ではない。
        (lib / "deps" / "fix" / ".git").mkdir(parents=True)
        (self.workspaces / "github.com" / "Warashi" / "empty" / "fix").mkdir(parents=True)
        self.session("--handoff", "fix", "run", "--", "claude", cwd=self.fixed)
        self.assertEqual(self.launched()["args"], ["run", "--", "claude"])
        self.assertEqual(self.launched()["leaked"], [])
        self.assertEqual(self.mounts(), sorted([
            f"{lib}:/home/warashi/ghq/github.com/acme/lib",
            f"{app}:/home/warashi/ghq/github.com/Warashi/app",
            f"{deep}:/home/warashi/ghq/gitlab.com/group/sub/tool",
        ]))

    def test_handoff_name_is_resolved_to_the_id_chelly_handoff_uses(self):
        name = "ログイン/修正"
        clone = self.clone("github.com/acme/lib/x-" + name.encode().hex())
        self.session("--handoff", name, "run")
        self.assertEqual(self.mounts(), [f"{clone}:/home/warashi/ghq/github.com/acme/lib"])

    def test_default_branch_names_start_a_single_session(self):
        self.clone("github.com/acme/lib/main")
        self.clone("github.com/acme/app/master")
        for name in ("main", "master"):
            result = self.session("--handoff", name, "run")
            self.assertEqual(self.launched()["mounts"], None, name)
            self.assertIn(name.encode(), result.stderr)

    def test_projects_mounted_by_the_settings_are_not_mounted_twice(self):
        # brainium は設定で常に ~/ghq/github.com/Warashi/brainium に mount する。
        # 同じ handoff 名の brainium の clone を集めると destination が重なる。
        self.clone("github.com/Warashi/brainium/fix")
        lib = self.clone("github.com/acme/lib/fix")
        self.session("--handoff", "fix", "run")
        self.assertEqual(self.mounts(), [f"{lib}:/home/warashi/ghq/github.com/acme/lib"])

    def test_clones_in_the_former_layout_are_not_collected(self):
        # 以前は <repo 名>/<ID> に置いていた。ghq の path ではないので mount 先が無い。
        self.clone("configurations/fix")
        lib = self.clone("github.com/acme/lib/fix")
        self.session("--handoff", "fix", "run")
        self.assertEqual(self.mounts(), [f"{lib}:/home/warashi/ghq/github.com/acme/lib"])

    def test_clones_reached_through_symlinks_are_not_collected(self):
        outside = self.root / "outside"
        (outside / "acme" / "lib" / "fix" / ".git").mkdir(parents=True)
        (self.workspaces / "github.com").mkdir(exist_ok=True)
        (self.workspaces / "github.com" / "evil").symlink_to(outside)
        (self.workspaces / "github.com" / "acme").mkdir()
        (self.workspaces / "github.com" / "acme" / "fix").symlink_to(outside / "acme" / "lib" / "fix")
        result = self.session("--handoff", "fix", "run", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"no workspace", result.stderr)
        self.assertIsNone(self.launched())

    def test_unknown_or_malformed_handoff_does_not_start(self):
        result = self.session("--handoff", "nothing", "run", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"no workspace", result.stderr)
        for args in (("--handoff",), ("--handoff", "fix"), ("--handoff", "fix", "build"),
                     ("--handoff", "", "run"), ("--handoff", "a\tb", "run")):
            result = self.session(*args, check=False)
            self.assertNotEqual(result.returncode, 0, args)
            self.assertIsNone(self.launched(), args)

    def running(self, *sources):
        self.containers.write_text("abc\n" if sources else "")
        self.sources.write_text("".join(f"{source}\n" for source in sources))

    def test_handoff_refuses_clones_another_container_mounts(self):
        lib = self.clone("github.com/acme/lib/fix")
        app = self.clone("github.com/Warashi/app/fix")
        # 単独起動は cwd を mount するので、clone の下のディレクトリも使用中にあたる。
        self.running("/nix", "claude-state", str(self.fixed), f"{app}/sub")
        result = self.session("--handoff", "fix", "run", cwd=self.fixed, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(str(app).encode(), result.stderr)
        self.assertNotIn(str(lib).encode(), result.stderr)
        self.assertIsNone(self.launched())

    def test_single_run_refuses_a_clone_a_handoff_session_uses(self):
        app = self.clone("github.com/Warashi/app/fix")
        (app / "sub").mkdir()
        self.running(str(app))
        result = self.session("run", cwd=app / "sub", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(str(app).encode(), result.stderr)
        self.assertIsNone(self.launched())

    def test_brainium_and_the_workspace_root_are_shared_freely(self):
        # brainium は複数のセッションが同時に書く前提で、chelly-handoff の転送は領域の
        # root から起動する。どちらも使用中の判定に入れない。
        self.clone("github.com/acme/lib/fix")
        self.running(str(self.fixed), str(self.workspaces))
        self.session("run", cwd=self.fixed)
        self.assertEqual(self.launched()["args"], ["run"])
        self.session("--handoff", "fix", "run", cwd=self.fixed)
        self.assertEqual(len(self.mounts()), 1)
        self.env["PODMAN_CONTAINERS"] = str(self.root / "missing")
        self.session("run", "--", "bash", cwd=self.workspaces)
        self.assertEqual(self.launched()["args"], ["run", "--", "bash"])

    def test_session_does_not_start_when_running_containers_are_unknown(self):
        self.clone("github.com/acme/lib/fix")
        self.env["PODMAN_CONTAINERS"] = str(self.root / "missing")
        result = self.session("--handoff", "fix", "run", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIsNone(self.launched())


if __name__ == "__main__":
    unittest.main()
