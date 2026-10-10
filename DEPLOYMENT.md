# Deploying the Databricks workload

The `CD` GitHub Actions workflow deploys the notebooks and medallion job. It
does not create Azure infrastructure, catalogs, or identities. Start it manually
from `main` after merging the implementation PR. There is no deployment on a PR
or automatic cloud rebuild on a push.

## Release flow

1. Check the release request and rerun CI on the selected commit.
2. Validate and deploy dev.
3. If selected, run the dev pipeline, then deploy and test staging.
4. If selected, wait for production approval, then deploy and test prod.

Every environment checks out the original dispatch SHA, even if `main` advances
while approval is pending. The full chain is serialized; running deployments
are not cancelled by newer requests. GitHub can replace an older pending run
with a newer pending run, so this is not a durable release queue.

| GitHub environment | Bundle target | Catalog | Workspace deployment root suffix |
| --- | --- | --- | --- |
| dev | dev-ci | dev | `/dbx-interview-lab/dev-ci` |
| staging | staging | staging | `/dbx-interview-lab/staging` |
| prod | prod | prod | `/dbx-interview-lab/prod` |

Roots are beneath `/Workspace/Shared/.bundle`. The existing personal `dev`
bundle target remains separate from `dev-ci`. Do not run personal and CD jobs
concurrently against the same dev tables: both overwrite their output tables.
All CD targets use production deployment mode, with explicit service-principal
run identities and distinct deployment state paths.

## GitHub configuration

Environments `dev`, `staging`, and `prod` must exist and restrict deployment to
the `main` branch. Production must require an approver. These settings were
configured on 2026-10-09, with `Nelsonchris1` as the production reviewer.
Self-approval is allowed for this solo lab; a team should require a different
reviewer. Repository administrators can manage protection settings.

Set these **environment variables** under Settings → Environments for each
environment, rather than repository-wide values:

| Variable | Required | Value |
| --- | --- | --- |
| `DATABRICKS_HOST` | Yes | The live `https://adb-….azuredatabricks.net` workspace URL |
| `DATABRICKS_CLIENT_ID` | Yes | Deployment service principal's application UUID |
| `DATABRICKS_RUN_AS_CLIENT_ID` | No | Separate job service principal application UUID; defaults to the deployer's UUID |

The workflow sets `DATABRICKS_AUTH_TYPE=github-oidc` and requests an OIDC token
only in deployment jobs. Do not add a PAT or client secret. Missing settings
fail before deployment. Updating the workspace host is necessary after a lab
rebuild; the workflow does not read your ignored `.env` or `terraform.tfvars`.

## Disposable dev identity

The account root can now create the dev CD principal, its federation policy and
workspace assignment. Set `github_oidc_subject` in its local `terraform.tfvars`
to the verified dev subject below, then use `scripts/terraform-up.sh`. The script
passes the generated application UUID to the workspace root, which grants dev
catalog/schema access and manages the dev-ci bundle directory permissions.
`terraform-down.sh` removes these resources, including the account principal.
The default empty subject disables this optional identity. Staging/prod
identities and catalogs remain separate future platform work.

## Databricks federation and permissions

Use a distinct Databricks service principal for each deployment environment.
Assign it to the live workspace. Configure an account-level federation policy
on that principal with issuer `https://token.actions.githubusercontent.com`,
the Databricks account UUID as audience, and the exact environment subject.

This repository uses GitHub's immutable OIDC subject format. Verified subjects:

```text
repo:Nelsonchris1@48487985/databricks-platform-engineering@1396452340:environment:dev
repo:Nelsonchris1@48487985/databricks-platform-engineering@1396452340:environment:staging
repo:Nelsonchris1@48487985/databricks-platform-engineering@1396452340:environment:prod
```

Confirm the prefix again if repository settings change:

```bash
gh api repos/Nelsonchris1/databricks-platform-engineering/actions/oidc/customization/sub
```

With an account-admin CLI profile and the following values already set, create
one policy at a time. `SERVICE_PRINCIPAL_ID` is the numeric account ID of the
principal, while `DATABRICKS_CLIENT_ID` above is its application UUID.

```bash
: "${ACCOUNT_PROFILE:?Set the Databricks account-admin CLI profile name}"
: "${DATABRICKS_ACCOUNT_ID:?Set the Databricks account UUID}"
: "${SERVICE_PRINCIPAL_ID:?Set the numeric account service-principal ID}"
: "${DEPLOY_ENVIRONMENT:?Set dev, staging or prod}"
case "$DEPLOY_ENVIRONMENT" in dev|staging|prod) ;; *) exit 1 ;; esac

jq -n --arg audience "$DATABRICKS_ACCOUNT_ID" \
  --arg subject "repo:Nelsonchris1@48487985/databricks-platform-engineering@1396452340:environment:$DEPLOY_ENVIRONMENT" \
  '{oidc_policy: {issuer: "https://token.actions.githubusercontent.com", audiences: [$audience], subject: $subject}}' \
  > /tmp/databricks-federation-policy.json

databricks account service-principal-federation-policy create \
  "$SERVICE_PRINCIPAL_ID" --profile "$ACCOUNT_PROFILE" \
  --json @/tmp/databricks-federation-policy.json
```

