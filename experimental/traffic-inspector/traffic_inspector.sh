#!/bin/bash
#
# ==========================================================
#  LAB4PHONE TRAFFIC INSPECTOR — projet Sombra
#  Version : 0.5-dev
# ==========================================================

VERSION="0.5-dev"

BASE="${L4P_TRAFFIC_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/lab4phone/traffic_inspector}"
CAPTURES="$BASE/captures"
REPORTS="$BASE/reports"
TMP="$BASE/tmp"
CLASSIF="$BASE/classification"
IOC_BASE="$BASE/iocs/processed"
IOC_DOMAINS="$IOC_BASE/domains.txt"
IOC_IPS="$IOC_BASE/ips.txt"
IOC_URLS="$IOC_BASE/urls.txt"
IOC_C2="$IOC_BASE/c2.txt"
IOC_TAGGED="$IOC_BASE/traffic_ioc_classified.csv"

SERVICES_FILE="$CLASSIF/services_connus.txt"
CDN_FILE="$CLASSIF/cdn.txt"
HOSTING_FILE="$CLASSIF/hebergeurs.txt"
VPN_FILE="$CLASSIF/vpn.txt"
TRACKING_FILE="$CLASSIF/tracking.txt"
IOT_FILE="$CLASSIF/iot.txt"
HOTSPOT_IF="wlan0"
WAN_IF="eth0"

HOTSPOT_SSID="Lab4Phone_Analyse"
HOTSPOT_IP="192.168.50.1"
HOTSPOT_CIDR="192.168.50.1/24"
DHCP_START="192.168.50.10"
DHCP_END="192.168.50.100"

HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
HOSTAPD_LOG="$TMP/hostapd.log"
HOSTAPD_PIDFILE="$TMP/hostapd.pid"

DNSMASQ_LOG="$TMP/dnsmasq.log"
DNSMASQ_PIDFILE="$TMP/dnsmasq.pid"
LEASE_FILE="$TMP/dnsmasq.leases"

CLIENT_IP=""
CLIENT_MAC=""
CLIENT_NAME=""
CLIENT_VENDOR=""

MODE="NOMADE"
INTERNET=0
DURATION=60
CLEANED=0
NM_WAS_ACTIVE=0

# Résumé opérateur
QUICK_DNS=0
QUICK_IPS=0
QUICK_UNKNOWN=0
QUICK_CRITICAL=0
QUICK_SPYWARE=0
QUICK_MALWARE=0
QUICK_VPN_DETECTED=0
QUICK_VPN_PROTOCOL=""
QUICK_VPN_ENDPOINT=""
QUICK_VPN_PORT=""
QUICK_VPN_PERCENT="0.00"
QUICK_DIRECT_IPS=0
QUICK_DURATION=""
QUICK_REPORT=""
ANALYSIS_ONLY=0
EXISTING_PCAP=""

mkdir -p "$CAPTURES" "$REPORTS" "$TMP"

#############################
# Nettoyage
#############################

stop_hotspot() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1

    echo
    echo "[10/10] Arrêt du hotspot..."

    if [ -f "$DNSMASQ_PIDFILE" ]; then
        sudo kill "$(cat "$DNSMASQ_PIDFILE")" 2>/dev/null || true
    fi

    if [ -f "$HOSTAPD_PIDFILE" ]; then
        sudo kill "$(cat "$HOSTAPD_PIDFILE")" 2>/dev/null || true
    fi

    sudo pkill -f "dnsmasq.*$LEASE_FILE" 2>/dev/null || true
    sudo nft delete table ip sombra_traffic 2>/dev/null || true

    sudo ip addr flush dev "$HOTSPOT_IF" 2>/dev/null || true
    sudo ip link set "$HOTSPOT_IF" down 2>/dev/null || true

    rm -f "$HOSTAPD_PIDFILE" "$DNSMASQ_PIDFILE"

    if [ "$NM_WAS_ACTIVE" -eq 1 ]; then
        sudo systemctl start NetworkManager 2>/dev/null || true
    fi

    echo "[OK] Hotspot arrêté."
}

trap stop_hotspot EXIT INT TERM

#############################
# Affichage
#############################

banner() {
    clear
    echo "=========================================="
    echo "     SOMBRA TRAFFIC INSPECTOR"
    echo "=========================================="
    echo "Version : $VERSION"
    echo
}

#############################
# Dépendances
#############################

check_dep() {
    local missing=0

    for bin in \
        tcpdump tshark timeout ip ping iw \
        hostapd dnsmasq nft geoiplookup whois sed od
    do
        if command -v "$bin" >/dev/null 2>&1; then
            printf "[ OK ] %-12s\n" "$bin"
        else
            printf "[ KO ] %-12s\n" "$bin"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        echo
        echo "[ERREUR] Une ou plusieurs dépendances sont absentes."
        exit 1
    fi

    [ -f "$HOSTAPD_CONF" ] || {
        echo "[ERREUR] $HOSTAPD_CONF introuvable."
        exit 1
    }
}

