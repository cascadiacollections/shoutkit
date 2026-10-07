#!/usr/bin/env bash
# Share one formatter version between CI and the manual Reformat workflow.
set -euo pipefail

version="0.63.1"
install_dir="${RUNNER_TEMP:?}/swiftformat-${version}"
mkdir -p "${install_dir}"
curl -fsSL "https://github.com/nicklockwood/SwiftFormat/releases/download/${version}/swiftformat.zip" \
    -o "${install_dir}/swiftformat.zip"
unzip -oq "${install_dir}/swiftformat.zip" -d "${install_dir}"
chmod +x "${install_dir}/swiftformat"
"${install_dir}/swiftformat" --version
echo "${install_dir}" >> "${GITHUB_PATH:?}"
