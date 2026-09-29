#!/usr/bin/env bash
#
# Build the lab in dependency order: Azure, then the Databricks account root,
# then the workspace root.
#
# Each downstream root needs values that only exist once Azure has been applied
# (workspace URL, workspace ID, access connector ID, storage URL). Those are read
# from the Azure root's outputs and passed with -var, so a recreated workspace
# wires itself up correctly instead of using a stale terraform.tfvars.
#
# Usage:
#   scripts/terraform-up.sh              # confirm, then apply
#   scripts/terraform-up.sh --dry-run    # generate plans only
#   scripts/terraform-up.sh --yes        # skip the confirmation prompt
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AZURE_DIR="infrastructure/azure"
ACCOUNT_DIR="infrastructure/databricks-account"
WORKSPACE_DIR="infrastructure/databricks-workspace"

ROOTS=("$AZURE_DIR" "$ACCOUNT_DIR" "$WORKSPACE_DIR")

PLAN_FILE="autogen-up.tfplan"

ASSUME_YES=false
DRY_RUN=false

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# Plan, then apply the saved plan — the same two-step this repo uses by hand.
# Extra args are passed straight through to `plan` as -var overrides.
plan_and_apply() {
  local dir="$1"
  shift

  echo
  echo "=============================================================="
  echo "  $dir"
  echo "=============================================================="

  terraform -chdir="$dir" init -input=false >/dev/null
  terraform -chdir="$dir" plan -input=false -no-color -out="$PLAN_FILE" "$@"

  if [ "$DRY_RUN" = true ]; then
    echo "Dry run: plan generated, not applied."
    return 0
  fi

  terraform -chdir="$dir" apply -input=false -no-color "$PLAN_FILE"
}

# Warn when terraform.tfvars disagrees with what Azure actually produced. The
# script itself is safe either way because it passes -var, but a later manual
# `terraform apply` in that root would silently use the stale file.
STALE_TFVARS=false
check_tfvar() {
  local file="$1" key="$2" expected="$3" current

  current="$(
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" 2>/dev/null |
      head -1 |
      sed -E 's/^[^=]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/'
  )"

  if [ "$current" != "$expected" ]; then
    echo "  STALE  ${file}"
    echo "         ${key} in file : ${current:-<missing>}"
    echo "         actual         : ${expected}"
    STALE_TFVARS=true
  fi
}

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

for dir in "${ROOTS[@]}"; do
  [ -f "$dir/terraform.tfvars" ] || {
    echo "error: $dir/terraform.tfvars is missing — it is gitignored, so it does" >&2
    echo "       not travel with the repo and must be recreated locally." >&2
    exit 1
  }
done

# --- Confirm -----------------------------------------------------------------

if [ "$DRY_RUN" = false ] && [ "$ASSUME_YES" = false ]; then
  cat <<'WARNING'

This creates billable Azure infrastructure: a Databricks workspace, an ADLS
Gen2 storage account, and the managed resource group Databricks provisions
alongside the workspace (NAT gateway, public IP, managed storage). Those accrue
charges with no clusters running.

It does not start compute. Running the medallion job does.

WARNING
  printf 'Continue? [y/N]: '
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "Aborted; nothing was changed."; exit 1 ;;
  esac
fi

# --- 1. Azure ----------------------------------------------------------------

plan_and_apply "$AZURE_DIR"

if [ "$DRY_RUN" = true ]; then
  echo
  echo "Dry run stops here: the account and workspace roots need real Azure"
  echo "outputs (workspace URL and ID) that only exist after an apply."
  exit 0
fi

# --- Wire Azure outputs into the downstream roots ----------------------------

WORKSPACE_HOST="$(terraform -chdir="$AZURE_DIR" output -raw workspace_url)"
WORKSPACE_ID="$(terraform -chdir="$AZURE_DIR" output -raw workspace_id)"
ACCESS_CONNECTOR_ID="$(terraform -chdir="$AZURE_DIR" output -raw unity_catalog_access_connector_id)"
STORAGE_URL="$(terraform -chdir="$AZURE_DIR" output -raw unity_catalog_storage_root)"

echo
echo "Azure outputs feeding the downstream roots:"
echo "  workspace_host = $WORKSPACE_HOST"
echo "  workspace_id   = $WORKSPACE_ID"

# --- 2. Databricks account ---------------------------------------------------

plan_and_apply "$ACCOUNT_DIR" \
  -var "workspace_id=${WORKSPACE_ID}" \
  -var "workspace_host=${WORKSPACE_HOST}"

# --- 3. Databricks workspace -------------------------------------------------

plan_and_apply "$WORKSPACE_DIR" \
  -var "workspace_host=${WORKSPACE_HOST}" \
  -var "access_connector_id=${ACCESS_CONNECTOR_ID}" \
  -var "storage_url=${STORAGE_URL}"

# --- Report ------------------------------------------------------------------

echo
echo "=============================================================="
echo "  Done"
echo "=============================================================="
echo "Workspace: $WORKSPACE_HOST"
echo

echo "Checking terraform.tfvars against the live Azure outputs:"
check_tfvar "$ACCOUNT_DIR/terraform.tfvars" "workspace_id" "$WORKSPACE_ID"
check_tfvar "$ACCOUNT_DIR/terraform.tfvars" "workspace_host" "$WORKSPACE_HOST"
check_tfvar "$WORKSPACE_DIR/terraform.tfvars" "workspace_host" "$WORKSPACE_HOST"
check_tfvar "$WORKSPACE_DIR/terraform.tfvars" "access_connector_id" "$ACCESS_CONNECTOR_ID"
check_tfvar "$WORKSPACE_DIR/terraform.tfvars" "storage_url" "$STORAGE_URL"

if [ "$STALE_TFVARS" = true ]; then
  cat <<'STALE'

  ^ Update those files before running terraform by hand in those roots. This
    script passed the correct values with -var, but a bare `terraform apply`
    would read the stale file and try to revert them.
STALE
else
  echo "  All current."
fi

cat <<'NEXT'

Next:
  - The metastore must be assigned before the catalog works. That assignment is
    the account root's job and has just run; confirm with:
      databricks metastores current
  - Terraform creates the platform only. Validate and deploy the workload with:
      databricks bundle validate -t dev
      databricks bundle deploy -t dev
  - Tear down with scripts/terraform-down.sh when you are finished.

NEXT
