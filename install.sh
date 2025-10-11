#!/bin/bash

set -e

SERVICE_NAME="psnat3resolverd"
REAL_PATH=$(realpath "$0")
SCRIPT_DIR_PATH=$(dirname "$REAL_PATH")
BASE_CONF_PATH=$SCRIPT_DIR_PATH/config/base.conf.sh

source $BASE_CONF_PATH

echo "Installing dependencies..."
apt install -y wireguard jq moreutils tcpdump

echo "Checking WG keys presence"
if [[ ! -n "$WG_SERVER_PUBKEY" ]]; then
    echo "WG keys missing. Generating new keys..."
    WG_SERVER_PRIVKEY=$(wg genkey)
    WG_SERVER_PUBKEY=$(echo $WG_SERVER_PRIVKEY | wg pubkey)
    WG_CLIENT_PRIVKEY=$(wg genkey)
    WG_CLIENT_PUBKEY=$(echo $WG_CLIENT_PRIVKEY | wg pubkey)
    echo "export WG_SERVER_PRIVKEY='$WG_SERVER_PRIVKEY'" >> $BASE_CONF_PATH
    echo "export WG_SERVER_PUBKEY='$WG_SERVER_PUBKEY'" >> $BASE_CONF_PATH
    echo "export WG_CLIENT_PRIVKEY='$WG_CLIENT_PRIVKEY'" >> $BASE_CONF_PATH
    echo "export WG_CLIENT_PUBKEY='$WG_CLIENT_PUBKEY'" >> $BASE_CONF_PATH
fi

echo "Checking SSH key presence"
if [[ ! -f "$SSH_KEY_PATH" ]]; then
    KEY_NAME=$(basename "$SSH_KEY_PATH")
    echo "SSH key is missing at $SSH_KEY_PATH. Creating a key..."
    ssh-keygen -t ed25519 -N "" -f $SSH_KEY_PATH -C "$KEY_NAME"
fi

chmod +x ./psnat3resolver
chmod +x ./psnat3resolver-auto
chmod +x ./psnat3resolverd

echo "Installing a script shortcut..."
ln -sf "$SCRIPT_DIR_PATH/psnat3resolver" /usr/local/bin/psnat3resolver

echo "Installing $SERVICE_NAME service..."
ln -sf "$SCRIPT_DIR_PATH/$SERVICE_NAME" /usr/local/bin/$SERVICE_NAME
ln -sf "$SCRIPT_DIR_PATH/$SERVICE_NAME.service" /usr/lib/systemd/system/$SERVICE_NAME.service

systemctl daemon-reload

echo "Done!"
