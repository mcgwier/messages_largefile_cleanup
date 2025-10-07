#!/bin/bash
# messages_largefile_cleanup.sh
# Safely remove large (≥N MB) Messages attachments by type while keeping iCloud copies intact.
# Adds a summary by file type (count + total size) before deletion.
#
# Default: dry-run preview. Add --delete to actually remove after backup.
# Example:
#   bash messages_largefile_cleanup.sh --types "mov mp4 heic" --threshold 50 --delete
#
THRESHOLD_MB=25
BACKUP_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs/Archive/Backup_Exports/Messages_Media"
ATTACH_DIR="${HOME}/Library/Messages/Attachments"
DRY_RUN=true
DO_DELETE=false
DO_BACKUP=true
FILE_TYPES="mov mp4 heic"

set -euo pipefail
bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
warn(){ printf "\033[33m%s\033[0m\n" "$*"; }
err(){  printf "\033[31m%s\033[0m\n" "$*"; }

usage() {
cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --threshold MB      Minimum file size in MB to target (default: ${THRESHOLD_MB})
  --types "ext1 ext2" Only match given file extensions (space-separated, no dots)
  --delete            Actually delete local files after backup (asks for confirmation)
  --no-backup         Skip creating a backup (NOT RECOMMENDED)
  --help              Show this help message

Examples:
  bash $0 --threshold 50 --types "mov mp4 heic"
  bash $0 --delete --types "mov mp4" --threshold 100
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold) THRESHOLD_MB="${2:-50}"; shift 2;;
    --types) FILE_TYPES="${2:-}"; shift 2;;
    --delete) DO_DELETE=true; DRY_RUN=false; shift;;
    --no-backup) DO_BACKUP=false; shift;;
    --help|-h) usage; exit 0;;
    *) err "Unknown option: $1"; usage; exit 1;;
  esac
done

[[ -d "$ATTACH_DIR" ]] || { err "No Messages attachments found at: $ATTACH_DIR"; exit 1; }

TMP_LIST=$(mktemp)

# Build find command dynamically
FIND_CMD=(find "$ATTACH_DIR" -type f -size +"${THRESHOLD_MB}"M)
if [[ -n "$FILE_TYPES" ]]; then
  EXTS=($FILE_TYPES)
  # Build a case-insensitive extension filter
  FIND_CMD+=('(')
  first=true
  for ext in "${EXTS[@]}"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      FIND_CMD+=(-o)
    fi
    FIND_CMD+=(-iname "*.${ext}")
  done
  FIND_CMD+=(')')
fi
FIND_CMD+=(-print0)

# Run find and store newline-delimited list in TMP_LIST
"${FIND_CMD[@]}" | tr '\0' '\n' >"$TMP_LIST"

COUNT=$(grep -c . "$TMP_LIST" || true)
if [[ $COUNT -eq 0 ]]; then
  warn "No matching files found for ≥${THRESHOLD_MB} MB and types '${FILE_TYPES:-all}'."
  rm -f "$TMP_LIST"
  exit 0
fi

bold "Found $COUNT files ≥${THRESHOLD_MB} MB matching types '${FILE_TYPES:-all}'."
echo

# Preview top 10 largest
bold "Preview (10 largest):"
xargs -I{} -0 stat -f "%z\t%N" -- {} < <(tr '\n' '\0' <"$TMP_LIST") \
 | sort -nr | head -n10 | awk -F'\t' '{printf " %8.2f MiB  %s\n",$1/1048576,$2}'
echo

# Summary by file type
bold "Summary by file type:"
# Build size and count per extension using awk
TYPE_SUMMARY=$(xargs -I{} -0 stat -f "%z\t%N" -- {} < <(tr '\n' '\0' <"$TMP_LIST") | \
  awk -F'\t' '
    {
      size=$1; file=$2; ext="(none)";
      if (match(file, /\.([^.\/]+)$/)) {
        ext=tolower(substr(file, RSTART+1, RLENGTH-1));
      }
      sum[ext]+=size; cnt[ext]++;
      total+=size;
    }
    END {
      for (e in sum) {
        printf "%s\t%d\t%.2f\n", e, cnt[e], sum[e]/1048576.0;
      }
      printf "TOTAL\t%d\t%.2f\n", 0, total/1048576.0 > "/dev/stderr";
    }')

# Print sorted by size (MiB) descending
echo "$TYPE_SUMMARY" | sort -t$'\t' -k3,3nr | awk -F'\t' 'BEGIN{printf "  %-8s %8s %12s\n","EXT","COUNT","SIZE (MiB)"; printf "  %-8s %8s %12s\n","--------","--------","-----------";} {printf "  %-8s %8d %12.2f\n",$1,$2,$3}'
# Extract total from stderr of awk above (captured separately)
TOTAL_LINE=$(xargs -I{} -0 stat -f "%z\t%N" -- {} < <(tr '\n' '\0' <"$TMP_LIST") | \
  awk -F'\t' '{
      size=$1; total+=size;
    } END { printf "%.2f", total/1048576.0 }')

echo
bold "Approx total size to process: ${TOTAL_LINE} MiB"
echo

if [[ "$DRY_RUN" == true ]]; then
  warn "Dry-run only. Re-run with --delete to remove after backup."
  rm -f "$TMP_LIST"
  exit 0
fi

read -r -p "Type YES to back up${DO_DELETE:+ and delete} these files: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { warn "Aborted."; rm -f "$TMP_LIST"; exit 1; }

TS=$(date +"%Y%m%d_%H%M%S")
DEST="${BACKUP_DIR}/backup_${TS}"

if [[ "$DO_BACKUP" == true ]]; then
  mkdir -p "$DEST"
  bold "Backing up $COUNT files..."
  
  # Copy files with progress indicator
  current=0
  while IFS= read -r file; do
    ((current++))
    rel_path="${file#$ATTACH_DIR/}"
    dest_file="$DEST/$rel_path"
    filename=$(basename "$file")
    
    # Show progress
    printf "\r  [%d/%d] Copying: %-50s" "$current" "$COUNT" "${filename:0:50}"
    
    mkdir -p "$(dirname "$dest_file")"
    cp -a "$file" "$dest_file"
  done < "$TMP_LIST"
  
  printf "\n"
  bold "Backup complete → $DEST"
fi

if [[ "$DO_DELETE" == true ]]; then
  bold "Deleting originals…"
  
  # Delete files with progress indicator
  current=0
  while IFS= read -r file; do
    ((current++))
    filename=$(basename "$file")
    printf "\r  [%d/%d] Deleting: %-50s" "$current" "$COUNT" "${filename:0:50}"
    rm -f "$file"
  done < "$TMP_LIST"
  
  printf "\n"
  find "$ATTACH_DIR" -type d -empty -delete
  bold "Deletion done."
else
  warn "Files not deleted (no --delete flag)."
fi

rm -f "$TMP_LIST"
