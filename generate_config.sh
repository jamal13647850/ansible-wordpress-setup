#!/bin/bash

# Check if required tools are installed
command -v openssl >/dev/null 2>&1 || { echo "Error: 'openssl' is required but not installed. Install it with 'sudo apt install openssl'."; exit 1; }

# Define the output file
OUTPUT_FILE="group_vars/all.yml"

# Function to generate a secure random password
generate_password() {
    openssl rand -base64 20 | tr -d '/+=' | head -c 20
}

# Function to generate a random database prefix (e.g., wp_, kh_)
generate_db_prefix() {
    echo "$(cat /dev/urandom | tr -dc 'a-z' | head -c 2)_"
}

# Prompt user for required inputs
echo "Let's configure your WordPress deployment!"
echo "-----------------------------------------"

read -p "Enter your domain name (e.g., example.com): " DOMAIN
read -p "Enter WordPress admin username (e.g., admin): " WP_ADMIN_USER
read -p "Enter WordPress admin email (e.g., admin@example.com): " WP_ADMIN_EMAIL
read -p "Enter WordPress site title (e.g., My Site): " WP_TITLE
read -p "Enter WordPress locale (e.g., en_US, fa_IR): " WP_LOCALE
read -p "Enter SSL email for Certbot (e.g., your@email.com): " SSL_EMAIL
read -p "Enter PHP version (e.g., 8.3): " PHP_VERSION
read -p "Enter Linux username (e.g., ubuntu): " LINUX_USERNAME

# Generate secure random values
MYSQL_ROOT_PASSWORD=$(generate_password)
MYSQL_DB_NAME="wp_$(echo "$DOMAIN" | tr -d '.' | tr '[:upper:]' '[:lower:]')"
MYSQL_DB_USER="wpuser_$(echo "$DOMAIN" | tr -d '.' | tr '[:upper:]' '[:lower:]')"
MYSQL_DB_PASSWORD=$(generate_password)
WP_ADMIN_PASSWORD=$(generate_password)
WP_DB_PREFIX=$(generate_db_prefix)

# IP restriction configuration
echo -e "\nIP Restriction Configuration"
echo "-----------------------------"
read -p "Would you like to restrict access to specific IPs for WordPress recovery and file manager? (y/n): " RESTRICT_IP
if [[ "$RESTRICT_IP" =~ ^[Yy]$ ]]; then
    RESTRICT_IP_ACCESS="true"
    echo "Enter allowed IP addresses (one per line). Press Ctrl+D or Ctrl+C when done:"
    ALLOWED_IPS=""
    while IFS= read -r ip; do
        # ساده‌سازی: حذف فاصله‌ها و اطمینان از اینکه خط خالی نباشه
        ip=$(echo "$ip" | xargs)
        if [[ -n "$ip" ]]; then
            ALLOWED_IPS="$ALLOWED_IPS  - \"$ip\"\n"
        fi
    done
else
    RESTRICT_IP_ACCESS="false"
    ALLOWED_IPS=""
fi



# Basic Auth configuration
echo -e "\nBasic Authentication Configuration"
echo "----------------------------------"
read -p "Would you like to enable Basic Authentication for file manager and WordPress recovery? (y/n): " ENABLE_AUTH
if [[ "$ENABLE_AUTH" =~ ^[Yy]$ ]]; then
    ENABLE_BASIC_AUTH="true"
    read -p "Enter username for Basic Authentication: " BASIC_AUTH_USER
    read -s -p "Enter password for Basic Authentication: " BASIC_AUTH_PASSWORD
    echo ""  # خط جدید بعد از وارد کردن رمز
else
    ENABLE_BASIC_AUTH="false"
    BASIC_AUTH_USER=""
    BASIC_AUTH_PASSWORD=""
fi

# Create or overwrite the all.yml file
cat <<EOF > "$OUTPUT_FILE"
---
mysql_root_password: "$MYSQL_ROOT_PASSWORD"
mysql_db_name: "$MYSQL_DB_NAME"
mysql_db_user: "$MYSQL_DB_USER"
mysql_db_password: "$MYSQL_DB_PASSWORD"
domain: "$DOMAIN"
wordpress_admin_user: "$WP_ADMIN_USER"
wordpress_admin_password: "$WP_ADMIN_PASSWORD"
wordpress_admin_email: "$WP_ADMIN_EMAIL"
wordpress_title: "$WP_TITLE"
wordpress_locale: "$WP_LOCALE"
wordpress_db_prefix: "$WP_DB_PREFIX"
ssl_email: "$SSL_EMAIL"
php_version: "$PHP_VERSION"
linux_username: "$LINUX_USERNAME"
# IP restriction settings
restrict_ip_access: $RESTRICT_IP_ACCESS
allowed_ips:
$ALLOWED_IPS
# Basic Auth settings
enable_basic_auth: $ENABLE_BASIC_AUTH
basic_auth_user: "$BASIC_AUTH_USER"
basic_auth_password: "$BASIC_AUTH_PASSWORD"
EOF




# Secure the file permissions
chmod 600 "$OUTPUT_FILE"



# Display the generated values
if [[ "$ENABLE_BASIC_AUTH" == "true" ]]; then
    echo "Basic Authentication Enabled: Yes"
    echo "Basic Auth Username: $BASIC_AUTH_USER"
    echo "Basic Auth Password: [hidden for security]"
else
    echo "Basic Authentication Enabled: No"
fi



echo -e "\nConfiguration file '$OUTPUT_FILE' has been created with the following values:"
echo "------------------------------------------------"
echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
echo "MySQL Database Name: $MYSQL_DB_NAME"
echo "MySQL Database User: $MYSQL_DB_USER"
echo "MySQL Database Password: $MYSQL_DB_PASSWORD"
echo "WordPress Admin Password: $WP_ADMIN_PASSWORD"
echo "WordPress Database Prefix: $WP_DB_PREFIX"
if [[ "$RESTRICT_IP_ACCESS" == "true" ]]; then
    echo "IP Restriction Enabled: Yes"
    echo "Allowed IPs:"
    echo "$ALLOWED_IPS" | sed 's/  - /  - /g'
else
    echo "IP Restriction Enabled: No"
fi
echo "------------------------------------------------"
echo "Please save these values in a secure place!"

# Optional: Encrypt with Ansible Vault
read -p "Would you like to encrypt this file with Ansible Vault? (y/n): " ENCRYPT
if [[ "$ENCRYPT" =~ ^[Yy]$ ]]; then
    ansible-vault encrypt "$OUTPUT_FILE"
    if [ $? -eq 0 ]; then
        echo "File encrypted successfully. Use '--ask-vault-pass' when running Ansible playbooks."
    else
        echo "Encryption failed. Please check Ansible Vault installation."
    fi
else
    echo "File was not encrypted. Be sure to store it securely."
fi

echo -e "\nSetup complete! You can now run the Ansible playbooks."