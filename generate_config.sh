#!/bin/bash

# Check for dependencies
command -v dialog >/dev/null 2>&1 || { echo "Error: 'dialog' is required but not installed. Install it with 'sudo apt install dialog'."; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "Error: 'openssl' is required but not installed. Install it with 'sudo apt install openssl'."; exit 1; }

# Define the output file
OUTPUT_FILE="group_vars/all.yml"
TEMP_FILE="/tmp/wp_config_temp_$$"

# Function to generate a secure random password
generate_password() {
    openssl rand -base64 20 | tr -d '/+=' | head -c 20
}

# Function to generate a random database prefix
generate_db_prefix() {
    echo "$(cat /dev/urandom | tr -dc 'a-z' | head -c 2)_"
}

# Cleanup function for temporary files
cleanup() {
    rm -f "$TEMP_FILE" "$TEMP_FILE"_* 2>/dev/null
}

trap cleanup EXIT

# Main menu function
main_menu() {
    dialog --title "WordPress Deployment Configuration" \
           --menu "Select a configuration category:" 15 50 8 \
           1 "Domain Settings" \
           2 "Basic Settings" \
           3 "Security Settings" \
           4 "Performance Settings" \
           5 "Plugins and Themes" \
           6 "Backup and Migration" \
           7 "Advanced Features" \
           8 "Generate Configuration" 2>"$TEMP_FILE"
    CHOICE=$(cat "$TEMP_FILE")
}

# Domain Settings
domain_settings() {
    dialog --title "Domain Settings" --yesno "Would you like to configure multiple domains?" 10 50
    MULTI_DOMAIN=$([[ $? -eq 0 ]] && echo "true" || echo "false")

    if [ "$MULTI_DOMAIN" = "true" ]; then
        dialog --title "Domain Settings" --inputbox "Enter domains (comma-separated, e.g., mysite.com,newsite.com):" 10 50 "" 2>"$TEMP_FILE"
        DOMAINS=$(cat "$TEMP_FILE" | tr ',' ' ')
    else
        dialog --title "Domain Settings" --inputbox "Enter domain name (e.g., mysite.com):" 10 50 "" 2>"$TEMP_FILE"
        DOMAINS=$(cat "$TEMP_FILE")
    fi
}

# Basic Settings for a single domain
basic_settings() {
    local domain=$1
    dialog --title "Basic Settings for $domain" --form "Enter basic configuration details for $domain:" 15 60 8 \
           "WP Admin Username:" 1 1 "${WP_ADMIN_USER:-admin}" 1 20 30 50 \
           "WP Admin Email:" 2 1 "${WP_ADMIN_EMAIL:-admin@$domain}" 2 20 30 255 \
           "WP Site Title:" 3 1 "${WP_TITLE:-My Site}" 3 20 30 255 \
           "WP Locale:" 4 1 "${WP_LOCALE:-en_US}" 4 20 10 10 \
           "SSL Email:" 5 1 "${SSL_EMAIL:-admin@$domain}" 5 20 30 255 \
           "PHP Version:" 6 1 "${PHP_VERSION:-8.3}" 6 20 10 10 \
           "Linux Username:" 7 1 "${LINUX_USERNAME:-ubuntu}" 7 20 30 50 \
           2>"$TEMP_FILE"
    IFS=$'\n' read -r -d '' WP_ADMIN_USER WP_ADMIN_EMAIL WP_TITLE WP_LOCALE SSL_EMAIL PHP_VERSION LINUX_USERNAME < "$TEMP_FILE"

    MYSQL_ROOT_PASSWORD=$(generate_password)
    MYSQL_DB_NAME="wp_$(echo "$domain" | tr -d '.' | tr '[:upper:]' '[:lower:]')"
    MYSQL_DB_USER="wpuser_$(echo "$domain" | tr -d '.' | tr '[:upper:]' '[:lower:]')"
    MYSQL_DB_PASSWORD=$(generate_password)
    WP_ADMIN_PASSWORD=$(generate_password)
    WP_DB_PREFIX=$(generate_db_prefix)

    # Store settings for this domain
    eval "DOMAIN_${domain//./_}_SETTINGS='
mysql_root_password: \"$MYSQL_ROOT_PASSWORD\"
mysql_db_name: \"$MYSQL_DB_NAME\"
mysql_db_user: \"$MYSQL_DB_USER\"
mysql_db_password: \"$MYSQL_DB_PASSWORD\"
domain: \"$domain\"
wordpress_admin_user: \"$WP_ADMIN_USER\"
wordpress_admin_password: \"$WP_ADMIN_PASSWORD\"
wordpress_admin_email: \"$WP_ADMIN_EMAIL\"
wordpress_title: \"$WP_TITLE\"
wordpress_locale: \"$WP_LOCALE\"
wordpress_db_prefix: \"$WP_DB_PREFIX\"
ssl_email: \"$SSL_EMAIL\"
php_version: \"$PHP_VERSION\"
linux_username: \"$LINUX_USERNAME\"'"
}

