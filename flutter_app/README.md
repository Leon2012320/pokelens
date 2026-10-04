# PokéLens

Eine Flutter-App für Pokémon-Sammler auf iPhone, iPad und Android, mit einer Browser-Version zum Ausprobieren. Helle Oberfläche, angepasste Handy- und Tablet-Navigation, Kartensuche, Marktpreise und eine lokale Sammlung.

## Starten

Entwicklungsstand: **Flutter 3.44.2 / Dart 3.12.2**. Flutter installieren und den Projektordner im Terminal öffnen:

```sh
flutter doctor
flutter pub get
npm ci --prefix tools/ocr-runtime
node tools/prepare-ocr.mjs
flutter run -d chrome
```

Für ein angeschlossenes Mobilgerät oder einen eingerichteten Emulator:

```sh
flutter devices
flutter run -d <geraete-id>
```

`<geraete-id>` durch eine ID aus `flutter devices` ersetzen. Android benötigt das Android SDK; das Projekt verwendet mindestens API 24 (Android 7.0). Für iPhone/iPad sind **ein Mac, Xcode und CocoaPods** nötig, einschließlich Gerätesignierung in Xcode. Das iOS-Ziel ist 15.5 oder neuer. Die Sprachmodelle sind bereits in Gradle und im Podfile eingetragen. Kamera- und Fotozugriff beim ersten Einsatz erlauben. Siehe [Flutter-Setup für iOS](https://docs.flutter.dev/platform-integration/ios/setup) und [ML-Kit-Pluginvoraussetzungen](https://pub.dev/packages/google_mlkit_text_recognition).

## Karten erfassen

1. Kartensprache wählen und die komplette Vorderseite fotografieren oder ein vorhandenes Foto auswählen.
2. Die Texterkennung schlägt im Browser und mobil einen Namen oder eine Sammlernummer vor. Ohne lesbare Nummer vergleicht die Browser-App das Foto mit den Katalogbildern der ähnlich geschriebenen Namen. Bild, Set und Nummer mit dem Suchtreffer vergleichen und die passende Karte öffnen.
3. Optional die Rückseite ergänzen, den Zustand prüfen und das Exemplar zur Sammlung hinzufügen. Mehrere gleiche Karten werden als separate Exemplare gespeichert und können einzeln entfernt werden.

Die Suche akzeptiert Namen, Nummern wie `199/165` und `TG05/TG30` sowie TCGdex-IDs wie `sv03.5-199`. Die native App nutzt lokale OCR für lateinische, japanische, chinesische und koreanische Schrift. Devanagari ist im Service ebenfalls vorbereitet. Die Schriftunterstützung stammt aus [ML Kit Text Recognition v2](https://developers.google.com/ml-kit/vision/text-recognition/v2).

Elf Kartensprachen sind auswählbar. OCR-Unterstützung und Katalogabdeckung sind getrennt: Nicht jede Sprache, Karte oder Druckvariante ist vollständig erfasst. Die Sprache wird vom Nutzer gewählt. Im Browser verarbeitet Tesseract.js 6.0.1 das Foto lokal mit dem passenden Sprachmodell. Die erste Nutzung lädt Sprachdaten aus `tessdata.projectnaptha.com`; die OCR-Laufzeit und WebAssembly-Dateien werden mit der App ausgeliefert. Native ML-Kit-OCR unterstützt beispielsweise thailändische Schrift nicht; dort kann man manuell suchen.

„Foto aufnehmen“ fordert auf unterstützten Mobilbrowsern die rückseitige Kamera an. Der Browser entscheidet, ob er direkt die Kamera oder eine Auswahl öffnet. „Aus Fotos wählen“ öffnet die Bildauswahl. Für Kameranutzung muss die Seite über HTTPS oder localhost laufen. Bei unscharfen Fotos, großen Bildrändern oder Reflexionen kann eine manuelle Korrektur nötig sein. Die Erkennung liefert Vorschläge, keine Garantie für Set, Druckvariante oder Echtheit.

## Preise und Zustand

Kartendaten und Cardmarket-Referenzpreise kommen über die öffentliche **TCGdex REST API**. Es sind kein API-Schlüssel und kein eigener Server erforderlich. Verfügbarkeit und Sprachabdeckung beschreibt die [TCGdex-FAQ](https://tcgdex.dev/faq).

Die App übernimmt ausschließlich vorhandene Werte aus `pricing.cardmarket`: Trend, niedrigsten Preis und Durchschnitt der letzten 7 bzw. 30 Tage, inklusive Währung und Quellenzeitpunkt. Fehlende oder ungültige Werte bleiben leer. Offline-Beispielkarten enthalten keine erfundenen Preise. Details werden für fünf Minuten im Arbeitsspeicher zwischengespeichert; gespeicherte Sammlungspreise sind Momentaufnahmen.

„Marktstandard“ bezeichnet das Basispreisfeld des Feeds, das auch bei ausschließlich holografischen Karten verwendet wird. Separate Holo-Werte erscheinen nur, wenn die Quelle sie liefert. Preise sind keine Angebote für einen bestimmten Zustand oder eine bestimmte Sprache. Die Zuordnung von Druckvarianten kann laut TCGdex noch Fehler enthalten. Der Cardmarket-Link öffnet die Produktsuche zum Abgleichen konkreter Angebote. Siehe [Preisfelder](https://tcgdex.dev/reference/card#cardmarket-pricing) und [bekannte Zuordnungsgrenzen](https://tcgdex.dev/faq#pricing).

**Die Zustandsbewertung ist eine geführte Selbsteinschätzung.** Angaben zu Ecken, Kanten, Oberfläche und Knicken ergeben eine vorsichtige Orientierung von Near Mint bis Poor. Fotos werden nicht automatisch auf Schäden oder Echtheit bewertet; es gibt kein zertifiziertes Grading und keinen erfundenen Zustandsabschlag auf den Marktpreis.

## Speicherung und Datenschutz

Die Sammlung und Spracheinstellung werden mit `shared_preferences` lokal gespeichert. Es gibt kein Konto und keine Cloud-Synchronisierung. Fotos und vollständige OCR-Texte werden von der App nicht auf einen Server hochgeladen oder in der Sammlung gespeichert. Suchtext, Kartennummern und gewählte Sprache werden an TCGdex gesendet; weitere Kartenbilder werden von TCGdex geladen. Fotos bleiben in der App nur während der aktuellen Sitzung sichtbar.

Beim Löschen der App oder ihrer Browserdaten kann die Sammlung verloren gehen. Es ist noch keine Export- oder Backup-Funktion enthalten. Speicherfehler werden angezeigt; beschädigte Sammlungsdaten werden nicht still überschrieben.

## Prüfen

```sh
flutter analyze
flutter test
flutter build web --release
```

Tests prüfen unter anderem Preis- und Variantenfelder, Unicode-Suchen, Sammlernummern mit führenden Nullen, Netzwerkfehler, OCR-Textauswertung, Zustandseinstufung und dauerhafte Speicherung separater Exemplare. Native Kamera/OCR muss zusätzlich auf echten iOS- und Android-Geräten geprüft werden.

Unabhängiges Fanprojekt. Kartendaten und Kartenbilder: [TCGdex](https://www.tcgdex.net/). Pokémon und die Kartengrafiken gehören ihren jeweiligen Rechteinhabern. Die gebündelte Schrift Manrope enthält ihre OFL-Lizenz im Projekt.
