Status: w toku
Od: wątek w chmurze "Ustal kierownicę, wibracje i dźwięki aut"
Decyzje użytkownika (2026-11-12 19:23, dosłownie): "tak, niech wibruje
w dłoniach, co trzymają, tak cały manekin, co do kolejności, zdam się
na Ciebie". Wcześniej (Twój commit 3e87e48): dłonie w powietrzu jako
alternatywne sterowanie, wartości proponowane.

# Kierownica, wibracje, dźwięki, manekin - ustalenia i kolejność

Dotyczy outbox `2026-11-11-kierownica-wibracje-dzwieki` i inbox
`2026-11-11-kierownica-w-powietrzu`.

## Ustalone

1. **Kierownica w powietrzu** - drugi tryb sterowania (Sterowanie ->
   Kierownica: "w powietrzu"), z dłońmi manekina. Wartości: zakres
   90/180/270/450° w opcjach, domyślnie 180 (`half_range = 180`); grip
   trzyma wieniec, puszczona wraca do środka; ręczny - lewy drążek w dół;
   wsteczny automatycznie (hamulec na postoju). Do oceny w goglach.
2. **Wibracje w dłoniach, które trzymają** - w trybie kierownicy pulsuje
   tylko kontroler, który ma wciśnięty grip (trzyma wieniec); puszczona
   ręka nic nie czuje. Przy drążku jak w propozycji (ABS w ręce hamulca,
   TCS w ręce gazu itd.). Opcja Wibracje: Wył./Słabe/Mocne, domyślnie
   Słabe; lekka faktura drogi jako osobny przełącznik (może męczyć).
3. **Cały manekin gracza** - tułów, ręce prowadzone do kontrolerów (IK
   ramię-łokieć-dłoń), prawa stopa między gazem a hamulcem wg spustów,
   lewa na sprzęgle przy zmianie biegu w manualu; głowa ukryta.
4. **Dźwięki innych aut z Dopplerem** - jak w propozycji (do 4 aut
   w ~80 m, próbki "wypalone" z naszej syntezy, bez pobierania; świst
   mijania); pomiar na goglach, przy spadku poniżej ~50 kl./s do 2 aut.

## Kolejność (użytkownik zostawił decyzję chmurze)

1. Kierownica w powietrzu + dłonie manekina (już w toku).
2. Wibracje - tanie, a od razu potrzebne kierownicy (ręce trzymające).
3. Dźwięki aut z Dopplerem + bench audio na Queście.
4. Cały manekin - na końcu, bo wymaga eksportu ze szkieletem: brakuje
   `python3-numpy` - **poproś użytkownika o instalację** (zasada: nic nie
   instalujemy bez zgody), a do tego czasu dłonie zostają osobną siatką,
   tak żeby potem dało się je podmienić na dłonie z pełnego modelu.
   Uwaga na koszt: skinning manekina gracza na Queście zmierz benchem.

Po każdym kroku wynik testów i pomiar do HANDOVER, krótko w outbox.

## Odpowiedź agenta lokalnego

(2026-11-12) Kolejność przyjęta z jednym wyjątkiem: użytkownik w terminalu
poprosił wprost o całego manekina ("fajnie by było, gdyby gracz był tym
manekinem ... a nie tylko dłonie"), a `python3-numpy` był już
zainstalowany - zrobione od razu: `models/dummy/player_dummy.glb` (szkielet,
poza siedząca jako spoczynkowa), `PlayerDummy` (TwoBoneIK3D ramion do
kontrolerów, głowa i własne dłonie tułowia schowane - dłonie zostają
z kontrolerów, prawa stopa gaz/hamulec), w VR od startu sceny. Lewa noga
przy sprzęgle w manualu - jeszcze nie. Rendery
`docs/renders/manekin_gracza_*.png` ("rendery super!" - użytkownik).
Bench skinningu na Queście - przy podłączonych goglach. Dalej: boty
(znikanie) -> wibracje -> pogoda -> dźwięki.

(2026-11-12, później) Boty (znikanie) - zrobione (516a1bb). Wibracje -
zrobione: `Haptics` (logika + `haptics_test`), opcje Wibracje (Wył./Słabe/
Mocne, domyślnie Słabe) i Faktura drogi (domyślnie wył.); w trybie
kierownicy tylko trzymające ręce. Dalej: pogoda, potem dźwięki.
