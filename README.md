# 🛰️ Lab4Phone – Android-Only v3

**Lab4Phone** est un outil d’analyse et de diagnostic forensique automatisé pour smartphones Android.  
Développé sous **Kali Linux ARM64 (Raspberry Pi 5)**, il fait partie du projet **Sombra CyberLab Solution** et permet d’évaluer rapidement le niveau de risque d’un appareil mobile (téléphone ou tablette).

---

## ⚙️ Fonctionnalités principales

| Fonction | Description |
|-----------|--------------|
| 🔍 **Analyse complète ADB** | Collecte des infos système, services, permissions, stockage, connexions Bluetooth/Wi-Fi, etc. |
| 🧠 **Évaluation du risque** | Classification automatique : 🟢 Sain, 🟠 Intrusif, 🔴 Critique |
| 📜 **Rapport humain & technique** | Génère un rapport lisible + un CSV/JSON horodaté pour archivage |
| 🔐 **Backup probatoire** | Optionnel : archive signée SHA256 contenant APKs & logs (chaîne de preuve) |
| ⛓️ **Mode Blockchain** | Génère un chaînage SHA pour l’authenticité des rapports |
| 🧩 **Recommandations claires** | Conseils opérateur et client selon le niveau de risque |
| 📱 **Compatibilité** | Android 8 → 15 (ARM/ARM64, téléphones & tablettes) |

---

## 🧰 Dépendances requises

Le script nécessite les outils suivants :

```bash
sudo apt install -y android-tools-adb jq tar coreutils grep awk
# Lab4Phone
# Lab4Phone
