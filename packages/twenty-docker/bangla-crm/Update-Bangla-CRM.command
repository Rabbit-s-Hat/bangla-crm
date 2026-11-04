#!/bin/bash
# macOS: double-click in Finder. Updates BanglaCRM to the newest release (a backup is made first).
# (The first time, right-click the file and choose Open; see README.md.)
cd "$(dirname "$0")" || exit 1
bash bangla-crm.sh update "$@"
status=$?
echo
read -r -p "Press Enter to close this window... " _
exit $status