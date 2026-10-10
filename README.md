# Azure Databricks Platform Engineering Lab

A complete, disposable Azure Databricks data platform built entirely as code — from an empty Azure subscription through Unity Catalog governance to a running medallion pipeline, and back down to nothing.

The point of this repository is the **full lifecycle**, not just the happy path. Everything here can be created with one command and destroyed with another, because a lab you cannot tear down cleanly is a lab that quietly bills you.

## What it builds

```
Azure subscription
  └─ resource group, Databricks workspace, ADLS Gen2 + access connector   [Terraform]
       └─ Unity Catalog metastore assignment, account groups              [Terraform]
            └─ storage credential, external location, dev catalog,
               bronze/silver/gold schemas, RBAC grants                    [Terraform]
                 └─ medallion job: bronze → silver → gold                 [Asset Bundle]
```

## Repository layout

| Path | What it is |
|---|---|
| `infrastructure/azure/` | Terraform root: resource group, workspace, ADLS Gen2 storage, access connector, role assignment |
| `infrastructure/databricks-account/` | Terraform root: metastore assignment, account-level groups, workspace permission assignments |
| `infrastructure/databricks-workspace/` | Terraform root: storage credential, external location, catalog, schemas, grants |
| `src/medallion/` | Three Databricks notebooks implementing the pipeline |
| `resources/medallion.job.yml` | Job definition — three sequential tasks |
| `databricks.yml` | Asset Bundle config with personal `dev` and automated `dev-ci`, `staging`, `prod` targets |
| `.github/workflows/` | CI validation and manually triggered CD promotion |
| `DEPLOYMENT.md` | Deployment prerequisites, OIDC setup and release commands |
| `scripts/` | One-command build and teardown |

### Why three Terraform roots

The Azure, Databricks-account and Databricks-workspace APIs are different endpoints with different scopes and different provider configuration. Splitting them also gives each layer an independent lifecycle — you can rebuild catalogs without touching the metastore — and separate state, so a mistake in one root cannot corrupt another.

The cost is that Terraform's dependency graph only works *inside* a root. Ordering across roots is the operator's job, which is what the scripts exist to enforce.

### Why the platform is Terraform but the workload is a bundle

Terraform owns long-lived governed objects: catalogs, schemas, credentials, grants. The Databricks Asset Bundle owns the workload — notebooks and the job that runs them — because that is what changes on every commit and what needs per-target promotion (`dev` vs `prod`). Mixing the two means a pipeline tweak makes you replan your entire governance layer.

## The pipeline

Synthetic orders → `bronze.orders_raw` → `silver.orders` → `gold.daily_sales`

- **Bronze** lands a fixed 19-row synthetic batch with no validation. Business fields stay strings, mirroring an untyped feed, and the batch deliberately contains bad rows — missing IDs, a non-numeric quantity, a negative price, an unsupported status, and a restated duplicate order.
- **Silver** conforms, validates and deduplicates. Rejected rows are **quarantined with a stated reason**, never silently dropped, and a row-count reconciliation asserts that every Bronze row landed in exactly one output.
- **Gold** aggregates completed orders by day into order count, distinct customers, units sold and revenue.

Each layer writes with `overwrite`, making it a pure function of the layer below — so reruns reproduce tables rather than accumulating duplicates. Data-quality assertions raise on failure, which fails the task and stops the next layer running on bad data.

See [`infrastructure/databricks-workspace/claude-workspace-build.md`](infrastructure/databricks-workspace/claude-workspace-build.md) for the catalog design notes.

## Getting started

**Prerequisites:** Terraform >= 1.5, Azure CLI, Databricks CLI, an Azure subscription, and a Unity Catalog metastore in your region.

Each Terraform root needs a local `terraform.tfvars`. These are gitignored — they hold subscription, tenant and account identifiers — so you must create them yourself. The `variables.tf` in each root documents and validates every required value.

