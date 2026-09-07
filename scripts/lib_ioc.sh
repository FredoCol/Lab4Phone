#!/usr/bin/env bash
# Lab4Phone IOC matching library
set -euo pipefail
IFS=$'\n\t'

[ -f "$HOME/.config/lab4phone.env" ] && . "$HOME/.config/lab4phone.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ioc_csv="${L4P_IOCS_DIR:-$PROJECT_ROOT/indicators}/indicators.csv"

require_file(){ [ -f "$1" ] || { echo "[!] Missing $1" >&2; return 1; }; }

IOC_CAT=(); IOC_TYPE=(); IOC_MATCH=(); IOC_VAL=(); IOC_SEV=(); IOC_NOTES=()
ioc_load(){
  require_file "$ioc_csv" || return 1
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # CSV simple sans guillemets
    local cat typ mch val sev nts
    cat=$(awk -F',' '{print $1}' <<<"$line")
    typ=$(awk -F',' '{print $2}' <<<"$line")
    mch=$(awk -F',' '{print $3}' <<<"$line")
    val=$(awk -F',' '{print $4}' <<<"$line")
    sev=$(awk -F',' '{print $5}' <<<"$line")
    nts=$(cut -d',' -f6- <<<"$line")
    IOC_CAT+=("$cat"); IOC_TYPE+=("$typ"); IOC_MATCH+=("$mch"); IOC_VAL+=("$val"); IOC_SEV+=("${sev:-0}"); IOC_NOTES+=("$nts")
  done < <(tail -n +2 "$ioc_csv")
}

ioc_match_android(){ # pkgs_file, out_csv
  local pkgs_file="$1" out="$2"
  : > "$out"; echo "package,category,type,match,value,severity,notes" >> "$out"
  sort -u "$pkgs_file" -o "$pkgs_file" 2>/dev/null || true
  while read -r p; do
    [ -z "${p:-}" ] && continue
    for i in "${!IOC_VAL[@]}"; do
      [ "${IOC_MATCH[$i]}" != "android" ] && continue
      case "${IOC_TYPE[$i]}" in
        package) [ "$p" = "${IOC_VAL[$i]}" ] && echo "$p,${IOC_CAT[$i]},package,android,${IOC_VAL[$i]},${IOC_SEV[$i]},${IOC_NOTES[$i]}" >> "$out" ;;
        pattern) printf "%s" "$p" | grep -Eiq -- "${IOC_VAL[$i]}" && echo "$p,${IOC_CAT[$i]},pattern,android,${IOC_VAL[$i]},${IOC_SEV[$i]},${IOC_NOTES[$i]}" >> "$out" ;;
      esac
    done
  done < "$pkgs_file"
}

ioc_match_ios(){ # ios_list, out_csv
  local ios_list="$1" out="$2"
  : > "$out"; echo "bundle_or_name,category,type,match,value,severity,notes" >> "$out"
  sort -u "$ios_list" -o "$ios_list" 2>/dev/null || true
  while read -r n; do
    [ -z "${n:-}" ] && continue
    for i in "${!IOC_VAL[@]}"; do
      [ "${IOC_MATCH[$i]}" != "ios" ] && continue
      printf "%s" "$n" | grep -Eiq -- "${IOC_VAL[$i]}" && \
        echo "$n,${IOC_CAT[$i]},${IOC_TYPE[$i]},ios,${IOC_VAL[$i]},${IOC_SEV[$i]},${IOC_NOTES[$i]}" >> "$out"
    done
  done < "$ios_list"
}

ioc_aggregate(){ # file
  awk -F',' 'NR>1{c[$2]++; s[$2]+=$6} END{for(k in c) printf "%s,%d,%d\n",k,c[k],s[k]}' "$1" | sort
}

ioc_score_to_level(){ # sum
  local sum="${1:-0}"
  if   [ "$sum" -ge 4 ]; then echo RED
  elif [ "$sum" -ge 1 ]; then echo ORANGE
  else echo GREEN
  fi
}
