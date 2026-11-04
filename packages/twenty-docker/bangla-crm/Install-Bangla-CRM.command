#!/bin/bash
# macOS: double-click in Finder. Installs BanglaCRM on this Mac (needs Docker Desktop) and opens it in the browser.
# (The first time, right-click the file and choose Open; see README.md.)
cd "$(dirname "$0")" || exit 1
bash install.sh "$@"
status=$?
echo
read -r -p "Press Enter to close this window... " _
exit $status