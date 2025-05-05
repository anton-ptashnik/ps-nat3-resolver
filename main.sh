#!/bin/bash

set -e

SCRIPT_PATH=$(dirname "$0")
DATADIR_PATH=$SCRIPT_PATH/config

ACTION=$1

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
    echo "Render config templates"
    envsubst < $DATADIR_PATH/wg0-client-template.conf > ./wg0-client.conf
    envsubst < $DATADIR_PATH/wg0-server-template.conf > ./wg0-server.conf

    echo "Install dependencies"
    sudo apt install -y wireguard
    wget https://github.com/digitalocean/doctl/releases/download/v1.124.0/doctl-1.124.0-linux-amd64.tar.gz -O doctl.tar.gz
    tar xf doctl.tar.gz
    sudo mv ~/doctl /usr/local/bin
    rm doctl.tar.gz
    ;;

  *)
    echo "unknown command"
    ;;
esac
