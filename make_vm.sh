#!/usr/bin/env bash
set -euo pipefail

source config

az group create --name $RG_NAME --location $AZ_LOCATION --tags project=plex

az vm create \
    --resource-group $RG_NAME \
    --name $VM_NAME \
    --image Ubuntu2204 \
    --admin-username $VM_ADMIN_USERNAME \
    --ssh-key-values $VM_SSH_KEY_PATH \
    --public-ip-sku Standard \
    --location $AZ_LOCATION \
    --size Standard_B2s


az network nsg rule create \
    --name "AllowPlex32400" \
    --resource-group $RG_NAME \
    --nsg-name ${VM_NAME}NSG \
    --priority 1200 \
    --protocol Tcp \
    --direction Inbound \
    --source-address-prefix "*" \
    --source-port-range "*" \
    --destination-port-range 32400


az vm list-ip-addresses -g "$RG_NAME" -n "$VM_NAME" -o table