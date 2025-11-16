#!/bin/bash

# ==============================================================================
# Script d'installation pour Frigate avec Docker sur Debian 13
# Auteur: Genere avec l'aide de Gemini
# Version: 2.4 (Detection materielle fiabilisee pour serveur)
# Description: Automatise l'installation de Frigate, Docker, et des pilotes
#              Intel pour l'acceleration materielle (VA-API).
# ==============================================================================

# --- Variables de couleur pour les messages ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Fonctions pour afficher les messages ---
log_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[ATTENTION] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# --- Verifications preliminaires ---
log_info "Debut des verifications preliminaires..."

# 1. Verifier si le script est execute en tant que root
if [ "$(id -u)" -ne 0 ]; then
  log_error "Ce script doit �tre execute avec les privileges root."
  log_error "Veuillez le lancer avec 'sudo $0' ou directement en tant que root (via 'su -')."
  exit 1
fi

# 2. Verifier si l'OS est Debian 13 et demander confirmation si ce n'est pas le cas
if ! grep -q 'VERSION_CODENAME=trixie' /etc/os-release; then
    log_warning "Ce script a ete con�u et teste pour Debian 13 (Trixie)."
    log_warning "Votre systeme d'exploitation n'a pas ete reconnu comme tel."
    log_warning "Certaines commandes (notamment pour l'ajout des depots) pourraient echouer."
    read -p "Voulez-vous continuer malgre tout ? (o/N) " -n 1 -r REPLY
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        log_info "Operation annulee par l'utilisateur."
        exit 0
    fi
    log_info "Continuation de l'installation sur un systeme non-standard a vos risques et perils."
else
    log_success "Systeme d'exploitation Debian 13 (Trixie) detecte."
fi

# --- Demander le nom de l'utilisateur a configurer ---
read -p "Entrez le nom de l'utilisateur non-root a configurer (ex: valentin): " TARGET_USER
if ! id "$TARGET_USER" &>/dev/null; then
    log_error "L'utilisateur '$TARGET_USER' n'existe pas. Veuillez le creer d'abord."
    exit 1
fi
log_info "L'utilisateur '$TARGET_USER' sera ajoute aux groupes 'sudo' et 'docker'."

# ==============================================================================
# SECTION 1: MISE A JOUR DU SYSTEME ET DePENDANCES (INCLUANT SUDO)
# ==============================================================================
log_info "SECTION 1: Mise a jour du systeme et installation des dependances..."

apt-get update
apt-get upgrade -y

log_info "Installation de sudo, curl et des paquets pour les pilotes Intel..."
apt-get install -y sudo curl intel-media-va-driver intel-gpu-tools vainfo ca-certificates ffmpeg

# Configuration des mises a jour automatiques (unattended-upgrades)
log_info "Configuration des mises a jour automatiques..."
apt-get install -y unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

log_info "Ajout de l'utilisateur $TARGET_USER au groupe sudo..."
usermod -aG sudo "$TARGET_USER"

log_success "Systeme mis a jour et dependances installees."

# ==============================================================================
# SECTION 2: VERIFICATION DE L'ACCELERATION MATERIELLE
# ==============================================================================
log_info "SECTION 2: Verification de l'acceleration materielle Intel (VA-API)..."

# La verification avec `vainfo` est supprimee car elle echoue dans un environnement serveur (SSH)
# sans interface graphique. Nous nous fions uniquement a la presence du device /dev/dri/renderD128,
# ce qui est suffisant pour confirmer que le pilote est charge.
if [ -e "/dev/dri/renderD128" ]; then
    log_success "Le peripherique /dev/dri/renderD128 a ete trouve. L'acceleration materielle est probablement disponible."
else
    log_error "Le peripherique /dev/dri/renderD128 est manquant. L'acceleration materielle ne fonctionnera pas."
    exit 1
fi

# ==============================================================================
# SECTION 3: INSTALLATION DE DOCKER
# ==============================================================================
log_info "SECTION 3: Installation de Docker et Docker Compose..."

# Ajout du depot officiel de Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Installation des paquets Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ajout de l'utilisateur au groupe docker
log_info "Ajout de l'utilisateur $TARGET_USER au groupe docker..."
groupadd -f docker
usermod -aG docker "$TARGET_USER"

# Activation des services Docker
log_info "Activation et demarrage des services Docker..."
systemctl enable docker.service
systemctl enable containerd.service
systemctl start docker.service

log_success "Docker et Docker Compose ont ete installes avec succes."

# ==============================================================================
# SECTION 4: CONFIGURATION DE FRIGATE
# ==============================================================================
log_info "SECTION 4: Creation de la configuration pour Frigate..."

FRIGATE_DIR="/home/$TARGET_USER/frigate"
CONFIG_DIR="$FRIGATE_DIR/config"
STORAGE_DIR="$FRIGATE_DIR/storage"
COMPOSE_FILE="$FRIGATE_DIR/docker-compose.yml"
CONFIG_FILE="$CONFIG_DIR/config.yml"

log_info "Creation de l'arborescence de dossiers dans $FRIGATE_DIR..."
mkdir -p "$CONFIG_DIR"
mkdir -p "$STORAGE_DIR"