# Security Settings
security_settings() {
    dialog --title "Security Settings" --checklist "Select security options:" 20 60 12 \
           "restrict_ip" "Restrict IP access" off \
           "basic_auth" "Enable Basic Authentication" off \
           "ssh_security" "Secure SSH access" off \
           "anti_hack" "Advanced anti-hack measures" off \
           "anti_bot" "Anti-bot protection" off \
           "anti_ddos" "Anti-DDoS protection" off \
           "waf" "Web Application Firewall" off \
           "login_limit" "Limit login attempts" off 2>"$TEMP_FILE"
    SECURITY_OPTIONS=$(cat "$TEMP_FILE")

    if echo "$SECURITY_OPTIONS" | grep -q "restrict_ip"; then
        RESTRICT_IP_ACCESS="true"
        dialog --title "IP Restriction" --inputbox "Enter allowed IPs (comma-separated):" 10 50 "" 2>"$TEMP_FILE"
        IPS=$(cat "$TEMP_FILE")
        ALLOWED_IPS=""
        for ip in $(echo "$IPS" | tr ',' ' '); do
            ALLOWED_IPS="$ALLOWED_IPS  - \"$ip\"\n"
        done
    else
        RESTRICT_IP_ACCESS="false"
        ALLOWED_IPS=""
    fi

    if echo "$SECURITY_OPTIONS" | grep -q "basic_auth"; then
        ENABLE_BASIC_AUTH="true"
        dialog --title "Basic Authentication" --form "Enter credentials:" 10 50 2 \
               "Username:" 1 1 "$BASIC_AUTH_USER" 1 20 20 50 \
               "Password:" 2 1 "$BASIC_AUTH_PASSWORD" 2 20 20 50 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' BASIC_AUTH_USER BASIC_AUTH_PASSWORD < "$TEMP_FILE"
    else
        ENABLE_BASIC_AUTH="false"
        BASIC_AUTH_USER=""
        BASIC_AUTH_PASSWORD=""
    fi

    ENABLE_SSH_SECURITY=$(echo "$SECURITY_OPTIONS" | grep -q "ssh_security" && echo "true" || echo "false")
    ENABLE_ANTI_HACK=$(echo "$SECURITY_OPTIONS" | grep -q "anti_hack" && echo "true" || echo "false")
    ENABLE_ANTI_BOT=$(echo "$SECURITY_OPTIONS" | grep -q "anti_bot" && echo "true" || echo "false")
    ENABLE_ANTI_DDOS=$(echo "$SECURITY_OPTIONS" | grep -q "anti_ddos" && echo "true" || echo "false")
    ENABLE_WAF=$(echo "$SECURITY_OPTIONS" | grep -q "waf" && echo "true" || echo "false")
    ENABLE_LOGIN_LIMIT=$(echo "$SECURITY_OPTIONS" | grep -q "login_limit" && echo "true" || echo "false")
}

