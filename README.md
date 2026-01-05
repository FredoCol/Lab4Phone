# 📱🔍 **Lab4Phone — Mobile Forensics Toolkit (FR + EN)**

Outils d’analyse **iOS & Android** : diagnostics, détection spyware, IOC, MVT, rapports et coffre probatoire.
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
* Backups complets (MVT + `idevicebackup2`)
* Extraction apps / permissions / réseau / Bluetooth
* IOC : fichiers suspects + domaines malveillants
* Détection spyware (parental, dual-use, mercenaire)
* Scoring : 🟢 GREEN / 🟠 ORANGE / 🔴 RED
* Rapports : TXT (opérateur), CSV (machine), JSON (API)
* Coffre probatoire : archive tar.gz + SHA256SUM + manifeste JSON

---

# 🍏 iOS Module — `scripts/ios_only.sh`

## 🇫🇷 Fonctions

* Détection iPhone/iPad
* Backups : MVT-iOS (flash/full) + fallback `idevicebackup2`
* Analyse automatique MVT-iOS
* Extraction apps (`ideviceinstaller` ou `Manifest.db`)
* IOC fichiers & domaines
* Scoring GREEN / ORANGE / RED
* Coffre probatoire SHA256

## 🇬🇧 Features

* Detects iPhone/iPad
* Backups via MVT-iOS (flash/full)
* Fallback to `idevicebackup2`
* Automatic MVT-iOS analysis
* App extraction (installer or Manifest.db)
* IOC matching (files & domains)
* Risk scoring
* SHA256 forensic vault

---

# 🤖 Android Module — `scripts/android_only.sh`

## 🇫🇷 Fonctions

* Détection Android via ADB
* Infos système (build, version, stockage, IMEI*)
* Inventaire apps + permissions sensibles
* Analyse réseau (interfaces, connexions, IP)
* Scan Bluetooth
* IOC Android (apps/dossiers/fichiers suspects)
* Scoring GREEN / ORANGE / RED
* Rapports : TXT + CSV + JSON

## 🇬🇧 Features

* Android detection via ADB
* System info (build, version, storage, IMEI*)
* Full app inventory + sensitive permissions
* Network analysis
* Bluetooth scan
* Android IOC analysis
* Risk scoring
* TXT, CSV, JSON reports

---

# 🛠 Prérequis / Requirements

```
sudo apt update && sudo apt install -y \
  android-tools-adb aapt apktool \
  python3 python3-venv python3-pip \
  jq coreutils grep awk sed tar sqlite3 \
  usbmuxd libimobiledevice-utils ideviceinstaller ifuse \
  usbutils udev \
  iproute2 net-tools \
  bluez rfkill \
  curl unzip rsync

```

---

# 🔐 Licence & Contributions

**FR :** Licence Apache-2.0 • Contributions bienvenues
**EN :** Apache-2.0 License • Pull requests welcome

---
