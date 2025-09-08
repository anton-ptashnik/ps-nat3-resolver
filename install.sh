set -e

SCRIPT_NAME=psnat3resolver
BASE_CONF_PATH=./config/base.conf.sh

source $BASE_CONF_PATH

echo "Installing dependencies..."
apt install -y wireguard jq moreutils tcpdump

echo "Checking WG keys presence"
if [[ ! -n "$WG_SERVER_PUBKEY" ]]; then
    echo "WG keys missing. Generating new keys..."
    export WG_SERVER_PRIVKEY=$(wg genkey)
    export WG_SERVER_PUBKEY=$(echo $WG_SERVER_PRIVKEY | wg pubkey)
    export WG_CLIENT_PRIVKEY=$(wg genkey)
    export WG_CLIENT_PUBKEY=$(echo $WG_CLIENT_PRIVKEY | wg pubkey)
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

echo "Installing a command shortcut (symlink)..."
rm -f /usr/local/bin/$SCRIPT_NAME
ln -s ./psnat3resolver /usr/local/bin/$SCRIPT_NAME