# Performance Settings
performance_settings() {
    dialog --title "Performance Settings" --checklist "Select performance options:" 20 60 12 \
           "php_opcache" "PHP OPcache" off \
           "redis" "Redis caching" off \
           "advanced_caching" "Advanced caching (e.g., Memcached)" off \
           "cdn" "CDN (e.g., Cloudflare)" off \
           "local_cdn" "Local CDN (e.g., ArvanCloud)" off \
           "lazy_loading" "Lazy loading" off \
           "browser_caching" "Browser caching" off \
           "db_optimization" "Database optimization" off \
           "quic_http3" "QUIC/HTTP3" off \
           "dynamic_caching" "Dynamic caching (e.g., Varnish)" off \
           "performance_report" "Performance report" off 2>"$TEMP_FILE"
    PERFORMANCE_OPTIONS=$(cat "$TEMP_FILE")

    if echo "$PERFORMANCE_OPTIONS" | grep -q "php_opcache"; then
        ENABLE_PHP_OPCACHE="true"
        dialog --title "PHP OPcache" --inputbox "Enter OPcache memory (default: 128):" 10 50 "128" 2>"$TEMP_FILE"
        OPCACHE_MEMORY=$(cat "$TEMP_FILE")
    else
        ENABLE_PHP_OPCACHE="false"
        OPCACHE_MEMORY=""
    fi

    if echo "$PERFORMANCE_OPTIONS" | grep -q "redis"; then
        INSTALL_REDIS="true"
        WP_REDIS_HOST="127.0.0.1"
        WP_REDIS_PORT="6379"
        WP_REDIS_PASSWORD=$(generate_password)
        dialog --title "Redis" --inputbox "Enter Redis database (0-15, default: 0):" 10 50 "0" 2>"$TEMP_FILE"
        WP_REDIS_DATABASE=$(cat "$TEMP_FILE")
    else
        INSTALL_REDIS="false"
        WP_REDIS_HOST=""
        WP_REDIS_PORT=""
        WP_REDIS_PASSWORD=""
        WP_REDIS_DATABASE=""
    fi

    if echo "$PERFORMANCE_OPTIONS" | grep -q "advanced_caching"; then
        ENABLE_ADVANCED_CACHING="true"
        dialog --title "Advanced Caching" --inputbox "Enter caching type (redis/memcached, default: memcached):" 10 50 "memcached" 2>"$TEMP_FILE"
        CACHE_TYPE=$(cat "$TEMP_FILE")
    else
        ENABLE_ADVANCED_CACHING="false"
        CACHE_TYPE=""
    fi

    if echo "$PERFORMANCE_OPTIONS" | grep -q "cdn"; then
        ENABLE_CDN="true"
        dialog --title "CDN" --form "Enter CDN details:" 15 60 3 \
               "Provider:" 1 1 "$CDN_PROVIDER" 1 20 20 50 \
               "API Key:" 2 1 "$CDN_API_KEY" 2 20 40 255 \
               "Account/Email:" 3 1 "$CDN_ACCOUNT" 3 20 40 255 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' CDN_PROVIDER CDN_API_KEY CDN_ACCOUNT < "$TEMP_FILE"
    else
        ENABLE_CDN="false"
        CDN_PROVIDER=""
        CDN_API_KEY=""
        CDN_ACCOUNT=""
    fi

    if echo "$PERFORMANCE_OPTIONS" | grep -q "local_cdn"; then
        ENABLE_LOCAL_CDN="true"
        dialog --title "Local CDN" --form "Enter Local CDN details:" 10 60 2 \
               "Provider:" 1 1 "$LOCAL_CDN_PROVIDER" 1 20 20 50 \
               "API Key:" 2 1 "$LOCAL_CDN_API_KEY" 2 20 40 255 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' LOCAL_CDN_PROVIDER LOCAL_CDN_API_KEY < "$TEMP_FILE"
    else
        ENABLE_LOCAL_CDN="false"
        LOCAL_CDN_PROVIDER=""
        LOCAL_CDN_API_KEY=""
    fi

    ENABLE_LAZY_LOADING=$(echo "$PERFORMANCE_OPTIONS" | grep -q "lazy_loading" && echo "true" || echo "false")
    ENABLE_BROWSER_CACHING=$(echo "$PERFORMANCE_OPTIONS" | grep -q "browser_caching" && echo "true" || echo "false")
    ENABLE_DB_OPTIMIZATION=$(echo "$PERFORMANCE_OPTIONS" | grep -q "db_optimization" && echo "true" || echo "false")
    ENABLE_QUIC_HTTP3=$(echo "$PERFORMANCE_OPTIONS" | grep -q "quic_http3" && echo "true" || echo "false")
    ENABLE_DYNAMIC_CACHING=$(echo "$PERFORMANCE_OPTIONS" | grep -q "dynamic_caching" && echo "true" || echo "false")
    ENABLE_PERFORMANCE_REPORT=$(echo "$PERFORMANCE_OPTIONS" | grep -q "performance_report" && echo "true" || echo "false")
}

