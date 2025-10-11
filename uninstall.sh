#!/bin/bash

SCRIPT_NAME=psnat3resolver
SERVICE_NAME=psnat3resolverd

echo "Uninstalling $SERVICE_NAME service..."
systemctl disable "$SERVICE_NAME"
systemctl stop "$SERVICE_NAME"
rm "/usr/lib/systemd/system/$SERVICE_NAME.service"
systemctl daemon-reload

echo "Removing script shortcuts..."
rm /usr/local/bin/$SCRIPT_NAME
rm /usr/local/bin/$SERVICE_NAME

echo "Done!"