#############################
# Connectivité
#############################

check_internet() {
    echo
    echo "[1/10] Vérification de la connectivité..."

    if ip link show "$WAN_IF" >/dev/null 2>&1 &&
       ping -I "$WAN_IF" -c1 -W2 1.1.1.1 >/dev/null 2>&1
    then
        INTERNET=1
        MODE="CONNECTE"
    else
        INTERNET=0
        MODE="NOMADE"
    fi

    echo
    echo "=========================="
    echo " MODE D'ANALYSE"
    echo
    echo " Mode        : $MODE"
    echo " Internet    : $([ "$INTERNET" -eq 1 ] && echo Oui || echo Non)"
    echo " Capture     : Oui"
    echo " GeoIP       : $([ "$INTERNET" -eq 1 ] && echo Oui || echo Différé)"
    echo " WHOIS       : $([ "$INTERNET" -eq 1 ] && echo Oui || echo Différé)"
    echo "=========================="
}

#############################
# Mot de passe temporaire
#############################

generate_wifi_password() {

    WIFI_PASSWORD="$(openssl rand -hex 4)"

    sudo sed -i         "s/^wpa_passphrase=.*/wpa_passphrase=$WIFI_PASSWORD/"         "$HOSTAPD_CONF"
}

#############################
# Hotspot
#############################

start_hotspot() {
    echo
    echo "[2/10] Démarrage du hotspot..."

    generate_wifi_password

    if systemctl is-active --quiet NetworkManager; then
        NM_WAS_ACTIVE=1
        sudo systemctl stop NetworkManager
    fi

    sudo pkill hostapd 2>/dev/null || true
    sudo pkill dnsmasq 2>/dev/null || true
    sudo nft delete table ip sombra_traffic 2>/dev/null || true

    rm -f \
        "$HOSTAPD_LOG" "$DNSMASQ_LOG" \
        "$HOSTAPD_PIDFILE" "$DNSMASQ_PIDFILE" \
        "$LEASE_FILE"

    sudo ip link set "$HOTSPOT_IF" down 2>/dev/null || true
    sudo ip addr flush dev "$HOTSPOT_IF" 2>/dev/null || true
    sudo ip link set "$HOTSPOT_IF" up

    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null

    echo "[+] Activation de hostapd..."

    sudo hostapd \
        -B \
        -P "$HOSTAPD_PIDFILE" \
        -f "$HOSTAPD_LOG" \
        "$HOSTAPD_CONF"

    echo "[+] Attente activation du hotspot..."

HOTSPOT_OK=0

for i in $(seq 1 15); do

    if iw dev "$HOTSPOT_IF" info 2>/dev/null | grep -q "type AP"; then

        sudo ip addr flush dev "$HOTSPOT_IF"
        sudo ip addr add "$HOTSPOT_CIDR" dev "$HOTSPOT_IF"

        HOTSPOT_OK=1
        break

    fi

    sleep 1

done

if [ "$HOTSPOT_OK" -ne 1 ]; then

    echo
    echo "[ERREUR] Le hotspot ne s'est jamais mis en mode AP."
    echo

    echo "===== HOSTAPD ====="
    cat "$HOSTAPD_LOG" 2>/dev/null

    echo
    echo "===== IW ====="
    iw dev

    exit 1

fi

echo "[OK] Hotspot actif."

echo "[+] Activation du DHCP..."

    sudo dnsmasq \
        --conf-file=/dev/null \
        --interface="$HOTSPOT_IF" \
        --bind-interfaces \
        --dhcp-range="$DHCP_START,$DHCP_END,255.255.255.0,24h" \
        --dhcp-option="3,$HOTSPOT_IP" \
        --dhcp-option="6,$HOTSPOT_IP" \
        --dhcp-leasefile="$LEASE_FILE" \
        --pid-file="$DNSMASQ_PIDFILE" \
        --log-facility="$DNSMASQ_LOG"

    sleep 1

    if [ ! -f "$DNSMASQ_PIDFILE" ] ||
       ! sudo kill -0 "$(cat "$DNSMASQ_PIDFILE")" 2>/dev/null
    then
        echo "[ERREUR] dnsmasq n'a pas démarré."
        cat "$DNSMASQ_LOG" 2>/dev/null
        exit 1
    fi

    if [ "$INTERNET" -eq 1 ]; then
        echo "[+] Activation du partage Internet..."

        sudo nft add table ip sombra_traffic
        sudo nft \
            'add chain ip sombra_traffic postrouting { type nat hook postrouting priority srcnat; policy accept; }'
        sudo nft add rule ip sombra_traffic postrouting \
            oifname "$WAN_IF" masquerade

        sudo nft \
            'add chain ip sombra_traffic forward { type filter hook forward priority filter; policy accept; }'
    fi

    echo
    echo "=========================================="
    echo " HOTSPOT D'ANALYSE ACTIF"
    echo
    echo " SSID         : $HOTSPOT_SSID"
    echo " Mot de passe : $WIFI_PASSWORD"
    echo " Passerelle   : $HOTSPOT_IP"
    echo " Internet     : $([ "$INTERNET" -eq 1 ] && echo Oui || echo Non)"
    echo "=========================================="
}

