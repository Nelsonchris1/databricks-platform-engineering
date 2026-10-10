"""Exercise the deployment boundary without a live Databricks workspace."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from scripts.deploy_bundle import deploy, deployment_environment


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "DATABRICKS_HOST": "https://adb-123456789.1.azuredatabricks.net",
            "DATABRICKS_CLIENT_ID": "11111111-1111-4111-8111-111111111111",
        }

    def test_missing_workspace_stops_before_any_cli_call(self):
        del self.env["DATABRICKS_HOST"]
        with patch("scripts.deploy_bundle.subprocess.run") as run:
            with self.assertRaisesRegex(ValueError, "DATABRICKS_HOST"):
                deploy("dev", False, self.env)
            run.assert_not_called()

    def test_untrusted_refs_and_events_cannot_deploy(self):
        for key, value in (("GITHUB_REF", "refs/heads/feature"),
                           ("GITHUB_REF", "refs/tags/main"),
                           ("GITHUB_EVENT_NAME", "pull_request")):
            with self.subTest(key=key, value=value):
                with self.assertRaises(ValueError):
                    deployment_environment("dev", {**self.env, key: value})

    def test_rejects_invalid_workspace_and_identity(self):
        for key, value in (
            ("DATABRICKS_HOST", "http://adb-123.1.azuredatabricks.net"),
            ("DATABRICKS_HOST", "https://example.com"),
            ("DATABRICKS_HOST", "https://user@adb-123.1.azuredatabricks.net"),
            ("DATABRICKS_HOST", "https://adb-123.1.azuredatabricks.net/path"),
            ("DATABRICKS_CLIENT_ID", "not-a-uuid"),
            ("DATABRICKS_RUN_AS_CLIENT_ID", "not-a-uuid"),
        ):
            with self.subTest(key=key, value=value):
                with self.assertRaises(ValueError):
                    deployment_environment("dev", {**self.env, key: value})

    def test_unknown_target_and_static_credentials_are_rejected(self):
        with self.assertRaises(ValueError):
            deployment_environment("other", self.env)
        for key in ("DATABRICKS_TOKEN", "DATABRICKS_CLIENT_SECRET"):
            with self.subTest(key=key):
                with self.assertRaises(ValueError):
                    deployment_environment("dev", {**self.env, key: "secret"})

    def test_local_development_target_is_not_used_by_cd(self):
        target, env, run_as = deployment_environment("dev", self.env)
        self.assertEqual(target, "dev-ci")
        self.assertEqual(env["DATABRICKS_AUTH_TYPE"], "github-oidc")
        self.assertEqual(run_as, self.env["DATABRICKS_CLIENT_ID"])

    def test_distinct_run_identity_is_supported(self):
        app_id = "22222222-2222-4222-8222-222222222222"
        _, _, run_as = deployment_environment(
            "prod", {**self.env, "DATABRICKS_RUN_AS_CLIENT_ID": app_id}
        )
        self.assertEqual(run_as, app_id)

    def test_staging_and_production_require_pipeline_verification(self):
        for environment in ("staging", "prod"):
            with self.subTest(environment=environment):
                with patch("scripts.deploy_bundle.subprocess.run") as run:
                    with self.assertRaisesRegex(ValueError, "smoke"):
                        deploy(environment, False, self.env)
                    run.assert_not_called()

    def test_cli_order_and_failures_stop_later_operations(self):
        # A recording CLI at the external process boundary exercises real
        # subprocess exit handling; it makes no Databricks correctness claims.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "calls"
            cli = root / "databricks"
            cli.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALL_LOG"\n'
                'if [ "$2" = "$FAIL_COMMAND" ]; then exit 9; fi\n'
            )
            cli.chmod(0o755)
            env = {**os.environ, **self.env, "PATH": f"{root}:{os.defpath}",
                   "CALL_LOG": str(log)}
            for failure, expected in (
                ("validate", ["validate"]),
                ("deploy", ["validate", "deploy"]),
                ("run", ["validate", "deploy", "run"]),
                ("", ["validate", "deploy", "run", "summary"]),
            ):
                with self.subTest(failure=failure):
                    log.write_text("")
                    env["FAIL_COMMAND"] = failure
                    if failure:
                        with self.assertRaises(subprocess.CalledProcessError):
                            deploy("staging", True, env)
                    else:
                        deploy("staging", True, env)
                    calls = log.read_text().splitlines()
                    self.assertEqual([line.split()[1] for line in calls], expected)
                    self.assertTrue(all("--target staging" in line for line in calls))
                    self.assertTrue(all("catalog=staging" in line for line in calls))

    def test_dev_deploy_only_does_not_start_compute(self):
        with patch("scripts.deploy_bundle.subprocess.run") as run:
            deploy("dev", False, self.env)
        commands = [call.args[0][2] for call in run.call_args_list]
        self.assertEqual(commands, ["validate", "deploy", "summary"])

    @unittest.skipUnless(os.environ.get("DATABRICKS_CLI_TEST_BIN"), "Pinned CLI not installed")
    def test_pinned_cli_accepts_every_deployment_command(self):
        actual_run = subprocess.run

        def check_command(command, **kwargs):
            # --help parses the real CLI flags but does not authenticate or deploy.
            command = [os.environ["DATABRICKS_CLI_TEST_BIN"], *command[1:], "--help"]
            return actual_run(command, check=True, capture_output=True, text=True)

        with patch("scripts.deploy_bundle.subprocess.run", side_effect=check_command):
            deploy("prod", True, self.env)


if __name__ == "__main__":
    unittest.main()
