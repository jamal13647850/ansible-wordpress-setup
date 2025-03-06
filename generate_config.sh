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
EOF

# Secure the file permissions
chmod 600 "$OUTPUT_FILE"

# Display the generated values
echo -e "\nConfiguration file '$OUTPUT_FILE' has been created with the following values:"
echo "------------------------------------------------"
echo "MySQL Root Password: $MYSQL_ROOT_PASSWORD"
echo "MySQL Database Name: $MYSQL_DB_NAME"
echo "MySQL Database User: $MYSQL_DB_USER"
echo "MySQL Database Password: $MYSQL_DB_PASSWORD"
echo "WordPress Admin Password: $WP_ADMIN_PASSWORD"
echo "WordPress Database Prefix: $WP_DB_PREFIX"
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