#!/bin/bash
# macOS: double-click in Finder. Restores a backup: lists the backups, newest first, and asks which one.
# (The first time, right-click the file and choose Open; see README.md.)
cd "$(dirname "$0")" || exit 1
list=()
for d in backups/20*_*; do
  [ -d "$d" ] || continue
  case "$d" in *.partial) continue ;; esac
  list=("$d" "${list[@]}")
done
if [ "${#list[@]}" -eq 0 ]; then
  echo "No backups found in the backups folder."
  status=1
else
  echo "Available backups (newest first):"
  i=1
  for d in "${list[@]}"; do echo "  $i) ${d#backups/}"; i=$((i + 1)); done
  read -r -p "Number of the backup to restore (Enter = cancel): " n
  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#list[@]}" ]; then
    bash bangla-crm.sh restore "${list[$((n - 1))]}"
    status=$?
  else
    echo "Cancelled."
    status=0
  fi
fi
echo
read -r -p "Press Enter to close this window... " _
exit $status