#############################
# Détection du smartphone
#############################

wait_client() {
    echo
    echo "[3/10] En attente d'un smartphone..."
    echo "Connectez le téléphone au Wi-Fi $HOTSPOT_SSID."
    echo

    for _ in $(seq 1 180); do
        if [ -s "$LEASE_FILE" ]; then
            read -r _ CLIENT_MAC CLIENT_IP CLIENT_NAME _ \
                < <(tail -n 1 "$LEASE_FILE")

            [ "$CLIENT_NAME" = "*" ] && CLIENT_NAME="Smartphone"

            case "${CLIENT_NAME,,}" in
                *iphone*|*ipad*)
                    CLIENT_VENDOR="Apple"
                    ;;
                *xiaomi*|*redmi*|*poco*)
                    CLIENT_VENDOR="Xiaomi"
                    ;;
                *pixel*)
                    CLIENT_VENDOR="Google"
                    ;;
                *samsung*|*galaxy*)
                    CLIENT_VENDOR="Samsung"
                    ;;
                *)
                    CLIENT_VENDOR="Inconnu ou MAC privée"
                    ;;
            esac

            echo "=========================================="
            echo " SMARTPHONE DÉTECTÉ"
            echo
            echo " Nom          : $CLIENT_NAME"
            echo " IP           : $CLIENT_IP"
            echo " MAC          : $CLIENT_MAC"
            echo " Constructeur : $CLIENT_VENDOR"
            echo "=========================================="
            return 0
        fi

        sleep 1
    done

    echo "[ERREUR] Aucun smartphone détecté après 180 secondes."
    exit 1
}

#############################
# Durée
#############################

analysis_mode_menu() {
    local choice

    echo
    echo "1) Nouvelle capture réseau"
    echo "2) Analyser un PCAP existant"
    echo "3) Quitter"
    echo
    read -rp "Choix : " choice

    case "$choice" in
        1) ANALYSIS_ONLY=0 ;;
        2) ANALYSIS_ONLY=1 ;;
        3) exit 0 ;;
        *) echo "[ERREUR] Choix invalide."; exit 1 ;;
    esac
}

prepare_existing_pcap() {
    local selection duration_seconds
    local -a pcap_list

    mapfile -t pcap_list < <(
        find "$CAPTURES" -maxdepth 1 -type f -name '*.pcap' \
            -printf '%T@|%p\n' 2>/dev/null |
        sort -t'|' -k1,1nr |
        cut -d'|' -f2-
    )

    [ "${#pcap_list[@]}" -gt 0 ] || {
        echo "[ERREUR] Aucun PCAP disponible dans $CAPTURES"
        exit 1
    }

    echo
    echo "PCAP DISPONIBLES"
    echo "------------------------------------------"
    for i in "${!pcap_list[@]}"; do
        printf "%2d) %s\n" "$((i + 1))" "$(basename "${pcap_list[$i]}")"
    done

    echo
    read -rp "Numéro du PCAP : " selection
    [[ "$selection" =~ ^[0-9]+$ ]] || {
        echo "[ERREUR] Sélection invalide."
        exit 1
    }
    [ "$selection" -ge 1 ] && [ "$selection" -le "${#pcap_list[@]}" ] || {
        echo "[ERREUR] Sélection hors plage."
        exit 1
    }

    EXISTING_PCAP="${pcap_list[$((selection - 1))]}"

    CLIENT_IP="$(
        tshark -r "$EXISTING_PCAP" -T fields -e ip.src 2>/dev/null |
        tr ',' '\n' |
        awk -F. -v gateway="$HOTSPOT_IP" '
            $0 == gateway {next}
            $1 == 10 {print; next}
            $1 == 172 && $2 >= 16 && $2 <= 31 {print; next}
            $1 == 192 && $2 == 168 {print; next}
        ' |
        sort | uniq -c | sort -nr | awk 'NR == 1 {print $2}'
    )"

    [ -n "$CLIENT_IP" ] || {
        echo "[ERREUR] Impossible d'identifier automatiquement l'IP locale."
        exit 1
    }

    CLIENT_MAC="$(
        tshark -r "$EXISTING_PCAP" -Y "ip.src == $CLIENT_IP" \
            -T fields -e eth.src 2>/dev/null |
        sed '/^$/d' | head -n 1
    )"
    CLIENT_NAME="Appareil relu"
    CLIENT_VENDOR="Non déterminé"

    duration_seconds="$(
        tshark -r "$EXISTING_PCAP" -T fields -e frame.time_epoch 2>/dev/null |
        awk 'NR == 1 {first=$1} {last=$1} END {if (last >= first) printf "%.0f", last-first; else print 0}'
    )"
    DURATION="${duration_seconds:-0}"
    MANUAL_CAPTURE=0
    MODE="RELECTURE PCAP"

    echo
    echo "[OK] PCAP sélectionné : $(basename "$EXISTING_PCAP")"
    echo "[OK] IP détectée      : $CLIENT_IP"
    echo "[OK] Durée observée   : $DURATION secondes"
}