# Plugins and Themes
plugins_themes() {
    dialog --title "Plugins and Themes" --checklist "Select options:" 15 60 7 \
           "plugins" "Install WordPress plugins" off \
           "seo" "Basic SEO setup" off \
           "woocommerce" "WooCommerce store" off \
           "form_builder" "Form builder (e.g., Contact Form 7)" off \
           "plugin_categories" "Plugin categories" off 2>"$TEMP_FILE"
    PLUGINS_OPTIONS=$(cat "$TEMP_FILE")

    if echo "$PLUGINS_OPTIONS" | grep -q "plugins"; then
        INSTALL_PLUGINS="true"
        dialog --title "Plugins" --inputbox "Enter plugins (slug or ZIP path, comma-separated):" 10 50 "" 2>"$TEMP_FILE"
        PLUGINS_LIST=$(cat "$TEMP_FILE")
        PLUGINS=""
        for plugin in $(echo "$PLUGINS_LIST" | tr ',' ' '); do
            if [[ "$plugin" =~ \.zip$ && -f "$plugin" ]]; then
                PLUGINS="$PLUGINS  - { path: \"$plugin\", source: \"local\" }\n"
            else
                PLUGINS="$PLUGINS  - { slug: \"$plugin\", source: \"wordpress\" }\n"
            fi
        done
    else
        INSTALL_PLUGINS="false"
        PLUGINS=""
    fi

    ENABLE_SEO=$(echo "$PLUGINS_OPTIONS" | grep -q "seo" && echo "true" || echo "false")
    ENABLE_WOOCOMMERCE=$(echo "$PLUGINS_OPTIONS" | grep -q "woocommerce" && echo "true" || echo "false")
    ENABLE_FORM_BUILDER=$(echo "$PLUGINS_OPTIONS" | grep -q "form_builder" && echo "true" || echo "false")
    if echo "$PLUGINS_OPTIONS" | grep -q "plugin_categories"; then
        ENABLE_PLUGIN_CATEGORIES="true"
        dialog --title "Plugin Categories" --inputbox "Enter categories (e.g., security,seo):" 10 50 "" 2>"$TEMP_FILE"
        PLUGIN_CATEGORIES=$(cat "$TEMP_FILE")
    else
        ENABLE_PLUGIN_CATEGORIES="false"
        PLUGIN_CATEGORIES=""
    fi
}

# Backup and Migration
backup_migration() {
    dialog --title "Backup and Migration" --checklist "Select options:" 15 60 6 \
           "backups" "Automatic backups" off \
           "advanced_backup" "Advanced backup (e.g., UpdraftPlus)" off \
           "migration" "Migrate existing site" off \
           "rollback" "Automatic rollback" off 2>"$TEMP_FILE"
    BACKUP_OPTIONS=$(cat "$TEMP_FILE")

    if echo "$BACKUP_OPTIONS" | grep -q "backups"; then
        ENABLE_BACKUPS="true"
        dialog --title "Backups" --form "Enter backup details:" 10 60 2 \
               "Directory:" 1 1 "$BACKUP_DIR" 1 20 30 255 \
               "Frequency:" 2 1 "$BACKUP_FREQ" 2 20 20 50 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' BACKUP_DIR BACKUP_FREQ < "$TEMP_FILE"
        BACKUP_DIR=${BACKUP_DIR:-"/var/backups"}
        BACKUP_FREQ=${BACKUP_FREQ:-"0 2 * * *"}
    else
        ENABLE_BACKUPS="false"
        BACKUP_DIR=""
        BACKUP_FREQ=""
    fi

    ENABLE_ADVANCED_BACKUP=$(echo "$BACKUP_OPTIONS" | grep -q "advanced_backup" && echo "true" || echo "false")

    if echo "$BACKUP_OPTIONS" | grep -q "migration"; then
        ENABLE_MIGRATION="true"
        dialog --title "Migration" --form "Enter migration details:" 10 60 2 \
               "DB Backup Path:" 1 1 "$MIGRATION_DB_PATH" 1 20 30 255 \
               "Files Backup Path:" 2 1 "$MIGRATION_FILES_PATH" 2 20 30 255 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' MIGRATION_DB_PATH MIGRATION_FILES_PATH < "$TEMP_FILE"
    else
        ENABLE_MIGRATION="false"
        MIGRATION_DB_PATH=""
        MIGRATION_FILES_PATH=""
    fi

    ENABLE_ROLLBACK=$(echo "$BACKUP_OPTIONS" | grep -q "rollback" && echo "true" || echo "false")
}

