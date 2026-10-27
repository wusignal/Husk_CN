#!/bin/bash
# Build Husk's IPA on a GitHub-hosted macOS runner and copy it back here.
#
# An iOS app has to be compiled by Xcode, which only runs on macOS. This script
# turns "no Mac" into a reproducible cloud build: it pushes this checkout to a
# GitHub repository, runs .github/workflows/build-ipa.yml on a macOS runner,
# waits for it, and downloads the IPA the workflow produced.
#
#   usage: ./scripts/cloud_build.sh [repo-name] [output.ipa]
#
#   VISIBILITY=private ./scripts/cloud_build.sh husk-cn
#
# Public repositories build for free (no billed minutes); private ones are billed
# at ten times the rate, so a two-hour build uses most of a free plan's month.
#
# Needs the GitHub CLI logged in once: `gh auth login`. If github.com is not
# reachable from this network but a proxy is, it is picked up automatically, or
# set HUSK_PROXY=http://host:port.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-husk-cn-build}"
OUT="${2:-$ROOT/build/Husk.ipa}"
VISIBILITY="${VISIBILITY:-public}"
WORKFLOW="build-ipa.yml"
BRANCH="main"

say() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }
die() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

# --- network ---------------------------------------------------------------
#
# github.com is blocked on some networks while api.github.com still resolves, and
# the failure mode reads as "could not connect to server", which looks like a
# GitHub outage. A local proxy is the usual fix here, so find one.
if ! curl -sf -o /dev/null -m 8 https://github.com; then
    PROXY="${HUSK_PROXY:-}"
    if [ -z "$PROXY" ] && command -v reg >/dev/null 2>&1; then
        PROXY="$(reg query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings' 2>/dev/null \
                 | sed -n 's/.*ProxyServer[[:space:]]*REG_SZ[[:space:]]*//p' | head -1 | tr -d '\r')"
    fi
    if [ -z "$PROXY" ] && command -v scutil >/dev/null 2>&1; then
        PROXY="$(scutil --proxy | awk '/HTTPSProxy/ {p=$3} /HTTPSPort/ {print p":"$3}')"
    fi
    [ -n "$PROXY" ] || die "github.com is unreachable and no proxy was found. Set HUSK_PROXY=http://host:port."
    case "$PROXY" in http://*|https://*) ;; *) PROXY="http://$PROXY" ;; esac
    say "direct route failed; using proxy $PROXY"
    export HTTPS_PROXY="$PROXY" HTTP_PROXY="$PROXY" ALL_PROXY="$PROXY"
    echo "$PROXY" > "$ROOT/.git/husk-proxy" 2>/dev/null || true
    curl -sf -o /dev/null -m 15 https://github.com \
        || die "github.com is still unreachable through $PROXY."
fi

# --- gh --------------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
    die "the GitHub CLI is not installed: https://cli.github.com"
fi
if ! gh auth status >/dev/null 2>&1; then
    cat >&2 <<'MSG'
Not logged in to GitHub. Run this once, in a terminal:

    gh auth login

Choose GitHub.com > HTTPS > Login with a web browser, and paste the one-time
code it shows. Then run this script again.
MSG
    exit 2
fi
ACCOUNT="$(gh api user --jq .login)"
say "GitHub account: $ACCOUNT"

# --- local repository ------------------------------------------------------
cd "$ROOT"
if [ ! -d .git ]; then
    say "initialising a repository (build outputs stay ignored)"
    git init -q -b "$BRANCH"
fi
git config user.name >/dev/null 2>&1 || git config user.name "$ACCOUNT"
git config user.email >/dev/null 2>&1 || git config user.email "$ACCOUNT@users.noreply.github.com"
git add -A
if ! git diff --cached --quiet; then
    git commit -q -m "Husk: Chinese localisation, manual developer-image download"
    say "committed the working tree"
fi

REMOTE="https://github.com/$ACCOUNT/$NAME.git"
if gh repo view "$ACCOUNT/$NAME" >/dev/null 2>&1; then
    say "repository $ACCOUNT/$NAME exists; pushing to it"
    git remote get-url origin >/dev/null 2>&1 || git remote add origin "$REMOTE"
    git remote set-url origin "$REMOTE"
    git push -q -u origin "$BRANCH" --force
else
    say "creating $VISIBILITY repository $ACCOUNT/$NAME"
    gh repo create "$NAME" "--$VISIBILITY" --source=. --remote=origin --push \
        --description "Husk with a full Chinese translation"
fi

# --- run -------------------------------------------------------------------
say "starting the macOS build"
gh workflow run "$WORKFLOW" --ref "$BRANCH"
# The run does not exist the instant the dispatch returns.
RUN=""
for _ in $(seq 1 30); do
    RUN="$(gh run list --workflow "$WORKFLOW" --branch "$BRANCH" --limit 1 \
           --json databaseId,status --jq '.[0].databaseId' 2>/dev/null || true)"
    [ -n "$RUN" ] && [ "$RUN" != "null" ] && break
    sleep 4
done
[ -n "$RUN" ] || die "the workflow did not start; see https://github.com/$ACCOUNT/$NAME/actions"
say "run $RUN: https://github.com/$ACCOUNT/$NAME/actions/runs/$RUN"

STARTED="$(date +%s)"
LAST=""
while :; do
    STATE="$(gh run view "$RUN" --json status,conclusion \
             --jq '"\(.status) \(.conclusion // "")"' 2>/dev/null || echo "unknown")"
    if [ "$STATE" != "$LAST" ]; then
        printf '    %-28s %s\n' "$STATE" "$(printf '%dm%02ds' $(( ($(date +%s) - STARTED) / 60 )) $(( ($(date +%s) - STARTED) % 60 )))"
        LAST="$STATE"
    fi
    case "$STATE" in
        completed*) break ;;
    esac
    sleep 20
done

if ! gh run view "$RUN" --json conclusion --jq .conclusion | grep -qx success; then
    warn "the build failed; the last 80 lines of the failing step:"
    gh run view "$RUN" --log-failed 2>/dev/null | tail -80 >&2 || true
    die "see https://github.com/$ACCOUNT/$NAME/actions/runs/$RUN"
fi

# --- fetch -----------------------------------------------------------------
say "downloading the IPA"
DEST="$ROOT/build/cloud"
rm -rf "$DEST"; mkdir -p "$DEST"
gh run download "$RUN" -n Husk-ipa -D "$DEST"

FOUND="$(find "$DEST" -name "*.ipa" | head -1)"
[ -n "$FOUND" ] || die "the run succeeded but no IPA was in the artifact"
mkdir -p "$(dirname "$OUT")"
cp -f "$FOUND" "$OUT"
say "$OUT ($(du -h "$OUT" | cut -f1))"
if [ -d "$HOME/Desktop" ]; then
    cp -f "$FOUND" "$HOME/Desktop/Husk.ipa"
    say "$HOME/Desktop/Husk.ipa"
fi
