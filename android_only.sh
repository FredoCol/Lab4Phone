#!/usr/bin/env bash
# Lab4Phone / Kit — ANDROID-ONLY v3-
# Version complète stable — horodatage, résumé humain, causes, backup, blockchain, ledger, recommandations
# Auteur : Sombra CyberLab Solution

set -euo pipefail
IFS=$'\n\t'

START_S=$(date +%s)
RUN_TS=$(date +%F_%H%M%S)
HOST=$(hostname | tr -d ' ')
BASE="/media/ssd/Sombra"
REPORT_DIR="$BASE/reports/$HOST"
BACKUP_DIR="$BASE/backups/$HOST"
LEDGER_DIR="$BASE/ledger"
LOG_DIR="$BASE/logs/$HOST"
mkdir -p "$REPORT_DIR" "$BACKUP_DIR" "$LEDGER_DIR" "$LOG_DIR"

RAPPORT_FILE="$REPORT_DIR/rapport_lab4phone_android_${RUN_TS}.txt"
DECISIONS_FILE="$REPORT_DIR/decisions_${RUN_TS}.txt"
LOGFILE="$LOG_DIR/android_${RUN_TS}.log"

exec > >(tee -a "$RAPPORT_FILE") 2>&1

echo "[+] === Début Lab4Phone ANDROID-ONLY v3 ==="
echo "[i] Horodatage début : $(date)"

# --- Vérification ADB
command -v adb >/dev/null 2>&1 || { echo "[!] adb manquant."; exit 1; }
adb start-server >/dev/null 2>&1

# --- Connexion
SERIAL="$(adb devices | awk 'NR>1 && /device$/{print $1;exit}')"
if [ -z "$SERIAL" ]; then
  echo "[!] Aucun appareil détecté ou non autorisé."
  exit 0
fi

# --- Collecte infos principales
VENDOR="$(adb shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')"
MODEL="$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
ANDROID_VER="$(adb shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')"
PATCH="$(adb shell getprop ro.build.version.security_patch 2>/dev/null | tr -d '\r')"

# --- Flags
ACC_RAW="$(adb shell settings get secure enabled_accessibility_services 2>/dev/null)"
NOTIF_RAW="$(adb shell settings get secure enabled_notification_listeners 2>/dev/null)"
HAS_ACC=$([ -n "$ACC_RAW" ] && [ "$ACC_RAW" != "null" ] && echo "on" || echo "off")
HAS_NOTIF=$([ -n "$NOTIF_RAW" ] && [ "$NOTIF_RAW" != "null" ] && echo "on" || echo "off")
OWNER_RAW="$(adb shell cmd device_policy list-owners 2>/dev/null || true)"
HAS_OWNER=0; [[ "$OWNER_RAW" =~ ComponentInfo ]] && HAS_OWNER=1

OWNER_TYPE="none"
if [ "$HAS_OWNER" -eq 1 ]; then
  if echo "$OWNER_RAW" | grep -Eiq 'mdm|enterprise|devicepolicy|dpc|emm'; then
    OWNER_TYPE="enterprise"
  elif echo "$OWNER_RAW" | grep -Eiq 'family|parent'; then
    OWNER_TYPE="parental"
  else
    OWNER_TYPE="unknown"
  fi
fi

# --- IOC et indicateurs
IOCS_DIR="$BASE/tools/iocs"
SUSPECTS_FILE="$REPORT_DIR/suspects_${RUN_TS}.txt"
TMP_IND="$(mktemp)"
cat "$IOCS_DIR"/indicators_android_*.txt 2>/dev/null | grep -v '^#' | sort -u > "$TMP_IND"
adb shell pm list packages -3 | sed 's/^package://g' | grep -iFf "$TMP_IND" > "$SUSPECTS_FILE" 2>/dev/null || true
SUSPECTS_COUNT=$(wc -l < "$SUSPECTS_FILE" 2>/dev/null || echo 0)

# --- Risque
RISK="GREEN"; ICON="🟢"
if [ "$SUSPECTS_COUNT" -gt 0 ] || [ "$HAS_NOTIF" = "on" ] || [ "$HAS_ACC" = "on" ] || [ "$HAS_OWNER" -eq 1 ]; then
  RISK="ORANGE"; ICON="🟠"
fi

# --- Affichage causes
echo
echo "=== Pourquoi le voyant ${ICON} ${RISK} ? ==="
[ "$HAS_NOTIF" = "on" ] && echo "• Accès aux notifications activé."
[ "$HAS_ACC" = "on" ] && echo "• Services d’accessibilité activés."
[ "$HAS_OWNER" -eq 1 ] && echo "• Gestionnaire d’appareil détecté (type: $OWNER_TYPE)."
[ "$SUSPECTS_COUNT" -gt 0 ] && echo "• Applications suspectes: $SUSPECTS_COUNT" && head -n 5 "$SUSPECTS_FILE" | sed 's/^/   - /'