The optional Terraform dev identity already owns its policy; do not also create
a manual policy for it. Create a policy only if it does not already exist. Use the account console to
inspect existing policies first. Environment-based subjects depend on GitHub's
deployment branch restrictions for main-only access.

The deployment identity needs workspace access, permission to create/manage its
job, and permission to write its bundle folder. The runtime identity needs read
access to deployed notebooks, serverless availability, and these Unity Catalog
privileges scoped to its own catalog:

- `USE_CATALOG` on the environment catalog.
- `USE_SCHEMA`, `CREATE_TABLE`, `SELECT`, and `MODIFY` on bronze/silver/gold.
- Ownership or the necessary rights on any pre-existing output tables it overwrites.

If runtime and deployment identities differ, grant the deployment identity the
Service Principal User role on the runtime identity and ensure the runtime
identity can read the deployed files. Existing `data-engineers` and
`data-analysts` groups must be assigned to the workspace because the job grants
reference them. Do not grant the runtime principal workspace admin merely to
make deployment pass.

## Platform prerequisites and ownership

Rebuild the platform with the existing Terraform lifecycle when ready for a
billable exercise. The current workspace Terraform root provisions only `dev`.
Staging/prod catalogs, schemas and runtime grants still need an explicit
Terraform extension before live promotion. Do not switch `catalog_name` in the
existing dev state to emulate another environment: that can replace dev and
delete its data. Do not apply copies of the workspace root blindly, since its
storage credential and external location have shared names.

Keep infrastructure deployment separate from this workload workflow. Automated
Terraform applies require a persistent remote backend and Azure deployment
identity; neither is configured by this change. Bundle deployment state lives
in each target's workspace path, independently of the local Terraform state.

## Run a release

In Actions → CD → Run workflow, select branch `main` and the last environment.
For dev only, leaving `smoke_test` false deploys the job without starting compute.
For staging or prod, `smoke_test` must be true; each environment must finish its
pipeline successfully before promotion continues. The pipeline uses synthetic
data and overwrites the selected catalog's tables.

Equivalent commands after the workflow has been merged:

```bash
gh workflow run cd.yml --ref main -f promote_to=dev -f smoke_test=false
# Billable: execute the pipeline in dev and staging.
gh workflow run cd.yml --ref main -f promote_to=staging -f smoke_test=true
# Billable: execute in all three environments, with a prod approval gate.
gh workflow run cd.yml --ref main -f promote_to=prod -f smoke_test=true
```

Review the exact commit and upstream smoke results before approving prod. Failed
validation, deployment, or pipeline execution stops the chain. Deployments fail
if the target job already has active runs. A successful earlier environment is
not rolled back when a later environment fails.

Each job has a 30-minute server-side timeout and no task retries. This bounds
runtime even if the GitHub runner disconnects; it does not impose a financial
spending cap. A cancelled runner may leave a job running until that timeout—
inspect and cancel it in Databricks when needed. Track the lab's USD 20 budget.

To revert workload code, revert the source change on main, pass CI and dispatch
CD again. This changes job/code definitions; it does not restore overwritten
data. Destroy deployed CD bundles in reverse order (`prod`, `staging`, `dev-ci`)
with the corresponding workspace and run-identity variables before Terraform
teardown, in addition to any personal `dev` bundle.

## Validation and current limits

CI validates bundle YAML against the pinned CLI schema and tests the deployment
guard, command syntax and failure handling without authenticating. Run locally:

```bash
python3.11 -m pip install -r requirements-ci.txt
python3.11 scripts/check_bundle_schema.py
DATABRICKS_CLI_TEST_BIN=databricks python3.11 -m unittest discover -s tests -v
```

Use Databricks CLI 1.20.0 for those checks; the workflow installs that version.
Schema checks do not resolve workspace objects or verify permissions. The live
workspace, identities, federation policies, environment variables, staging/prod
governance and a full deployment/approval run remain to be verified before this
lab can claim end-to-end CD. No cloud resources are created by the offline tests.

References: [Azure Databricks GitHub federation](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/auth/provider-github),
[bundle run identities](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/run-as),
[GitHub deployment environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments).
