"""Unit tests for scripts/next_release_version.py."""

import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "scripts" / "next_release_version.py"


def run(*args, stdin=""):
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        input=stdin,
        capture_output=True,
        text=True,
    )


def test_no_prior_release_major_starts_at_1_0_0():
    result = run("--bump", "major", "--prefix", "release/", stdin="")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "1.0.0"


def test_no_prior_release_minor_starts_at_0_1_0():
    result = run("--bump", "minor", "--prefix", "release/", stdin="")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "0.1.0"


def test_major_bump_from_existing():
    stdin = "release/v1.2.3\nrelease/v0.9.0\n"
    result = run("--bump", "major", "--prefix", "release/", stdin=stdin)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "2.0.0"


def test_minor_bump_from_existing():
    stdin = "release/v1.2.3\nrelease/v1.5.0\nrelease/v0.9.0\n"
    result = run("--bump", "minor", "--prefix", "release/", stdin=stdin)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "1.6.0"


def test_ignores_non_semver_branches():
    # Lenient variants (no 'v', prerelease tags, random branches) are skipped.
    stdin = (
        "release/1.2.3\n"          # no leading v
        "release/v1.2.3-rc1\n"     # prerelease tag
        "release/vfoo\n"           # not numeric
        "release/v0.0.5\n"         # valid - used
        "main\n"
        "feature/abc\n"
    )
    result = run("--bump", "major", "--prefix", "release/", stdin=stdin)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "1.0.0"


def test_picks_highest_by_semver_not_lexicographic():
    # v10.0.0 > v9.0.0 numerically but '9' > '10' lexicographically.
    stdin = "release/v9.0.0\nrelease/v10.2.0\n"
    result = run("--bump", "minor", "--prefix", "release/", stdin=stdin)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "10.3.0"


def test_respects_custom_prefix():
    stdin = "rel/v1.0.0\nrel/v2.1.0\nrelease/v9.9.9\n"
    result = run("--bump", "major", "--prefix", "rel/", stdin=stdin)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "3.0.0"


def test_rejects_invalid_bump():
    result = run("--bump", "patch", "--prefix", "release/", stdin="")
    assert result.returncode == 2
    assert "bump" in result.stderr.lower()


def test_rejects_missing_bump():
    result = run("--prefix", "release/", stdin="")
    assert result.returncode != 0


def test_rejects_missing_prefix():
    result = run("--bump", "major", stdin="")
    assert result.returncode != 0
