from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args: str) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)


def main() -> int:
    run(sys.executable, "scripts/compile_sources.py")
    run(sys.executable, "-m", "compileall", "-q", "sdk", "scripts", "tests")
    run(sys.executable, "-m", "pytest", "-q")
    run(sys.executable, "scripts/verify_release.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
