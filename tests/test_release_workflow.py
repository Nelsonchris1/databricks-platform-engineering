"""Run the workflow's actual shell guard with valid and invalid requests."""

import os
from pathlib import Path
import subprocess
import unittest

import yaml


class ReleaseRequestTests(unittest.TestCase):
    def test_release_guard(self):
        workflow = yaml.safe_load(Path(".github/workflows/cd.yml").read_text())
        guard = workflow["jobs"]["guard"]["steps"][0]["run"]
        for ref, target, smoke, accepted in (
            ("refs/heads/main", "dev", "false", True),
            ("refs/heads/main", "staging", "true", True),
            ("refs/heads/main", "prod", "true", True),
            ("refs/heads/feature", "dev", "false", False),
            ("refs/tags/main", "dev", "false", False),
            ("refs/heads/main", "staging", "false", False),
            ("refs/heads/main", "prod", "false", False),
            ("refs/heads/main", "unknown", "true", False),
        ):
            with self.subTest(ref=ref, target=target, smoke=smoke):
                result = subprocess.run(
                    ["bash", "-e", "-c", guard], capture_output=True, text=True,
                    env={**os.environ, "RELEASE_REF": ref,
                         "PROMOTE_TO": target, "SMOKE_TEST": smoke},
                )
                self.assertEqual(result.returncode == 0, accepted, result.stdout)