capture_menu() {
    echo
    echo "1) Capture 1 min"
    echo "2) Capture 5 min"
    echo "3) Capture 10 min"
    echo "4) Capture 15 min"
    echo "5) Capture 30 min"
    echo "6) Fin manuelle"
    echo

    read -rp "Choix : " CHOICE

    MANUAL_CAPTURE=0

    case "$CHOICE" in
        1) DURATION=60 ;;
        2) DURATION=300 ;;
        3) DURATION=600 ;;
        4) DURATION=900 ;;
        5) DURATION=1800 ;;
        6)
            MANUAL_CAPTURE=1
            DURATION=0
            ;;
        *)
            echo "[ERREUR] Choix invalide."
            exit 1
            ;;
    esac
}

#############################
# Capture et rapport
#############################

match_suffix_file() {
    local value="$1"
    local file="$2"
    local pattern

    [ -f "$file" ] || return 1

    while IFS= read -r pattern; do
        pattern="${pattern%%#*}"
        pattern="$(echo "$pattern" | xargs)"
        [ -z "$pattern" ] && continue

        if [[ "$value" == "$pattern" || "$value" == *".$pattern" ]]; then
            return 0
        fi
    done < "$file"

    return 1
}

classify_domain() {
    local domain="${1,,}"

    # Bruit local / résolution système
    if [[ "$domain" == "localhost" ||
          "$domain" == "_dns.resolver.arpa" ||
          "$domain" == *.in-addr.arpa ||
          "$domain" == *.local ||
          "$domain" == *".local,"* ||
          "$domain" == *",_"* ]]; then
        echo "LOCAL"
    elif [ -f "$IOC_DOMAINS" ] && grep -Fxqi "$domain" "$IOC_DOMAINS"; then
        echo "IOC"
    elif match_suffix_file "$domain" "$SERVICES_FILE"; then
        echo "KNOWN"
    elif match_suffix_file "$domain" "$CDN_FILE"; then
        echo "CDN"
    elif match_suffix_file "$domain" "$TRACKING_FILE"; then
        echo "TRACKING"
    elif match_suffix_file "$domain" "$HOSTING_FILE"; then
        echo "HOSTING"
    elif match_suffix_file "$domain" "$VPN_FILE"; then
        echo "VPN"
    elif match_suffix_file "$domain" "$IOT_FILE"; then
        echo "IOT"
    else
        echo "UNKNOWN"
    fi
}
capture_traffic() {
    local date pcap report dns_file ip_file dns_count ip_count
    local class_file ioc_hits_file ioc_count direct_file
    local capture_status country org
    local total_packets vpn_packets vpn_filter
    local vpn_detected=0 vpn_protocol="" vpn_endpoint="" vpn_port=""
    local vpn_percent="0.00" direct_count=0

    date="$(date +%F_%H-%M-%S)"

    if [ "${ANALYSIS_ONLY:-0}" -eq 1 ]; then
        pcap="$EXISTING_PCAP"
        report="$REPORTS/reanalysis_$(basename "${pcap%.pcap}")_$date.txt"
    else
        pcap="$CAPTURES/traffic_$date.pcap"
        report="$REPORTS/traffic_$date.txt"
    fi
    dns_file="$TMP/dns_$date.txt"
    ip_file="$TMP/ip_$date.txt"

    echo

    if [ "${ANALYSIS_ONLY:-0}" -eq 1 ]; then

        echo "[4/10] Analyse du PCAP existant..."
        echo "[+] $(basename "$pcap")"
        capture_status=0

    elif [ "${MANUAL_CAPTURE:-0}" -eq 1 ]; then

        echo "[4/10] Capture en mode MANUEL..."
        echo "Utilisez normalement le téléphone."
        echo
        echo "Appuyez sur ENTRÉE pour terminer la capture."
        echo

        sudo tcpdump \
            -i "$HOTSPOT_IF" \
            -nn \
            -w "$pcap" \
            "host $CLIENT_IP" &

        TCPDUMP_PID=$!

        read -r

        echo
        echo "[+] Arrêt propre de la capture..."

        sudo kill -INT "$TCPDUMP_PID" 2>/dev/null || true
        wait "$TCPDUMP_PID" 2>/dev/null

        capture_status=$?

        # SIGINT manuel est attendu
        [ "$capture_status" -eq 130 ] && capture_status=0

    else

        echo "[4/10] Capture durant $DURATION secondes..."
        echo "Utilisez normalement le téléphone pendant la capture."
        echo

        sudo timeout --signal=INT "$DURATION" \
            tcpdump \
            -i "$HOTSPOT_IF" \
            -nn \
            -w "$pcap" \
            "host $CLIENT_IP"

        capture_status=$?

        # timeout normal
        [ "$capture_status" -eq 124 ] && capture_status=0

    fi

    if [ "$capture_status" -ne 0 ]; then
        echo "[ERREUR] Échec de la capture tcpdump."
        exit 1
    fi

    [ -s "$pcap" ] || {
        echo "[ERREUR] Aucun paquet n'a été capturé."
        exit 1
    }

    echo "[5/10] Extraction des domaines DNS..."

    tshark -r "$pcap" \
        -Y "ip.src == $CLIENT_IP && dns.qry.name" \
        -T fields \
        -e dns.qry.name 2>/dev/null |
        sed '/^$/d' |
        sort -u > "$dns_file"

    echo "[6/10] Extraction des destinations IPv4..."

    tshark -r "$pcap" \
    -Y "ip.src == $CLIENT_IP && ip.dst" \
    -T fields \
    -e ip.dst 2>/dev/null |
    tr ',' '\n' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
    grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
    awk -F. '
        $1 == 10 {next}
        $1 == 100 && $2 >= 64 && $2 <= 127 {next}
        $1 == 127 {next}
        $1 == 169 && $2 == 254 {next}
        $1 == 172 && $2 >= 16 && $2 <= 31 {next}
        $1 == 192 && $2 == 168 {next}
        $1 >= 224 {next}
        {print}
    ' |
    sort -u > "$ip_file"

    dns_count="$(wc -l < "$dns_file")"
    ip_count="$(wc -l < "$ip_file")"

    # Détection des tunnels visibles sur le réseau. Cette analyse prouve
    # qu'un tunnel est actif, pas que l'application VPN est malveillante.
    direct_file="$TMP/direct_outside_vpn_$date.txt"
    : > "$direct_file"

    if tshark -r "$pcap" -Y 'wg' -T fields -e frame.number 2>/dev/null | grep -q .; then
        vpn_detected=1
        vpn_protocol="WireGuard"
        vpn_filter='wg || udp.port == 51820'
    elif tshark -r "$pcap" -Y 'openvpn || udp.port == 1194 || tcp.port == 1194' -T fields -e frame.number 2>/dev/null | grep -q .; then
        vpn_detected=1
        vpn_protocol="OpenVPN probable"
        vpn_filter='openvpn || udp.port == 1194 || tcp.port == 1194'
    elif tshark -r "$pcap" -Y 'esp || udp.port == 500 || udp.port == 4500' -T fields -e frame.number 2>/dev/null | grep -q .; then
        vpn_detected=1
        vpn_protocol="IPsec/IKE"
        vpn_filter='esp || udp.port == 500 || udp.port == 4500'
    fi

    if [ "$vpn_detected" -eq 1 ]; then
        total_packets="$(tshark -r "$pcap" -T fields -e frame.number 2>/dev/null | wc -l)"

        vpn_packets="$(tshark -r "$pcap" -Y "$vpn_filter" -T fields -e frame.number 2>/dev/null | wc -l)"
        vpn_percent="$(awk -v vpn="$vpn_packets" -v total="$total_packets" 'BEGIN {if (total > 0) printf "%.2f", (vpn * 100) / total; else print "0.00"}')"

        vpn_endpoint="$(tshark -r "$pcap" \
            -Y "ip.src == $CLIENT_IP && ($vpn_filter) && ip.dst" \
            -T fields -e ip.dst 2>/dev/null |
            tr ',' '\n' | sed '/^$/d' | sort | uniq -c | sort -nr |
            awk 'NR == 1 {print $2}')"

        vpn_port="$(tshark -r "$pcap" \
            -Y "ip.src == $CLIENT_IP && ($vpn_filter)" \
            -T fields -e udp.dstport -e tcp.dstport 2>/dev/null |
            tr '\t,' '\n\n' | sed '/^$/d' | sort | uniq -c | sort -nr |
            awk 'NR == 1 {print $2}')"

        tshark -r "$pcap" \
            -Y "ip.src == $CLIENT_IP && ip.dst && !($vpn_filter)" \
            -T fields -e ip.dst 2>/dev/null |
            tr ',' '\n' |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
            grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
            awk -F. '
                $1 == 10 {next}
                $1 == 100 && $2 >= 64 && $2 <= 127 {next}
                $1 == 127 {next}
                $1 == 169 && $2 == 254 {next}
                $1 == 172 && $2 >= 16 && $2 <= 31 {next}
                $1 == 192 && $2 == 168 {next}
                $1 >= 224 {next}
                {print}
            ' | sort -u > "$direct_file"

        direct_count="$(wc -l < "$direct_file")"
    fi

    class_file="$TMP/classification_$date.txt"
    ioc_hits_file="$TMP/ioc_hits_$date.txt"

    : > "$class_file"
    : > "$ioc_hits_file"

