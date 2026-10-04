# PokéLens

Flutter-App zum Fotografieren, Erkennen und Sammeln von Pokémon-Karten. Die veröffentlichte Browser-Version liegt im Repository-Hauptverzeichnis:

**[App öffnen](https://leon2012320.github.io/pokelens/)**

Der Flutter-Quellcode für Web, Android und iOS liegt in [`flutter_app/`](flutter_app/). Details zu Preisen, Speicherung und Zustandseinschätzung stehen in der [Projektbeschreibung](flutter_app/README.md).

## Fotoerkennung

„Foto aufnehmen“ fordert auf unterstützten Handys und iPads die rückseitige Kamera an. „Aus Fotos wählen“ öffnet die Bildauswahl. Der Browser entscheidet, ob eine Kamera oder eine Auswahl angezeigt wird.

Die Browser-App liest Fotos lokal mit Tesseract.js. Erkannte Sammlernummern werden im Katalog gesucht. Ohne lesbare Nummer werden ähnlich geschriebene Kartennamen gesucht und die Katalogbilder mit dem Foto verglichen. Bild, Set und Nummer vor der Auswahl überprüfen. Fotos werden nicht hochgeladen. Sprachmodelle und Katalogdaten benötigen eine Internetverbindung; der erste Scan lädt das ausgewählte Sprachmodell.

Die Zustandseinschätzung bleibt eine geführte Selbsteinschätzung. Fotos liefern keine automatische Schadensbewertung oder Echtheitsprüfung.

## Entwickeln und bauen

Benötigt werden Flutter 3.44.2 / Dart 3.12.2 sowie Node.js mit npm für die Browser-OCR-Dateien.

```sh
cd flutter_app
flutter pub get
npm ci --prefix tools/ocr-runtime
node tools/prepare-ocr.mjs
flutter analyze
flutter test
flutter build web --release --base-href /pokelens/
```

Zum lokalen Testen nach dem Build: `node tools/serve.mjs 58123`, dann `http://127.0.0.1:58123/pokelens/` öffnen. Die OCR-Laufzeit ist exakt auf Tesseract.js 6.0.1 festgelegt; der npm-Lockfile hält die übrigen Versionen fest. Der Vorbereitungsschritt kopiert Laufzeit, WebAssembly-Dateien und Lizenzen nach `web/ocr/`.

Für eine GitHub-Pages-Aktualisierung den **gesamten** Inhalt von `flutter_app/build/web/`, einschließlich `ocr/` und `.nojekyll`, ins Repository-Hauptverzeichnis übernehmen und committen. GitHub Pages veröffentlicht den Hauptzweig aus dem Root-Verzeichnis. Nur `main.dart.js` zu kopieren genügt nicht für die Fotoerkennung.

## Prüfung dieser Änderung

49 Flutter-Tests bestanden, `flutter analyze` ohne Befunde und Release-Webbuild erfolgreich. Der Browser-Fototest auf der öffentlichen GitHub-Pages-App mit Glurak-ex aus 151, 199/165, lieferte die richtige Karte als ersten Bildtreffer. Physische iOS-/Android-Kameras müssen zusätzlich auf den jeweiligen Geräten geprüft werden.

Unabhängiges Fanprojekt. Kartendaten und Bilder stammen von [TCGdex](https://www.tcgdex.net/); die Rechte an Pokémon und den Kartengrafiken liegen bei ihren jeweiligen Rechteinhabern.
