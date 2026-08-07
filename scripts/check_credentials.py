#!/usr/bin/env python3
"""Detect credential-like records without exposing their values."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
from collections.abc import Iterable
from dataclasses import dataclass


SCANNED_EXTENSIONS = frozenset({".conf", ".md", ".txt"})
SENSITIVE_FIELDS = ("username", "user", "password", "passwd", "certificate")
RECORD_PATTERN = re.compile(
    r"^[ \t]*(?P<identifier>\S+)[ \t]+"
    r"(?P<field>username|user|password|passwd|certificate)[ \t]+"
    r"(?P<value>\S+)[ \t]*$",
    re.IGNORECASE,
)


class OperationalError(Exception):
    """Raised when scanner input cannot be obtained or read."""


@dataclass(frozen=True, order=True)
class Finding:
    filename: str
    line_number: int
    identifier: str
    field: str


def _run_git(arguments: list[str]) -> bytes:
    try:
        result = subprocess.run(
            ["git", *arguments],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        raise OperationalError(f"could not run git: {error}") from error

    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        message = f"git {' '.join(arguments[:2])} failed"
        if detail:
            message = f"{message}: {detail}"
        raise OperationalError(message)
    return result.stdout


def _eligible(filename: str) -> bool:
    return Path(filename).suffix.lower() in SCANNED_EXTENSIONS


def _decode_text(content: bytes) -> str | None:
    if b"\0" in content:
        return None
    try:
        return content.decode("utf-8-sig")
    except UnicodeDecodeError:
        return None


def _safe_for_log(value: str) -> str:
    return "".join(
        character
        if character.isprintable() and character not in {"\x1b", "\r", "\n"}
        else f"\\u{ord(character):04x}"
        for character in value
    )


def _scan_content(filename: str, content: bytes) -> list[Finding]:
    text = _decode_text(content)
    if text is None:
        return []

    findings = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        match = RECORD_PATTERN.fullmatch(line)
        if match:
            findings.append(
                Finding(
                    filename=filename,
                    line_number=line_number,
                    identifier=match.group("identifier"),
                    field=match.group("field"),
                )
            )
    return findings


def _nul_delimited_paths(output: bytes) -> list[str]:
    return sorted(
        os.fsdecode(path)
        for path in output.split(b"\0")
        if path and _eligible(os.fsdecode(path))
    )


def _staged_inputs() -> Iterable[tuple[str, bytes]]:
    output = _run_git(
        ["diff", "--cached", "--name-only", "--diff-filter=ACMRT", "-z"]
    )
    for filename in _nul_delimited_paths(output):
        yield filename, _run_git(["cat-file", "blob", f":{filename}"])


def _tracked_inputs() -> Iterable[tuple[str, bytes]]:
    for filename in _nul_delimited_paths(_run_git(["ls-files", "-z"])):
        try:
            yield filename, Path(filename).read_bytes()
        except OSError as error:
            raise OperationalError(f"could not read {_safe_for_log(filename)}: {error}") from error


def _working_tree_inputs(filenames: list[str]) -> Iterable[tuple[str, bytes]]:
    for filename in sorted(set(filenames)):
        if not _eligible(filename):
            continue
        try:
            yield filename, Path(filename).read_bytes()
        except OSError as error:
            raise OperationalError(f"could not read {_safe_for_log(filename)}: {error}") from error


def _parse_arguments(arguments: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--all-tracked",
        action="store_true",
        help="scan all tracked files instead of staged content",
    )
    parser.add_argument("files", nargs="*", help="working-tree files to scan")
    parsed = parser.parse_args(arguments)
    if parsed.all_tracked and parsed.files:
        parser.error("--all-tracked cannot be combined with file arguments")
    return parsed


def main(arguments: list[str] | None = None) -> int:
    parsed = _parse_arguments(sys.argv[1:] if arguments is None else arguments)
    try:
        if parsed.all_tracked:
            inputs = _tracked_inputs()
        elif parsed.files:
            inputs = _working_tree_inputs(parsed.files)
        else:
            inputs = _staged_inputs()

        findings = []
        for filename, content in inputs:
            findings.extend(_scan_content(filename, content))
    except OperationalError as error:
        print(f"credential scan error: {error}", file=sys.stderr)
        return 2

    if not findings:
        print("Credential scan passed: no credential-like records found.")
        return 0

    print("Credential scan failed: credential-like records were found.", file=sys.stderr)
    for finding in sorted(findings):
        print(
            f"{_safe_for_log(finding.filename)}:{finding.line_number}: "
            f"identifier={_safe_for_log(finding.identifier)} "
            f"field={_safe_for_log(finding.field)} value=[REDACTED]",
            file=sys.stderr,
        )
    print(
        "Remove the credential, replace it with a safe placeholder, or rewrite "
        "non-sensitive documentation so it is not shaped like a credential record.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
