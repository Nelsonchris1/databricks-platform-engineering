# CI Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution, or superpowers:subagent-driven-development if the user selects delegation. Steps use checkbox syntax for tracking.

**Goal:** Validate changes in GitHub Actions and demonstrate that a failed required check prevents merging into main.

**Architecture:** One workflow provides independent formatting, Terraform validation, Python syntax and shell syntax jobs. It runs without a live Azure workspace or cloud credentials. Deployment automation follows as a separate milestone.

**Tech Stack:** GitHub Actions, Ubuntu 24.04, Terraform 1.15.8, Python 3.11, Bash and actionlint.

**Spec:** [Approved CI design](../specs/2026-10-05-ci-foundation-design.md)

## Global Constraints

- Azure remains torn down during this milestone.
- CI must work from committed files without local tfvars, Terraform state, Azure credentials, Databricks credentials, or a running workspace.
- Run on pull requests targeting `main`, pushes to `main`, and manual dispatch.
- Run for all paths so required checks are not accidentally absent on a PR.
- Provider versions come from the committed lock files, not an upgrade operation.
- Publish only the reviewed CI design and implementation plan; other local notes remain ignored.
- Commit and push each significant verified stage, as requested by the user.
- No Terraform plan/apply/destroy or live notebook execution in CI.

## Review Focus

1. Clean runners have no provider cache or tfvars: verify from an exported checkout and in Linux Actions.
2. Fork and documentation-only PRs must receive checks without secrets: inspect permissions and exercise a documentation-only PR update.
3. One matrix failure must not hide other roots: use `fail-fast: false` and inspect the failing hosted run.
4. Syntax compilation must not execute notebooks or shell scripts: inject a valid top-level exception in a temporary notebook and compile it successfully.
5. A failed workflow is not merge protection: inspect required checks and the failing PR's merge state without attempting a merge.

## Task 1: Implement and verify the workflow locally

**Files:** Create `.github/workflows/ci.yml`; modify `README.md`; modify provider lock hashes only if Linux support requires it.

**Interfaces:** Consumes the three existing Terraform roots, notebooks and lifecycle scripts. Produces six stable status names: `Terraform format`, `Terraform validate (azure)`, `Terraform validate (databricks-account)`, `Terraform validate (databricks-workspace)`, `Python syntax`, and `Shell syntax`.

- [ ] Create an isolated implementation branch using the worktree skill. Preserve the published planning checkpoint.
- [ ] Verify Terraform 1.15.8 has an official Linux AMD64 distribution before installation. If unavailable, stop and report the discrepancy rather than substituting a floating version.
- [ ] Use the following verified action pins (resolved via GitHub API on 2026-10-09):

```yaml
# actions/checkout v4
uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262
# actions/setup-python v5
uses: actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065
# hashicorp/setup-terraform v3
uses: hashicorp/setup-terraform@b9cd54a3c349d3f38e8881555d616ced269862dd
```

- [ ] Create this workflow envelope:

```yaml
name: CI
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```

- [ ] Add four jobs, each with `runs-on: ubuntu-24.04`, `timeout-minutes: 10`, checkout with `persist-credentials: false`, and the stable display names above. Terraform jobs use the pinned setup action with `terraform_version: 1.15.8` and `terraform_wrapper: false`. Python uses the pinned setup action with `python-version: '3.11'`.
- [ ] Set the validation matrix and commands exactly as follows; other jobs run their corresponding commands below:

```yaml
name: Terraform validate (${{ matrix.root }})
strategy:
  fail-fast: false
  matrix:
    root: [azure, databricks-account, databricks-workspace]
defaults:
  run:
    working-directory: infrastructure/${{ matrix.root }}
```

```bash
# Terraform format job, from repository root
terraform fmt -check -recursive infrastructure
# Each Terraform validation matrix job, from its root
terraform init -backend=false -input=false -lockfile=readonly
terraform validate -no-color
# Python syntax job, from repository root
python -m compileall -q src/medallion
# Shell syntax job, from repository root (check both separately)
bash -n scripts/terraform-up.sh
bash -n scripts/terraform-down.sh
```

