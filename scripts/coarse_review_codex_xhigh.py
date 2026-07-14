#!/usr/bin/env python3
"""Run coarse-review with Codex reasoning effort forced to xhigh.

The coarse-review 1.4.1 CLI exposes only low/medium/high/max, and its
Codex adapter currently maps max back to high. This wrapper leaves the
pipeline untouched but patches that one mapping before invoking the CLI.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


DETACHED_ENV = "COARSE_REVIEW_XHIGH_DETACHED"


def _arg_value(argv: list[str], flag: str, default: str) -> str:
    try:
        idx = argv.index(flag)
    except ValueError:
        return default
    if idx + 1 >= len(argv):
        return default
    return argv[idx + 1]


def _without_flag(argv: list[str], flag: str) -> list[str]:
    return [arg for arg in argv if arg != flag]


def _open_log(path: Path):
    path = path.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.fchmod(fd, 0o600)
    except OSError:
        pass
    return os.fdopen(fd, "w", encoding="utf-8")


def _detach(argv: list[str]) -> int:
    log_path = Path(_arg_value(argv, "--log-file", "/tmp/coarse-review-xhigh.log"))
    child_argv = _without_flag(argv, "--detach")

    env = dict(os.environ)
    env[DETACHED_ENV] = "1"
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"

    with _open_log(log_path) as log:
        proc = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), *child_argv],
            cwd=str(Path.cwd()),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            close_fds=True,
            start_new_session=True,
        )

    pidfile = log_path.expanduser().resolve().with_suffix(log_path.suffix + ".pid")
    pidfile.write_text(f"{proc.pid}\n", encoding="utf-8")
    os.chmod(pidfile, 0o600)

    print(f"Review PID: {proc.pid}")
    print(f"Log file:   {log_path.expanduser().resolve()}")
    return 0


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)

    if "--detach" in argv and os.environ.get(DETACHED_ENV) != "1":
        return _detach(argv)

    from coarse.headless_clients import CodexClient
    from coarse.models import HEADLESS_DEFAULT_MODELS
    from coarse.cli_review import main as coarse_main

    CodexClient._EFFORT_MAP["max"] = "xhigh"
    CodexClient._config_override_probed = True
    CodexClient._config_override_supported = True
    HEADLESS_DEFAULT_MODELS["codex"] = "gpt-5.5"

    return coarse_main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
