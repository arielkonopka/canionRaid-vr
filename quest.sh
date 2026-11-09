#!/usr/bin/env bash
# Canion Raid VR - Copyright (C) 2026 Ariel Konopka, GPL-3.0-or-later.
#
# Budowanie i wgrywanie gry na Meta Questa 3. Jedno polecenie na wszystko.
#
#   ./quest.sh            zbuduj APK, wgraj na gogle i uruchom (domyślnie)
#   ./quest.sh all        testy + build + wgranie + uruchomienie
#   ./quest.sh build      tylko zbuduj APK (build/stunt-track-vr.apk)
#   ./quest.sh install    wgraj już zbudowany APK i uruchom
#   ./quest.sh test       tylko testy headless (bez gogli)
#   ./quest.sh log        logi gry z gogli na żywo (Ctrl+C kończy)
#   ./quest.sh stop       zatrzymaj grę na goglach
#   ./quest.sh awake      gogle nie usypiają zdjęte z głowy (czujnik "na głowie"
#                         wymuszony; zużywa baterię) - wygodne przy wgrywaniu
#   ./quest.sh sleep      przywraca normalny czujnik
#   ./quest.sh wifi       adb przez Wi-Fi: raz z kablem, potem bez kabla
#                         (do restartu gogli; adres w build/.quest_wifi)
#
# Gogle: kabel USB, tryb dewelopera włączony, debugowanie USB zatwierdzone
# w goglach. Jeśli gogle czekają na zgodę, skrypt mówi o tym i czeka.
#
# Wszystko lokalnie, nic nie jest pobierane: Android SDK w $ANDROID_HOME
# albo ~/opt/android-sdk, JDK i keystore z ustawień edytora Godota,
# cache Gradle w ~/.gradle, wtyczka addons/godotopenxrvendors.
set -euo pipefail
cd "$(dirname "$0")"

SDK="${ANDROID_HOME:-$HOME/opt/android-sdk}"
# Zawsze adb z SDK (wersja 37). W systemie jest też /usr/bin/adb (34) -
# mieszanie wersji restartuje serwer adb, co zrywa połączenie z goglami
# i kasuje okno zgody na debugowanie, zanim gracz zdąży je zatwierdzić.
ADB="$SDK/platform-tools/adb"
PKG=com.stunttrackvr.game
APK=build/stunt-track-vr.apk
WAIT_S=300          # jak długo czekać na podłączenie / zgodę gogli

