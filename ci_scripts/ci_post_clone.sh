#!/bin/bash
# Xcode Cloud runs this after clone. The workflow may point at the workspace
# (this copy) or at HolmdelApp/Holmdel.xcodeproj (the twin beside it). Both
# files must stay identical; .github/scripts/testflight-changes.sh holds the
# rule and is what CI executes.
set -euo pipefail

repo="${CI_PRIMARY_REPOSITORY_PATH:-}"
if [ -z "$repo" ] || [ ! -f "$repo/.github/scripts/testflight-changes.sh" ]; then
  exit 0
fi

exec /bin/bash "$repo/.github/scripts/testflight-changes.sh" gate
