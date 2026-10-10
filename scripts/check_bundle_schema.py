#!/usr/bin/env python3
"""Check bundle YAML against the installed CLI's schema, without cloud access."""

import json
from pathlib import Path
import subprocess
import sys

import jsonschema
import regex
import yaml


def unicode_pattern(validator, pattern, instance, schema):
    # The CLI schema uses Unicode property escapes such as \p{L}, which
    # Python's built-in re (used by jsonschema) does not implement.
    if isinstance(instance, str) and not regex.search(pattern, instance):
        yield jsonschema.ValidationError(f"{instance!r} does not match {pattern!r}")


def make_validator(schema):
    base = jsonschema.validators.validator_for(schema)
    return jsonschema.validators.extend(base, {"pattern": unicode_pattern})(schema)


def main():
    schema = json.loads(subprocess.check_output(
        ["databricks", "bundle", "schema"], text=True
    ))
    validator = make_validator(schema)
    root = Path("databricks.yml")
    document = yaml.safe_load(root.read_text())
    files = {root}
    for pattern in document.get("include", []):
        matches = set(Path(".").glob(pattern))
        if not matches:
            raise ValueError(f"No bundle files match {pattern!r}")
        files.update(matches)
    failures = []
    for path in sorted(files):
        data = yaml.safe_load(path.read_text())
        for error in validator.iter_errors(data):
            location = ".".join(str(part) for part in error.absolute_path)
            failures.append(f"{path}:{location}: {error.message}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Bundle schema valid: {len(files)} files (offline; no workspace checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
