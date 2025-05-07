#!/bin/bash

set -e

SCRIPT_PATH=$(dirname "$0")
DATADIR_PATH=$SCRIPT_PATH/config
BASE_CONF_PATH=$DATADIR_PATH/base.conf.sh
USER_CONF_PATH=$DATADIR_PATH/user.conf

source $BASE_CONF_PATH
source $USER_CONF_PATH

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
do_create_droplet ()
{
  local DROPLET_NAME=$1
  DROPLET_ID=$(curl -sS -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DO_TOKEN" \
    -d "{\"name\":\"$DROPLET_NAME\",\"region\":\"nyc1\",\"size\":\"s-1vcpu-512mb-10gb\",\"image\":\"ubuntu-24-04-x64\",\"ssh_keys\":[\"$SSH_KEY_FINGERPRINT\"]}" \
    "https://api.digitalocean.com/v2/droplets" | jq .droplet.id)
  SERVER_IP=$(timeout 50 sh -c '
    DO_TOKEN=$0
    DROPLET_ID=$1
    IPADDR=null
    until [ "$IPADDR" != "null" ]; do 
      sleep 5
      IPADDR=$(curl -sS -X GET \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $DO_TOKEN" \
        "https://api.digitalocean.com/v2/droplets/$DROPLET_ID" | jq ".droplet.networks.v4 | map(select(.type == \"public\")) | first | .ip_address")
    done
    echo $IPADDR
  ' "$DO_TOKEN" "$DROPLET_ID")
  SERVER_IP=$(echo "$SERVER_IP" | tr -d '"')
  echo "$DROPLET_ID $SERVER_IP"
}
do_remove_droplet ()
{
  local DROPLET_ID=$1
  curl -X DELETE \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DO_TOKEN" \
    "https://api.digitalocean.com/v2/droplets/$DROPLET_ID"
}
do_check_sshkey_allowed ()
{
  SSH_KEY_FINGERPRINT=$1
  OUT=$(curl -sS -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DO_TOKEN" \
    "https://api.digitalocean.com/v2/account/keys" \
    | jq ".ssh_keys | map(select(.fingerprint == \"$SSH_KEY_FINGERPRINT\")) | first")
  [ "$OUT" != "null" ]
}
do_allow_sshkey ()
{
  SSH_PUBKEY_PATH=$1
  SSH_PUBKEY=$(<$SSH_PUBKEY_PATH)
  curl -sS -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DO_TOKEN" \
    -d "{\"name\":\"droplet-key\",\"public_key\":\"$SSH_PUBKEY\"}" \
    "https://api.digitalocean.com/v2/account/keys" >& /dev/null
}

case $ACTION in
  up)
    echo "Create a droplet..."
    read SSH_KEY_FINGERPRINT <<< $(ssh-keygen -E md5 -lf "${SSH_KEY_PATH}.pub" | awk '{print $2}' | sed 's/^MD5://')
    read DROPLET_ID SERVER_IP <<< "$(do_create_droplet $DROPLET_NAME)"

    sed -i "/SERVER_IP/d" $BASE_CONF_PATH
    sed -i "/DROPLET_ID/d" $BASE_CONF_PATH
    echo "SERVER_IP=$SERVER_IP" >> $BASE_CONF_PATH
    echo "DROPLET_ID=$DROPLET_ID" >> $BASE_CONF_PATH

    echo "Wait for a server to be accessible"
    export SERVER_IP
    export SSH_KEY_PATH
    timeout 50 sh -c '
      until ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no root@$SERVER_IP "echo Server is ready"; do
        echo "Server is still offline, waiting..."
        sleep 5
      done
    ' || { echo "Failed to connect to the server within 50sec"; exit 1; }

    echo "Setup WG on a server"
    timeout 80 sh -c '
      until ssh -i $SSH_KEY_PATH root@$SERVER_IP "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y wireguard"; do
        echo "Retrying server setup in 10sec..."
        sleep 10
      done
    '
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
    do_remove_droplet "$DROPLET_ID"
    ;;

  init)
    [[ -n "$DO_TOKEN" ]] || { echo "DO_TOKEN is not set. Please set and rerun"; exit 1; }
    [[ -n "$PS_IP" ]] || { echo "PS_IP is not set. Please set and rerun"; exit 1; }

    echo "Install dependencies"
    sudo apt install -y wireguard
    sudo apt install -y jq

    DEFAULT_SSH_KEY_PATH=$DATADIR_PATH/digital-ocean
    if [[ ! -n "$SSH_KEY_PATH" ]]; then
        echo "SSH_KEY_PATH is not set. Creating a key..."
        ssh-keygen -t ed25519 -N "" -f $DEFAULT_SSH_KEY_PATH -C "digital-ocean"
        SSH_KEY_PATH=$DEFAULT_SSH_KEY_PATH
        echo "SSH_KEY_PATH=$SSH_KEY_PATH" >> $USER_CONF_PATH
    fi

    [[ -f "$SSH_KEY_PATH"  ]] || { echo "SSH key not found at $SSH_KEY_PATH. Please fix SSH_KEY_PATH and rerun"; exit 1; }

    SSH_PUBKEY_PATH="${SSH_KEY_PATH}.pub"

    echo "Check the SSH key is allowed on DO"
    read SSH_KEY_FINGERPRINT <<< $(ssh-keygen -E md5 -lf "${SSH_KEY_PATH}.pub" | awk '{print $2}' | sed 's/^MD5://')
    if ! do_check_sshkey_allowed "$SSH_KEY_FINGERPRINT"; then
       echo "New SSH key. Do upload to allow on DO"
       do_upload_sshkey "$SSH_PUBKEY_PATH"
    fi

    echo "Check WG keys presence"
    if [[ ! -n "$WG_SERVER_PUBKEY" ]]; then
      echo "Generate WG keys"
      export WG_SERVER_PRIVKEY=$(wg genkey)
      export WG_SERVER_PUBKEY=$(echo $WG_SERVER_PRIVKEY | wg pubkey)
      export WG_CLIENT_PRIVKEY=$(wg genkey)
      export WG_CLIENT_PUBKEY=$(echo $WG_CLIENT_PRIVKEY | wg pubkey)
      echo "export WG_SERVER_PRIVKEY=$WG_SERVER_PRIVKEY" >> $BASE_CONF_PATH
      echo "export WG_SERVER_PUBKEY=$WG_SERVER_PUBKEY" >> $BASE_CONF_PATH
      echo "export WG_CLIENT_PRIVKEY=$WG_CLIENT_PRIVKEY" >> $BASE_CONF_PATH
      echo "export WG_CLIENT_PUBKEY=$WG_CLIENT_PUBKEY" >> $BASE_CONF_PATH
    fi

    echo "Render config templates"
    export PS_IP
    export SERVER_IP='$SERVER_IP'
    envsubst < $DATADIR_PATH/wg0-client-template.conf > $DATADIR_PATH/wg0-client.conf
    envsubst < $DATADIR_PATH/wg0-server-template.conf > $DATADIR_PATH/wg0-server.conf
    ;;

  *)
    usage
    ;;
esac
