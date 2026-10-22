#!/bin/bash
# Qualitätssicherung für StudyApp – dieselben Prüfungen lokal und in der CI.
#
#   scripts/qa.sh                 # lint + test (vor jedem Push sinnvoll)
#   scripts/qa.sh lint [--fix]    # SwiftLint (streng: jede Warnung ist ein Fehler)
#   scripts/qa.sh build           # Release-Build ohne Signatur
#   scripts/qa.sh test            # Unit-Tests (StudyAppTests)
#   scripts/qa.sh release-check   # Voraussetzungen für scripts/release.sh prüfen
#   scripts/qa.sh commit-msg <datei|text>  # Conventional-Commit-Nachricht prüfen
#   scripts/qa.sh hooks           # Git-Hooks aus .githooks/ aktivieren
#
# Option --ci: GitHub-Actions-Ausgabe (Anmerkungen direkt im PR).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SWIFTLINT_VERSION="0.59.1"
RESULTS="$ROOT/build/qa"
CI=false
for arg in "$@"; do [[ "$arg" == "--ci" ]] && CI=true; done
COMMAND="${1:-all}"
[[ "$COMMAND" == "--ci" ]] && COMMAND="all"

# Signatur aus: Die CI hat kein Entwicklerzertifikat, lokal soll kein Team nötig sein.
UNSIGNED=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# xcodebuild-Ausgabe lesbar machen, falls xcbeautify installiert ist (auf GitHub-Runnern vorhanden).
pretty() {
    if command -v xcbeautify >/dev/null; then
        if $CI; then xcbeautify --renderer github-actions; else xcbeautify; fi
    else
        cat
    fi
}

lint() {
    step "SwiftLint"
    local args=(lint --strict --quiet)
    [[ "${2:-}" == "--fix" ]] && args=(lint --fix --quiet)
    $CI && args+=(--reporter github-actions-logging)
    if command -v swiftlint >/dev/null; then
        swiftlint "${args[@]}"
    elif command -v docker >/dev/null; then
        docker run --rm -v "$ROOT:/work" -w /work "ghcr.io/realm/swiftlint:$SWIFTLINT_VERSION" swiftlint "${args[@]}"
    else
        fail "SwiftLint fehlt. Installieren mit: brew install swiftlint"
    fi
    ok "SwiftLint ohne Befund"
}

build() {
    step "Release-Build"
    xcodebuild build \
        -project StudyApp.xcodeproj -scheme StudyApp -configuration Release \
        -destination "generic/platform=macOS" \
        -clonedSourcePackagesDirPath "$ROOT/.spm" \
        "${UNSIGNED[@]}" | pretty
    ok "Build erfolgreich"
}

run_tests() {
    step "Unit-Tests"
    rm -rf "$RESULTS/Tests.xcresult"
    mkdir -p "$RESULTS"
    # UI-Tests brauchen Bedienungshilfen-Rechte, die es auf CI-Runnern nicht gibt.
    if ! xcodebuild test \
        -project StudyApp.xcodeproj -scheme StudyApp \
        -destination "platform=macOS,arch=$(uname -m)" \
        -skip-testing:StudyAppUITests \
        -clonedSourcePackagesDirPath "$ROOT/.spm" \
        -resultBundlePath "$RESULTS/Tests.xcresult" \
        "${UNSIGNED[@]}" | pretty; then
        test_failures
        fail "Tests fehlgeschlagen (Details: build/qa/Tests.xcresult)"
    fi
    ok "Alle Tests bestanden (Ergebnis: build/qa/Tests.xcresult)"
}

# Fehlermeldungen der fehlgeschlagenen Tests mit Datei und Zeile – die xcodebuild-Ausgabe nennt nur die Namen.
test_failures() {
    [[ -d "$RESULTS/Tests.xcresult" ]] || return 0
    xcrun xcresulttool get test-results summary --path "$RESULTS/Tests.xcresult" 2>/dev/null | python3 -c '
import json, os, sys
try:
    failures = json.load(sys.stdin).get("testFailures", [])
except ValueError:
    sys.exit(0)
ci = os.environ.get("GITHUB_ACTIONS") == "true"
for failure in failures:
    name, text = failure.get("testName", "?"), failure.get("failureText", "").strip()
    print(f"::error title={name}::{text}" if ci else f"✗ {name}: {text}")
' || true
}

release_check() {
    step "Release-Voraussetzungen"
    local plist="Config/Info.plist" problems=0
    check() { if eval "$2"; then ok "$1"; else printf '\033[1;31m✗ %s\033[0m\n' "$1"; problems=$((problems + 1)); fi; }
    check "Öffentlicher Sparkle-Schlüssel eingetragen" \
        "grep -A1 SUPublicEDKey '$plist' | grep -q '<string>[A-Za-z0-9+/=]\{40,\}</string>'"
    check "Update-Feed zeigt auf GitHub Pages" "grep -q 'github.io/StudyApp/appcast.xml' '$plist'"
    check "Entitlement für ad-hoc-signiertes Sparkle vorhanden" \
        "grep -q 'com.apple.security.cs.disable-library-validation' Config/StudyApp.entitlements"
    check "docs/appcast.xml ist gültiges XML" "python3 -c 'import sys,xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' docs/appcast.xml"
    check "Package.resolved versioniert (feste Sparkle-Version)" \
        "git ls-files --error-unmatch StudyApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved >/dev/null 2>&1"
    local latest
    latest="$(ls docs/release-notes/*.md 2>/dev/null | sed 's|.*/||; s|\.md$||' | sort -t. -k1,1n -k2,2n | tail -1)"
    check "Release-Notizen vorhanden (neueste: ${latest:-keine})" "[[ -n '$latest' ]]"
    ((problems == 0)) || fail "$problems Voraussetzung(en) fehlen"
}

# Conventional Commits wie in commitlint.config.mjs: typ(bereich)!: beschreibung
commit_msg() {
    local input="${2:-}"
    [[ -n "$input" ]] || fail "Aufruf: scripts/qa.sh commit-msg <datei|text>"
    local header
    if [[ -f "$input" ]]; then header="$(grep -v '^#' "$input" | head -1)"; else header="$(printf '%s' "$input" | head -1)"; fi
    # Merge- und Revert-Nachrichten von Git bleiben unangetastet.
    [[ "$header" =~ ^(Merge|Revert\ \") ]] && return 0
    local pattern='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: [^ ].*$'
    if ! [[ "$header" =~ $pattern ]]; then
        printf '\033[1;31m✗ Keine Conventional-Commit-Nachricht:\033[0m %s\n' "$header" >&2
        printf '  Format: typ(bereich): beschreibung   z. B. „feat(studip): add file downloads“\n' >&2
        printf '  Typen:  feat fix docs style refactor perf test build ci chore revert\n' >&2
        exit 1
    fi
    ((${#header} <= 100)) || fail "Kopfzeile ist ${#header} Zeichen lang (höchstens 100)."
    ok "Commit-Nachricht passt"
}

hooks() {
    step "Git-Hooks"
    chmod +x .githooks/*
    git config core.hooksPath .githooks
    ok "Hooks aktiv: commit-msg (Conventional Commits), pre-commit (SwiftLint), pre-push (SwiftLint)"
}

case "$COMMAND" in
    lint) lint "$@" ;;
    build) build ;;
    test) run_tests ;;
    release-check) release_check ;;
    commit-msg) commit_msg "$@" ;;
    hooks) hooks ;;
    all) lint; run_tests ;;
    -h|--help|help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) fail "Unbekannter Befehl „$COMMAND“. Hilfe: scripts/qa.sh help" ;;
esac
