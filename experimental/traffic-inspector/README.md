# Lab4Phone Traffic Inspector 0.5-dev

Traffic Inspector est un module expérimental du projet Sombra intégré
à Lab4Phone.

Il sert à recueillir et interpréter le trafic réseau d'un appareil
testé avec l'autorisation de son propriétaire.

## Fonctions disponibles

- création d'un hotspot Wi-Fi temporaire ;
- mot de passe aléatoire généré à chaque lancement ;
- capture PCAP avec tcpdump ;
- analyse DNS, IP et TLS avec tshark ;
- relecture d'une capture PCAP existante ;
- détection indicative de WireGuard, OpenVPN et IPsec ;
- classification des services, CDN, hébergeurs, VPN, trackers et IoT ;
- comparaison avec des bases IOC locales ;
- génération d'un résumé destiné à l'opérateur.

## Avertissement technique

Le script peut temporairement :

- arrêter NetworkManager ;
- modifier l'adresse de l'interface Wi-Fi ;
- activer le routage IPv4 ;
- lancer hostapd et dnsmasq ;
- créer une table nftables dédiée.

Il doit être utilisé sur une machine Linux de laboratoire dédiée.

Une interruption réseau reste possible si le programme est arrêté
brutalement ou si la configuration matérielle est différente.

## Interfaces par défaut

    Hotspot Wi-Fi : wlan0
    Accès Internet : eth0

Ces interfaces doivent être vérifiées avant chaque utilisation.

## Stockage

Les données sont placées par défaut dans :

    ~/.local/state/lab4phone/traffic_inspector

Un autre emplacement peut être défini avec :

    export L4P_TRAFFIC_HOME=/chemin/traffic_inspector

Les captures, rapports, classifications privées et bases IOC ne sont
pas distribués avec le dépôt.

## Dépendances principales

- Bash ;
- OpenSSL ;
- tcpdump ;
- tshark ;
- hostapd ;
- dnsmasq ;
- nftables ;
- iproute2 ;
- iw.

## Exécution

Valider temporairement les privilèges administrateur :

    sudo -v

Puis lancer :

    bash experimental/traffic-inspector/traffic_inspector.sh

## Cadre légal

Utilisez Traffic Inspector uniquement sur un appareil et un réseau
vous appartenant, ou avec une autorisation explicite.

## Statut du module

Cette version est publiée pour recueillir des retours techniques,
des signalements de bugs et des propositions d'amélioration.

Elle n'est pas présentée comme un outil forensic certifié ou finalisé.
