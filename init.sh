#!/bin/bash

set -e

SCRIPT_PATH=$(dirname "$0")
DATADIR_PATH=$SCRIPT_PATH
source $DATADIR_PATH/vars.sh

echo "Render config templates"
envsubst < $DATADIR_PATH/wg0-client-template.conf > ./wg0-client.conf
envsubst < $DATADIR_PATH/wg0-server-template.conf > ./wg0-server.conf

echo "Install dependencies"
sudo apt install -y wireguard
wget https://github.com/digitalocean/doctl/releases/download/v1.124.0/doctl-1.124.0-linux-amd64.tar.gz -O doctl.tar.gz
tar xf doctl.tar.gz
sudo mv ~/doctl /usr/local/bin
