#!/usr/bin/env bash
# Stub test for `bangla-crm.sh backup` (no Docker needed): a fake `docker` on PATH answers the size
# queries and copies, so the test can prove that (1) a finished backup is a plain backups/<date-time>
# folder, (2) a backup that fails halfway leaves no folder behind, (3) a stale *.partial folder from an
# interrupted run is removed, and (4) the free-space check counts the uploaded files.
# Run: bash tests/backup-stub.sh
set -uo pipefail

pkg="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$pkg/bangla-crm.sh" "$work/"
printf 'TAG=0.1.0\nPG_DATABASE_USER=postgres\n' > "$work/.env"
mkdir -p "$work/bin"
cat > "$work/bin/docker" <<'STUB'
#!/usr/bin/env bash
line="$*"
case "$line" in
  "compose version"|info) exit 0 ;;
  "compose ps"*) echo stubcontainer; exit 0 ;;
  inspect*) echo healthy; exit 0 ;;
  "compose images"*) printf 'CONTAINER REPOSITORY TAG\nx bangla-crm 0.1.0\n'; exit 0 ;;
  *" du -sk "*) printf '%s\t/app/packages/twenty-server/.local-storage\n' "${STUB_FILES_KB:-2048}"; exit 0 ;;
  *pg_database_size*) echo 1024; exit 0 ;;
  cp\ *)
    case "$2" in
      *.local-storage)
        [ "${STUB_FAIL_FILES_COPY:-0}" = 1 ] && exit 1
        mkdir -p "$3" && echo x > "$3/upload.bin" ;;
      *) echo 'PGDMP stub' > "$3" ;;
    esac
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$work/bin/docker"
export PATH="$work/bin:$PATH"

failures=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; failures=$((failures + 1)); fi; }
dirs() { find "$work/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null; }
count() { dirs | wc -l | tr -d ' '; }

echo 'Scenario 1: successful backup'
bash "$work/bangla-crm.sh" backup >/dev/null 2>&1
check 'exactly one backup folder' '[ "$(count)" = 1 ]'
d="$(dirs | head -n 1)"
check 'folder is named <date-time> (no .partial)' '[[ "$(basename "$d")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$ ]]'
for f in database.dump files/upload.bin version.txt env.txt; do
  check "contains $f" '[ -e "$d/$f" ]'
done
rm -rf "$work/backups"

echo 'Scenario 2: copying the uploaded files fails halfway'
STUB_FAIL_FILES_COPY=1 bash "$work/bangla-crm.sh" backup >/dev/null 2>&1
code=$?
check 'backup reports the failure' '[ "$code" != 0 ]'
check 'no backup folder (complete or .partial) is left behind' '[ "$(count)" = 0 ]'

echo 'Scenario 3: a stale .partial folder from an interrupted run'
mkdir -p "$work/backups/2026-01-01_000000.partial"
bash "$work/bangla-crm.sh" backup >/dev/null 2>&1
check 'stale .partial removed, new backup kept' '[ "$(count)" = 1 ] && ! dirs | grep -q partial'
rm -rf "$work/backups"

echo 'Scenario 4: uploaded files larger than the free disk space'
out="$(STUB_FILES_KB=100000000000 bash "$work/bangla-crm.sh" backup 2>&1)"
check 'free-space check counts the uploaded files' '[[ "$out" == *"Not enough free disk space"* ]]'
check 'nothing written when there is no room' '[ "$(count)" = 0 ]'

if [ "$failures" -gt 0 ]; then echo "$failures check(s) FAILED"; exit 1; fi
echo 'All backup stub checks passed (bash).'