```bash
az login

./scripts/terraform-up.sh          # build the platform (billable)
databricks bundle deploy -t dev    # deploy the workload
databricks bundle run medallion_job -t dev

databricks bundle destroy -t dev   # remove the workload first
./scripts/terraform-down.sh        # then the platform
```

`terraform-up.sh` reads the Azure root's outputs and passes them to the downstream roots with `-var`, so a recreated workspace wires itself up instead of using a stale tfvars. `terraform-down.sh` destroys in reverse dependency order, verifies both resource groups are gone, and prints the leftovers Terraform does not manage. Both support `--dry-run`.

## Continuous integration

The [CI workflow](.github/workflows/ci.yml) runs on pull requests targeting
`main`, pushes to `main`, and manual dispatch. CD also reuses it before deployment.
It reports seven checks:

- Terraform formatting across all three roots.
- Terraform validation for Azure, Databricks account and Databricks workspace
  independently (three checks).
- Python syntax for the medallion notebooks, using Python 3.11.
- Shell syntax for both lifecycle scripts.
- Offline bundle schema checks and deployment guard/failure tests.

CI installs the locked providers with the state backend disabled. It needs no
Azure or Databricks credentials, local `terraform.tfvars`, or deployed workspace.
It does not provision infrastructure or execute the notebooks. These checks
catch syntax and configuration errors; they do not prove Spark data correctness,
cloud permissions, quota, or deployment readiness.

Run the equivalent checks locally with Terraform 1.15.8 and Python 3.11:

```bash
terraform fmt -check -recursive infrastructure
for root in azure databricks-account databricks-workspace; do
  terraform -chdir="infrastructure/$root" init -backend=false -input=false -lockfile=readonly || exit
  terraform -chdir="infrastructure/$root" validate -no-color || exit
done
python3.11 -m compileall -q src/medallion scripts tests
bash -n scripts/terraform-up.sh
bash -n scripts/terraform-down.sh
# With Databricks CLI 1.20.0 installed:
python3.11 -m pip install -r requirements-ci.txt
python3.11 scripts/check_bundle_schema.py
DATABRICKS_CLI_TEST_BIN=databricks python3.11 -m unittest discover -s tests -v
```

Required checks on `main` are a separate GitHub repository setting: a failed
workflow alone does not prevent a merge.

## Continuous delivery

The [CD workflow](.github/workflows/cd.yml) promotes one commit through dev →
staging → prod using GitHub OIDC and environment-scoped service principals.
Start it manually from `main`. Dev can deploy without starting compute;
promotion to staging/prod requires successful billable pipeline tests, and
production waits for approval. Existing personal `dev` deployments remain
separate from the automated `dev-ci` target.

The workflow code is implemented; live deployment requires a rebuilt workspace,
configured identities and environment variables, and staging/prod catalogs and
grants. See [the deployment guide](DEPLOYMENT.md) for setup, operation, cleanup
and limitations. Terraform provisioning remains separate; a remote state backend
is required before adding automated Terraform applies.

## Cost

This lab provisions billable infrastructure. The Databricks-managed resource group alone contains a NAT gateway, public IP and managed storage, all of which accrue charges **with no clusters running** — which is why the teardown path is treated as a first-class feature rather than an afterthought.

Set a subscription budget before building. A budget alerts; it does not cap.

## Deliberate lab trade-offs

Called out honestly rather than presented as production-ready:

- **Local Terraform state.** Fine for one operator; a remote backend with locking is the prerequisite for CI/CD.
- **`force_destroy = true`** on the catalog and schemas. Correct for regenerable synthetic data, wrong for real tables.
- **Public workspace access**, no VNet injection or private endpoints. Retrofitting these forces workspace replacement, so in production the network is decided first.
- **Full-overwrite pipeline.** At real volumes Bronze would use Auto Loader with checkpoints and Gold would `MERGE` incrementally.

Working notes, the lab journal and a fuller production-readiness review live in `docs/`, which is kept local and not published.
