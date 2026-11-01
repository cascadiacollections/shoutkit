#!/usr/bin/env bash
# Decide whether a push should produce a TestFlight build.
#
# Xcode Cloud is what archives Holmdel and uploads it. Its start condition
# lives in App Store Connect, not in this repo, and today it fires on every
# push to main — including Dependabot workflow bumps, docs, and the marketing
# site. ci_scripts/ci_post_clone.sh calls `gate` after clone and stops that
# run before the archive when every changed path is non-shipping. The
# App Store Connect file rule (see docs/RELEASING.md) is what keeps the run
# from starting at all; this script is the check that still works before
# that setting is changed, and the one CI can execute.
#
# A path is non-shipping only when it matches the list below. Anything else
# — app sources, Packages/ (including tests, DocC, and Package.resolved),
# the workspace, project settings, resources, entitlements, or a path this
# list does not recognize — keeps the build. Skipping an unrecognized path
# is how a new shipping tree would silently stop reaching testers.
#
#   .github/**                 Actions, Dependabot, CodeQL, CI scripts
#   docs/**                    documentation
#   site/**                    marketing site
#   ci_scripts/**              this gate
#   HolmdelApp/ci_scripts/**   the same gate beside the xcodeproj
#   *.md / *.markdown          outside the three shipping trees
#   .editorconfig .gitignore .git-blame-ignore-revs
#   .swiftformat .swiftlint.yml LICENSE
#
# Shipping trees, checked before the markdown rule so a DocC article or a
# README inside a package still builds:
#
#   HolmdelApp/**   except HolmdelApp/ci_scripts/**
#   Packages/**
#   Holmdel.xcworkspace/**
#
# `gate` exits 1 only for an Xcode Cloud branch push whose entire diff is
# non-shipping. That exit is the skip: Xcode Cloud will not archive and will
# not upload. Manual Start, Rebuild, a tag, a pull request, a schedule, and a
# commit message containing [testflight] or [ci build] all continue.

set -euo pipefail

