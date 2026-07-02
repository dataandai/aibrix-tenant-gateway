#!/usr/bin/env bash
set -euo pipefail

>&2 echo "NOTE: kept for backwards compatibility. Spoofed routing headers are stripped and ignored; the valid request is allowed with trusted tenant-a headers."
"$(dirname "$0")/spoofed-header-ignored.sh"
