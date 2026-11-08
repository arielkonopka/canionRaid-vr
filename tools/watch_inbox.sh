#!/bin/sh
# Nasłuch skrzynki od wątków w chmurze: co INTERVAL s pobiera wszystkie
# gałęzie z GitHuba i kończy się (kod 0), gdy pojawi się nowy commit
# zmieniający docs/agent/ na którejkolwiek gałęzi zdalnej. Wypisuje te
# commity. Agent lokalny uruchamia go w tle i po powiadomieniu - po
# przeczytaniu wiadomości - uruchamia ponownie.
#   tools/watch_inbox.sh [INTERVAL_S]
INTERVAL="${1:-120}"
cd "$(dirname "$0")/.." || exit 1
snapshot() { git for-each-ref --format='%(objectname)' refs/remotes/origin | sort | tr '\n' ' '; }
git fetch --all --quiet 2>/dev/null
BEFORE="$(snapshot)"
BASE_REFS="$(git for-each-ref --format='%(refname)' refs/remotes/origin)"
OLD=""
for r in $BASE_REFS; do OLD="$OLD $(git rev-parse "$r")"; done
while true; do
	sleep "$INTERVAL"
	git fetch --all --quiet 2>/dev/null || continue
	NOW="$(snapshot)"
	[ "$NOW" = "$BEFORE" ] && continue
	FOUND=""
	for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do
		# Commity nowe względem stanu z początku nasłuchu.
		EXCL=""
		for o in $OLD; do EXCL="$EXCL ^$o"; done
		C="$(git log --format='%h %s' "$r" $EXCL -- docs/agent 2>/dev/null)"
		[ -n "$C" ] && FOUND="$FOUND
== ${r#refs/remotes/}:
$C"
	done
	if [ -n "$FOUND" ]; then
		echo "NOWA WIADOMOŚĆ W SKRZYNCE:$FOUND"
		exit 0
	fi
	BEFORE="$NOW"
done
