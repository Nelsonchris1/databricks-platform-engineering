# Workspace-level Unity Catalog root

## What was created

A new Terraform root at `infrastructure/databricks-workspace/` holding the catalog structure for the orders platform:

- one `databricks_catalog` named from `var.catalog_name` (default `dev`), with properties `environment`, `managed_by` and `purpose`;
- one `databricks_schema` per entry in `var.schema_names`, created with `for_each`, each carrying a medallion-layer comment from a local map and properties `environment`, `layer` and `managed_by`.

No tables, compute, groups or grants. Identity and RBAC come later, once the catalog structure is confirmed working.

`force_destroy = true` is set on the catalog, as specified, because this lab holds only regenerable synthetic data. It is also set on the schemas: Terraform destroys schemas before their parent catalog, so without it a teardown would fail as soon as these layers contain tables. Both carry comments saying production should normally leave `force_destroy` unset, so a destroy fails loudly rather than dropping real data.

## Why this is a separate root

The account and workspace APIs are different endpoints with different scopes, and the provider is configured differently for each. `infrastructure/databricks-account/` points at `accounts.azuredatabricks.net` with an `account_id`; this root points at the workspace host with no `account_id`. Keeping them apart also means the objects have independent lifecycles: you can rebuild or drop catalogs without touching the metastore, and the metastore survives catalog churn. Separate roots means separate state, so a mistake in one cannot corrupt the other.

## Prerequisite

**A Unity Catalog metastore must already be assigned to this workspace.** Creating a catalog against an unassigned workspace fails. The account root creates the metastore, assigns it and configures data access; it must be applied first, and `databricks metastores current` should return a metastore rather than `No metastore assigned for the current workspace`.

This root also needs the workspace itself to exist and be reachable, and an authenticated Azure CLI session for the tenant in `var.azure_tenant_id`. `workspace_host` comes from the Azure root's `workspace_url` output and changes whenever the workspace is recreated.

## Expected resource count

**4 to add** — 1 catalog + 3 schemas (`bronze`, `silver`, `gold`), with no changes and no destroys on a first apply. The count tracks the size of `var.schema_names`.

## Create and destroy order

Create, each root applied only after the previous one succeeds:

1. `infrastructure/azure/` — resource group and workspace
2. `infrastructure/databricks-account/` — metastore, assignment, data access
3. `infrastructure/databricks-workspace/` — catalog and schemas

Destroy in exact reverse:

1. `infrastructure/databricks-workspace/`
2. `infrastructure/databricks-account/`
3. `infrastructure/azure/`

The ordering is not automatic. Terraform's dependency graph works inside a single root, not across roots, so nothing stops you destroying the workspace while catalogs still reference its metastore. Running them out of order leaves orphaned objects that Terraform can no longer reach, and state entries pointing at things that no longer exist.
