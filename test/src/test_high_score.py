#!/usr/bin/env python3
"""Test score persistence in temporary directories and across real processes."""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = ROOT / "test" / "build" / "exec" / "chompit-test"
GAME = ROOT / "build" / "exec" / "chompit"


def run(args, *, cwd, env=None, success=True, preexec_fn=None):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True,
                            timeout=30, preexec_fn=preexec_fn)
    assert (result.returncode == 0) == success, (args, result.stdout, result.stderr)
    return result


def main():
    with tempfile.TemporaryDirectory(prefix="chompit-scores-") as directory:
        root = Path(directory)
        env = dict(os.environ, HOME=str(root / "home"), XDG_STATE_HOME=str(root / "state"))

        def driver(*args, success=True, environment=env, preexec_fn=None):
            return run([str(DRIVER), *map(str, args)], cwd=root, env=environment,
                       success=success, preexec_fn=preexec_fn)

        score = root / "nested" / "directory" / "score"
        assert driver("--read-score", score).stdout.strip() == "0"
        assert not score.parent.exists(), "Reading a missing score must not create directories."
        assert driver("--write-score", score, 0).stdout.strip() == "0"
        assert not score.exists()
        assert driver("--write-score", score, 12345).stdout.strip() == "12345"
        assert score.read_bytes() == b"12345\n"
        assert driver("--read-score", score).stdout.strip() == "12345"
        before = score.stat().st_mtime_ns
        assert driver("--write-score", score, 42).stdout.strip() == "12345"
        assert score.stat().st_mtime_ns == before, "A lower score must not rewrite the file."
        assert driver("--write-score", score, 20000).stdout.strip() == "20000"
        assert not list(score.parent.glob("score.tmp.*")), "Successful saves must remove temporary names."

        for data in [b"", b"-1\n", b"+10", b"1.5", b"100\n200", b"100\0ignored", b"\xff\xfe",
                     b"99999999999999999999999999999", b"9" * 100000]:
            score.write_bytes(data)
            assert driver("--read-score", score).stdout.strip() == "0", data[:50]
        assert driver("--write-score", score, 300).stdout.strip() == "300"
        assert score.read_bytes() == b"300\n", "A new best score must repair malformed data."
        driver("--write-score", score, -1, success=False)
        assert score.read_bytes() == b"300\n"

        # Reserve the exact temporary name before exec. Exclusive fopen must not
        # follow the symlink, remove it, or alter the previous valid score.
        victim = root / "keep-me"
        victim.write_bytes(b"unrelated data")

        def reserve_temporary_name():
            os.symlink(victim, f"{score}.tmp.{os.getpid()}")

        # Bypass the generated shell launcher, which starts Chez in a child.
        # The native process must keep the PID used by the pre-exec hook.
        app = DRIVER.parent / "chompit-test_app"
        direct_env = dict(env, LD_LIBRARY_PATH=str(app) + ":" + env.get("LD_LIBRARY_PATH", ""),
                          IDRIS2_INC_SRC=str(app))
        run([str(app / "chompit-test.so"), "--write-score", str(score), "400"],
            cwd=root, env=direct_env, success=False, preexec_fn=reserve_temporary_name)
        assert victim.read_bytes() == b"unrelated data"
        assert score.read_bytes() == b"300\n"
        links = list(score.parent.glob("score.tmp.*"))
        assert len(links) == 1 and links[0].is_symlink()
        links[0].unlink()

        blocker = root / "not-a-directory"
        blocker.write_bytes(b"keep this file")
        driver("--write-score", blocker / "score", 100, success=False)
        assert blocker.read_bytes() == b"keep this file"
        directory_score = root / "directory-score"
        directory_score.mkdir()
        driver("--read-score", directory_score, success=False)
        driver("--write-score", directory_score, 100, success=False)
        assert directory_score.is_dir()

        assert driver("--session-score", 500).stdout.strip() == "0 500"
        assert driver("--session-score", 1).stdout.strip() == "500 500"
        assert driver("--session-score", 700).stdout.strip() == "500 700"
        assert (root / "state/chompit/high-score").read_bytes() == b"700\n"
        fallback_env = dict(env, XDG_STATE_HOME="relative-state")
        assert driver("--session-score", 80, environment=fallback_env).stdout.strip() == "0 80"
        assert (root / "home/.local/state/chompit/high-score").read_bytes() == b"80\n"
        assert not (root / "relative-state").exists()

        broken_env = dict(env, XDG_STATE_HOME=str(blocker))
        failed = driver("--session-score", 900, environment=broken_env)
        assert failed.stdout.strip() == "0 900" and "remain in memory" in failed.stderr

        # Exercise Main's normal start, movement, quit, and save path. The helper
        # supplies SDL events; --smoke is deliberately absent.
        helper = root / "score-input.so"
        flags = shlex.split(subprocess.check_output(
            ["pkg-config", "--cflags", "--libs", "sdl3"], text=True))
        compiler = shlex.split(os.environ.get("CC", "cc"))
        run([*compiler, "-shared", "-fPIC", "-Wall", "-Wextra", str(ROOT / "test/src/score_input.c"),
             "-o", str(helper), *flags, "-ldl"], cwd=root)
        game_env = dict(env, SDL_VIDEODRIVER="dummy", SDL_RENDER_DRIVER="software",
                        XDG_STATE_HOME=str(root / "game-state"))
        game_env["LD_PRELOAD"] = str(helper) + (":" + env["LD_PRELOAD"] if env.get("LD_PRELOAD") else "")
        run([str(GAME), "--silent"], cwd=ROOT, env=game_env)
        game_score = root / "game-state/chompit/high-score"
        assert int(game_score.read_text()) > 0, "Quitting during play must save the new high score."
        game_score.write_text("200000\n")
        before = game_score.stat().st_mtime_ns
        run([str(GAME), "--silent"], cwd=ROOT, env=game_env)
        assert game_score.read_text() == "200000\n" and game_score.stat().st_mtime_ns == before

        disabled_env = dict(game_env, XDG_STATE_HOME=str(blocker))
        disabled = run([str(GAME), "--silent", "--no-save"], cwd=ROOT, env=disabled_env)
        assert "score" not in disabled.stderr.lower(), "--no-save must not even read score storage."
        smoke_env = dict(disabled_env)
        smoke_env.pop("LD_PRELOAD", None)
        smoked = run([str(GAME), "--smoke", "--silent"], cwd=ROOT, env=smoke_env)
        assert "smoke passed" in smoked.stdout and "score" not in smoked.stderr.lower()
        assert blocker.read_bytes() == b"keep this file"

        if os.geteuid() != 0:
            readonly = root / "readonly/chompit"
            readonly.mkdir(parents=True)
            (readonly / "high-score").write_text("1\n")
            readonly.chmod(0o500)
            try:
                failed = run([str(GAME), "--silent"], cwd=ROOT,
                             env=dict(game_env, XDG_STATE_HOME=str(readonly.parent)))
                assert failed.stderr.count("remain in memory") == 1
                assert (readonly / "high-score").read_text() == "1\n"
            finally:
                readonly.chmod(0o700)

    print("High-score tests passed: process restart, atomic replacement, malformed files, failures, quit, and no-save isolation.")


if __name__ == "__main__":
    main()