while IFS= read -r domain; do
    [ -z "$domain" ] && continue
    category="$(classify_domain "$domain")"
    printf '%s|%s\n' "$category" "$domain" >> "$class_file"
done < "$dns_file"

known_count=$(grep -c '^KNOWN|' "$class_file" || true)
cdn_count=$(grep -c '^CDN|' "$class_file" || true)
tracking_count=$(grep -c '^TRACKING|' "$class_file" || true)
hosting_count=$(grep -c '^HOSTING|' "$class_file" || true)
vpn_count=$(grep -c '^VPN|' "$class_file" || true)
iot_count=$(grep -c '^IOT|' "$class_file" || true)
local_count=$(grep -c '^LOCAL|' "$class_file" || true)
unknown_count=$(grep -c '^UNKNOWN|' "$class_file" || true)

echo "[7/10] Corrélation avec la base IOC Traffic..."

python3 -     "$dns_file"     "$ip_file"     "$IOC_TAGGED"     "$ioc_hits_file" <<'PYIOC'
import csv
import sys
from collections import defaultdict

dns_file, ip_file, csv_file, output_file = sys.argv[1:5]

observed = set()

for path, typ in ((dns_file, "domain"), (ip_file, "ip")):
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            for line in f:
                value = line.strip().lower()
                if value:
                    observed.add((value, typ))
    except FileNotFoundError:
        pass

