# SirJoe Player

Lettore musicale per **Windows, Mac e Android** con interfaccia semplice, playlist salvabili,
equalizzatore e **collegamento Bluetooth automatico** al dispositivo predefinito.

Le versioni pronte da installare si trovano in **Releases**.

## Come si compila
Le build vengono create da GitHub Actions (`.github/workflows/build.yml`) quando si pubblica
un tag `vX.Y.Z`. Su GitHub vengono tenute solo le ultime 2 versioni.

## Tecnologia
- Flutter (un solo codice per i tre sistemi)
- media_kit / mpv per la riproduzione di quasi tutti i formati audio
- Bluetooth: codice nativo su Android, PowerShell + API Windows su Windows, `blueutil` su Mac
