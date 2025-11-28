#!/usr/bin/env bash
# Lab4Phone — IOS-ONLY v3.4-fix7c
# Usage:
#   ios [--offline] [--refresh-iocs] [--quick|--full] [--skip-mvt]
#       [--export-artifacts] [--evidence] [--full-inventory] [--max-apps N]
#       [--advice] [--dry-run] [--udid UDID] [--no-backup] [--enc-backup]
#       [--debug] [--interactive]
#
# Changements clés fix7c:
# - Vérif dépendances critiques (ideviceinfo / idevice_id / idevicepair)
# - mvt-ios check-backup: syntaxe corrigée (--output avant BACKUP_PATH)
# - L4P_IOS_BKPASS unset après usage (meilleure hygiène)
# - sqlite3 Manifest.db: -noheader pour inventaire apps plus propre

set -euo pipefail
IFS=$'\n\t'

# ===================== CONFIG =====================
[ -f "$HOME/.config/lab4phone.env" ] && . "$HOME/.config/lab4phone.env"
HOST="$(hostname | tr -d ' ')"
KIT_NAME="${KIT_NAME:-$HOST}"

detect_ssd_base(){
  if [ -n "${L4P_BASE_SSD:-}" ] && [ -d "$L4P_BASE_SSD" ]; then printf "%s" "$L4P_BASE_SSD"; return; fi
  [ -d /media/ssd/Lab4Phone ] && { printf "%s" "/media/ssd/Lab4Phone"; return; }
  for d in /media/*/Lab4Phone /media/*/*/Lab4Phone; do
    [ -d "$d" ] || continue
    case "$d" in */ssd/*) continue;; esac
    printf "%s" "$d"; return
  done
  printf "%s" "$HOME/Lab4Phone"
}
SSD_BASE="$(detect_ssd_base)"

REPORT_DIR="${L4P_REPORT_DIR:-$SSD_BASE/reports}/$HOST"
BACKUP_ROOT="${L4P_BACKUP_DIR:-$SSD_BASE/backups}/$HOST"
LOG_DIR="${L4P_LOG_DIR:-$SSD_BASE/logs}/$HOST"

detect_tools_dir(){
  if [ -n "${L4P_TOOLS_DIR:-}" ] && [ -d "$L4P_TOOLS_DIR" ]; then printf "%s" "$L4P_TOOLS_DIR"; return; fi
  for root in /media/* /media/*/*; do
    [ -d "$root/Lab4Phone/tools" ] || continue
    case "$root" in */ssd|*/ssd/*) continue;; esac
    printf "%s" "$root/Lab4Phone/tools"; return
  done
  printf "%s" "$HOME/Lab4Phone/tools"
}
TOOLS_DIR="$(detect_tools_dir)"
IOCS_DIR="${L4P_IOCS_DIR:-$TOOLS_DIR/iocs}"

mkdir -p "$REPORT_DIR" "$BACKUP_ROOT" "$LOG_DIR" "$IOCS_DIR" >/dev/null 2>&1 || true

# ===================== PARAMS & FLAGS =====================
FORCE_OFFLINE=0; REFRESH_IOCS="${REFRESH_IOCS:-0}"; QUICK=1; FULL=0; SKIP_MVT=0
EXPORT_ART=0; EVIDENCE=0; FULL_INV=0; MAX_APPS=600; ADVICE=0; DRY_RUN=0
TARGET_UDID=""; NO_BACKUP=0; ENC_BACKUP=0; DEBUG=0; INTERACTIVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --offline) FORCE_OFFLINE=1;;
    --refresh-iocs) REFRESH_IOCS=1;;
    --quick) QUICK=1; FULL=0;;
    --full) FULL=1; QUICK=0;;
    --skip-mvt) SKIP_MVT=1;;
    --export-artifacts) EXPORT_ART=1;;
    --evidence) EVIDENCE=1;;
    --full-inventory) FULL_INV=1;;
    --max-apps) shift; MAX_APPS="${1:-600}";;
    --advice) ADVICE=1;;
    --dry-run) DRY_RUN=1;;
    --udid) shift; TARGET_UDID="${1:-}";;
    --no-backup) NO_BACKUP=1;;
    --enc-backup) ENC_BACKUP=1;;
    --debug) DEBUG=1;;
    --interactive) INTERACTIVE=1;;
    --help|-h)
      cat <<EOF
Usage: $0 [options]
  --offline, --refresh-iocs, --quick|--full, --skip-mvt, --no-backup
  --enc-backup (utilise L4P_IOS_BKPASS), --export-artifacts, --evidence
  --full-inventory, --max-apps N, --udid UDID, --advice, --dry-run, --debug
  --interactive  Active un mini-assistant (backup ? quick/full ? chiffré ?)
EOF
      exit 0;;
    *) echo "[i] Arg ignoré: $1";;
  esac; shift || true
done

# ===== Helpers interaction =====
ask_yesno() {
  local q="$1"; local def="${2:-y}"; local prompt="[y/N]"
  [ "$def" = "y" ] && prompt="[Y/n]"
  while true; do
    read -r -p "$q $prompt " ans || return 1
    ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
    [ -z "$ans" ] && ans="$def"
    case "$ans" in y|yes) return 0;; n|no) return 1;; esac
    echo "→ Réponds y/n"
  done
}
ask_secret() { local p="$1"; local v; read -r -s -p "$p " v; echo; printf '%s' "$v"; }

# ===================== LOGGING =====================
ts(){ date +%F_%H%M%S; }
hms(){ local s=${1:-0}; printf "%02dh%02dm%02ds" $((s/3600)) $(((s%3600)/60)) $((s%60)); }
START_TS="$(date +%s)"; RUN_TS="$(ts)"

RAPPORT_FILE="$REPORT_DIR/rapport_lab4phone_ios_${RUN_TS}.txt"
CSV="$REPORT_DIR/summary_${RUN_TS}.csv"
JSON="$REPORT_DIR/summary_${RUN_TS}.json"
APPS_CSV="$REPORT_DIR/apps_ios_${RUN_TS}.csv"
APPS_JSON="$REPORT_DIR/apps_ios_${RUN_TS}.json"
LOGFILE="$LOG_DIR/ios_${RUN_TS}.log"
SUSPECTS_FILE="$REPORT_DIR/suspects_${RUN_TS}.txt"

exec > >(tee -a "$LOGFILE") 2>&1

log(){ printf "%s\n" "$*" | tee -a "$RAPPORT_FILE"; }
run(){ "$@"; rc=$?; [ $rc -ne 0 ] && echo "[!] RC=$rc : $*" >> "$LOGFILE"; return $rc; }

# ===================== Dépendances critiques =====================
check_critical_deps() {
  local dep missing=0
  for dep in ideviceinfo idevice_id idevicepair; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "[!] DÉPENDANCE MANQUANTE: $dep — communication iOS potentiellement limitée."
      missing=1
    fi
  done
  return $missing
}

echo "[+] === Lab4Phone IOS-ONLY v3.4-fix7c ==="
log "[+] Début : $(date '+%F %T')"
echo "[i] TOOLS_DIR=$TOOLS_DIR"
echo "[i] REPORT_DIR=$REPORT_DIR"
echo "[i] BACKUP_ROOT=$BACKUP_ROOT"; echo

if ! check_critical_deps; then
  echo "[!] Attention: certaines dépendances critiques manquent. Le run peut être dégradé."
fi

MODE_TXT="EN LIGNE"
if [ "$FORCE_OFFLINE" -eq 1 ]; then
  MODE_TXT="HORS-LIGNE"
else
  ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || MODE_TXT="HORS-LIGNE"
fi
echo "[i] Mode réseau : $MODE_TXT"

# IOC refresh (optionnel)
if [ "$REFRESH_IOCS" -eq 1 ]; then
  echo "[*] Mise à jour des indicateurs…"
  run "$HOME/Lab4Phone/scripts/update_indicators_fetch.sh" || echo "[!] update_indicators_fetch.sh a échoué (on continue local)"
fi

echo "[i] Dépendances: usbmuxd, ideviceinfo, idevice_id, idevicepair, ideviceinstaller (opt), mvt-ios (opt), sqlite3 (opt)"
echo
run sudo systemctl start usbmuxd >/dev/null 2>&1 || true

# ===================== CONNEXION / UDID =====================
IOS_READY=0; IOS_UDID=""
sel_udid(){
  local want="${1:-}"
  if [ -n "$want" ]; then
    if idevice_id -l 2>/dev/null | grep -Fxq "$want"; then echo "$want"; return 0; else return 1; fi
  fi
  idevice_id -l 2>/dev/null | head -n1
}

DEVICE_KIND="iOS"; PRODUCT_TYPE=""; PRODUCT_VER=""; NAME=""; TOTAL_H=""; FREE_H=""
IOS_APPS="0"; IOS_APPS_USER="0"; IOS_APPS_SYSTEM="0"
BACKUP_DIR=""; MVT_OUT=""; BACKUP_DONE=0; BACKUP_DIR_ACTUAL=""

# debug folder if requested
if [ "$DEBUG" -eq 1 ]; then
  DEBUG_DIR="/tmp/l4p_debug_${RUN_TS}"
  mkdir -p "$DEBUG_DIR"
  log "[i] DEBUG enabled -> $DEBUG_DIR"
fi

for t in $(seq 1 60); do
  IOS_UDID="$(sel_udid "$TARGET_UDID" || true)"
  if [ -n "$IOS_UDID" ]; then
    if run idevicepair validate >/dev/null 2>&1; then
      IOS_READY=1
      break
    else
      echo "[iOS] Déverrouille & 'Faire confiance'…"
      run idevicepair pair >/dev/null 2>&1 || true
    fi
  fi
  sleep 1
done

if [ "$IOS_READY" -eq 1 ]; then
  PRODUCT_TYPE="$(run ideviceinfo -k ProductType 2>/dev/null || true)"
  PRODUCT_VER="$(run ideviceinfo -k ProductVersion 2>/dev/null || true)"
  NAME="$(run ideviceinfo -k DeviceName 2>/dev/null || true)"
  case "$PRODUCT_TYPE" in
    iPad*) DEVICE_KIND="iPad";;
    iPhone*) DEVICE_KIND="iPhone";;
    iPod*) DEVICE_KIND="iPod";;
  esac
  log "[iOS] Appairé: $IOS_UDID  (${DEVICE_KIND} ${PRODUCT_TYPE} ; iOS ${PRODUCT_VER})"
  [ -n "$NAME" ] && log "[iOS] Nom: $NAME"

  TOTAL_B=$(run ideviceinfo -q com.apple.disk_usage 2>/dev/null | awk -F': ' '/TotalDiskCapacity/{print $2}')
  FREE_B=$(run  ideviceinfo -q com.apple.disk_usage 2>/dev/null | awk -F': ' '/FreeDiskCapacity/{print $2}')
  if [ -n "${TOTAL_B:-}" ] && [ -n "${FREE_B:-}" ]; then
    TOTAL_H=$(numfmt --to=iec --suffix=B "$TOTAL_B" 2>/dev/null || echo "${TOTAL_B}B")
    FREE_H=$(numfmt  --to=iec --suffix=B "$FREE_B" 2>/dev/null || echo "${FREE_B}B")
    log "[iOS] Stockage: total=$TOTAL_H, libre=$FREE_H"
  fi

  # Listing d’apps via ideviceinstaller (optionnel)
  if command -v ideviceinstaller >/dev/null 2>&1; then
    UTXT="/tmp/ios_user_${RUN_TS}.txt"; STXT="/tmp/ios_sys_${RUN_TS}.txt"
    run ideviceinstaller -u "$IOS_UDID" -l -o list_user   2>/dev/null | sed 's/ - /|/g' > "$UTXT" || true
    run ideviceinstaller -u "$IOS_UDID" -l -o list_system 2>/dev/null | sed 's/ - /|/g' > "$STXT" || true
    [ "$DEBUG" -eq 1 ] && cp -f "$UTXT" "$DEBUG_DIR/ideviceinstaller_user_${RUN_TS}.txt" 2>/dev/null || true
    [ "$DEBUG" -eq 1 ] && cp -f "$STXT" "$DEBUG_DIR/ideviceinstaller_sys_${RUN_TS}.txt" 2>/dev/null || true
    IOS_APPS_USER="$(wc -l < "$UTXT" 2>/dev/null | tr -d '[:space:]' || echo 0)"; : "${IOS_APPS_USER:=0}"
    IOS_APPS_SYSTEM="$(wc -l < "$STXT" 2>/dev/null | tr -d '[:space:]' || echo 0)"; : "${IOS_APPS_SYSTEM:=0}"
    IOS_APPS_USER="${IOS_APPS_USER//[^0-9]/}"; IOS_APPS_SYSTEM="${IOS_APPS_SYSTEM//[^0-9]/}"
    [ -z "$IOS_APPS_USER" ] && IOS_APPS_USER=0
    [ -z "$IOS_APPS_SYSTEM" ] && IOS_APPS_SYSTEM=0
    IOS_APPS=$(( IOS_APPS_USER + IOS_APPS_SYSTEM ))
    log "[iOS] Applications: total=${IOS_APPS} (user=${IOS_APPS_USER}; système=${IOS_APPS_SYSTEM})"
  else
    log "[iOS] ideviceinstaller absent → inventaire sommaire only."
  fi

  # ========== Mode interactif ==========
  if [ "$INTERACTIVE" -eq 1 ] && [ -t 0 ]; then
    echo
    if ! ask_yesno "→ Lancer un backup + analyse MVT maintenant ?" y; then
      NO_BACKUP=1; SKIP_MVT=1
      echo "[i] OK, pas de backup ni d'analyse sur ce run."
    else
      if ask_yesno "→ Type de backup : complet ? (sinon flash)" n; then
        FULL=1; QUICK=0
      else
        FULL=0; QUICK=1
      fi
      if ask_yesno "→ Chiffrer le backup iOS ?" n; then
        ENC_BACKUP=1
        if [ -z "${L4P_IOS_BKPASS:-}" ]; then
          L4P_IOS_BKPASS="$(ask_secret '   Mot de passe (non affiché) :')"
          export L4P_IOS_BKPASS
        fi
      fi
    fi
    echo
  fi

  # Backup + MVT
  BACKUP_DIR="$BACKUP_ROOT/ios_${RUN_TS}$([ $FULL -eq 1 ] && echo '_full' || echo '_flash')"
  MVT_OUT="$REPORT_DIR/mvt_${RUN_TS}"
  mkdir -p "$BACKUP_DIR" "$MVT_OUT"

  if [ $DRY_RUN -eq 1 ] || [ $SKIP_MVT -eq 1 ] || [ $NO_BACKUP -eq 1 ]; then
    echo "[DRY/SKIP] Backup MVT sauté (dry/skip/no-backup)."
  else
    if command -v mvt-ios >/dev/null 2>&1; then
      BK_ARGS=(--output "$BACKUP_DIR")
      [ $FULL -eq 1 ] && BK_ARGS=(--full --output "$BACKUP_DIR")
      if [ $ENC_BACKUP -eq 1 ]; then
        if [ -n "${L4P_IOS_BKPASS:-}" ]; then
          BK_ARGS+=("--password" "$L4P_IOS_BKPASS")
        else
          echo "[!] --enc-backup demandé mais L4P_IOS_BKPASS vide. Backup non chiffré."
        fi
      fi
      echo "[i] mvt-ios backup…"
      if run mvt-ios backup "${BK_ARGS[@]}"; then
        echo "[i] mvt-ios backup OK"
      else
        echo "[i] mvt-ios backup non disponible/échoué ; tentative idevicebackup2 (fallback)"
        if command -v idevicebackup2 >/dev/null 2>&1; then
          echo "[i] idevicebackup2 backup vers $BACKUP_DIR"
          mkdir -p "$BACKUP_DIR/itunes/$IOS_UDID"
          if [ $FULL -eq 1 ]; then
            stdbuf -oL -eL idevicebackup2 -u "$IOS_UDID" backup --full "$BACKUP_DIR/itunes/$IOS_UDID" 2>&1 | tee -a "$LOGFILE" || true
          else
            stdbuf -oL -eL idevicebackup2 -u "$IOS_UDID" backup "$BACKUP_DIR/itunes/$IOS_UDID" 2>&1 | tee -a "$LOGFILE" || true
          fi
        else
          echo "[!] Aucun moyen de backup disponible (mvt-ios et idevicebackup2 manquants/échoués)."
        fi
      fi

      # Chemin réel du backup
      if [ -d "$BACKUP_DIR/itunes/$IOS_UDID" ]; then
        BACKUP_DIR_ACTUAL="$BACKUP_DIR/itunes/$IOS_UDID"
      elif [ -d "$BACKUP_DIR/$IOS_UDID" ]; then
        BACKUP_DIR_ACTUAL="$BACKUP_DIR/$IOS_UDID"
      else
        BACKUP_DIR_ACTUAL="$BACKUP_DIR"
      fi

      # Sanity backup
      BK_FILES=$(find "$BACKUP_DIR_ACTUAL" -type f 2>/dev/null | wc -l | tr -d "[:space:]" || echo 0)
      BK_SZ=$(du -sh "$BACKUP_DIR_ACTUAL" 2>/dev/null | awk '{print $1}' || echo "?")
      if [ -z "$BK_FILES" ] || [ "$BK_FILES" = "0" ]; then
        echo "[!] Alerte: backup vide (interruption ? mdp requis ?)."
      else
        echo "[i] Backup OK: $BK_FILES fichiers (~$BK_SZ) → $BACKUP_DIR_ACTUAL"
      fi

      # mvt-ios check-backup (analyse backup)
      echo "[i] mvt-ios check-backup --output \"$MVT_OUT\" \"$BACKUP_DIR_ACTUAL\""
      if mvt-ios check-backup --output "$MVT_OUT" "$BACKUP_DIR_ACTUAL" >/dev/null 2>&1; then
        echo "[i] mvt-ios check-backup ✅"
      else
        echo "[i] mvt-ios check-backup --output a échoué, essai sans --output"
        if mvt-ios check-backup "$BACKUP_DIR_ACTUAL" >/dev/null 2>&1; then
          echo "[i] mvt-ios check-backup (sans --output) ✅"
        else
          echo "[!] mvt-ios check-backup a échoué. Vérifie version/chemins."
        fi
      fi

      BACKUP_DONE=1
    else
      echo "[i] MVT indisponible → backup MVT sauté."
    fi
  fi

  # On nettoie le mot de passe de backup de l'environnement (hygiène)
  if [ $ENC_BACKUP -eq 1 ] && [ -n "${L4P_IOS_BKPASS:-}" ]; then
    unset L4P_IOS_BKPASS || true
  fi

  # Fallback apps depuis Manifest.db si inventaire vide
  if [ "$IOS_APPS_USER" -eq 0 ] && [ "$IOS_APPS_SYSTEM" -eq 0 ]; then
    MANIFEST_DB_CAND=""
    if [ -n "$BACKUP_DIR_ACTUAL" ] && [ -f "$BACKUP_DIR_ACTUAL/Manifest.db" ]; then
      MANIFEST_DB_CAND="$BACKUP_DIR_ACTUAL/Manifest.db"
    elif [ -n "$BACKUP_DIR_ACTUAL" ]; then
      MANIFEST_DB_CAND="$(find "$BACKUP_DIR_ACTUAL" -maxdepth 2 -type f -name 'Manifest.db' -print -quit 2>/dev/null || true)"
    fi

    if [ -n "$MANIFEST_DB_CAND" ] && [ -f "$MANIFEST_DB_CAND" ]; then
      log "[i] Fallback: extraction apps depuis Manifest.db -> $MANIFEST_DB_CAND"
      if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 -noheader "$MANIFEST_DB_CAND" \
"SELECT DISTINCT substr(domain, 11) AS bundle
   FROM Files
  WHERE domain GLOB 'AppDomain-*'
  ORDER BY bundle
  LIMIT $MAX_APPS;" > /tmp/ios_manifest_apps_${RUN_TS}.txt 2>/dev/null || true

        [ "$DEBUG" -eq 1 ] && cp -f /tmp/ios_manifest_apps_${RUN_TS}.txt "$DEBUG_DIR/manifest_apps_${RUN_TS}.txt" 2>/dev/null || true

        MANIFEST_APP_COUNT=$(wc -l < /tmp/ios_manifest_apps_${RUN_TS}.txt 2>/dev/null | tr -d '[:space:]' || echo 0)
        MANIFEST_APP_COUNT="${MANIFEST_APP_COUNT//[^0-9]/}"; [ -z "$MANIFEST_APP_COUNT" ] && MANIFEST_APP_COUNT=0
        if [ "$MANIFEST_APP_COUNT" -gt 0 ]; then
          IOS_APPS_USER="$MANIFEST_APP_COUNT"; IOS_APPS_SYSTEM=0
          IOS_APPS=$(( IOS_APPS_USER + IOS_APPS_SYSTEM ))
          log "[i] Apps (fallback Manifest.db): total=${IOS_APPS} (user=${IOS_APPS_USER}; système=${IOS_APPS_SYSTEM})"
          if [ "$FULL_INV" -eq 1 ]; then
            awk 'BEGIN{print "bundle"}{print $0}' /tmp/ios_manifest_apps_${RUN_TS}.txt > "$APPS_CSV" 2>/dev/null || true
            printf '{"bundles":[' > "$APPS_JSON"
            awk 'BEGIN{first=1} {gsub(/"/,"\\\""); if(!first) printf ","; printf "\"%s\"", $0; first=0} END{print "]"}' \
              /tmp/ios_manifest_apps_${RUN_TS}.txt >> "$APPS_JSON"
            echo "}" >> "$APPS_JSON"
            log "[+] Inventaire apps (fallback) : $APPS_CSV ; $APPS_JSON"
          fi
        else
          log "[i] Aucun bundle app trouvé dans Manifest.db"
        fi
      else
        log "[!] sqlite3 absent → impossible d'extraire apps depuis Manifest.db"
      fi
    else
      log "[i] Manifest.db introuvable dans le backup (chemin: ${BACKUP_DIR_ACTUAL:-?}) — backup incomplet ?"
    fi
  fi

else
  log "[iOS] Aucun appareil détecté/appairé."
fi

# ===================== IOC iOS (fichiers/domaines) =====================
: > "$SUSPECTS_FILE"
TMP_FILES="$(mktemp)"; TMP_DOMS="$(mktemp)"; TMP_ANY="$(mktemp)"

# Listes locales d'IOCs fichiers (parental, dual-use, spyware)
{
  cat "$IOCS_DIR/indicators_ios_parental.txt" 2>/dev/null
  cat "$IOCS_DIR/indicators_ios_enterprise_dualuse.txt" 2>/dev/null
  cat "$HOME/Lab4Phone/indicators/spyware_ios.txt" 2>/dev/null
} | sed '/^\s*#/d;/^\s*$/d' | sort -u > "$TMP_FILES" || true

# Placeholder pour IOC de domaines (futurs fichiers: indicators_ios_domains.txt, etc.)
: > "$TMP_DOMS"

if [ -n "$BACKUP_DIR_ACTUAL" ] && [ -d "$BACKUP_DIR_ACTUAL" ] && [ -s "$TMP_FILES" ]; then
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    lit=$(printf '%s' "$pat" | sed 's/[][*?]/\\&/g')
    if find "$BACKUP_DIR_ACTUAL" -type f -iname "*${lit}*" -print -quit >/dev/null 2>&1; then
      echo "ios:file:${pat}" >> "$SUSPECTS_FILE"
    fi
  done < "$TMP_FILES"
fi

if [ -n "${MVT_OUT:-}" ] && [ -d "$MVT_OUT" ]; then
  find "$MVT_OUT" -maxdepth 2 -type f \( -name "*.txt" -o -name "*.log" -o -name "*.json" \) -print0 2>/dev/null \
    | xargs -0 -r cat > "$TMP_ANY" || true
  if [ -s "$TMP_DOMS" ] && [ -s "$TMP_ANY" ]; then
    while IFS= read -r dom; do
      [ -z "$dom" ] && continue
      grep -Eiq "$dom" "$TMP_ANY" && echo "ios:domain:${dom}" >> "$SUSPECTS_FILE"
    done < "$TMP_DOMS"
  fi
fi

sort -u -o "$SUSPECTS_FILE" "$SUSPECTS_FILE" || true
SUSPECTS_COUNT=$( [ -s "$SUSPECTS_FILE" ] && wc -l < "$SUSPECTS_FILE" | tr -d ' ' || echo 0 )

# ===================== Évaluation du risque (réel) =====================
has_real_mvt_hits(){
  [ -d "${MVT_OUT:-}" ] || return 1
  find "$MVT_OUT" -type f -iname '*detections*.json' -size +2c | grep -q . && return 0
  grep -Riq '"matched"[[:space:]]*:[[:space:]]*true' "$MVT_OUT" && return 0
  grep -Riq '^\[ALERT\]' "$MVT_OUT" && return 0
  return 1
}

if has_real_mvt_hits; then
  RISK_LEVEL="RED"; RISK_ICON="🔴"; RISK_MSG="Indicateurs mercenaires CRITIQUES détectés."
elif [ "$SUSPECTS_COUNT" -gt 0 ]; then
  RISK_LEVEL="ORANGE"; RISK_ICON="🟠"; RISK_MSG="Éléments suspects détectés (IOC fichiers/domaines)."
else
  RISK_LEVEL="GREEN"; RISK_ICON="🟢"; RISK_MSG="Aucun élément notable."
fi

paint_risk(){
  case "$1" in
    GREEN)  printf "🟢 GREEN";;
    ORANGE) printf "🟠 ORANGE";;
    RED)    printf "🔴 RED";;
    *)      printf "%s" "$1";;
  esac
}

# ===================== Coffre probatoire =====================
evidence_vault_pack(){
  case "$RISK_LEVEL" in ORANGE|RED) : ;; *) echo "[i] Pas de coffre (risk=$RISK_LEVEL)."; return 0;; esac
  local VAULT_DIR="$BACKUP_ROOT/vault_${RUN_TS}"
  local TAR="$VAULT_DIR/vault_${RUN_TS}.tar.gz"
  local MANIFEST="$VAULT_DIR/manifest_${RUN_TS}.json"
  local SUMS="$VAULT_DIR/SHA256SUMS.txt"
  mkdir -p "$VAULT_DIR"
  cp -a "$RAPPORT_FILE" "$CSV" "$JSON" "$LOGFILE" "$SUSPECTS_FILE" 2>/dev/null || true
  [ -d "$MVT_OUT" ] && cp -a "$MVT_OUT" "$VAULT_DIR/" 2>/dev/null || true
  cat > "$MANIFEST" <<EOF
{"host":"$HOST","kit":"$KIT_NAME","run_ts":"$RUN_TS","mode":"$MODE_TXT",
 "ios":{"device_kind":"${DEVICE_KIND:-}","product_type":"${PRODUCT_TYPE:-}","version":"${PRODUCT_VER:-}"},
 "risk":{"level":"$RISK_LEVEL","msg":"$RISK_MSG"},
 "paths":{"report":"$RAPPORT_FILE","csv":"$CSV","json":"$JSON","log":"$LOGFILE","suspects":"$SUSPECTS_FILE","mvt":"$MVT_OUT"}}
EOF
  (cd "$VAULT_DIR/.." && tar -czf "$TAR" "$(basename "$VAULT_DIR")")
  (cd "$VAULT_DIR" && find . -type f -print0 | xargs -0 sha256sum > "$SUMS")
  VAULT_HASH=$(sha256sum "$TAR" | awk '{print $1}'); echo "$VAULT_HASH" > "$VAULT_DIR/ANCHOR_READY_SHA256.txt"
  log "[+] Coffre probatoire: $VAULT_DIR"
  log "[+] Archive: $TAR"
  log "[+] SHA256 (archive): $VAULT_HASH"
  log "[i] Conserver ANCHOR_READY_SHA256.txt pour ancrage horodaté ultérieur."
}

# ===================== Rapport (humain) =====================
log
log "=== Résumé exécutif (iOS) — opérateur ==="
if [ "$IOS_READY" -eq 1 ]; then
  log "• Appareil : ${DEVICE_KIND} — ${PRODUCT_TYPE:-?} (iOS ${PRODUCT_VER:-?})"
  [ -n "${TOTAL_H:-}" ] && log "• Stockage : total=${TOTAL_H:-?}, libre=${FREE_H:-?}"
  log "• Apps     : total=${IOS_APPS:-0} | user=${IOS_APPS_USER:-0} | système=${IOS_APPS_SYSTEM:-0}"
else
  log "• Appareil : (aucun iPhone/iPad appairé)"
fi
log "• IOC      : ${SUSPECTS_COUNT} hit(s)"
log "• Risque   : $(paint_risk "$RISK_LEVEL") — ${RISK_MSG}"

if [ "${RISK_LEVEL:-GREEN}" != "GREEN" ]; then
  log
  log "=== Recommandations immédiates ==="
  if [ $BACKUP_DONE -eq 0 ]; then
    log "1) Backup chiffré conseillé :"
    log "   - export L4P_IOS_BKPASS='******'"
    log "   - ios --enc-backup $([ $FULL -eq 1 ] && echo --full || echo --quick)"
  else
    log "1) Backup : fait."
  fi
  log "2) Coffre probatoire : ios --evidence (archive + manifeste + SHA256)."
  log "3) Remédiation : iOS → Réglages > Général > Stockage iPhone > <App> > Supprimer."
  [ "$EVIDENCE" -eq 1 ] && evidence_vault_pack
fi

# ===================== CSV / JSON =====================
{
  echo "host,date,kit,platform,device_kind,product_type,ios_version,apps_total,apps_user,apps_system,storage_total,storage_free,mode,suspects,risk"
  echo "${HOST},${RUN_TS},${KIT_NAME},iOS,${DEVICE_KIND:-},${PRODUCT_TYPE:-},${PRODUCT_VER:-},${IOS_APPS:-0},${IOS_APPS_USER:-0},${IOS_APPS_SYSTEM:-0},${TOTAL_H:-},${FREE_H:-},${MODE_TXT},${SUSPECTS_COUNT:-0},${RISK_LEVEL}"
} > "$CSV" 2>/dev/null || true
log "[+] Résumé CSV : $CSV"

# suspects JSON sûr
SUS_JSON="[]"
if [ -s "$SUSPECTS_FILE" ]; then
  SUS_JSON="["
  sep=""
  while IFS= read -r ln; do
    esc=${ln//\"/\\\"}
    SUS_JSON="${SUS_JSON}${sep}\"$esc\""
    sep=","
  done < "$SUSPECTS_FILE"
  SUS_JSON="${SUS_JSON}]"
fi

cat > "$JSON" <<EOF
{"host":"$HOST","kit":"$KIT_NAME","run_ts":"$RUN_TS","mode":"$MODE_TXT",
 "ios":{"ready":$([ "$IOS_READY" -eq 1 ] && echo true || echo false),
        "device_kind":"${DEVICE_KIND:-}","product_type":"${PRODUCT_TYPE:-}","version":"${PRODUCT_VER:-}","name":"${NAME:-}",
        "apps_total":${IOS_APPS:-0},"apps_user":${IOS_APPS_USER:-0},"apps_system":${IOS_APPS_SYSTEM:-0},
        "storage_total":"${TOTAL_H:-}","storage_free":"${FREE_H:-}","backup_dir":"${BACKUP_DIR_ACTUAL:-}"},
 "risk":{"level":"$RISK_LEVEL","icon":"$RISK_ICON","msg":"$RISK_MSG"},
 "suspects": ${SUS_JSON} }
EOF

# Export artefacts (rapport + CSV/JSON + MVT)
if [ "$EXPORT_ART" -eq 1 ]; then
  TAR="$REPORT_DIR/run_ios_${RUN_TS}.tar.gz"
  echo "[*] Export artefacts → $TAR"
  tar -czf "$TAR" -C "$REPORT_DIR" "$(basename "$RAPPORT_FILE")" "$(basename "$CSV")" "$(basename "$JSON")" 2>/dev/null || true
  [ -d "$MVT_OUT" ] && tar -rzf "$TAR" -C "$REPORT_DIR" "$(basename "$MVT_OUT")" 2>/dev/null || true
  echo "[i] (Backup iOS non inclus par défaut — volumineux)"
fi

# Conseils (optionnels)
if [ "$ADVICE" -eq 1 ]; then
  echo
  echo "[Conseils iOS] Réglages > Général > Stockage iPhone > <App> > Supprimer."
  echo "Profils : Réglages > Général > VPN et gestion de l’appareil (supprimer profils non légitimes)."
  echo "Centre de contrôle : retirer ‘Enregistrement de l’écran’ si abus."
fi

# Sortie console
END_TS="$(date +%s)"; ELAPSED=$((END_TS-START_TS))
echo
echo "=== Résumé opérateur (iOS-only v3.4-fix7c) ==="
echo "Modèle: ${DEVICE_KIND:-?} ${PRODUCT_TYPE:-?} | iOS ${PRODUCT_VER:-?}"
[ -n "${TOTAL_H:-}" ] && echo "Stockage: total=${TOTAL_H:-?}, libre=${FREE_H:-?}"
echo "Apps: total=${IOS_APPS:-0} | user=${IOS_APPS_USER:-0} | système=${IOS_APPS_SYSTEM:-0}"
echo "Suspects=${SUSPECTS_COUNT} | Risque=$(paint_risk "$RISK_LEVEL") — ${RISK_MSG}"
echo "Rapport: ${RAPPORT_FILE}"
echo "==============================================="; echo

log "[+] Fin : $(date '+%F %T')"
log "[+] Durée : $(hms $ELAPSED)"
ln -sfn "$RAPPORT_FILE" "$REPORT_DIR/latest_ios.txt" 2>/dev/null || true
echo "[+] === Fin Lab4Phone IOS-ONLY v3.4-fix7c ==="
