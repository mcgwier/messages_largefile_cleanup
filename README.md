# Messages Large File Cleanup

A safe utility to free up disk space by removing very large iMessage attachments from your Mac **without deleting them from iCloud**. Designed for use when **Messages in iCloud** is enabled so files remain accessible from iCloud and other devices while local copies are removed.

## Requirements
- macOS with the Messages app.
- Messages in iCloud enabled and fully synced:
  - Mac: Messages → Settings → iMessage → Enable “Messages in iCloud”
  - iPhone: Settings → [your name] → iCloud → Messages
- `rsync` available on your Mac (`which rsync`). If missing, install via Homebrew: `brew install rsync`.

## Quick Start
1. Make the script executable:
   ```bash
   chmod +x messages_largefile_cleanup.sh
   ```
2. Preview what would be removed (safe dry run):
   ```bash
   bash messages_largefile_cleanup.sh --types "mov mp4 heic"
   ```
3. Backup and delete local copies after confirmation:
   ```bash
   bash messages_largefile_cleanup.sh --types "mov mp4 heic" --threshold 75 --delete
   ```

## Options
```
--threshold MB       Minimum file size to target (default: 50)
--types "ext ext"    Space-separated file extensions to include (no dots). Example: "mov mp4 heic jpg"
--delete             After backup, delete the matching local files (prompts for YES)
--no-backup          Skip backup (not recommended)
--help               Show usage
```
Targets only files inside: `~/Library/Messages/Attachments`

## What the Script Does
1. Finds attachments in `~/Library/Messages/Attachments` that are at least the threshold size and match any specified types.
2. Shows a preview of the ten largest files and a **summary by file type** (count and MiB).
3. Performs a **local backup** of all targeted files to a timestamped folder:
   - `~/MessagesAttachmentsBackups_LargeFiles/backup_YYYYMMDD_HHMMSS/`
4. After you type `YES`, removes the local copies and prunes now-empty directories.

## Data Safety
- **Dry-run default:** Nothing is deleted unless you add `--delete`.
- **Local backup first:** Files are copied to a dedicated backup directory before any deletion.
- **Explicit confirmation:** You must type `YES` before deletion occurs.
- **Scoped to media cache:** Only touches `~/Library/Messages/Attachments`; it does not modify your message database or chat history.
- **iCloud continuity:** With Messages in iCloud enabled, attachments remain in iCloud and can re-download on demand.

## Restoring Files
To restore any items back to your local attachments cache:
```bash
rsync -a ~/MessagesAttachmentsBackups_LargeFiles/backup_YYYYMMDD_HHMMSS/ ~/Library/Messages/Attachments/
```
You can also copy individual files from the backup back into the corresponding subfolders.

## Examples
- Preview `.mov` and `.mp4` files over 100 MB:
  ```bash
  bash messages_largefile_cleanup.sh --types "mov mp4" --threshold 100
  ```
- Backup and delete large image files:
  ```bash
  bash messages_largefile_cleanup.sh --types "heic jpg png" --delete
  ```

## Notes
- Best used when iCloud Messages has finished syncing.
- If you disable Messages in iCloud, removing local attachments may remove your only copy.
- Backups are local to your Mac; keep them on external storage if you are very low on disk space.
