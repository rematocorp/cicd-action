"""Unit tests for scripts/resolve_package_versions.py."""

import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
RESOLVER = REPO_ROOT / "scripts" / "resolve_package_versions.py"


def run_resolver(path: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(RESOLVER), str(path)],
        capture_output=True,
        text=True,
    )


# --- version-only conflict: should resolve, keeping HEAD ---

VERSION_ONLY_CONFLICT = '''{
  "name": "frontend",
<<<<<<< HEAD
  "version": "17.9.2",
=======
  "version": "17.9.1",
>>>>>>> origin/main
  "private": true
}
'''

VERSION_ONLY_RESOLVED = '''{
  "name": "frontend",
  "version": "17.9.2",
  "private": true
}
'''


def test_resolves_version_only_conflict(tmp_path):
    target = tmp_path / "package.json"
    target.write_text(VERSION_ONLY_CONFLICT)

    result = run_resolver(target)

    assert result.returncode == 0, result.stderr
    assert target.read_text() == VERSION_ONLY_RESOLVED


def test_accepts_any_origin_branch_in_closing_marker(tmp_path):
    # The closing marker can name any upstream branch (main, master, custom).
    src = VERSION_ONLY_CONFLICT.replace(">>>>>>> origin/main", ">>>>>>> origin/custom-name")
    target = tmp_path / "package.json"
    target.write_text(src)

    result = run_resolver(target)

    assert result.returncode == 0, result.stderr
    assert target.read_text() == VERSION_ONLY_RESOLVED


# --- non-version conflict: should refuse and leave the file unchanged ---

EXTRA_LINE_CONFLICT = '''{
  "name": "frontend",
<<<<<<< HEAD
  "version": "17.9.2",
  "description": "ours",
=======
  "version": "17.9.1",
  "description": "theirs",
>>>>>>> origin/main
  "private": true
}
'''


def test_refuses_when_head_side_has_extra_lines(tmp_path):
    target = tmp_path / "package.json"
    target.write_text(EXTRA_LINE_CONFLICT)

    result = run_resolver(target)

    assert result.returncode == 1
    assert "version-line" in result.stderr.lower() or "single version" in result.stderr.lower()
    assert target.read_text() == EXTRA_LINE_CONFLICT  # unchanged


NON_VERSION_CONFLICT = '''{
<<<<<<< HEAD
  "description": "ours",
=======
  "description": "theirs",
>>>>>>> origin/main
  "version": "17.9.0"
}
'''


def test_refuses_when_conflict_is_not_a_version_line(tmp_path):
    target = tmp_path / "package.json"
    target.write_text(NON_VERSION_CONFLICT)

    result = run_resolver(target)

    assert result.returncode == 1
    assert target.read_text() == NON_VERSION_CONFLICT  # unchanged


# --- multiple conflict blocks: all must be version-only ---

TWO_VERSION_BLOCKS = '''{
<<<<<<< HEAD
  "version": "17.9.2",
=======
  "version": "17.9.1",
>>>>>>> origin/main
  "dependencies": {
<<<<<<< HEAD
    "lib": "2.0.0",
=======
    "lib": "1.0.0",
>>>>>>> origin/main
  }
}
'''


def test_refuses_when_second_block_is_not_version_line(tmp_path):
    target = tmp_path / "package.json"
    target.write_text(TWO_VERSION_BLOCKS)

    result = run_resolver(target)

    assert result.returncode == 1
    assert target.read_text() == TWO_VERSION_BLOCKS  # unchanged


# --- usage / error paths ---

def test_exits_nonzero_when_no_path_given():
    result = subprocess.run(
        [sys.executable, str(RESOLVER)],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "usage" in result.stderr.lower()


def test_file_without_conflicts_is_left_unchanged(tmp_path):
    # No markers at all — resolver should do nothing and exit 0.
    # (Orchestrator's defense-in-depth re-checks for unmerged paths.)
    clean = '{"name": "x", "version": "1.0.0"}\n'
    target = tmp_path / "package.json"
    target.write_text(clean)

    result = run_resolver(target)

    assert result.returncode == 0, result.stderr
    assert target.read_text() == clean
