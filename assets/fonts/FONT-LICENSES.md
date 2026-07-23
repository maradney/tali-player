# Bundled font licenses

All fonts bundled with this app are redistributable under the SIL Open Font
License, Version 1.1 (OFL-1.1). The app ships the font files directly (no
runtime download) so it keeps working offline and makes no third-party
network calls, consistent with the project's no-telemetry stance.

The full OFL-1.1 text for each font is bundled next to this file in
`licenses/*-OFL.txt` (the authoritative upstream copy, including each font's
copyright notice and any Reserved Font Name), and is registered with
Flutter's `LicenseRegistry` (see `lib/font_licenses.dart`) so it appears in
the app under About > Licenses.

Canonical OFL-1.1 text: https://openfontlicense.org/open-font-license-official-text/

| Font | Copyright | Source |
| --- | --- | --- |
| Lato | © Łukasz Dziedzic | https://github.com/google/fonts/tree/main/ofl/lato |
| IBM Plex Sans Arabic | © 2019 IBM Corp. | https://github.com/google/fonts/tree/main/ofl/ibmplexsansarabic |
| Atkinson Hyperlegible | © Braille Institute of America, Inc. | https://github.com/google/fonts/tree/main/ofl/atkinsonhyperlegible |
| Space Mono | © Colophon Foundry | https://github.com/google/fonts/tree/main/ofl/spacemono |
| Noto Sans Arabic | © The Noto Project Authors | https://github.com/google/fonts/tree/main/ofl/notosansarabic |
| Tajawal | © Boutros International | https://github.com/google/fonts/tree/main/ofl/tajawal |
| Cairo | © The Cairo Project Authors | https://github.com/google/fonts/tree/main/ofl/cairo |

Cairo and Noto Sans Arabic are bundled as their upstream variable fonts
(single file each); Flutter maps `fontWeight` to the `wght` axis.

Each font is used under OFL-1.1; the license permits bundling and
redistribution as part of this software.
