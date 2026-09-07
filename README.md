# Lab4Phone

Lab4Phone est un projet Sombra consacré au diagnostic de sécurité
et à l'analyse forensic légère des smartphones Android et iOS.

> Statut : prototype en développement.
>
> Lab4Phone ne remplace pas une expertise judiciaire, un laboratoire
> accrédité ou une plateforme commerciale de forensic mobile.

## Modules publiés

| Module | Version | Statut |
|---|---:|---|
| Android Only | 3.16-k02 | Prototype fonctionnel |
| iOS Only | 3.4-fix7c | Prototype fonctionnel |
| IOC Library | développement | Expérimental |
| Traffic Inspector | 0.5-dev | Expérimental |

## Android Only

Fonctions actuellement présentes :

- détection du terminal via ADB ;
- informations système et niveau de correctif ;
- inventaire des applications ;
- contrôle des accès sensibles ;
- recherche d'indicateurs locaux ;
- score GREEN, ORANGE ou RED ;
- rapport opérateur et empreinte SHA-256.

## iOS Only

Fonctions actuellement présentes :

- détection et appairage iPhone/iPad ;
- sauvegarde complète ou rapide ;
- intégration MVT lorsqu'il est disponible ;
- inventaire applicatif ;
- recherche d'indicateurs ;
- rapports TXT, CSV et JSON ;
- coffre probatoire avec empreinte SHA-256.

## Traffic Inspector

Traffic Inspector crée un hotspot d'analyse sur une machine Linux dédiée,
capture le trafic autorisé d'un équipement de test et produit un résumé
des domaines, adresses IP, protocoles VPN et correspondances IOC.

Documentation :
experimental/traffic-inspector/README.md

## Installation

    git clone https://github.com/FredoCol/Lab4Phone.git
    cd Lab4Phone
    chmod +x scripts/*.sh

Les dépendances varient selon le module :

- ADB pour Android ;
- libimobiledevice et MVT pour iOS ;
- tcpdump, tshark, hostapd, dnsmasq et nftables pour Traffic Inspector.

## Stockage et configuration

Les rapports, sauvegardes, captures et journaux ne doivent jamais être
publiés dans le dépôt.

Variables disponibles :

- L4P_DATA_DIR : données et rapports Android ;
- L4P_IOCS_DIR : répertoire contenant indicators.csv ;
- L4P_BASE_SSD : emplacement Lab4Phone sur SSD ;
- L4P_TRAFFIC_HOME : données de Traffic Inspector.

## Indicateurs

Les bases opérationnelles d'IOC et de CVE ne sont pas distribuées dans
ce dépôt. Un exemple entièrement fictif sera fourni dans indicators/.

## Cadre d'utilisation

Utilisez ces outils uniquement :

- sur vos propres appareils et réseaux ;
- avec l'autorisation explicite du propriétaire ;
- dans un laboratoire ou un cadre professionnel légal.

Les résultats constituent des éléments d'orientation qui doivent être
confirmés par une analyse humaine.

## Projet

Projet personnel maintenu par FredoCol sous l'identité Sombra.

Les retours terrain, signalements de bugs et propositions d'amélioration
sont bienvenus.

## Utilisation du code

Aucune licence open source n’est accordée à ce stade.
Le code est publié pour consultation, retours techniques et signalement de bugs.
Tous droits réservés.
