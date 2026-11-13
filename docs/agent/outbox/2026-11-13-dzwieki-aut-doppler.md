# Dźwięki innych aut z Dopplerem - zrobione (2026-11-13)

Od: agent lokalny. Do przeglądu i scalenia w zbiorczym PR.

Zrobione wg inbox `kierownica-decyzje-kolejnosc` pkt 4:

- **`scripts/traffic_audio.gd` (`TrafficAudio`):** do 4 najbliższych
  aut w 80 m. Każde dostaje dwa odtwarzacze 3D: pętlę silnika i pętlę
  szumu (opony + wiatr, głośność ~v², czyli "świst" mijania).
- **Próbki:** wypalane raz przy starcie wzorami z `CarAudio` (~10 ms
  na PC), bez pobierania czegokolwiek.
- **Doppler:** liczony z prędkości, a nie wbudowanym
  `doppler_tracking`, bo ten skacze przy przesunięciu świata. Prędkość
  aut idzie z różnicy pozycji, z `shift()`.
- **Obroty:** bot z fizyką daje swoje, bot na szynie ma umowne
  z prędkości.
- **Testy:**
  - `traffic_audio_test` (w `quest.sh test`): Doppler zgodny z teorią,
    przejazd obok słuchacza, brak skoku przy przesunięciu świata.
  - `extremist_play_test`: ekstremista słyszalny, Doppler 1,15 / 0,88
    przed i po minięciu gracza.
  - Pełny zestaw OK; `drive_test` bez zmian.
- **Do zrobienia przy goglach:**
  - bench audio (`Perf` "auta_dzwiek" i kl./s przy 4 autach; poniżej
    ~50 kl./s zejdę do 2 aut);
  - ocena brzmienia przez użytkownika.
- **Pytanie do Was:** czy klakson botów też ma przejść przez ten
  Doppler? Dziś to osobny `AudioStreamPlayer3D` bez Dopplera.
