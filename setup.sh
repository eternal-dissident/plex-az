#!/usr/bin/env bash

# Install Plex Media Server on Ubuntu 22.04
sudo apt install -y curl apt-transport-https ca-certificates gnupg jq ufw
curl -fsSL https://downloads.plex.tv/plex-keys/PlexSign.key | sudo gpg --dearmor -o /usr/share/keyrings/plex.gpg
echo "deb [signed-by=/usr/share/keyrings/plex.gpg] https://downloads.plex.tv/repo/deb public main" | sudo tee /etc/apt/sources.list.d/plexmediaserver.list >/dev/null
sudo apt update
sudo apt install -y plexmediaserver
systemctl status plexmediaserver --no-pager

# Directories for transcoding and downloads
# You may want to set more restrictive permissions here
sudo mkdir -p /transcode
sudo chmod -R 777 /transcode
sudo mkdir -p /plexdl
sudo chmod -R 777 /plexdl

# Install blobfuse2
sudo wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt update
sudo apt install -y blobfuse2

# Prepare mount point and cache directories
sudo mkdir -p /srv/plexmedia
sudo mkdir -p /var/cache/blobfuse2/plex
sudo chmod 777 /srv/plexmedia /var/cache/blobfuse2/plex
echo "user_allow_other" | sudo tee -a /etc/fuse.conf >/dev/null

# Setup blobfuse2 as a service
sudo cp blobfuse2.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl start blobfuse2.service
sudo systemctl enable blobfuse2.service
systemctl status blobfuse2.service --no-pager

