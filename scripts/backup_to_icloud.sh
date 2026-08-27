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
#
# TWO SAFETY PROPERTIES, both deliberate:
#
#   1. It never deletes at the destination. rsync --delete would mirror an
#      accidental deletion into the backup, destroying the very copy the backup
#      exists to preserve. The cost is that the destination accumulates renamed
#      and retired files, which is irrelevant at this size.
#
#   2. It never overwrites a destination file in place without keeping the old
#      one. A file truncated or corrupted at the source would otherwise
#      overwrite the good backup copy on the next run. Superseded versions go
#      to _attic/<timestamp>/ instead, which stays empty on clean runs.

set -euo pipefail

SRC="/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade"
DEST="$HOME/Library/Mobile Documents/com~apple~CloudDocs/red_trade_backup"
ATTIC="$DEST/_attic/$(date +%Y%m%d_%H%M%S)"

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

failures=0

copy_dir() {
  # $1 = path relative to the project root
  local rel
  rel="$1"
  if [ ! -d "$SRC/$rel" ]; then
    echo "  SOURCE MISSING (nothing to copy): $rel" >&2
    return 1
  fi
  mkdir -p "$DEST/$rel"
  # -rlth: recurse, keep symlinks, preserve times, human-readable sizes.
  # --no-perms/--no-owner/--no-group: iCloud does not preserve them and would
  # otherwise report an error per file.
  # --backup/--backup-dir: a file replaced at the destination is moved to the
  # attic rather than overwritten, so a truncated source cannot destroy a good
  # backup copy.
  if ! rsync -rlth --no-perms --no-owner --no-group \
       --backup --backup-dir="$ATTIC/$rel" \
       --exclude=".DS_Store" \
       "$SRC/$rel/" "$DEST/$rel/"; then
    echo "  RSYNC FAILED: $rel" >&2
    return 1
  fi
  echo "  copied: $rel"
}

copy_file() {
  local rel
  rel="$1"
  if [ ! -f "$SRC/$rel" ]; then
    echo "  SOURCE MISSING (nothing to copy): $rel" >&2
    return 1
  fi
  mkdir -p "$DEST/$(dirname "$rel")"
  if ! rsync -lth --no-perms --no-owner --no-group \
       --backup --backup-dir="$ATTIC/$(dirname "$rel")" \
       "$SRC/$rel" "$DEST/$rel"; then
    echo "  RSYNC FAILED: $rel" >&2
    return 1
  fi
  echo "  copied: $rel"
}

copy_dir  "quality_reports"             || failures=$((failures + 1))
copy_dir  "data/raw/network_caches"     || failures=$((failures + 1))
copy_file "data/folha_classificado.rds" || failures=$((failures + 1))

echo
echo "Destination now holds:"
# -A reports apparent size, so iCloud-evicted files are not counted as 0 bytes.
du -shA "$DEST" | awk '{print "  " $1 "  total"}' || echo "  (could not measure)"

# Completeness check on quality_reports/, the real payload: most of it exists
# nowhere else. Every source file must have a counterpart at the destination.
# Extra files at the destination are expected and fine — that is what retiring
# without deleting looks like.
echo
echo "Completeness check on quality_reports/:"
missing_count=0
total_count=0
# -print0 and read -d '' so that a newline inside a filename cannot split one
# path into two. Counting inside the loop, rather than walking the tree a second
# time, keeps the count consistent with what was checked and avoids a second
# pipeline that pipefail could turn into a silent exit.
while IFS= read -r -d '' f; do
  total_count=$((total_count + 1))
  rel="${f#"$SRC/"}"
  if [ ! -f "$DEST/$rel" ]; then
    missing_count=$((missing_count + 1))
    [ "$missing_count" -le 10 ] && echo "  NOT BACKED UP: $rel" >&2
  fi
done < <(find "$SRC/quality_reports" -type f ! -name ".DS_Store" -print0 2>/dev/null)

if [ "$total_count" -eq 0 ]; then
  echo "  nothing found to check (is quality_reports/ still there?)" >&2
  failures=$((failures + 1))
elif [ "$missing_count" -eq 0 ]; then
  echo "  ok: all $total_count files present at the destination"
else
  echo "  $missing_count of $total_count file(s) missing at the destination" >&2
  failures=$((failures + 1))
fi

# Byte-level check on the files that cannot be regenerated at all: the Folha
# scrape cache (the newspaper cannot be re-scraped) and its classification.
echo
echo "Integrity check on the files that cannot be regenerated:"
check_hash() {
  local rel a b
  rel="$1"
  if [ ! -f "$SRC/$rel" ]; then
    echo "  GONE FROM THE PROJECT (the backup copy is now the only one): $rel" >&2
    return 1
  fi
  if [ ! -f "$DEST/$rel" ]; then
    echo "  NOT BACKED UP: $rel" >&2
    return 1
  fi
  a=$(shasum -a 256 "$SRC/$rel"  | awk '{print $1}') || a=""
  b=$(shasum -a 256 "$DEST/$rel" | awk '{print $1}') || b=""
  if [ -z "$a" ] || [ -z "$b" ]; then
    echo "  COULD NOT HASH: $rel" >&2
    return 1
  fi
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

# The attic is empty on a clean run. Anything in it means a destination file was
# replaced — worth a look, because the superseded version may be the good one.
if [ -d "$ATTIC" ]; then
  # `|| attic_n=0` because this is a pipeline, and under pipefail a failing
  # find would otherwise end the script here, before the summary below.
  attic_n=$(find "$ATTIC" -type f 2>/dev/null | wc -l | tr -d ' ') || attic_n=0
  if [ "$attic_n" -gt 0 ]; then
    echo
    echo "  NOTE: $attic_n destination file(s) were replaced this run."
    echo "  The superseded versions are kept at: $ATTIC"
  else
    rmdir "$ATTIC" 2>/dev/null || true
    rmdir "$DEST/_attic" 2>/dev/null || true
  fi
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "Finished with $failures problem(s) above." >&2
  exit 1
fi
echo "Backup complete."
echo
echo "Note: iCloud uploads in the background. Until the upload finishes, the"
echo "copy exists only on this Mac. Check progress in Finder under iCloud Drive."