- [ ] Run actionlint against `.github/workflows/ci.yml`. Use a verified official actionlint release if the tool is unavailable. Resolve every diagnostic.
- [ ] Export tracked files into a temporary directory and copy the new workflow into it. Run the exact workflow commands there. Record individual exit codes; a later successful command must not mask an earlier failure.
- [ ] In a temporary copy append `def broken(:` to a notebook; confirm Python compilation fails. Restore it and append `raise RuntimeError('must not execute')`; compilation must pass. Discard the temporary copy.
- [ ] In a temporary shell copy append `if then`; confirm `bash -n` fails. Restore and confirm success.
- [ ] In a temporary Terraform copy introduce `resource "broken" {`; confirm validation fails, restore, and confirm validation passes. Separately disturb formatting in valid HCL and confirm `fmt -check` fails.
- [ ] Check Linux provider installation in the hosted run. If extra lock hashes are necessary, run `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` in each affected root and verify selected provider versions did not change.
- [ ] Add a README section describing triggers, six check names, the commands above, and the limitations: syntax/configuration checks do not prove data correctness or cloud deployability. Document that remote state is a prerequisite for automated applies, not this CI milestone.
- [ ] Review `git diff --check` and the complete diff. Commit only the workflow, README and any verified lock-file changes with message `ci: validate Terraform and notebook syntax`. Push the implementation branch. Update the plan's completed checkboxes in the same milestone commit where practical.

## Task 2: Verify hosted checks and merge protection

**Files:** Update `README.md` with verified CI behavior and this plan with evidence links. Update local `docs/phase.md` and `docs/commands.md` without publishing them.

**Interfaces:** Consumes Task 1's six check names. Produces a passing PR, evidence of a rejected bad change, and required checks on main.

- [ ] Open a PR targeting `main`, describing the actual checks and local validation. Record the PR URL in this plan.
- [ ] Watch the hosted run and inspect any failures with `gh run view --log-failed`. Fix demonstrated errors and push a checkpoint commit. Require all six checks to succeed before claiming hosted validation works.
- [ ] Read existing branch protection and rulesets through the GitHub API. Preserve unrelated settings. Configure all six observed check names as required for main with an up-to-date branch requirement. Require PRs; do not add unrelated review-count requirements to this solo lab.
- [ ] Verify resulting protection through a fresh API read. If permissions prevent configuration, report the exact limitation and leave merge-blocking acceptance incomplete.
- [ ] On the unmerged feature branch, introduce a small deliberate Terraform formatting error, commit as `test: demonstrate CI rejects Terraform formatting`, and push. Confirm formatting fails, other checks still report, and the PR merge state reflects the required-check failure. Do not attempt a merge.
- [ ] Restore only the deliberate formatting change. Commit as `test: restore formatting after CI failure demonstration`, push, and confirm all checks succeed.
- [ ] Make a documentation-only evidence update; confirm all required checks still run. Record successful and failed run URLs plus merge-protection evidence in this plan and summarize the completed checkpoint in README. Record any remaining limitations explicitly.
- [ ] Update local phase/command journals. Mark CI complete only once its acceptance evidence exists; keep overall Phase 4 in progress because CD remains outstanding.
- [ ] Commit as `docs: record verified CI and merge protection` and push. Report the final hosted result and PR link. Integrate through the branch-finishing workflow; do not delete the verification history.

## Milestone commits

1. Approved design and implementation plan (this planning checkpoint).
2. Locally verified CI workflow and README.
3. Hosted failure demonstration and correction (two intentionally separate commits).
4. Verified hosted checks and merge-protection evidence.

## Current evidence

- Design approved: 2026-10-09.
- Action pins resolved through the GitHub API: 2026-10-09.
- Workflow implementation and hosted CI evidence: not started.
- Implementation plan: awaiting user review and execution-method selection.
