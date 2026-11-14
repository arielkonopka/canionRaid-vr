// Ziemia: zmienność koloru w kilku skalach (płaty, kępy), w układzie świata,
// więc ziemia może jechać za autem bez "pływania" wzoru.
//
// Tryb Autostrada (etap 2, docs/AUTOSTRADA.md pkt 5): dwie palety biomu
// (a, b) mieszane współczynnikiem biome_t (przejście 2 km, ustawia xr_main
// z HighwayPlan.biome_blend). Wąwóz: obie palety = łąka, biome_t = 0.
// Szum okresowy z world_wrap.gdshaderinc - odporny na przesuwanie świata
// (WorldOrigin) i bez rozsypki sin() przy dużych współrzędnych.
shader_type spatial;

#include "res://shaders/world_wrap.gdshaderinc"

#include "res://shaders/ground_body.gdshaderinc"
