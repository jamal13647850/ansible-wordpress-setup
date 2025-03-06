#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

ARVANCLOUD_FILE_PATH=${1:-$SCRIPT_DIR'/arvancloud.conf'}

echo "#ArvanCloud" > $ARVANCLOUD_FILE_PATH;
echo "" >> $ARVANCLOUD_FILE_PATH;

echo "# - IPv4" >> $ARVANCLOUD_FILE_PATH;
for i in `curl https://www.arvancloud.ir/fa/ips.txt`; do
    echo "set_real_ip_from $i;" >> $ARVANCLOUD_FILE_PATH;
done

echo "" >> $ARVANCLOUD_FILE_PATH;
echo "real_ip_header ar-real-ip;" >> $ARVANCLOUD_FILE_PATH;


for i in `curl https://www.arvancloud.ir/fa/ips.txt`; do sudo csf -a $i; done

for i in `curl https://www.arvancloud.ir/fa/ips.txt`; do sudo echo $i >> /etc/csf/csf.ignore; done