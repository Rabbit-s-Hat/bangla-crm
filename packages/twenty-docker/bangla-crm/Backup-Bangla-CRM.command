#!/bin/bash
# macOS: double-click in Finder. Saves a backup into the backups folder.
# (The first time, right-click the file and choose Open; see README.md.)
cd "$(dirname "$0")" || exit 1
bash bangla-crm.sh backup "$@"
status=$?
echo
read -r -p "Press Enter to close this window... " _
exit $status