# --- Creation du fichier docker-compose.yml ---
log_info "Creation du fichier docker-compose.yml..."
cat << 'EOF' > "$COMPOSE_FILE"
services:
  frigate:
    container_name: frigate
    privileged: true
    restart: unless-stopped
    image: ghcr.io/blakeblackshear/frigate:stable
    shm_size: '2g'
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
    volumes:
      - ./config:/config
      - ./storage:/media/frigate
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 4096m
    ports:
      - "8971:8971" # Internal authenticated access
      - "5000:5000" # Internal unauthenticated access. Expose carefully.
      - "8554:8554" # RTSP feeds
      - "8555:8555/tcp" # WebRTC over tcp
#      - "8555:8555/udp" # WebRTC over udp
#      - "1935:1935" # RMTP feeds
EOF

# --- Creation du fichier config.yml ---
log_info "Creation du fichier de configuration config.yml..."
cat << 'EOF' > "$CONFIG_FILE"
mqtt:
  enabled: False
#  host: IP_frigate
#  user: mqtt
#  password: passwordmqtt
#  topic_prefix: frigate
#  client_id: frigate
#  stats_interval: 60

detectors:
  ov:
    type: openvino
    device: GPU

model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  path: /openvino-model/ssdlite_mobilenet_v2.xml
  labelmap_path: /openvino-model/coco_91cl_bkgr.txt

ffmpeg:
  hwaccel_args: preset-vaapi

go2rtc:
  streams:
    camera1:
      - rtsp://utilisateur:motdepasse@IP_camera1:554/
    camera1_sub:
      - rtsp://utilisateur:motdepasse@IP_camera1:554/
  webrtc:
    listen: 8555
    candidates:
      - 127.0.0.1:8555
      - IP_frigate:8555

cameras:
  camera1:
    ffmpeg:
      inputs:
        - path: rtsp://utilisateur:motdepasse@xxx.xxx.x.xx/camera1
          roles:
            - record
        - path: rtsp://utilisateur:motdepasse@xxx.xxx.x.xx/camera1_sub
          roles:
            - detect
    live:
      streams:
        main_stream: camera1
        #sub_streams: camera1_sub
    detect:
      enabled: true
      height: 360 # Hauteur des images utilisées pour la détection
      width: 640 # Largeur des images utilisées pour la détection
      fps: 5 # Taux de détection en images par seconde
    objects:
      track:
        - person
      filters:
        person:
          min_score: 0.7 # Optional: minimum score for the object to initiate tracking
          threshold: 0.8 # Optional: minimum decimal percentage for tracked object's computed score to be considered a true positive
    motion:
      threshold: 30 # Seuil de détection de mouvement
      contour_area: 10
      improve_contrast: true

record:
  enabled: true # Active l'enregistrement des vidéos
  expire_interval: 60
  retain:
    days: 0 # Nb de jour de sauvegarde des enregistrements, mettre 0 pour purger
    mode: motion # Enregistre uniquement les mouvements détectés
  alerts:
    pre_capture: 5 # Capture x secondes avant l'alerte
    post_capture: 5 # Capture x secondes apres l'alecte
    retain:
      days: 1 # Nb de jour de sauvegarde des alertes, mettre 0 pour purger
      mode: motion # Enregistre les alertes déclenchés par des mouvements
  detections:
    pre_capture: 5 # Nb de jour de sauvegarde des detections, mettre 0 pour purger
    post_capture: 5 # Nb de jour de sauvegarde des detections, mettre 0 pour purger
    retain:
      days: 1 # Nb de jour de sauvegarde des detections, mettre 0 pour purger
      mode: motion # Enregistre les detections déclenchés par des mouvements

snapshots:
  enabled: true
  bounding_box: true # Affiche une boîte de délimitation autour des objets détectés
  clean_copy: true # Garde une copie propre des snapshots sans annotations
  timestamp: false # Ajoute un timestamp aux snapshots
  crop: false # Ne recadre pas les snapshots
  quality: 70  # Contrôle la qualité de compression JPEG du snapshot, 70 est un bon equilibre entre qualité et taille de fichier
  retain:
    default: 1 # Nb de jour de sauvegarde des snapshots
    objects:
      person: 10
EOF

# --- Attribution des permissions ---
log_info "Attribution des permissions a l'utilisateur $TARGET_USER..."
chown -R "$TARGET_USER":"$TARGET_USER" "$FRIGATE_DIR"

log_success "La configuration de Frigate a ete creee avec succes."

# ==============================================================================
# FIN DU SCRIPT
# ==============================================================================
echo
log_success "--------------------------------------------------------"
log_success "L'installation est terminee !"
log_success "--------------------------------------------------------"
echo
log_info "Actions requises de votre part :"
log_info "1. Deconnectez-vous et reconnectez-vous avec l'utilisateur '$TARGET_USER' pour que les changements de groupe (sudo, docker) prennent effet."
log_info "2. Une fois reconnecte, naviguez vers le dossier Frigate avec : cd ~/frigate"
log_info "3. Lancez Frigate avec la commande : docker compose up -d"
echo
log_warning "IMPORTANT: N'oubliez pas de modifier le fichier '~/frigate/config/config.yml' pour ajouter vos cameras."
log_warning "Si vous utilisez MQTT, decommentez et configurez la section 'mqtt' dans ce m�me fichier."
echo