# Advanced Features
advanced_features() {
    dialog --title "Advanced Features" --checklist "Select options:" 20 60 12 \
           "multisite" "WordPress Multisite" off \
           "smtp" "SMTP email" off \
           "monitoring" "Monitoring and logging" off \
           "image_optimization" "Image optimization" off \
           "add_wp_users" "Add WordPress users" off \
           "auto_test" "Auto-test after install" off \
           "php_versions" "Manage PHP versions" off \
           "staging" "Staging environment" off \
           "headless_cms" "Headless CMS" off \
           "dev_tools" "Developer tools (e.g., phpMyAdmin)" off \
           "cloud_monitoring" "Cloud monitoring (e.g., UptimeRobot)" off 2>"$TEMP_FILE"
    ADVANCED_OPTIONS=$(cat "$TEMP_FILE")

    if echo "$ADVANCED_OPTIONS" | grep -q "multisite"; then
        ENABLE_MULTISITE="true"
        dialog --title "Multisite" --inputbox "Enter type (subdomain/subdirectory, default: subdomain):" 10 50 "subdomain" 2>"$TEMP_FILE"
        MULTISITE_TYPE=$(cat "$TEMP_FILE")
    else
        ENABLE_MULTISITE="false"
        MULTISITE_TYPE=""
    fi

    if echo "$ADVANCED_OPTIONS" | grep -q "smtp"; then
        ENABLE_SMTP="true"
        dialog --title "SMTP" --form "Enter SMTP details:" 15 60 4 \
               "Host:" 1 1 "$SMTP_HOST" 1 20 30 255 \
               "Port:" 2 1 "$SMTP_PORT" 2 20 10 10 \
               "Username:" 3 1 "$SMTP_USERNAME" 3 20 30 50 \
               "Password:" 4 1 "$SMTP_PASSWORD" 4 20 30 50 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD < "$TEMP_FILE"
    else
        ENABLE_SMTP="false"
        SMTP_HOST=""
        SMTP_PORT=""
        SMTP_USERNAME=""
        SMTP_PASSWORD=""
    fi

    if echo "$ADVANCED_OPTIONS" | grep -q "monitoring"; then
        ENABLE_MONITORING="true"
        dialog --title "Monitoring" --yesno "Enable WP_DEBUG logging?" 10 50
        WP_DEBUG=$([[ $? -eq 0 ]] && echo "true" || echo "false")
    else
        ENABLE_MONITORING="false"
        WP_DEBUG="false"
    fi

    ENABLE_IMAGE_OPTIMIZATION=$(echo "$ADVANCED_OPTIONS" | grep -q "image_optimization" && echo "true" || echo "false")

    if echo "$ADVANCED_OPTIONS" | grep -q "add_wp_users"; then
        ADD_WP_USERS="true"
        dialog --title "WordPress Users" --inputbox "Enter users (username:role:email, comma-separated):" 10 50 "" 2>"$TEMP_FILE"
        USERS=$(cat "$TEMP_FILE")
        WP_USERS=""
        for user in $(echo "$USERS" | tr ',' ' '); do
            IFS=':' read -r username role email <<< "$user"
            WP_USERS="$WP_USERS  - { username: \"$username\", role: \"$role\", email: \"$email\" }\n"
        done
    else
        ADD_WP_USERS="false"
        WP_USERS=""
    fi

    ENABLE_AUTO_TEST=$(echo "$ADVANCED_OPTIONS" | grep -q "auto_test" && echo "true" || echo "false")

    if echo "$ADVANCED_OPTIONS" | grep -q "php_versions"; then
        ENABLE_PHP_VERSIONS="true"
        dialog --title "PHP Versions" --inputbox "Enter additional PHP versions (e.g., 7.4,8.0):" 10 50 "" 2>"$TEMP_FILE"
        PHP_ADDITIONAL_VERSIONS=$(cat "$TEMP_FILE")
    else
        ENABLE_PHP_VERSIONS="false"
        PHP_ADDITIONAL_VERSIONS=""
    fi

    if echo "$ADVANCED_OPTIONS" | grep -q "staging"; then
        ENABLE_STAGING="true"
        dialog --title "Staging" --inputbox "Enter staging subdomain (e.g., staging):" 10 50 "" 2>"$TEMP_FILE"
        STAGING_SUBDOMAIN=$(cat "$TEMP_FILE")
    else
        ENABLE_STAGING="false"
        STAGING_SUBDOMAIN=""
    fi

    ENABLE_HEADLESS_CMS=$(echo "$ADVANCED_OPTIONS" | grep -q "headless_cms" && echo "true" || echo "false")
    ENABLE_DEV_TOOLS=$(echo "$ADVANCED_OPTIONS" | grep -q "dev_tools" && echo "true" || echo "false")

    if echo "$ADVANCED_OPTIONS" | grep -q "cloud_monitoring"; then
        ENABLE_CLOUD_MONITORING="true"
        dialog --title "Cloud Monitoring" --inputbox "Enter API key (e.g., UptimeRobot):" 10 50 "" 2>"$TEMP_FILE"
        CLOUD_MONITORING_API_KEY=$(cat "$TEMP_FILE")
    else
        ENABLE_CLOUD_MONITORING="false"
        CLOUD_MONITORING_API_KEY=""
    fi
}

