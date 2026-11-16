# Etap 4 (pułapki): co jest dziś, prośba o zlecenie

Od: agent lokalny (2026-11-16). Etap 3 jest zrobiony (3a-3e, pas dla
wolnych, łuk w tunelu; PR #101-#112). W kolejności zatwierdzonej przez
użytkownika następne są pułapki (b2 kodu odcinka). Niżej rozpoznanie, jak
przy etapach 2 i 3.

## Stan dziś

- `SegmentCode` liczy `trap` (0-15, 15 = brak), `trap_at` (0-3,
  ćwiartka odcinka) i `trap_level` (0-3: do km 30 najwyżej 1, do km 100
  najwyżej 2). Do tego reżyser (BUILD/FADE: poziom <= 1, REST: bez
  pułapek), kalendarz `UNLOCK_TRAP` i `TRAP_LIE` raz na 33 odcinki.
  Pułapka wymusza budowlę (`TRAP_STRUCT` 1->tunel, 7->wiadukt,
  10->most, 11->estakada) albo przekrój (`TRAP_SECTION` 8->1+1,
  13->roboty, 9->1+1; 1 -> zwężenie).
- **W scenie użyta jest tylko pułapka 7** (niski wiadukt):
  `StructurePlan` daje prześwit 4,4 m zamiast 6,5. Jest ślepa, bo nie ma
  ani znaku, ani skutku dla auta. Reszta pułapek jest tylko w kodzie,
  przez wymuszoną budowlę albo przekrój.
- Uwaga: kod odcinka ma przekrój 1 (pas dla wolnych) tylko przy
  podjeździe. Pas dla wolnych w scenie (PR #111) powstaje z każdego
  podjazdu `StructurePlan`, a przekroju 1 z kodu nie czyta. Jeśli to ma
  być rzadsze, zdecydujcie.

## Pułapki i co by trzeba

| nr | pułapka | co już jest | brakuje |
|----|---------|-------------|---------|
| 0 | zakręt po długiej prostej | generator: łuki R 900-2500 m | ciasny łuk (R < 400?) po >= 2 km prostej, ostrzeżenie A-1/A-3 albo bez (poziom) |
| 1 | zwężenie za tunelem | tunel + przekrój 7 (wymuszone) | strefa 7 zaraz za wylotem (dziś zaczyna się w punkcie zmiany odcinka, nie przy wylocie) |
| 2 | zjazd z lewej | - | rozjazd/węzeł: pas wyjazdu po lewej (przekrój 5 rozjazd L/P też nie zrobiony) |
| 3 | pułapka pasa | - | prawy (albo lewy) pas kończy się jako zjazd ("tylko w prawo"), znak późno |
| 4 | krótki pas włączenia | - | wjazd z ruchem włączającym się z prawej, krótki pas |
| 5 | odcinek przeplatania | - | wjazd + zjazd blisko, boty zmieniają pasy |
| 6 | szczyt zasłaniający korek | podjazd + zdarzenie "korek" | korek zaraz za szczytem (zdarzenie spięte z budową, trap_at = szczyt) |
| 7 | niski wiadukt | prześwit 4,4 m | znak B-16 (wysokość), skutek: dach/kolizja dla wysokiego auta? Nasze auta są niższe - pułapka tylko przy skoku (lot pod wiaduktem)? |
| 8 | przejazd kolejowy | wiadukt z pociągiem (3c), RailTrain | przejazd w poziomie na 1+1: rogatki, pociąg przez drogę, sygnalizacja |
| 9 | drzewa przy jezdni | 1+1 (wymuszone), dekoracje | aleja drzew z kolizją tuż za krawędzią, bez barier |
| 10 | wąski most | most (wymuszony) | węższy pomost (bez pasa awaryjnego / 1 pas), znak A-5? |
| 11 | boczny wiatr | estakada (wymuszona) | siła boczna na auto (podmuchy), rękaw wiatrowy / znak A-19; fizyka: siła z powierzchni bocznej |
| 12 | zmiana nawierzchni | pogoda (`WeatherPlan.surface`, oblodzenie mostów) | odcinek śliskiej nawierzchni (kostka? mokra plama?) - czy to inne niż pogoda? |
| 13 | roboty z przejazdem | przekrój 6 (zrobiony) | pułapka = co dodatkowo? (np. skos krótszy, tablica późno) |
| 14 | znak kłamie | znaki ograniczeń | znak niezgodny ze stanem (np. "koniec robót", a roboty trwają; zła strzałka) |

## Pytania

1. Kolejność i zakres: wszystkie 15 naraz czy w podetapach jak 2a-2e
   i 3a-3e? Proponuję najpierw te, które mają już budowlę lub przekrój
   (1, 6, 7, 9, 10, 11, 13, 0). Węzły (2, 3, 4, 5) i przejazd
   kolejowy (8) to nowa geometria, więc osobno.
2. `trap_level` 0-3: co ma znaczyć dla każdej pułapki (np. znak
   wcześnie / późno / brak, długość, siła wiatru)?
3. Realizm: pomoce tylko jawne i wyłączalne. Czy pułapka może być
   "niewidoczna", np. bez znaku na poziomie 3? Wtedy gracz uczy się jej
   z jazdy.
4. 7 niski wiadukt: nasze auta mieszczą się pod 4,4 m. Czy pułapka
   to wiadukt nad skocznią (lot w pomost)? Inaczej nic nie robi.
5. 11 boczny wiatr: czy fizyka może dostać boczną siłę (jawnie,
   rękaw wiatrowy widoczny)? Proponuję podmuchy 0-15 m/s, siła z
   powierzchni bocznej auta i współczynnika oporu.

Do czasu zlecenia robię porządki z kolejki (kamera w zrzutach
`structure_drive_test`, szwy kolizji terenu między kawałkami).
