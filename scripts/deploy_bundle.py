#!/usr/bin/env python3
"""Deploy an environment from GitHub Actions; never provision the platform."""

import argparse
import os
import re
import subprocess
import sys
from uuid import UUID


TARGETS = {"dev": "dev-ci", "staging": "staging", "prod": "prod"}


def deployment_environment(environment, environ):
    """Reject incomplete or unsafe configuration before invoking the CLI."""
    if environment not in TARGETS:
        raise ValueError("Environment must be dev, staging or prod")
    if environ.get("GITHUB_REF") != "refs/heads/main":
        raise ValueError("Deployment is restricted to refs/heads/main")
    if environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch":
        raise ValueError("Deployment requires a manual workflow_dispatch")
    host = environ.get("DATABRICKS_HOST", "").rstrip("/")
    if not re.fullmatch(r"https://adb-[0-9]+\.[0-9]+\.azuredatabricks\.net", host):
        raise ValueError("Set DATABRICKS_HOST to the environment's Azure Databricks workspace URL")
    client_id = environ.get("DATABRICKS_CLIENT_ID", "")
    run_as = environ.get("DATABRICKS_RUN_AS_CLIENT_ID") or client_id
    for key, value in (("DATABRICKS_CLIENT_ID", client_id),
                       ("DATABRICKS_RUN_AS_CLIENT_ID", run_as)):
        try:
            if str(UUID(value)) != value.lower():
                raise ValueError()
        except (ValueError, AttributeError):
            raise ValueError(f"Set {key} to a service principal application UUID") from None
    if any(environ.get(key) for key in ("DATABRICKS_TOKEN", "DATABRICKS_CLIENT_SECRET")):
        raise ValueError("Use GitHub OIDC; static Databricks credentials are not accepted")
    child_env = dict(environ)
    child_env.update(DATABRICKS_AUTH_TYPE="github-oidc", DATABRICKS_HOST=host)
    return TARGETS[environment], child_env, run_as


def deploy(environment, smoke_test, environ):
    target, child_env, run_as = deployment_environment(environment, environ)
    if environment != "dev" and not smoke_test:
        raise ValueError("staging/prod promotion requires the billable smoke test")
    options = ["--target", target, "--var",
               f"catalog={environment},run_as_service_principal={run_as}"]
    commands = [
        ["databricks", "bundle", "validate", *options],
        ["databricks", "bundle", "deploy", *options, "--auto-approve", "--fail-on-active-runs"],
    ]
    if smoke_test:
        # The CLI waits for completion; the server enforces the job timeout.
        commands.append(["databricks", "bundle", "run", "medallion_job",
                         *options])
    commands.append(["databricks", "bundle", "summary", *options])
    for command in commands:
        print(f"{command[2]}: environment={environment}, target={target}", flush=True)
        subprocess.run(command, env=child_env, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("environment", choices=TARGETS)
    parser.add_argument("--smoke-test", action="store_true",
                        help="Run the medallion job after deploying (billable)")
    args = parser.parse_args()
    try:
        deploy(args.environment, args.smoke_test, os.environ)
    except ValueError as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        return 2
    except subprocess.CalledProcessError as error:
        return error.returncode
    return 0


if __name__ == "__main__":
    sys.exit(main())
