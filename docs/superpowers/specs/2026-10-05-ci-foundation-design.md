# Phase 4a: GitHub Actions CI foundation

Status: approved by the user on 2026-10-09. No workflow has been implemented yet.

## Outcome and constraints

Add automated pull-request validation to the existing
`Nelsonchris1/databricks-platform-engineering` repository. Continue the lab's
explain/build/verify approach. Azure remains torn down during this milestone.
CI must work from committed files without local tfvars, Terraform state,
Azure credentials, Databricks credentials, or a running workspace.

The user approved starting CI/CD with CI first. This document specifies that
first milestone; live deployment and promotion remain subsequent work.

## Approach

Use one `.github/workflows/ci.yml` workflow with independent validation jobs.
This keeps failures easy to locate while avoiding separate workflows for a
small repository. A single sequential job would be simpler but obscure
individual checks; introducing cloud deployment immediately would require
identity, environment and state work before proving basic CI.

Run on pull requests targeting `main`, pushes to `main`, and manual dispatch.
Run for all paths so required checks are not accidentally absent on a PR.
Use Ubuntu runners, explicit tool versions, actions pinned to verified commit
SHAs, read-only repository permissions, and checkout without persisting Git
credentials. Cancel superseded CI runs on the same branch or pull request.
Give jobs a finite timeout and avoid secrets or cloud login steps.

## Checks

1. Terraform formatting: `terraform fmt -check -recursive infrastructure`.
2. Terraform validation: a matrix covers `infrastructure/azure`,
   `infrastructure/databricks-account`, and
   `infrastructure/databricks-workspace`. Each initializes with
   `terraform init -backend=false -input=false -lockfile=readonly`, then runs
   `terraform validate -no-color`. Disable matrix fail-fast so each root reports.
   Verify committed lock files support Linux before finalizing the workflow;
   preserve the currently selected provider versions if hashes need expanding.
3. Python syntax: compile the three notebooks with Python 3.11. Compilation
   must not execute their Spark or `dbutils` calls. This is a syntax check,
   not a pipeline behavior test.
4. Shell syntax: run `bash -n` on both Terraform lifecycle scripts without
   executing either script.

Pin Terraform initially to the locally verified 1.15.8 release, subject to
confirming its official Linux distribution during implementation. Provider
versions come from the committed lock files, not an upgrade operation.

Provider installation needs network access, but validation does not need a
cloud session. Terraform plan/apply/destroy and authenticated bundle validation
are outside this milestone. Remote state is needed before automated Terraform
deployment, not before this configuration-only validation workflow.

## Files and documentation

- Add `.github/workflows/ci.yml`.
- Update `README.md` with triggers, checks, local equivalents and limitations.
- Update the local `docs/phase.md` and `docs/commands.md` with verified progress.
- Update provider lock hashes only if necessary for Linux initialization.

The user requested GitHub commits at each significant stage on 2026-10-09.
Publish this design and its implementation plan through narrowly scoped
`.gitignore` exceptions. Keep other local notes and lab journals ignored.
Commit and push each significant verified implementation milestone; report
pending checks accurately in checkpoint documentation.

## Evidence and acceptance

- Run the actual check commands against a clean export of tracked files, which
  excludes local state, tfvars and provider caches.
- Validate the workflow with actionlint and inspect its event/permission setup.
- In temporary copies, introduce malformed Python, malformed shell syntax and
  a Terraform error; confirm the corresponding checks exit nonzero. Restore
  clean inputs and confirm success. Avoid tests that merely inspect YAML text.
- Publish a feature branch and PR once implementation is ready. Record actual
  GitHub Actions results before claiming hosted CI works.
- Demonstrate a failing check and a subsequent passing fix on the PR. Keep the
  failure example isolated from `main`.
- Configure the verified job names as required checks for `main`, preserving
  existing repository rules. Confirm a failing required check prevents merging;
  a red workflow alone is not merge protection. Report any permission or
  repository-policy limitation explicitly.

No implementation, hosted run, or merge-protection evidence exists at design time.

## Remaining Phase 4 milestones

After CI is verified, design automated deployment separately: a persistent
Azure state backend, federated CI identities, reachable platform resources,
dev/staging/prod governance, bundle execution identities, environment-scoped
deployment, and production approval. The current bundle lacks staging and a
production execution identity. These are prerequisites to resolve before
claiming end-to-end promotion works. Preserve the lab's USD 20 total budget
constraint when planning any cloud rebuild or pipeline execution.

## References

- HashiCorp validation behavior and backend-free initialization:
  https://developer.hashicorp.com/terraform/cli/commands/validate
- GitHub workflow events, permissions, concurrency and matrix syntax:
  https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
