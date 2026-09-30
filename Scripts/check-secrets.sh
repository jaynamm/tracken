#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

case "${1:---staged}" in
  --staged) scan_args=(--pre-commit --staged) ;;
  --history) scan_args=(--log-opts=--all) ;;
  *) echo "Usage: Scripts/check-secrets.sh [--staged|--history]" >&2; exit 2 ;;
esac

if command -v gitleaks >/dev/null 2>&1; then
  scanner="$(command -v gitleaks)"
elif [[ -x "$repo_root/.local/bin/gitleaks" ]]; then
  scanner="$repo_root/.local/bin/gitleaks"
else
  echo "Secret scan requires Gitleaks. Install it with: brew install gitleaks" >&2
  exit 1
fi

exec "$scanner" git "${scan_args[@]}" --redact --no-banner --no-color "$repo_root"
