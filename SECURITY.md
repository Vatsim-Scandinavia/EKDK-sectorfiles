# Credential scanning

This repository checks selected text files for records shaped as three
whitespace-delimited columns: an identifier or section, a sensitive field, and
a non-empty value. The field match is case-insensitive. The sensitive fields
are `username`, `user`, `password`, `passwd`, and `certificate`.

Only files ending in `.conf`, `.md`, or `.txt` are scanned. Binary files are
ignored, and detected values are always displayed as `[REDACTED]`.

## Local pre-commit hook

Enable the version-controlled hook once in your clone:

```bash
git config core.hooksPath .githooks
```

The hook runs `python3 scripts/check_credentials.py`, which examines staged Git
content and blocks a commit when a credential-like record is present.

## Manual use

Scan staged content:

```bash
python3 scripts/check_credentials.py
```

Scan specific working-tree files (filenames containing spaces are supported):

```bash
python3 scripts/check_credentials.py "path/to/example file.txt"
```

Scan every tracked file with a supported extension, as CI does:

```bash
python3 scripts/check_credentials.py --all-tracked
```

## False positives

Do not add broad exclusions. First verify that the record is non-sensitive. If
it is documentation, rewrite it as prose or replace the value with a clearly
safe placeholder while avoiding the three-column credential-record shape. If
the format cannot be changed, propose a narrowly scoped, documented exception
for review; the scanner currently has no suppression directives because none
are needed by the repository.
