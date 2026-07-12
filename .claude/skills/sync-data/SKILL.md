# sync-data

Copy the app's Core Data SQLite files from a connected device or running
simulator into `.database/` at the project root for local inspection.

## Invocation

```
/sync-data           # auto-detect: device first, then simulator
/sync-data device    # force real device
/sync-data simulator # force simulator
```

## Steps

### 1. Resolve target (device or simulator)

**Device:**
```bash
xcrun devicectl list devices
```
Pick the first `connected` entry. If none → fall back to simulator.

**Simulator:**
```bash
xcrun simctl list devices | grep Booted | head -1
```
Get the booted simulator UUID.

### 2. Find the bundle ID

```bash
# always com.semibold.semibold unless project.yml says otherwise
grep -E "PRODUCT_BUNDLE_IDENTIFIER" semibold.xcodeproj/project.pbxproj | head -1
```

### 3. Determine DB mode (local vs iCloud)

Read the print log or check which file exists. Default: try `cloud.sqlite`
first, fall back to `local.sqlite`.

### 4. Copy files to `.database/`

**Device** — copy main + WAL + SHM for each store:
```bash
for ext in "" "-wal" "-shm"; do
  xcrun devicectl device copy from \
    --device <udid> \
    --domain-type appDataContainer \
    --domain-identifier <bundle-id> \
    --source "Library/Application Support/cloud.sqlite${ext}" \
    --destination .database/cloud.sqlite${ext}
done
```
Repeat for `local.sqlite` if `cloud.sqlite` is absent or empty.

**Simulator:**
```bash
DB_DIR=$(xcrun simctl get_app_container booted <bundle-id> data)/Library/Application\ Support
cp "$DB_DIR/cloud.sqlite"     .database/cloud.sqlite     2>/dev/null
cp "$DB_DIR/cloud.sqlite-wal" .database/cloud.sqlite-wal 2>/dev/null
cp "$DB_DIR/cloud.sqlite-shm" .database/cloud.sqlite-shm 2>/dev/null
cp "$DB_DIR/local.sqlite"     .database/local.sqlite     2>/dev/null
cp "$DB_DIR/local.sqlite-wal" .database/local.sqlite-wal 2>/dev/null
cp "$DB_DIR/local.sqlite-shm" .database/local.sqlite-shm 2>/dev/null
```

### 5. Report

```
✅ [SYNC] .database/cloud.sqlite (+ wal, shm) — device 이진혁의 iPhone
   Tables: ZFOLDER, ZDOCUMENT, ZDOCUMENTBLOCK
   ZFOLDER rows: N
```

Run a quick row count per table so the user can confirm data is present:
```bash
sqlite3 .database/cloud.sqlite "
  SELECT 'ZFOLDER', count(*) FROM ZFOLDER UNION ALL
  SELECT 'ZDOCUMENT', count(*) FROM ZDOCUMENT UNION ALL
  SELECT 'ZDOCUMENTBLOCK', count(*) FROM ZDOCUMENTBLOCK;
"
```

## Notes

- `.database/` is git-ignored — never committed.
- WAL + SHM files must be in the same directory as the `.sqlite` file for
  sqlite3 / DB Browser to read current (un-checkpointed) data.
- If the app is actively running during copy, data may be in the WAL.
  Close or background the app for a clean checkpoint before copying.
