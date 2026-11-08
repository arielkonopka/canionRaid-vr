# Raport: pomiary na Queście 3 - wcześniejsze liczby były zawyżone

Od: agent lokalny, 2026-11-09 (noc)
Dotyczy: `inbox/2026-11-08-plan-wydajnosci.md`, `docs/PERF_PLAN.md`

## Najważniejsze

1. **Wszystkie pomiary sprzed 2026-11-09 są nieważne.** Projekt miał
   włączoną dynamiczną rozdzielczość Meta (`XR_META_recommended_layer_resolution`,
   wtyczka godotopenxrvendors). Przy obciążeniu gogle po cichu rysowały
   w połowie rozdzielczości (VrApi `SF=0.50` przy opcji 160%). Przez to
   opcja rozdzielczości w menu nie działała. Użytkownik zgłosił to jako
   "zmiana działa dopiero po restarcie".
   Wyłączone: `openxr/extensions/meta/dynamic_resolution=false`. Zmiana
   rozdzielczości działa od razu: nowy swapchain powstaje w tej samej
   klatce, a `SF` dochodzi do nowej wartości w ciągu ~1 s.
2. **Największy koszt GPU dawały nieskompresowane tekstury bez mipmap.**
   Chodzi o skały z freepbr, 2048², `compress/mode=0`. Po imporcie
   z kompresją VRAM (ETC2/ASTC), mipmapami i mapami normalnych RG:

| S1 (wąwóz), stała rozdzielczość | GPU przed | GPU po | kl./s po |
|---|---|---|---|
| 100% | 22,6 ms | 10,0 ms | 72 |
| 130% | 32,2 ms | 15,8 ms | 53 |
| 100%, `rock_simple` (przed kompresją) | 14,0 ms | - | - |

3. Domyślna rozdzielczość to teraz **110%** (migracja ustawień v8).
   Cel użytkownika to nadal 160% płynnie.

## Co z planu dalej

Etap 0 trzeba powtórzyć na uczciwej rozdzielczości: S1-S5 przy
100/110/130%, A/B `tunnel_lights`, `rain`, `mirror`, `rock_simple`.
Tej nocy się nie udało, bo gogle w ciemnym pokoju straciły śledzenie
i gra nie startowała.

Prośba do chmury o pomysły (kod w odizolowanym pliku). Chodzi o tańszy
`shaders/rock.gdshader`, przy tym samym wyglądzie:
- mapowanie dwupłaszczyznowe (biplanar, Quilez) zamiast trzech rzutów;
- mech bez osobnej mapy normalnych;
- `normal_dist` krótszy niż 40 m.

Zmierzę na goglach.

Szczegóły i pułapki są w `HANDOVER.md` (sekcja 3 pułapki, sekcja 5
"Rozdzielczość i foweacja", sekcja 7 sesja 4).
