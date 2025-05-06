#!/bin/bash

set -e

SCRIPT_PATH=$(dirname "$0")
DATADIR_PATH=$SCRIPT_PATH/config
source $DATADIR_PATH/vars.sh

ACTION=$1

usage() {
    echo "Usage: sudo $0 up|down"
    echo
    echo "Note init is required before the first usage!"
    echo
    echo "Example:"
    echo "  sudo $0 init - to prepare the script for the first usage"
    echo "  sudo $0 up - to setup network"
    echo "  sudo $0 down - to cleanup network"
    exit 1
}

case $ACTION in
  up)
    echo "Create a droplet..."
    read SSH_KEY_FINGERPRINT <<< $(ssh-keygen -E md5 -lf "${SSH_KEY_PATH}.pub" | awk '{print $2}' | sed 's/^MD5://')
    RES=$(doctl compute droplet create $DROPLET_NAME --size s-1vcpu-512mb-10gb --image ubuntu-24-04-x64 --region nyc1 --ssh-keys $SSH_KEY_FINGERPRINT --wait --format PublicIPv4 --no-header -t "$DO_TOKEN")
    read SERVER_IP <<< $RES

    sed -i "/SERVER_IP/d" $DATADIR_PATH/vars.sh
    echo "SERVER_IP=$SERVER_IP" >> $DATADIR_PATH/vars.sh

    echo "Setup WG on a server"
    ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no root@$SERVER_IP "apt-get update && apt-get install -y wireguard"
    scp -i $SSH_KEY_PATH $DATADIR_PATH/wg0-server.conf root@$SERVER_IP:/etc/wireguard/wg0.conf

    echo "Setup WG on a client (this machine)"
    export SERVER_IP
    envsubst < $DATADIR_PATH/wg0-client.conf > /etc/wireguard/wg0.conf

    echo "Activate a WG link"
    ssh -i $SSH_KEY_PATH root@$SERVER_IP "wg-quick up wg0"
    wg-quick up wg0
    ;;

  down)
    echo "Deactivating a WG link..."
    wg-quick down wg0

    echo "Removing a droplet..."
    doctl compute droplet delete -f $DROPLET_NAME -t "$DO_TOKEN"
    ;;

  init)
    [[ -n "$DO_TOKEN" ]] || { echo "DO_TOKEN is not set. Please set and rerun"; exit 1; }
    [[ -n "$PS_IP" ]] || { echo "PS_IP is not set. Please set and rerun"; exit 1; }

    echo "Install dependencies"
    sudo apt install -y wireguard
    wget https://github.com/digitalocean/doctl/releases/download/v1.124.0/doctl-1.124.0-linux-amd64.tar.gz -O doctl.tar.gz
    tar xf doctl.tar.gz
    sudo mv ~/doctl /usr/local/bin
    rm doctl.tar.gz

    DEFAULT_SSH_KEY_PATH=$DATADIR_PATH/digital-ocean
    if [[ ! -n "$SSH_KEY_PATH" ]]; then
        echo "SSH_KEY_PATH is not set. Creating a key..."
        ssh-keygen -t ed25519 -N "" -f $DEFAULT_SSH_KEY_PATH -C "digital-ocean"
        SSH_KEY_PATH=$DEFAULT_SSH_KEY_PATH
        echo "SSH_KEY_PATH=$SSH_KEY_PATH" >> $DATADIR_PATH/vars.sh
    fi

    [[ -f "$SSH_KEY_PATH"  ]] || { echo "SSH key not found at $SSH_KEY_PATH. Please fix SSH_KEY_PATH and rerun"; exit 1; }

    SSH_PUBKEY_PATH="${SSH_KEY_PATH}.pub"

    read SSH_KEY_FINGERPRINT <<< $(ssh-keygen -E md5 -lf "${SSH_KEY_PATH}.pub" | awk '{print $2}' | sed 's/^MD5://')
    if ! doctl compute ssh-key get $SSH_KEY_FINGERPRINT -t "$DO_TOKEN" >& /dev/null; then
        echo "Uploading the key to Digital ocean"
        doctl compute ssh-key import example-key --public-key-file "$SSH_PUBKEY_PATH"
    else
        echo "Skip: Uploading the key to Digital ocean. The key already exists"
    fi

    echo "Check WG keys presence"
    if [[ ! -n "$WG_SERVER_PUBKEY" ]]; then
      echo "Generate WG keys"
      export WG_SERVER_PRIVKEY=$(wg genkey)
      export WG_SERVER_PUBKEY=$(echo $WG_SERVER_PRIVKEY | wg pubkey)
      export WG_CLIENT_PRIVKEY=$(wg genkey)
      export WG_CLIENT_PUBKEY=$(echo $WG_CLIENT_PRIVKEY | wg pubkey)
      echo "export WG_SERVER_PRIVKEY=$WG_SERVER_PRIVKEY" >> $DATADIR_PATH/vars.sh
      echo "export WG_SERVER_PUBKEY=$WG_SERVER_PUBKEY" >> $DATADIR_PATH/vars.sh
      echo "export WG_CLIENT_PRIVKEY=$WG_CLIENT_PRIVKEY" >> $DATADIR_PATH/vars.sh
      echo "export WG_CLIENT_PUBKEY=$WG_CLIENT_PUBKEY" >> $DATADIR_PATH/vars.sh
    fi

    echo "Render config templates"
    envsubst < $DATADIR_PATH/wg0-client-template.conf > $DATADIR_PATH/wg0-client.conf
    envsubst < $DATADIR_PATH/wg0-server-template.conf > $DATADIR_PATH/wg0-server.conf
    ;;

  *)
    usage
    ;;
esac
