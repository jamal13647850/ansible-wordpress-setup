#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

CLOUDFLARE_FILE_PATH=${1:-$SCRIPT_DIR'/cloudflare.conf'}
echo $CLOUDFLARE_FILE_PATH;
echo "#Cloudflare" > $CLOUDFLARE_FILE_PATH;
echo "" >> $CLOUDFLARE_FILE_PATH;

echo "# - IPv4" >> $CLOUDFLARE_FILE_PATH;
for i in `curl https://www.cloudflare.com/ips-v4`; do
        echo "set_real_ip_from $i;" >> $CLOUDFLARE_FILE_PATH;
done

echo "" >> $CLOUDFLARE_FILE_PATH;
echo "# - IPv6" >> $CLOUDFLARE_FILE_PATH;
for i in `curl https://www.cloudflare.com/ips-v6`; do
        echo "set_real_ip_from $i;" >> $CLOUDFLARE_FILE_PATH;
done

echo "" >> $CLOUDFLARE_FILE_PATH;
echo "real_ip_header CF-Connecting-IP;" >> $CLOUDFLARE_FILE_PATH;

if ! command -v csf >/dev/null 2>&1; then
    echo "Error: CSF is not installed. Skipping CSF rules."
else
    for i in `curl https://www.cloudflare.com/ips-v4`; do sudo csf -a $i; done
    for i in `curl https://www.cloudflare.com/ips-v4`; do sudo echo $i >> /etc/csf/csf.ignore; done
fi    