# Generate Configuration
generate_config() {
    cat <<EOF > "$OUTPUT_FILE"
---
domains:
EOF

    for domain in $DOMAINS; do
        eval "echo \"  $domain:\" >> \"$OUTPUT_FILE\""
        eval "echo \"\${DOMAIN_${domain//./_}_SETTINGS}\" >> \"$OUTPUT_FILE\""
        cat <<EOF >> "$OUTPUT_FILE"
    restrict_ip_access: $RESTRICT_IP_ACCESS
    allowed_ips:
$ALLOWED_IPS
    enable_basic_auth: $ENABLE_BASIC_AUTH
    basic_auth_user: "$BASIC_AUTH_USER"
    basic_auth_password: "$BASIC_AUTH_PASSWORD"
    enable_ssh_security: $ENABLE_SSH_SECURITY
    enable_anti_hack: $ENABLE_ANTI_HACK
    enable_anti_bot: $ENABLE_ANTI_BOT
    enable_anti_ddos: $ENABLE_ANTI_DDOS
    enable_waf: $ENABLE_WAF
    enable_login_limit: $ENABLE_LOGIN_LIMIT
    enable_php_opcache: $ENABLE_PHP_OPCACHE
    opcache_memory: "$OPCACHE_MEMORY"
    install_redis: $INSTALL_REDIS
    wp_redis_host: "$WP_REDIS_HOST"
    wp_redis_port: "$WP_REDIS_PORT"
    wp_redis_password: "$WP_REDIS_PASSWORD"
    wp_redis_database: "$WP_REDIS_DATABASE"
    enable_advanced_caching: $ENABLE_ADVANCED_CACHING
    cache_type: "$CACHE_TYPE"
    enable_cdn: $ENABLE_CDN
    cdn_provider: "$CDN_PROVIDER"
    cdn_api_key: "$CDN_API_KEY"
    cdn_account: "$CDN_ACCOUNT"
    enable_local_cdn: $ENABLE_LOCAL_CDN
    local_cdn_provider: "$LOCAL_CDN_PROVIDER"
    local_cdn_api_key: "$LOCAL_CDN_API_KEY"
    enable_lazy_loading: $ENABLE_LAZY_LOADING
    enable_browser_caching: $ENABLE_BROWSER_CACHING
    enable_db_optimization: $ENABLE_DB_OPTIMIZATION
    enable_quic_http3: $ENABLE_QUIC_HTTP3
    enable_dynamic_caching: $ENABLE_DYNAMIC_CACHING
    enable_performance_report: $ENABLE_PERFORMANCE_REPORT
    install_plugins: $INSTALL_PLUGINS
    plugins:
$PLUGINS
    enable_seo: $ENABLE_SEO
    enable_woocommerce: $ENABLE_WOOCOMMERCE
    enable_form_builder: $ENABLE_FORM_BUILDER
    enable_plugin_categories: $ENABLE_PLUGIN_CATEGORIES
    plugin_categories: "$PLUGIN_CATEGORIES"
    enable_backups: $ENABLE_BACKUPS
    backup_dir: "$BACKUP_DIR"
    backup_freq: "$BACKUP_FREQ"
    enable_advanced_backup: $ENABLE_ADVANCED_BACKUP
    enable_migration: $ENABLE_MIGRATION
    migration_db_path: "$MIGRATION_DB_PATH"
    migration_files_path: "$MIGRATION_FILES_PATH"
    enable_rollback: $ENABLE_ROLLBACK
    enable_multisite: $ENABLE_MULTISITE
    multisite_type: "$MULTISITE_TYPE"
    enable_smtp: $ENABLE_SMTP
    smtp_host: "$SMTP_HOST"
    smtp_port: "$SMTP_PORT"
    smtp_username: "$SMTP_USERNAME"
    smtp_password: "$SMTP_PASSWORD"
    enable_monitoring: $ENABLE_MONITORING
    wp_debug: $WP_DEBUG
    enable_image_optimization: $ENABLE_IMAGE_OPTIMIZATION
    add_wp_users: $ADD_WP_USERS
    wp_users:
$WP_USERS
    enable_auto_test: $ENABLE_AUTO_TEST
    enable_php_versions: $ENABLE_PHP_VERSIONS
    php_additional_versions: "$PHP_ADDITIONAL_VERSIONS"
    enable_staging: $ENABLE_STAGING
    staging_subdomain: "$STAGING_SUBDOMAIN"
    enable_headless_cms: $ENABLE_HEADLESS_CMS
    enable_dev_tools: $ENABLE_DEV_TOOLS
    enable_cloud_monitoring: $ENABLE_CLOUD_MONITORING
    cloud_monitoring_api_key: "$CLOUD_MONITORING_API_KEY"
EOF
    done

    chmod 600 "$OUTPUT_FILE"
    dialog --title "Configuration Generated" --msgbox "Configuration saved to $OUTPUT_FILE.\nCheck the file for generated passwords and save them securely!" 10 60

    dialog --title "Encrypt File" --yesno "Encrypt with Ansible Vault?" 10 50
    if [[ $? -eq 0 ]]; then
        ansible-vault encrypt "$OUTPUT_FILE" && dialog --msgbox "File encrypted successfully." 10 50 || dialog --msgbox "Encryption failed." 10 50
    fi
}

# Main loop
while true; do
    main_menu
    case "$CHOICE" in
        1) domain_settings ;;
        2) 
           if [ -z "$DOMAINS" ]; then
               dialog --msgbox "Please configure domains first!" 10 50
           else
               for domain in $DOMAINS; do
                   basic_settings "$domain"
               done
           fi ;;
        3) security_settings ;;
        4) performance_settings ;;
        5) plugins_themes ;;
        6) backup_migration ;;
        7) advanced_features ;;
        8) generate_config; break ;;
        *) break ;;
    esac
done

echo "Setup complete! Run Ansible playbooks to deploy."