is_non_shipping() {
  local path="${1#./}"

  case "$path" in
    .github/* | docs/* | site/* | ci_scripts/* | HolmdelApp/ci_scripts/*)
      return 0
      ;;
  esac

  # Checked after the exclusions above so the hook directory, which lives
  # inside HolmdelApp, does not count as an app change.
  case "$path" in
    HolmdelApp/* | Packages/* | Holmdel.xcworkspace/*)
      return 1
      ;;
  esac

  case "$path" in
    *.md | *.markdown | .editorconfig | .git-blame-ignore-revs | .gitignore | .swiftformat | .swiftlint.yml | LICENSE)
      return 0
      ;;
  esac

  return 1
}

# 0 = at least one shipping path, or no paths at all (build).
# 1 = every path is non-shipping (skip).
classify_paths() {
  local path saw=0
  for path in "$@"; do
    if [ -z "$path" ]; then
      continue
    fi
    saw=1
    if ! is_non_shipping "$path"; then
      return 0
    fi
  done
  if [ "$saw" -eq 0 ]; then
    return 0
  fi
  return 1
}

collect_changed_paths() {
  local status old new path
  changed_paths=()
  while IFS= read -r -d '' status; do
    case "$status" in
      R* | C*)
        IFS= read -r -d '' old || return 1
        IFS= read -r -d '' new || return 1
        changed_paths+=("$old")
        changed_paths+=("$new")
        ;;
      *)
        IFS= read -r -d '' path || return 1
        changed_paths+=("$path")
        ;;
    esac
  done < <(git diff --name-status -z -M HEAD^ HEAD)
  return 0
}

commit_requests_build() {
  local message
  message="$(git log -1 --format=%B 2>/dev/null || true)"
  if printf '%s\n' "$message" | grep -E -i -q '\[testflight\]|\[ci build\]'; then
    return 0
  fi
  return 1
}

in_xcode_cloud() {
  case "${CI_XCODE_CLOUD:-}" in
    TRUE | true | True | 1) return 0 ;;
    *) return 1 ;;
  esac
}

gate() {
  local repo
  if ! in_xcode_cloud; then
    exit 0
  fi

  repo="${CI_PRIMARY_REPOSITORY_PATH:-}"
  if [ -z "$repo" ] || [ ! -d "$repo" ]; then
    echo "TestFlight gate: no repository path; building."
    exit 0
  fi
  cd "$repo"

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "TestFlight gate: not a git checkout; building."
    exit 0
  fi

  # Manual Start and Rebuild are the force hatch. They are separate start
  # conditions from Branch Changes, so the App Store Connect file rule does
  # not apply to them either. A tag, a pull request, and a schedule are not
  # the "every merge to main" upload this gate exists to thin out.
  case "${CI_START_CONDITION:-}" in
    manual | manual_rebuild)
      echo "TestFlight gate: ${CI_START_CONDITION} start; building."
      exit 0
      ;;
    schedule | pr_open | pr_update)
      echo "TestFlight gate: ${CI_START_CONDITION} start; building."
      exit 0
      ;;
    "" | push) ;;
    *)
      echo "TestFlight gate: start condition ${CI_START_CONDITION}; building."
      exit 0
      ;;
  esac

  if [ -n "${CI_TAG:-}" ] || [ -n "${CI_PULL_REQUEST_NUMBER:-}" ]; then
    echo "TestFlight gate: tag or pull request; building."
    exit 0
  fi

  if commit_requests_build; then
    echo "TestFlight gate: commit message requested a build; building."
    exit 0
  fi

  if ! git rev-parse --verify --quiet 'HEAD^' >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 git fetch --deepen=2 >/dev/null 2>&1 || true
  fi
  if ! git rev-parse --verify --quiet 'HEAD^' >/dev/null 2>&1; then
    echo "TestFlight gate: cannot see the parent commit; building."
    exit 0
  fi

  changed_paths=()
  if ! collect_changed_paths; then
    echo "TestFlight gate: could not read the full diff; building."
    exit 0
  fi

  if [ "${#changed_paths[@]}" -eq 0 ]; then
    echo "TestFlight gate: empty diff; building."
    exit 0
  fi

  if classify_paths "${changed_paths[@]}"; then
    echo "TestFlight gate: shipping changes; building."
    exit 0
  fi

  echo "============================================================"
  echo "BUILD SKIPPED — this is not a broken archive."
  echo "Every file in this push is outside the shipped app"
  echo "(GitHub Actions, docs, the marketing site, or repo metadata)."
  echo "TestFlight will not get a new build."
  echo "Changed files:"
  printf '  %s\n' "${changed_paths[@]}"
  echo "To force an upload, start or rebuild the workflow in Xcode"
  echo "or App Store Connect, or push a commit message containing"
  echo "[testflight]."
  echo "============================================================"
  exit 1
}

classify_stdin() {
  local line
  local paths=()
  while IFS= read -r line || [ -n "$line" ]; do
    paths+=("$line")
  done
  if [ "${#paths[@]}" -eq 0 ]; then
    echo build
    exit 0
  fi
  if classify_paths "${paths[@]}"; then
    echo build
    exit 0
  fi
  echo skip
  exit 10
}

self_test() {
  local root script failures=0
  # Assertions record mismatches themselves. A gate that exits 1 is a
  # successful skip, and set -e would treat that exit as a failed test run.
  set +e
  root="$(cd "$(dirname "$0")/../.." && pwd)"
  script="$root/.github/scripts/testflight-changes.sh"

  assert_class() {
    local want="$1" label="$2" output code=0
    shift 2
    output="$(printf '%s\n' "$@" | bash "$script" --classify)" || code=$?
    if [ "$want" = "build" ]; then
      if [ "$code" -ne 0 ] || [ "$output" != "build" ]; then
        echo "FAIL: $label expected build, got status $code output [$output]" >&2
        failures=$((failures + 1))
      fi
    else
      if [ "$code" -ne 10 ] || [ "$output" != "skip" ]; then
        echo "FAIL: $label expected skip, got status $code output [$output]" >&2
        failures=$((failures + 1))
      fi
    fi
  }

  assert_class skip "CodeQL workflow bump" \
    .github/workflows/codeql.yml
  assert_class skip "actions and dependabot config" \
    .github/workflows/ci.yml \
    .github/dependabot.yml \
    .github/scripts/check-url-scheme.sh
  assert_class skip "docs only" \
    docs/RELEASING.md \
    docs/TESTFLIGHT.md
  assert_class skip "marketing site" \
    DECISIONS.md \
    site/index.html \
    site/og-image.html \
    site/og-image.png
  assert_class skip "root metadata" \
    README.md \
    CHANGELOG.md \
    CONTRIBUTING.md \
    LICENSE \
    .swiftlint.yml \
    .swiftformat \
    .gitignore \
    .editorconfig
  assert_class skip "the gate itself" \
    ci_scripts/ci_post_clone.sh \
    HolmdelApp/ci_scripts/ci_post_clone.sh \
    .github/scripts/testflight-changes.sh
  assert_class build "app source" \
    HolmdelApp/Holmdel/RootView.swift
  assert_class build "project settings" \
    HolmdelApp/Holmdel.xcodeproj/project.pbxproj
  assert_class build "xcconfig" \
    HolmdelApp/Config/Release.xcconfig
  assert_class build "entitlements" \
    HolmdelApp/Holmdel/Holmdel.entitlements
  assert_class build "resources" \
    HolmdelApp/Holmdel/Assets.xcassets/AppIcon.appiconset/AppIcon.png \
    HolmdelApp/Holmdel/Localizable.xcstrings \
    HolmdelApp/Holmdel/PrivacyInfo.xcprivacy \
    HolmdelApp/Holmdel/Info.plist
  assert_class build "package code and lockfile" \
    Packages/Playback/Sources/Playback/Playback.docc/Playback.md \
    Packages/Playback/Package.swift \
    Packages/Playback/Package.resolved \
    Holmdel.xcworkspace/xcshareddata/swiftpm/Package.resolved
  assert_class build "docs plus app code" \
    docs/RELEASING.md \
    README.md \
    HolmdelApp/Holmdel.xcodeproj/project.pbxproj \
    Packages/LiveActivity/Sources/NowPlayingActivityCore/NowPlayingActivityAttributes.swift
  assert_class build "site plus a test" \
    site/index.html \
    Packages/Playback/Tests/PlaybackTests/SleepTimerTests.swift
  assert_class build "unrecognized path" \
    scripts/new-tool.sh
  assert_class build "empty input"

  if [ ! -x "$root/ci_scripts/ci_post_clone.sh" ] || [ ! -x "$root/HolmdelApp/ci_scripts/ci_post_clone.sh" ]; then
    echo "FAIL: ci_post_clone.sh hooks must be executable" >&2
    failures=$((failures + 1))
  fi
  if ! cmp -s "$root/ci_scripts/ci_post_clone.sh" "$root/HolmdelApp/ci_scripts/ci_post_clone.sh"; then
    echo "FAIL: the two ci_post_clone.sh hooks have drifted" >&2
    failures=$((failures + 1))
  fi
  if ! grep -q 'testflight-changes.sh" gate' "$root/ci_scripts/ci_post_clone.sh"; then
    echo "FAIL: ci_post_clone.sh does not invoke the gate" >&2
    failures=$((failures + 1))
  fi

  make_repo() {
    local dir
    dir="$(mktemp -d)"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "testflight-gate@example.com"
    git -C "$dir" config user.name "TestFlight gate"
    git -C "$dir" config commit.gpgsign false
    printf '%s' "$dir"
  }

  commit_file() {
    local dir="$1" path="$2" message="$3"
    mkdir -p "$dir/$(dirname "$path")"
    printf 'x\n' >>"$dir/$path"
    git -C "$dir" add -- "$path"
    git -C "$dir" commit -q -m "$message"
  }

  run_gate() {
    local dir="$1" condition="${2:-push}"
    shift 2 || true
    (
      unset CI_TAG CI_PULL_REQUEST_NUMBER CI_START_CONDITION CI_XCODE_CLOUD
      export CI_XCODE_CLOUD=TRUE
      export CI_PRIMARY_REPOSITORY_PATH="$dir"
      export CI_START_CONDITION="$condition"
      while [ "$#" -gt 0 ]; do
        export "$1"
        shift
      done
      bash "$script" gate
    )
  }

  local repo code
  repo="$(make_repo)"
  commit_file "$repo" docs/notes.md "docs"
  commit_file "$repo" .github/workflows/codeql.yml "ci: bump codeql"
  code=0
  run_gate "$repo" push >/dev/null || code=$?
  if [ "$code" -ne 1 ]; then
    echo "FAIL: docs/workflow push should skip, got $code" >&2
    failures=$((failures + 1))
  fi

  commit_file "$repo" HolmdelApp/Holmdel/RootView.swift "app"
  code=0
  run_gate "$repo" push >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: app source push should build, got $code" >&2
    failures=$((failures + 1))
  fi

  commit_file "$repo" site/index.html "site [testflight]"
  code=0
  run_gate "$repo" push >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: [testflight] should force a build, got $code" >&2
    failures=$((failures + 1))
  fi

  commit_file "$repo" docs/again.md "docs again"
  for condition in manual manual_rebuild schedule pr_update; do
    code=0
    run_gate "$repo" "$condition" >/dev/null || code=$?
    if [ "$code" -ne 0 ]; then
      echo "FAIL: $condition should build, got $code" >&2
      failures=$((failures + 1))
    fi
  done

  code=0
  run_gate "$repo" push CI_TAG=v0.5.2 >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: a tag should build, got $code" >&2
    failures=$((failures + 1))
  fi

  code=0
  run_gate "$repo" push CI_PULL_REQUEST_NUMBER=213 >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: a pull request should build, got $code" >&2
    failures=$((failures + 1))
  fi

  code=0
  (
    unset CI_XCODE_CLOUD
    export CI_PRIMARY_REPOSITORY_PATH="$repo"
    export CI_START_CONDITION=push
    bash "$script" gate
  ) >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: a non-Xcode-Cloud run should continue, got $code" >&2
    failures=$((failures + 1))
  fi

  local renamed
  renamed="$(make_repo)"
  commit_file "$renamed" docs/moved.md "docs"
  mkdir -p "$renamed/HolmdelApp"
  git -C "$renamed" mv docs/moved.md HolmdelApp/moved.md
  git -C "$renamed" commit -q -m "move a doc into the app"
  code=0
  run_gate "$renamed" push >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: renaming into HolmdelApp should build, got $code" >&2
    failures=$((failures + 1))
  fi

  local removed
  removed="$(make_repo)"
  commit_file "$removed" HolmdelApp/Holmdel/Gone.swift "add"
  git -C "$removed" rm -q HolmdelApp/Holmdel/Gone.swift
  git -C "$removed" commit -q -m "remove a source file"
  code=0
  run_gate "$removed" push >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: deleting an app source should build, got $code" >&2
    failures=$((failures + 1))
  fi

  local root_only
  root_only="$(make_repo)"
  commit_file "$root_only" README.md "initial"
  code=0
  run_gate "$root_only" push >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: a commit with no parent should build, got $code" >&2
    failures=$((failures + 1))
  fi

  # Squash commits are the common case above. Merge commits still show up; the
  # gate diffs the first parent, which is the change the merge introduces.
  local merged
  merged="$(make_repo)"
  commit_file "$merged" README.md "readme"
  git -C "$merged" checkout -q -b feature
  commit_file "$merged" site/index.html "site on branch"
  git -C "$merged" checkout -q main
  git -C "$merged" merge -q --no-ff feature -m "Merge site-only work"
  code=0
  run_gate "$merged" push >/dev/null || code=$?
  if [ "$code" -ne 1 ]; then
    echo "FAIL: merging a site-only branch should skip, got $code" >&2
    failures=$((failures + 1))
  fi
  git -C "$merged" checkout -q -b feature-app
  commit_file "$merged" Packages/Playback/Sources/Playback/Engine.swift "engine"
  git -C "$merged" checkout -q main
  git -C "$merged" merge -q --no-ff feature-app -m "Merge app work"
  code=0
  run_gate "$merged" push >/dev/null || code=$?
  if [ "$code" -ne 0 ]; then
    echo "FAIL: merging an app change should build, got $code" >&2
    failures=$((failures + 1))
  fi

  rm -rf "$repo" "$renamed" "$removed" "$root_only" "$merged"

  if [ "$failures" -ne 0 ]; then
    echo "$failures TestFlight path rule failure(s)." >&2
    exit 1
  fi
  echo "TestFlight path rules passed."
}

changed_paths=()

case "${1:-}" in
  gate) gate ;;
  --classify) classify_stdin ;;
  --self-test) self_test ;;
  *)
    echo "usage: testflight-changes.sh gate | --classify | --self-test" >&2
    exit 2
    ;;
esac
