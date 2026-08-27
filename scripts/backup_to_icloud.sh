#!/bin/bash
# Copy the irreplaceable, un-versioned parts of this project to iCloud Drive.
#
# Why this exists: the repository is public, so quality_reports/ (internal
# reviews and referee correspondence) is deliberately gitignored, and raw data/
# is far too large to version. On 2026-08-26 two deletions destroyed the only
# in-repository copy of the Folha network cache and of cow2iso.csv; both were
# recovered by chance from directories outside the repository. Everything the
# git push protects is safe; this script covers what git deliberately does not.
#
# What it copies (about 140 MB):
#   quality_reports/           reviews, audits, plans, referee correspondence
#   data/raw/network_caches/   Folha and World Bank caches, cow2iso, ChatGPT output
#   data/folha_classificado.rds  headline classification
#
# What it deliberately skips:
#   raw data/          8.4 GB of it is the ITPD-E, public at the USITC
#   _targets/          reproducible by rerunning the pipeline
#   anything in git    already protected by the push
#
# It never deletes anything at the destination. That is the point: rsync
# --delete would mirror an accidental deletion into the backup, destroying the
# very copy the backup exists to preserve. The cost is that the destination
# accumulates renamed and retired files, which is irrelevant at this size.

set -euo pipefail

SRC="/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade"
DEST="$HOME/Library/Mobile Documents/com~apple~CloudDocs/red_trade_backup"

if [ ! -d "$SRC" ]; then
  echo "Source project not found: $SRC" >&2
  exit 1
fi

ICLOUD_ROOT="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
if [ ! -d "$ICLOUD_ROOT" ]; then
  echo "iCloud Drive is not available at: $ICLOUD_ROOT" >&2
  echo "Enable iCloud Drive in System Settings, then run this again." >&2
  exit 1
fi

mkdir -p "$DEST"

echo "Backing up to: $DEST"
echo

copy_dir() {
  # $1 = path relative to the project root
  local rel="$1"
  if [ ! -d "$SRC/$rel" ]; then
    echo "  SKIP (missing): $rel" >&2
    return 1
  fi
  mkdir -p "$DEST/$rel"
  # -a archive, -h human sizes, --no-perms/--no-owner/--no-group because iCloud
  # does not preserve them and would otherwise report an error per file
  rsync -rlth --no-perms --no-owner --no-group --exclude=".DS_Store" \
    "$SRC/$rel/" "$DEST/$rel/"
  echo "  copied: $rel"
}

copy_file() {
  local rel="$1"
  if [ ! -f "$SRC/$rel" ]; then
    echo "  SKIP (missing): $rel" >&2
    return 1
  fi
  mkdir -p "$DEST/$(dirname "$rel")"
  rsync -lth --no-perms --no-owner --no-group "$SRC/$rel" "$DEST/$rel"
  echo "  copied: $rel"
}

failures=0
copy_dir  "quality_reports"          || failures=$((failures + 1))
copy_dir  "data/raw/network_caches"  || failures=$((failures + 1))
copy_file "data/folha_classificado.rds" || failures=$((failures + 1))

echo
echo "Destination now holds:"
du -sh "$DEST" 2>/dev/null | awk '{print "  " $1 "  total"}'

# Verify the two files that cannot be regenerated at all: the Folha scrape
# cache (the newspaper cannot be re-scraped) and its classification.
echo
echo "Integrity check on the files that cannot be regenerated:"
check_hash() {
  local rel="$1"
  if [ ! -f "$SRC/$rel" ] || [ ! -f "$DEST/$rel" ]; then
    echo "  MISSING: $rel" >&2
    return 1
  fi
  local a b
  a=$(shasum -a 256 "$SRC/$rel"  | awk '{print $1}')
  b=$(shasum -a 256 "$DEST/$rel" | awk '{print $1}')
  if [ "$a" = "$b" ]; then
    echo "  ok: $rel"
  else
    echo "  HASH MISMATCH: $rel" >&2
    return 1
  fi
}

check_hash "data/raw/network_caches/folha_scrape_cache.rds" || failures=$((failures + 1))
check_hash "data/raw/network_caches/wb_data_cache.rds"      || failures=$((failures + 1))
check_hash "data/raw/network_caches/cow2iso.csv"            || failures=$((failures + 1))
check_hash "data/folha_classificado.rds"                    || failures=$((failures + 1))

echo
if [ "$failures" -ne 0 ]; then
  echo "Finished with $failures problem(s) above." >&2
  exit 1
fi
echo "Backup complete."
echo
echo "Note: iCloud uploads in the background. Until the upload finishes, the"
echo "copy exists only on this Mac. Check progress in Finder under iCloud Drive."
