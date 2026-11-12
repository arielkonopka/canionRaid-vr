Status: nowe
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