say()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m OK\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mBŁĄD\033[0m %s\n' "$*" >&2; exit 1; }

# Godot bez okna. --xr-mode off: bez runtime'u OpenXR na PC Godot
# zawiesza się przy wyjściu; </dev/null: błąd skryptu nie wpuści go
# w interaktywny debugger.
godot_cli() { godot --headless --xr-mode off "$@" </dev/null; }

do_import() {
	say "Import zasobów"
	local out
	out=$(godot_cli --import 2>&1) || true
	if grep -qE "SCRIPT ERROR|Parse Error" <<<"$out"; then
		grep -E "SCRIPT ERROR|Parse Error|at: " <<<"$out" | head -20
		fail "błędy w skryptach - popraw przed buildem"
	fi
	ok "import"
	# Import nie kompiluje wszystkich skryptów - błąd składni w skrypcie
	# sceny przeszedłby do APK. Sprawdzamy każdy osobno.
	say "Kompilacja skryptów"
	local f bad=0
	for f in scripts/*.gd; do
		# --check-only nie zna autoloadów - "Identifier not found: GameSettings"
		# to fałszywy alarm.
		out=$(godot_cli --check-only -s "res://$f" 2>&1 | grep -E "Parse Error|Compile Error" \
				| grep -v "Identifier not found: GameSettings") || true
		if [[ -n "$out" ]]; then
			echo "  $f:"
			head -5 <<<"$out" | sed 's/^/    /'
			bad=1
		fi
	done
	[[ $bad == 0 ]] || fail "błędy kompilacji skryptów"
	ok "skrypty"
}

do_test() {
	do_import
	local failed=0
	# test: nazwa, argumenty, linie wyniku do pokazania
	run_test() {
		local name=$1 args=$2 pattern=$3 out
		say "Test: $name $args"
		out=$(timeout 300 godot --headless --xr-mode off -s "res://tests/$name.gd" -- $args </dev/null 2>&1) || true
		# Błąd skryptu albo test zgłaszający porażkę ("..._test: BŁĄD").
		if grep -qE "SCRIPT ERROR|Parse Error|_test: BŁĄD" <<<"$out"; then
			grep -E "SCRIPT ERROR|Parse Error|at: |BŁĄD" <<<"$out" | head -10
			printf '\033[1;31m  NIE PRZESZEDŁ\033[0m\n'
			failed=1
		else
			# Brak dopasowania nie jest błędem testu (pipefail zabiłby skrypt).
			grep -E "$pattern" <<<"$out" | sed 's/^/    /' || true
		fi
	}
	run_test drive_test  "95 sport auto" "RESPAWN|META|stanęło|wgniecenia|systemy"
	run_test assist_test "wet"           "WŁ|WYŁ"
	run_test engine_test ""              "180 kW"
	run_test dent_test   ""              "wgnieceń|czas"
	run_test title_test  ""              "auto:"
	run_test generator_test "777"        "Section|skok"
	run_test track_height_test ""        "najniższa|track_height_test|za nisko"
	run_test reverse_test ""             "^t="
	run_test respawn_test ""             "max obrót"
	run_test service_test ""             "station|workshop"
	run_test endless_test "180 petrol 777 150" "upadek|KONIEC|LIMIT"
	run_test highway_test ""             "spadek|highway_test"
	run_test score_test ""               "score_test|pkt"
	run_test score_play_test ""          "score_play_test"
	run_test stunt_shop_test ""          "stunt_shop_test"
	run_test radio_test ""               "radio_test"
	run_test hill_test ""                "wzniesienie|hill_test"
	run_test fuel_test ""                "paliwo skończyło|fuel_test"
	[[ $failed == 0 ]] || fail "któryś test się wysypał"
	ok "testy"
}

do_build() {
	do_import
	say "Build APK (Quest 3, debug)"
	mkdir -p build
	rm -f "$APK"
	local args=(--headless --path . --export-debug Quest "$APK")
	# Szablon buildu gradle'owego instaluje się przy pierwszym eksporcie.
	[[ -d android/build ]] || args=(--install-android-build-template "${args[@]}")
	local out
	out=$(godot "${args[@]}" </dev/null 2>&1) || true
	grep -E "^ERROR" <<<"$out" | grep -v "cannot connect to daemon" | head -10 || true
	[[ -f "$APK" ]] || { echo "$out" | tail -30; fail "eksport się nie udał"; }
	ok "$APK ($(du -h "$APK" | cut -f1))"
}

# adb przez Wi-Fi: adres gogli zapisany przez "./quest.sh wifi".
WIFI_FILE="build/.quest_wifi"

# Czeka, aż gogle będą podłączone i zatwierdzone. Gdy jest zapisany adres
# Wi-Fi, łączy się przez sieć; przy kilku urządzeniach (kabel + Wi-Fi to
# te same gogle widziane dwa razy) wybiera jedno przez ANDROID_SERIAL.
wait_device() {
	"$ADB" start-server >/dev/null 2>&1 || true
	local said="" st serial
	for ((i = 0; i < WAIT_S; i++)); do
		if [[ -f "$WIFI_FILE" ]] && ! "$ADB" devices | grep -q "^$(cat "$WIFI_FILE")"; then
			"$ADB" connect "$(cat "$WIFI_FILE")" >/dev/null 2>&1 || true
		fi
		# Najpierw Wi-Fi (adres z dwukropkiem), potem kabel.
		serial=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}' | grep ':' | head -1 || true)
		[[ -n $serial ]] || serial=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')
		st=$("$ADB" devices | awk 'NR>1 && NF {print $2; exit}')
		[[ -n $serial ]] && st=device
		case "$st" in
			device) export ANDROID_SERIAL="$serial"; ok "gogle: $serial"; return 0 ;;
			unauthorized)
				[[ $said == u ]] || say "Gogle czekają na zgodę: załóż je i zatwierdź debugowanie USB (\"Zawsze zezwalaj\")."
				said=u ;;
			*)
				[[ $said == n ]] || say "Nie widzę gogli. Podłącz Questa kablem USB (tryb dewelopera włączony)."
				said=n ;;
		esac
		sleep 1
	done
	fail "gogle niedostępne po ${WAIT_S} s"
}

do_install() {
	[[ -f "$APK" ]] || fail "brak $APK - najpierw ./quest.sh build"
	wait_device
	say "Wgrywanie na gogle"
	"$ADB" install -r "$APK" >/dev/null
	ok "zainstalowano $PKG"
	say "Uruchamianie"
	"$ADB" shell am force-stop "$PKG" || true
	local act
	act=$("$ADB" shell cmd package resolve-activity --brief "$PKG" | tail -1 | tr -d '\r')
	"$ADB" shell am start -n "$act" >/dev/null
	ok "gra wystartowała - załóż gogle. Logi: ./quest.sh log"
}

case "${1:-}" in
	"")      do_build; do_install ;;
	all)     do_test; do_build; do_install ;;
	build)   do_build ;;
	install) do_install ;;
	test)    do_test ;;
	log)     wait_device; exec "$ADB" logcat -s godot ;;
	stop)    wait_device; "$ADB" shell am force-stop "$PKG"; ok "zatrzymano" ;;
	awake)   wait_device
	         # Zgoda ADB bez wygasania (domyślnie Android unieważnia ją po 7 dniach).
	         "$ADB" shell settings put global adb_allowed_connection_time 0
	         "$ADB" shell am broadcast -a com.oculus.vrpowermanager.prox_close >/dev/null
	         ok "gogle nie usną (./quest.sh sleep przywraca)" ;;
	sleep)   wait_device
	         "$ADB" shell am broadcast -a com.oculus.vrpowermanager.automation_disable >/dev/null
	         ok "czujnik zbliżeniowy znów działa normalnie" ;;
	wifi)    # Gogle muszą być raz podłączone kablem; potem kabel niepotrzebny.
	         rm -f "$WIFI_FILE"
	         wait_device
	         ip=$("$ADB" shell ip -f inet addr show wlan0 | awk '/inet /{print $2}' | cut -d/ -f1 | tr -d '\r')
	         [[ -n $ip ]] || fail "gogle nie mają adresu Wi-Fi (włącz Wi-Fi w goglach)"
	         "$ADB" tcpip 5555 >/dev/null
	         # adb w goglach restartuje się w trybie sieciowym - kilka prób.
	         conn=""
	         for _ in 1 2 3 4 5 6; do
	         	sleep 2
	         	"$ADB" connect "$ip:5555" 2>&1 | grep -q "connected to" && { conn=1; break; }
	         done
	         [[ -n $conn ]] || fail "nie udało się połączyć z $ip:5555"
	         mkdir -p build
	         echo "$ip:5555" > "$WIFI_FILE"
	         ok "adb przez Wi-Fi: $ip:5555 - można odłączyć kabel (do restartu gogli)" ;;
	-h|--help|help) sed -n '4,21p' "$0" | sed 's/^# \{0,1\}//' ;;
	*)       fail "nieznane polecenie '$1' - zobacz ./quest.sh help" ;;
esac
