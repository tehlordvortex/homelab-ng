#!/bin/ash
set -euo pipefail

# https://stackoverflow.com/questions/20983217/how-to-display-the-subject-alternative-name-of-a-certificate
# openssl x509 -noout -ext subjectAltName -in /cert/tls.crt |
#   grep -oE 'DNS:[^,]+' | grep -E '^DNS:\*' > /tmp/sans.txt
echo "$DNS_NAMES" >/tmp/sans.txt

# echo "DNS:*.kaos.nexus" >> /tmp/sans.txt
# echo "DNS:*.vrtx.sh" >> /tmp/sans.txt
# echo "DNS:*.vrtx.run" >> /tmp/sans.txt
# echo "DNS:*.sphns.run" >> /tmp/sans.txt
# echo "DNS:*.sophons.cloud" >> /tmp/sans.txt

echo "SANs:"
cat /tmp/sans.txt
