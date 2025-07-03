#!/bin/bash

echo "=== Lab4Phone : démarrage inspection complète ==="

# Fonction pour tester la connexion Internet
check_internet() {
    wget -q --spider http://google.com
    return $?
}

# Mise à jour et installation outils (mode online)
update_and_install() {
    echo "=== Connexion internet détectée, mise à jour et installation des outils ==="
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y libimobiledevice-utils ifuse usbmuxd ideviceinstaller python3-pip adb android-tools-adb android-tools-fastboot jq libplist-utils curl

    pip3 install --upgrade pip
    pip3 install iphonebackup iphone-dataprotector python-libimobiledevice

    echo "=== Récupération des indicateurs spyware en ligne ==="
    curl -fsSL https://raw.githubusercontent.com/tonrepo/Lab4Phone/main/spyware_indicators.txt -o spyware_indicators.txt || echo "Erreur récupération indicateurs, on continue."
}

# Backup iPhone
run_backup_iphone() {
    echo "[*] Lancement backup iPhone..."
    idevicebackup2 backup ./backup_iphone
    if [ $? -ne 0 ]; then
        echo "Erreur backup iPhone."
        return 1
    fi
    echo "[+] Backup iPhone terminé."
}

# Inspection Android
inspect_android() {
    echo "[*] Inspection Android démarrée..."
    if ! command -v adb &> /dev/null; then
        echo "adb non installé."
        return 1
    fi
    adb devices | grep -w "device" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Aucun appareil Android connecté."
        return 1
    fi
    echo "Appareil connecté:"
    adb devices | grep -w "device"
    echo "Liste applications installées:"
    adb shell pm list packages
    echo "Processus suspects:"
    adb shell ps | grep -i -E "spy|malware|root"
    echo "[+] Fin inspection Android."
}

# Détection spyware
detect_spyware() {
    echo "[*] Détection spyware dans backup iPhone..."
    local indicators_file="spyware_indicators.txt"
    if [ ! -f "$indicators_file" ]; then
        indicators_file="spyware_indicators_local.txt"
        echo "Utilisation des indicateurs locaux : $indicators_file"
    else
        echo "Utilisation des indicateurs en ligne : $indicators_file"
    fi

    found=0
    while IFS= read -r indicator; do
        if [ -z "$indicator" ] || [[ "$indicator" =~ ^# ]]; then
            continue
        fi
        matches=$(find ./backup_iphone -type f -name "*$indicator*" 2>/dev/null)
        if [ ! -z "$matches" ]; then
            echo "[!] Indicateur détecté : $indicator"
            echo "$matches"
            found=1
        fi
    done < "$indicators_file"

    if [ $found -eq 0 ]; then
        echo "[+] Aucun spyware suspect détecté."
    fi
}

# Génération rapport
generate_report() {
    REPORT="rapport_inspection_$(date +%Y%m%d_%H%M%S).txt"
    echo "Rapport Inspection Lab4Phone" > "$REPORT"
    echo "Date: $(date)" >> "$REPORT"
    echo "============================" >> "$REPORT"

    echo -e "\n--- iPhone ---" >> "$REPORT"
    if [ -d "./backup_iphone" ]; then
        echo "Backup iPhone détecté." >> "$REPORT"
        
        echo -e "\nFichiers suspects détectés :" >> "$REPORT"
        local indicators_file="spyware_indicators.txt"
        if [ ! -f "$indicators_file" ]; then
            indicators_file="spyware_indicators_local.txt"
        fi

        found=0
        while IFS= read -r indicator; do
            if [ -z "$indicator" ] || [[ "$indicator" =~ ^# ]]; then
                continue
            fi
            matches=$(find ./backup_iphone -type f -name "*$indicator*" 2>/dev/null)
            if [ ! -z "$matches" ]; then
                echo "[!] Indicateur détecté : $indicator" >> "$REPORT"
                echo "$matches" >> "$REPORT"
                found=1
            fi
        done < "$indicators_file"

        if [ $found -eq 0 ]; then
            echo "Aucun fichier suspect trouvé." >> "$REPORT"
        fi
    else
        echo "Aucun backup iPhone détecté." >> "$REPORT"
    fi

    echo -e "\n--- Android ---" >> "$REPORT"
    if adb devices | grep -w "device" > /dev/null; then
        echo "Appareil Android connecté." >> "$REPORT"
        echo -e "\nApplications installées :" >> "$REPORT"
        adb shell pm list packages >> "$REPORT"
    else
        echo "Aucun appareil Android connecté." >> "$REPORT"
    fi

    echo "Rapport sauvegardé dans : $REPORT"
    echo "[*] Rapport généré : $REPORT"
}

# Script principal

if check_internet; then
    update_and_install
else
    echo "=== Pas de connexion Internet détectée, mode hors ligne activé ==="
fi

run_backup_iphone
inspect_android
detect_spyware
generate_report

echo "=== Fin inspection Lab4Phone ==="