matches = defaultdict(list)

try:
    with open(csv_file, newline="", encoding="utf-8", errors="ignore") as f:
        reader = csv.DictReader(f)

        for row in reader:
            indicator = (row.get("indicator") or "").strip().lower()
            typ = (row.get("type") or "").strip().lower()

            if (indicator, typ) not in observed:
                continue

            matches[(indicator, typ)].append(row)

except FileNotFoundError:
    pass


with open(output_file, "w", encoding="utf-8") as out:

    for (indicator, typ), rows in sorted(matches.items()):

        # Une ligne par provenance/famille pertinente
        seen = set()

        for row in rows:

            family = (row.get("family") or "unknown").strip()
            source = (row.get("source") or "unknown").strip()
            category = (row.get("category") or "unknown").strip()
            confidence = (row.get("confidence") or "UNSPECIFIED").strip()
            ioc_class = (row.get("ioc_class") or "UNCLASSIFIED").strip()
            class_basis = (row.get("class_basis") or "NO_RULE").strip()

            key = (
                family,
                source,
                category,
                confidence,
                ioc_class,
                class_basis
            )

            if key in seen:
                continue

            seen.add(key)

            out.write(
                f"{indicator} | "
                f"type={typ} | "
                f"classe={ioc_class} | "
                f"famille={family} | "
                f"source={source} | "
                f"categorie={category} | "
                f"confiance={confidence} | "
                f"classification={class_basis}\n"
            )

print(f"[+] Correspondances IOC enrichies : {sum(len(set(
    (
        (r.get('family') or 'unknown').strip(),
        (r.get('source') or 'unknown').strip(),
        (r.get('category') or 'unknown').strip(),
        (r.get('confidence') or 'UNSPECIFIED').strip()
    )
    for r in rows
)) for rows in matches.values())}")

PYIOC

ioc_count=$(wc -l < "$ioc_hits_file")

# ----------------------------------------------------------
# Compteurs pour le résumé opérateur final
# ----------------------------------------------------------

QUICK_DNS="$dns_count"
QUICK_IPS="$ip_count"
QUICK_UNKNOWN="$unknown_count"
QUICK_REPORT="$report"
QUICK_VPN_DETECTED="$vpn_detected"
QUICK_VPN_PROTOCOL="$vpn_protocol"
QUICK_VPN_ENDPOINT="$vpn_endpoint"
QUICK_VPN_PORT="$vpn_port"
QUICK_VPN_PERCENT="$vpn_percent"
QUICK_DIRECT_IPS="$direct_count"

if [ "${ANALYSIS_ONLY:-0}" -eq 1 ]; then
    QUICK_DURATION="${DURATION}s relus"
elif [ "${MANUAL_CAPTURE:-0}" -eq 1 ]; then
    QUICK_DURATION="manuel"
else
    QUICK_DURATION="$((DURATION / 60)) min"
fi

QUICK_CRITICAL=$(grep -c 'classe=MERCENARY_SPYWARE' "$ioc_hits_file" 2>/dev/null || true)

QUICK_SPYWARE=$(
    grep -Ec     'classe=(COMMERCIAL_SURVEILLANCE|MOBILE_THREAT|STALKERWARE|STALKERWARE_SOURCE|PARENTAL_DUALUSE)'     "$ioc_hits_file" 2>/dev/null || true
)

