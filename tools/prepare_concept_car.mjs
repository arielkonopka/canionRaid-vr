// Przygotowanie modelu "Car Concept" (Khronos glTF Sample Assets, CC BY 4.0:
// Darmstadt Graphics Group GmbH, Eric Chadwick; oryginał Unity Fan, CC0)
// pod Questa: logotypy Khronos zastąpione neutralnymi teksturami (cudze
// znaki towarowe), wersja dla botów bez wnętrza i drobnych części.
// Upraszczanie i zmniejszanie tekstur robi potem `gltf-transform optimize`
// (patrz tools/prepare_concept_car.sh).
//
//   node tools/prepare_concept_car.mjs WEJŚCIE.glb WYJŚCIE.glb [bot]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune } from '@gltf-transform/functions';
import { readFileSync } from 'node:fs';

const [, , input, output, mode] = process.argv;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();

// Neutralne tekstury (PNG z tools/concept_car_tex/, robione przez
// prepare_concept_car.sh) w miejsce obrazów z logotypami - po indeksie
// obrazu w oryginalnym pliku.
const replace = { 3: 'plate.png', 10: 'tireside.png', 11: 'flat_normal.png' };
const texDir = new URL('./concept_car_tex/', import.meta.url);
root.listTextures().forEach((t, i) => {
  if (replace[i]) {
    t.setImage(readFileSync(new URL(replace[i], texDir)));
    t.setMimeType('image/png');
  }
});

// Bot: z zewnątrz nie widać wnętrza, wycieraczek, pedałów ani zacisków.
if (mode === 'bot') {
  const drop = /^(Interior|BodyWindshieldWipers|Engine|BodyHoodInterior|BodyHoodUnder|Wheel.*Brake|Axles|License)/;
  for (const node of root.listNodes()) {
    if (drop.test(node.getName() || '')) node.dispose();
  }
}
// Wycieraczki modelu (24 tys. trójkątów) zastępują nasze (StuntCar._build_wipers).
for (const node of root.listNodes()) {
  if (/^BodyWindshieldWipers$/.test(node.getName() || '')) node.dispose();
}
// Warianty materiałów (lakiery) - lakier ustawia gra.
const variants = root.listExtensionsUsed().find((e) => e.extensionName === 'KHR_materials_variants');
if (variants) variants.dispose();

await doc.transform(prune());
await io.write(output, doc);
console.log('zapisano', output);
