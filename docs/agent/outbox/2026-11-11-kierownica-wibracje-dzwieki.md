Od: agent lokalny, 2026-11-11 wieczór
Do: wątek projektu w chmurze
Status: do ustalenia z użytkownikiem (prośba o specyfikację)

# Trzy pomysły użytkownika: kierownica w powietrzu, wibracje, dźwięki innych aut

Użytkownik (2026-11-11, dosłownie): "zastanawiam się, czy możemy dodać
tryb sterowania 'powietrzną kierownicą'" oraz "no i reaktywność drążków,
powinny reagować na uderzenia, i różne takie, brakuje też dźwięków innych
pojazdów i efektów, gdy się je mija, jak dopplera...".
Stan dziś: sterowanie drążkiem (`xr_main._read_drive_input`), brak
wibracji (nigdzie `trigger_haptic_pulse`), boty i auta z naprzeciwka bez
dźwięku (`StuntCar._ready`: bot bez CarAudio - koszt syntezy w GDScript).

## 1. Kierownica w powietrzu (nowa wartość opcji Sterowanie -> Kierownica)

Propozycja agenta:
- kąt = obrót linii między dłońmi wokół osi kolumny kierowniczej
  (`StuntCar` ma `_steering_wheel`, przełożenie 14:1 - wizualna kierownica
  obraca się 1:1 z rękami); jedną ręką - położenie dłoni na wieńcu;
- pełny skręt kół przy obrocie kierownicy o ±180° (może opcja 90-450°);
- gaz/hamulec na spustach bez zmian; drążki wolne: biegi jak dziś (drążek
  w górę/dół albo A/X), ręczny - przycisk B lub drążek w dół, wsteczny -
  automat (hamulec na postoju); grip - "trzymanie" kierownicy (puszczona
  wraca do zera, sama się prostuje z prędkością jak prawdziwa);
- tryb "Wg przyczepności" dalej działa (limit kąta kół).
Pytania do użytkownika: zakres obrotu, czy kierownica ma się sama
prostować, mapowanie ręcznego/wstecznego.

## 2. Wibracje kontrolerów ("reaktywność drążków")

Propozycja: `XRController3D.trigger_haptic_pulse(...)`, opcja "Wibracje"
(wył./słabe/mocne). Zdarzenia: zderzenie (siła z impulsu, `last_hit`),
lądowanie, krawężnik / tarka / szuter (nawierzchnia pod kołami), ABS
(ręka hamulca, pulsowanie), poślizg kół napędzanych / TCS (ręka gazu),
ogranicznik obrotów, lekka faktura drogi rosnąca z prędkością. W trybie
kierownicy - obie ręce (siła na kierownicy z bocznej siły przednich kół?).

## 3. Dźwięki innych aut i Doppler

Propozycja: kilka najbliższych aut (np. 4 w promieniu ~80 m) dostaje
AudioStreamPlayer3D z zapętlonymi próbkami (silnik, opony, wiatr) i
`pitch_scale` z obrotów/prędkości - bez syntezy w GDScript (koszt).
Doppler: `AudioStreamPlayer3D.doppler_tracking` + kamera z
`doppler_tracking` (wbudowane w Godota). Mijanie aut z naprzeciwka:
krótki "szum przelotu" zależny od prędkości względnej. Klakson botów
już jest (3D?). Do sprawdzenia: koszt audio na Queście (bench).

Prośba: dopracujcie z użytkownikiem zakres i kolejność (który pierwszy),
odpowiedź w `inbox/`. Agent lokalny zrobi i zmierzy na goglach.
