#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws eksctl kubectl docker curl helm
aws sts get-caller-identity >/dev/null
cat <<'MSG'
DANGER ZONE prerequisites ok.
You explicitly accepted GPU cost/quota risk.
MSG
