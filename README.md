# 🛰️ Lab4Phone — Mobile Forensics Toolkit  
_Outils d’analyse iOS & Android : diagnostics, detection spyware, IOC, MVT, rapports, coffre probatoire._

![License](https://img.shields.io/badge/license-Apache--2.0-blue)
![Shell](https://img.shields.io/badge/lang-shell-89e051.svg)

---

# 📦 Modules inclus

| Script | Plateforme | Fonction |
|--------|------------|----------|
| `scripts/ios_only.sh` | **iOS** | Backup, analyse MVT-iOS, extraction apps, IOC, scoring |
| `android_only.sh` | **Android** | ADB triage, permissions, réseau, IOC, scoring |

---

# ✨ Fonctionnalités principales

- Analyse **iOS + Android**
- Backup complet ou rapide (iOS : MVT + idevicebackup2)
- Extraction des apps & permissions
- Analyse MVT-iOS automatique
- IOC : spyware / parental / dual-use / fichiers / domaines
- Scoring risque :
  - 🟢 **GREEN** — sain  
  - 🟠 **ORANGE** — douteux  
  - 🔴 **RED** — intrusion ou spyware détecté  
- Rapports complets :
  - TXT (opérateur)  
  - CSV (machine)  
  - JSON (API friendly)
- Coffre probatoire :
  - archive tar.gz  
  - manifeste JSON  
  - SHA256SUMS  
- Mode HORS-LIGNE total  
- Inventaire apps (iOS : ideviceinstaller + fallback sqlite3 Manifest.db)

---

# 🍏 iOS Module — `scripts/ios_only.sh`

## 🔍 Fonctions
- Détection appareil (iPhone/iPad)
- Backup :
  - `mvt-ios backup` (flash/full)
  - fallback `idevicebackup2`
- Analyse automatique MVT-iOS  
- Extraction apps :
  - `ideviceinstaller`
  - ou fallback `Manifest.db`
- IOC fichiers & domaines  
- Scoring GREEN/ORANGE/RED  
- Rapport TXT + CSV + JSON  
- Coffre probatoire SHA256  

## ▶️ Lancement

Analyse rapide :
```bash
./scripts/ios_only.sh --quick