QUICK_MALWARE=$(
    grep -Ec     'classe=(GENERIC_C2|GENERIC_MALWARE|GENERIC_OFFENSIVE|NETWORK_IOC)'     "$ioc_hits_file" 2>/dev/null || true
)

    echo "[8/10] Génération du rapport..."
    {
        echo "=========================================="
        echo " SOMBRA TRAFFIC REPORT"
        echo "=========================================="
        echo

        echo "ANALYSE"
        echo "------------------------------------------"
        echo "Date              : $date"
        echo "Durée             : $DURATION secondes"
        echo "Mode              : $MODE"
        echo "Internet          : $([ "$INTERNET" -eq 1 ] && echo Oui || echo Non)"
        echo "Interface         : $HOTSPOT_IF"
        echo

        echo "APPAREIL"
        echo "------------------------------------------"
        echo "Nom               : $CLIENT_NAME"
        echo "Constructeur      : $CLIENT_VENDOR"
        echo "IP locale         : $CLIENT_IP"
        echo "MAC               : $CLIENT_MAC"
        echo

        echo "=========================================="
        echo " DESTINATIONS IP / GEOIP / WHOIS"
        echo "=========================================="
        echo

        if [ "$INTERNET" -eq 1 ]; then
            while read -r ip; do
                [ -z "$ip" ] && continue

                country="$(geoiplookup "$ip" 2>/dev/null |
                    sed 's/GeoIP Country Edition: //' |
                    head -n 1)"

                org="$(timeout 8 whois "$ip" 2>/dev/null |
                    grep -Ei '^(OrgName|org-name|Organization|descr|netname):' |
                    head -n 1 |
                    sed 's/^[[:space:]]*//')"

                [ -z "$country" ] && country="Pays inconnu"
                [ -z "$org" ] && org="Organisation inconnue"

                echo "$ip | $country | $org"
            done < "$ip_file"
        else
            cat "$ip_file"
            echo
            echo "Enrichissement GeoIP/WHOIS différé : absence d'Internet."
        fi

        echo
        echo
        echo "DOMAINES DNS OBSERVÉS"
        echo "------------------------------------------"
        cat "$dns_file"

        echo
        echo "=========================================="
        echo " RÉSUMÉ FINAL"
        echo "=========================================="
        echo

        echo "ACTIVITÉ RÉSEAU"
        echo "------------------------------------------"

        if [ "${MANUAL_CAPTURE:-0}" -eq 1 ]; then
            echo "Durée                 : Fin manuelle"
        else
            echo "Durée                 : $DURATION secondes"
        fi

        echo "Domaines DNS uniques : $dns_count"
        echo "IP distantes uniques : $ip_count"
        echo

        echo "CLASSIFICATION"
        echo "------------------------------------------"
        echo "Services connus       : $known_count"
        echo "CDN                   : $cdn_count"
        echo "Tracking / publicité  : $tracking_count"
        echo "Hébergement / cloud   : $hosting_count"
        echo "VPN / Proxy (DNS)     : $vpn_count"
        echo "Tunnel VPN actif      : $([ "$vpn_detected" -eq 1 ] && echo Oui || echo Non)"
        echo "IoT / Backend         : $iot_count"
        echo "Local / système       : $local_count"
        echo "Inconnus              : $unknown_count"
        echo

        if [ "$vpn_detected" -eq 1 ]; then
            echo "VPN / TUNNEL CHIFFRÉ"
            echo "------------------------------------------"
            echo "Protocole             : $vpn_protocol"
            echo "Destination tunnel    : ${vpn_endpoint:-Inconnue}"
            echo "Port destination      : ${vpn_port:-Inconnu}"
            echo "Paquets tunnelisés     : $vpn_percent %"
            echo "IP directes hors VPN  : $direct_count"
            echo "Visibilité applicative: TRÈS LIMITÉE"
            echo
            echo "Le point d'entrée du tunnel n'est pas nécessairement"
            echo "la destination finale des données. Un VPN actif ne"
            echo "prouve pas une compromission, mais doit être expliqué."
            echo
            echo "ACTION OPÉRATEUR"
            echo "------------------------------------------"
            echo "Vérifier le profil VPN, l'application, le MDM et le mode"
            echo "Always-On. Si le propriétaire ne connaît pas ce tunnel :"
            echo "niveau ORANGE, désactivation contrôlée puis nouvelle capture."
            echo
            echo "DESTINATIONS DIRECTES HORS TUNNEL"
            echo "------------------------------------------"
            if [ "$direct_count" -gt 0 ]; then
                cat "$direct_file"
            else
                echo "Aucune destination IPv4 directe observée."
            fi
            echo
        fi

        echo "SÉCURITÉ"
        echo "------------------------------------------"
        echo "IOC réseau Lab4Phone     : $ioc_count"

        if [ "$ioc_count" -gt 0 ]; then
            echo "Statut                : Correspondance(s) IOC détectée(s)"
            echo
            echo "DÉTAIL DES CORRESPONDANCES"
            echo "------------------------------------------"
            cat "$ioc_hits_file"
        else
            echo "Statut                : Aucun match IOC exact"
        fi

        echo
        echo "Note : l'absence de correspondance IOC ne permet pas"
        echo "d'exclure une compromission du terminal."
        echo

        echo "À EXAMINER"
        echo "------------------------------------------"

        if [ "$unknown_count" -gt 0 ]; then
            grep '^UNKNOWN|' "$class_file" | cut -d'|' -f2-
        else
            echo "Aucun domaine non classé."
        fi

        echo
        echo "FICHIER PCAP"
        echo "------------------------------------------"
        echo "$pcap"

    } > "$report"

    echo
    echo "[OK] Capture terminée."
    echo "[OK] PCAP    : $pcap"
    echo "[OK] Rapport : $report"
}

