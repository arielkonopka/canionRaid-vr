#!/usr/bin/env bash
# Pomiar bazowy na Queście (plan wydajności, etap 0): kolejne przejazdy
# porównawcze. Dla każdego wpisu: bench.cfg do danych gry (adb run-as),
# start gry, log gry i VrApi przez czas przejazdu, wynik do pliku.
#   tools/bench_quest.sh WYNIKI.txt "S1:130:" "S1:160:" "S1:130:mirror" ...
# Wpis: scenariusz:rozdzielczość:wyłączone (po przecinku).
# Gogle: adb (Wi-Fi albo kabel), "./quest.sh awake" (nie usypiają zdjęte),
# leżą nieruchomo. Czas przejazdu: BENCH_TIME (domyślnie 75 s).
set -uo pipefail
cd "$(dirname "$0")/.."
ADB="${ANDROID_HOME:-$HOME/opt/android-sdk}/platform-tools/adb"
PKG=com.stunttrackvr.game
OUT="$1"; shift
T="${BENCH_TIME:-75}"
: > "$OUT"
act=$("$ADB" shell cmd package resolve-activity --brief "$PKG" | tail -1 | tr -d '\r')
for spec in "$@"; do
	IFS=: read -r sc res ab <<<"$spec"
	echo "== $sc ${res}% wyłączone=[${ab}]" | tee -a "$OUT"
	# Plik lokalnie -> /data/local/tmp -> dane gry (run-as); cudzysłowy
	# ConfigFile rozbijały cytowanie w "adb shell".
	tmp=$(mktemp)
	printf '[bench]\nscenario="%s"\ntime=%s\nseed=4242\nres=%s\nab="%s"\n' "$sc" "$T" "$res" "$ab" > "$tmp"
	"$ADB" shell am force-stop "$PKG"
	"$ADB" push "$tmp" /data/local/tmp/bench.cfg >/dev/null
	rm -f "$tmp"
	"$ADB" shell run-as "$PKG" cp /data/local/tmp/bench.cfg files/bench.cfg
	"$ADB" logcat -c
	"$ADB" shell am start -n "$act" >/dev/null
	# Czas przejazdu + wczytanie; gra sama kończy się po "BENCH END".
	for ((i = 0; i < T + 40; i++)); do
		sleep 1
		"$ADB" logcat -d -s godot 2>/dev/null | grep -q "BENCH END" && break
	done
	"$ADB" logcat -d -s godot 2>/dev/null | grep -E "BENCH|PERF" | sed 's/^.*godot[^:]*: //' >> "$OUT"
	# VrApi: średnie z linii w trakcie przejazdu (po "BENCH START").
	# Tylko linie procesu gry (pid z logu godot), ostatnie T sekund.
	pid=$("$ADB" shell pidof "$PKG" | tr -d '\r')
	"$ADB" logcat -d -s VrApi 2>/dev/null | { [[ -n $pid ]] && grep " $pid " || cat; } | tail -n "$T" |
		sed -E 's/.*FPS=([0-9]+)\/[0-9]+.*,Stale=([0-9]+),.*,App=([0-9.]+)ms.*/\1 \2 \3/' | grep -E '^[0-9]+ [0-9]+ [0-9.]+$' |
		awk '{f+=$1; s+=$2; a+=$3; n++} END{if(n) printf "VRAPI: śr. FPS %.1f, Stale/s %.1f, App GPU %.1f ms (%d s)\n", f/n, s/n, a/n, n}' >> "$OUT"
	"$ADB" logcat -d -s VrApi 2>/dev/null | tail -2 | sed 's/^.*VrApi *: /VRAPI-ostatnia: /' >> "$OUT"
	"$ADB" shell am force-stop "$PKG"
	sleep 5
done
"$ADB" shell "run-as $PKG rm -f files/bench.cfg"
echo "gotowe: $OUT"
