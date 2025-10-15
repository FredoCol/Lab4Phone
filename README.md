# Lab4Phone — Android-Only v3 (K02)

[![CI](https://github.com/FredoCol/Lab4Phone/actions/workflows/ci.yml/badge.svg)](../../actions)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/lang-shell-89e051.svg)]()

> **Lab4Phone** est un outil d’analyse et de diagnostic “forensic-lite” pour **smartphones/tablettes Android** via ADB.
> Il produit un **rapport humain**, un **CSV/JSON horodaté**, et un **niveau de risque** (🟢 sain, 🟠 intrusif, 🔴 critique).
> Fait pour **Kali Linux ARM64 (Raspberry Pi 5)** mais fonctionne aussi sur x86_64.

---

## ✨ Fonctionnalités

- **Analyse hors/ligne** : infos système, apps, permissions sensibles, réseau/BT
- **Évaluation du risque** : 🟢 **GREEN**, 🟠 **ORANGE**, 🔴 **RED** (codes retour: 0/10/20)
- **Rapport humain** + **CSV/JSON** (horodatés)
- **Questions opérateur (yes/no)** *après voyant ORANGE/ROUGE* :
  - backup probatoire
  - rapport “blockchain” (chaînage SHA)
  - neutraliser apps suspectes (optionnel si IOC)
  - reset usine (optionnel)
- **Recommandations** claires (client & opérateur)
- **Traçabilité** : SHA256 du rapport + **ledger** CSV global

---

## 🧰 Prérequis

```bash
sudo apt update && sudo apt install -y android-tools-adb jq coreutils grep awk sed tar