# --- Actions opérateur
echo
echo "=== Actions opérateur ==="
read -rp "Effectuer un backup probatoire ? [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]] && BACKUP="yes" || BACKUP="no"
read -rp "Générer un rapport blockchain (forensic) ? [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]] && BLOCK="yes" || BLOCK="no"
read -rp "Réinitialiser le téléphone (factory reset) ? [y/N] " ans; [[ "$ans" =~ ^[Yy]$ ]] && RESET="yes" || RESET="no"

echo "backup=$BACKUP" > "$DECISIONS_FILE"
echo "blockchain=$BLOCK" >> "$DECISIONS_FILE"
echo "reset=$RESET" >> "$DECISIONS_FILE"

# --- Backup probatoire
if [ "$BACKUP" = "yes" ]; then
  TAR="$REPORT_DIR/backup_probatoire_${RUN_TS}.tar.gz"
  tar -czf "$TAR" "$SUSPECTS_FILE" "$RAPPORT_FILE" 2>/dev/null
  sha256sum "$TAR" > "${TAR}.sha256"
  echo "[✓] Backup créé : $TAR"
fi

# --- Rapport blockchain
if [ "$BLOCK" = "yes" ]; then
  CHAIN_DIR="$REPORT_DIR/chain"; mkdir -p "$CHAIN_DIR"
  PREV_SHA_FILE="$CHAIN_DIR/last.sha256"
  PREV_SHA=$(cat "$PREV_SHA_FILE" 2>/dev/null || echo "GENESIS")
  CUR_SHA=$(sha256sum "$RAPPORT_FILE" | awk '{print $1}')
  BLOCK_FILE="$CHAIN_DIR/block_${RUN_TS}.json"
  printf '{\n  "ts":"%s",\n  "host":"%s",\n  "report":"%s",\n  "sha256":"%s",\n  "prev":"%s"\n}\n' "$RUN_TS" "$HOST" "$RAPPORT_FILE" "$CUR_SHA" "$PREV_SHA" > "$BLOCK_FILE"
  echo "$CUR_SHA" > "$PREV_SHA_FILE"
  sha256sum "$BLOCK_FILE" > "${BLOCK_FILE}.sha256"
  echo "[✓] Bloc forensic ajouté : $BLOCK_FILE"
fi

# --- Recommandations
echo
echo "=== Recommandations (résumé humain) ==="
if [ "$HAS_NOTIF" = "on" ]; then
  echo "• L’accès aux notifications est actif — peut exposer vos messages."
  echo "  → Désactiver : Paramètres > Applications > Accès spéciaux > Notifications."
fi
if [ "$HAS_ACC" = "on" ]; then
  echo "• Les services d’accessibilité sont actifs — peuvent contrôler l’écran ou lire le contenu."
  echo "  → Vérifier : Paramètres > Accessibilité."
fi
if [ "$OWNER_TYPE" = "enterprise" ]; then
  echo "• Appareil géré (MDM entreprise) — à vérifier avec le service IT avant toute action."
elif [ "$OWNER_TYPE" = "parental" ]; then
  echo "• Mode parental détecté — restrictions et apps cachées possibles."
fi
if [ "$SUSPECTS_COUNT" -gt 0 ]; then
  echo "• $SUSPECTS_COUNT applications suspectes détectées."
  echo "  → Recommandation : backup probatoire + suppression ou neutralisation."
fi

echo
if [ "$RISK" = "GREEN" ]; then
  echo "→ Risque faible : aucune anomalie détectée."
elif [ "$RISK" = "ORANGE" ]; then
  echo "→ Risque moyen : vérifier accès spéciaux et apps tierces suspectes."
else
  echo "→ Risque élevé : envisager sauvegarde probatoire + réinitialisation sécurisée."
fi

# --- Résumé technique (aperçu)
echo
echo "=== Résumé technique ==="
adb shell df -h /data | tail -n1
adb shell pm list packages -3 | wc -l | xargs echo "Apps tierces détectées :"
adb shell ip addr show wlan0 2>/dev/null | grep -E 'inet ' | awk '{print "Adresse IP : "$2}' || true
adb shell getprop ro.product.device 2>/dev/null | awk '{print "Device : "$1}'

# --- Ledger
SHA=$(sha256sum "$RAPPORT_FILE" | awk '{print $1}')
LEDGER="$LEDGER_DIR/inspections.csv"
[ ! -f "$LEDGER" ] && echo "date,host,model,android,patch,risk,sha256,report" > "$LEDGER"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$HOST,$MODEL,$ANDROID_VER,$PATCH,$RISK,$SHA,$RAPPORT_FILE" >> "$LEDGER"

END_S=$(date +%s)
ELAPSED=$((END_S - START_S))
echo
echo "=== Résumé opérateur (K0V3) ==="
echo "Modèle: $VENDOR / $MODEL | Android $ANDROID_VER ($PATCH)"
echo "Risque: $ICON $RISK — Éléments potentiellement intrusifs"
echo "--- Décisions opérateur ---"
cat "$DECISIONS_FILE"
echo "Rapport: $RAPPORT_FILE"
echo "Durée d’analyse: ${ELAPSED}s"
echo "[i] Ledger: $LEDGER"
echo "[i] Horodatage fin : $(date)"
echo "[+] === Fin Lab4Phone ANDROID-ONLY v3 ==="
