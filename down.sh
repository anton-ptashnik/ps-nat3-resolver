#!/bin/bash

set -e

SCRIPT_PATH=$(dirname "$0")
DATADIR_PATH=$SCRIPT_PATH
source $DATADIR_PATH/vars.sh

echo "Deactivating a WG link..."
wg-quick down wg0

echo "Removing a droplet..."
doctl compute droplet delete -f $DROPLET_NAME -t "$DO_TOKEN"
