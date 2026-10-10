#!/usr/bin/env bash
#
# Tear down every Terraform-managed platform resource in this lab, in dependency
# order. Destroy all deployed bundles before running this script.
#
# Order is not optional. Terraform's dependency graph only works inside a single
# root, so nothing stops you destroying the Azure workspace while Databricks
# objects still reference it. Destroy the workspace root first, then the account
# root, then Azure last.
#
# Usage:
#   scripts/terraform-down.sh              # confirm, then destroy
#   scripts/terraform-down.sh --dry-run    # generate destroy plans only
#   scripts/terraform-down.sh --yes        # skip the confirmation prompt
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AZURE_DIR="infrastructure/azure"

# Reverse of the create order.
ROOTS=(
  "infrastructure/databricks-workspace"
  "infrastructure/databricks-account"
  "$AZURE_DIR"
)

# Distinct name so this never clobbers a plan you saved by hand.
PLAN_FILE="autogen-destroy.tfplan"

ASSUME_YES=false
DRY_RUN=false

usage() {
  sed -n '3,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cleanup() {
  for dir in "${ROOTS[@]}"; do
    rm -f "$REPO_ROOT/$dir/$PLAN_FILE"
  done
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) ASSUME_YES=true ;;
    -n|--dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# --- Preflight ---------------------------------------------------------------

for tool in terraform az; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: '$tool' not found on PATH" >&2
    exit 1
  }
done

az account show >/dev/null 2>&1 || {
  echo "error: no active Azure CLI session — run 'az login' first" >&2
  exit 1
}

# Capture the resource group names while Azure state still exists, so the
# verification step at the end has something to check.
LAB_RG=""
MANAGED_RG=""
terraform -chdir="$AZURE_DIR" init -input=false >/dev/null 2>&1 || true
if terraform -chdir="$AZURE_DIR" output -raw resource_group_name >/dev/null 2>&1; then
  LAB_RG="$(terraform -chdir="$AZURE_DIR" output -raw resource_group_name)"
  MANAGED_RG="$(terraform -chdir="$AZURE_DIR" output -raw managed_resource_group_name)"
fi

# --- Confirm -----------------------------------------------------------------

if [ "$DRY_RUN" = false ] && [ "$ASSUME_YES" = false ]; then
  cat <<'WARNING'

This destroys ALL Terraform-managed lab infrastructure:

  workspace root : grants, catalog + schemas (force_destroy is ON, so the dev
                   catalog and every table in it goes with it), external
                   location, storage credential
  account root   : metastore ASSIGNMENT, lab groups, workspace permissions
  azure root     : resource group, Databricks workspace, ADLS storage account
                   and container, access connector, role assignment

The bundle-managed job and source files are not in Terraform state. Before
continuing, destroy them with:

  databricks bundle destroy -t dev

Also destroy any CD targets (prod, staging, dev-ci) that were deployed, using
their workspace and run-identity variables; see DEPLOYMENT.md.

Deleted data is not recoverable. The medallion tables are regenerable from the
notebooks; nothing else here is.

WARNING
  printf 'Type "destroy" to continue: '
  read -r reply
  if [ "$reply" != "destroy" ]; then
    echo "Aborted; nothing was changed."
    exit 1
  fi
fi

# --- Destroy, root by root ---------------------------------------------------

for dir in "${ROOTS[@]}"; do
  echo
  echo "=============================================================="
  echo "  $dir"
  echo "=============================================================="

  terraform -chdir="$dir" init -input=false >/dev/null

  if [ -z "$(terraform -chdir="$dir" state list 2>/dev/null)" ]; then
    echo "Nothing in state — skipping."
    continue
  fi

  terraform -chdir="$dir" plan -destroy -input=false -no-color -out="$PLAN_FILE"

  if [ "$DRY_RUN" = true ]; then
    echo "Dry run: destroy plan generated, not applied."
    continue
  fi

  terraform -chdir="$dir" apply -input=false -no-color "$PLAN_FILE"
done

if [ "$DRY_RUN" = true ]; then
  echo
  echo "Dry run complete. No infrastructure was changed."
  exit 0
fi

# --- Verify ------------------------------------------------------------------

echo
echo "=============================================================="
echo "  Verification"
echo "=============================================================="

if [ -n "$LAB_RG" ]; then
  echo "resource group '$LAB_RG' still exists: $(az group exists --name "$LAB_RG")"
  echo "resource group '$MANAGED_RG' still exists: $(az group exists --name "$MANAGED_RG")"
  echo "(both should print 'false')"
else
  echo "Azure state was already empty; no resource groups to check."
fi

cat <<'LEFTOVERS'

Still to check by hand — Terraform does not manage these:

  1. THE UNITY CATALOG METASTORE SURVIVES. The account root only creates a
     metastore *assignment*; the metastore itself is an input (metastore_id),
     not a Terraform resource. It is now pointing at an ADLS container this
     script just deleted. Delete it in the Databricks account console if you
     want it gone, or leave it and reuse it on the next build.
  2. Soft-deleted or orphaned Azure resources: storage accounts pending purge,
     stray public IPs or NAT gateways.
  3. Your subscription budget alert — it outlives the lab by design.
  4. Cost reporting lags 24-48h, so today's charges are not final.

Keep the local terraform.tfstate files: they are your record of what existed.

LEFTOVERS
