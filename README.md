# 📱🔍 **Lab4Phone — Mobile Forensics Toolkit (FR + EN)**

Outils d’analyse **iOS & Android** : diagnostics, détection spyware, IOC, MVT, rapports, coffre probatoire.
Tools for **iOS & Android** diagnostics, spyware detection, IOC analysis, MVT, reporting & forensic vault.

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![Shell](https://img.shields.io/badge/lang-shell-89e051)

---

## 📦 Modules inclus / Included Modules

| Script                    | Plateforme / Platform | Fonction / Function                                           |
| ------------------------- | --------------------- | ------------------------------------------------------------- |
| `scripts/ios_only.sh`     | iOS                   | Backup, analyse MVT-iOS, extraction apps, IOC, scoring, vault |
| `scripts/android_only.sh` | Android               | ADB triage, permissions, network, BT, IOC, scoring, reports   |

---

# ✨ Fonctionnalités principales / Main Features

* Analyse **iOS + Android**
* Backups avancés (iOS : MVT + idevicebackup2 fallback)
* Extraction apps / permissions / réseau / Bluetooth
* Détection spyware (parental, dual-use, mercenaire)
* IOC : fichiers + domaines
* Scoring risque :

  * 🟢 **GREEN** — sain / clean
  * 🟠 **ORANGE** — douteux / suspicious
  * 🔴 **RED** — spyware détecté / spyware detected
* Rapports : TXT + CSV + JSON
* Coffre probatoire sécurisé : tar.gz + SHA256SUM + manifeste JSON

---

# 🍏 iOS Module — `scripts/ios_only.sh`

## 🇫🇷 Fonctions

* Détection iPhone / iPad
* Backups (MVT-iOS flash/full + fallback `idevicebackup2`)
* Analyse automatique MVT-iOS
* Extraction apps (`ideviceinstaller` ou `Manifest.db`)
* IOC fichiers & domaines
* Scoring GREEN / ORANGE / RED
* Coffre probatoire SHA256

## 🇬🇧 Features

* Detects iPhone / iPad
* Backup via MVT-iOS (flash/full)
* Fallback to `idevicebackup2`
* Automatic MVT-iOS analysis
* App extraction (`ideviceinstaller` or Manifest.db)
* IOC matching (files & domains)
* Risk scoring
* SHA256 forensic vault

---

# 🤖 Android Module — `scripts/android_only.sh`

## 🇫🇷 Fonctions

* Détection Android (ADB)
* Infos système : build, version, stockage, IMEI*
* Inventaire apps + permissions sensibles
* Analyse réseau (interfaces, connexions, IP)
* Analyse Bluetooth
* IOC Android (apps, chemins, fichiers suspects)
* Scoring GREEN / ORANGE / RED
* Rapports : TXT + CSV + JSON

(*IMEI si accessible*)

## 🇬🇧 Features

* Android detection (ADB)
* System info: build, version, storage, IMEI*
* Full app inventory + sensitive permissions
* Network analysis
* Bluetooth scan
* Android IOC analysis
* Risk scoring
* Reports: TXT, CSV, JSON

---

# 🛠 Prérequis / Requirements

```
sudo apt update && sudo apt install -y \
  android-tools-adb jq coreutils grep awk sed tar sqlite3 \
  usbmuxd libimobiledevice-utils
```

---

# 🔐 Licence & Contributions

* Licence : Apache-2.0
* Contributions bienvenues
* License : Apache-2.0
* Pull requests welcome

---