#############################
# Résumé opérateur
#############################

show_quick_summary() {

    local critical_dot="🟢"
    local spyware_dot="🟢"
    local malware_dot="🟢"
    local risk_dot="🟢"
    local risk="FAIBLE"

    [ "${QUICK_CRITICAL:-0}" -gt 0 ] && critical_dot="🔴"
    [ "${QUICK_SPYWARE:-0}" -gt 0 ] && spyware_dot="🟠"
    [ "${QUICK_MALWARE:-0}" -gt 0 ] && malware_dot="🟠"

    if [ "${QUICK_CRITICAL:-0}" -gt 0 ]; then
        risk_dot="🔴"
        risk="CRITIQUE"

    elif [ "${QUICK_SPYWARE:-0}" -gt 0 ]; then
        risk_dot="🟠"
        risk="ÉLEVÉ"

    elif [ "${QUICK_MALWARE:-0}" -gt 0 ]; then
        risk_dot="🟡"
        risk="À CONFIRMER"

    elif [ "${QUICK_VPN_DETECTED:-0}" -eq 1 ]; then
        risk_dot="🟠"
        risk="VIGILANCE — VPN ACTIF"
    fi

    echo
    echo "=========================================="
    echo "        SOMBRA — RÉSULTAT RAPIDE"
    echo "=========================================="
    echo
    printf "%s IOC critiques       : %s\n" \
        "$critical_dot" "${QUICK_CRITICAL:-0}"

    printf "%s Spyware / Stalker   : %s\n" \
        "$spyware_dot" "${QUICK_SPYWARE:-0}"

    printf "%s C2 / Malware        : %s\n" \
        "$malware_dot" "${QUICK_MALWARE:-0}"

    printf "🟡 Non classifiées     : %s\n" \
        "${QUICK_UNKNOWN:-0}"

    if [ "${QUICK_VPN_DETECTED:-0}" -eq 1 ]; then
        printf "🟠 VPN actif            : %s → %s:%s (%s %%)\n" \
            "${QUICK_VPN_PROTOCOL:-inconnu}" \
            "${QUICK_VPN_ENDPOINT:-inconnue}" \
            "${QUICK_VPN_PORT:-?}" \
            "${QUICK_VPN_PERCENT:-0.00}"
        printf "🟠 IP directes hors VPN : %s\n" "${QUICK_DIRECT_IPS:-0}"
    fi

    echo
    printf "📡 %s domaines | %s IP | %s\n" \
        "${QUICK_DNS:-0}" \
        "${QUICK_IPS:-0}" \
        "${QUICK_DURATION:-?}"

    echo
    printf "%s RISQUE : %s\n" "$risk_dot" "$risk"
    echo

    if [ "${QUICK_CRITICAL:-0}" -eq 0 ] && \
       [ "${QUICK_SPYWARE:-0}" -eq 0 ] && \
       [ "${QUICK_MALWARE:-0}" -eq 0 ]; then

        echo "Aucun IOC connu détecté pendant la capture."

    else
        echo "Une ou plusieurs correspondances IOC ont été détectées."
    fi

    if [ "${QUICK_UNKNOWN:-0}" -gt 0 ]; then
        echo "${QUICK_UNKNOWN} destinations nécessitent une classification."
    else
        echo "Aucune destination non classifiée."
    fi

    if [ "${QUICK_VPN_DETECTED:-0}" -eq 1 ]; then
        echo "Visibilité limitée : désactiver le VPN avec l'accord du"
        echo "propriétaire, puis effectuer une capture comparative."
    fi

    echo
    echo "Rapport : $(basename "${QUICK_REPORT:-inconnu}")"
    echo "=========================================="
}

#############################
# MAIN
#############################

case "${1:-}" in
    "")
        ANALYSIS_ONLY=0
        ;;
    --pcap)
        ANALYSIS_ONLY=1
        ;;
    -h|--help)
        echo "Usage :"
        echo "  $0          Nouvelle capture réseau"
        echo "  $0 --pcap   Analyser un PCAP existant"
        trap - EXIT INT TERM
        exit 0
        ;;
    *)
        echo "[ERREUR] Option inconnue : $1"
        echo "Utilisez : $0 --help"
        trap - EXIT INT TERM
        exit 1
        ;;
esac

banner
check_dep
check_internet

if [ "$ANALYSIS_ONLY" -eq 1 ]; then
    prepare_existing_pcap
else
    start_hotspot
    wait_client
    capture_menu
fi

capture_traffic

if [ "$ANALYSIS_ONLY" -eq 0 ]; then
    stop_hotspot
fi

trap - EXIT INT TERM
show_quick_summary
