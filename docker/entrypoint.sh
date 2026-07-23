#!/bin/bash
cd /home/container || exit 1

INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
export INTERNAL_IP

mkdir -p /home/container/.cargo

echo "rust: $(rustc --version 2>/dev/null)  ·  cargo: $(cargo --version 2>/dev/null)"
echo "cloudflared: $(cloudflared --version 2>/dev/null | head -n1)"

# Replace {{VARIABLE}} with its environment value (Pterodactyl format)
MODIFIED_STARTUP=$(echo -e "$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

eval "${MODIFIED_STARTUP}"
