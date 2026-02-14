#!/bin/bash

DROPLETS_TO_DELETE=$(doctl compute droplet list --format Name,PublicIPv4 --no-header | grep -E 'wp-' | awk '{print $2}')

for droplet in $DROPLETS_TO_DELETE; do
	echo "Deleting droplet with IP: $droplet"
	doctl compute droplet delete "$droplet"
done