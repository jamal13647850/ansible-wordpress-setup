#!/bin/bash

command -v dialog >/dev/null 2>&1 || { echo "Error: 'dialog' is required but not installed. Install it with 'sudo apt install dialog'."; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "Error: 'openssl' is required but not installed. Install it with 'sudo apt install openssl'."; exit 1; }

OUTPUT_FILE="group_vars/all.yml"
TEMP_FILE="/tmp/config_temp_$$"

# Associative array to store platform for each domain
declare -A DOMAIN_PLATFORMS

# Create directories if they don't exist
mkdir -p group_vars

generate_password() {
    openssl rand -base64 20 | tr -d '/+=' | head -c 20
}

generate_db_prefix() {
    echo "$(cat /dev/urandom | tr -dc 'a-z' | head -c 2)_"
}

cleanup() {
    rm -f "$TEMP_FILE" "$TEMP_FILE"_* 2>/dev/null
}

trap cleanup EXIT

# Function to get the platform context for global sections
# Defaults to the platform of the first domain, or prompts if ambiguous / not set
get_functional_platform_context() {
    local context_platform=""
    if [ -n "$DOMAINS" ]; then
        local first_domain_in_list=$(echo "$DOMAINS" | awk '{print $1}')
        if [ -n "${DOMAIN_PLATFORMS[$first_domain_in_list]}" ]; then
            context_platform="${DOMAIN_PLATFORMS[$first_domain_in_list]}"
        fi
    fi

    if [ -z "$context_platform" ]; then
        # If no domains are configured yet, or platform couldn't be determined,
        # we might need a default or ask the user. For simplicity, default to wordpress for now.
        # This part might need refinement for a truly mixed environment UI.
        dialog --title "Platform Context" --msgbox "Could not determine a specific platform context for this section (e.g., no domains configured yet). Some options may be based on a default (WordPress) or appear generic." 10 70
        echo "wordpress" # Default platform if none can be derived
    else
        echo "$context_platform"
    fi
}


# Main menu
main_menu() {
    local menu_item_5_label="Application Specific Settings"
    # Attempt to make item 5 label more specific if a platform context can be determined
    local current_platform_for_menu=$(get_functional_platform_context)
    if [ "$current_platform_for_menu" == "wordpress" ]; then
        menu_item_5_label="Plugins and Themes (WordPress)"
    elif [ "$current_platform_for_menu" == "laravel" ]; then
        menu_item_5_label="Laravel Packages"
    fi

    dialog --title "Deployment Configuration" \
           --menu "Select a configuration category:" 15 60 8 \
           1 "Domain Settings" \
           2 "Basic Settings (Per Domain)" \
           3 "Security Settings" \
           4 "Performance Settings" \
           5 "$menu_item_5_label" \
           6 "Backup and Migration" \
           7 "Advanced Features" \
           8 "Generate Configuration" 2>"$TEMP_FILE"

    CHOICE=$(cat "$TEMP_FILE")
}

# Domain settings
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

# Basic settings
basic_settings() {
    local domain=$1
    local domain_platform

    # Select platform for this specific domain
    dialog --title "Platform for $domain" \
           --menu "Select the platform for $domain:" 15 50 2 \
           1 "WordPress" \
           2 "Laravel" 2>"$TEMP_FILE"
    local PLATFORM_CHOICE_DOMAIN=$(cat "$TEMP_FILE")

    case $PLATFORM_CHOICE_DOMAIN in
        1) domain_platform="wordpress" ;;
        2) domain_platform="laravel" ;;
        *) echo "Invalid platform selection for $domain. Skipping."; return ;;
    esac
    DOMAIN_PLATFORMS["$domain"]="$domain_platform" # Store platform for this domain

    if [ "$domain_platform" == "wordpress" ]; then
        dialog --title "Basic Settings for $domain (WordPress)" --form "Enter basic configuration details for $domain:" 15 60 8 \
               "Admin Username:" 1 1 "${WP_ADMIN_USER:-admin}" 1 20 30 50 \
               "Admin Email:" 2 1 "${WP_ADMIN_EMAIL:-admin@$domain}" 2 20 30 255 \
               "Site Title:" 3 1 "${WP_TITLE:-My Site}" 3 20 30 255 \
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

        eval "DOMAIN_${domain//./_}_SETTINGS='platform: \"wordpress\"\\nmysql_root_password: \"$MYSQL_ROOT_PASSWORD\"\\nmysql_db_name: \"$MYSQL_DB_NAME\"\\nmysql_db_user: \"$MYSQL_DB_USER\"\\nmysql_db_password: \"$MYSQL_DB_PASSWORD\"\\ndomain: \"$domain\"\\nwordpress_admin_user: \"$WP_ADMIN_USER\"\\nwordpress_admin_password: \"$WP_ADMIN_PASSWORD\"\\nwordpress_admin_email: \"$WP_ADMIN_EMAIL\"\\nwordpress_title: \"$WP_TITLE\"\\nwordpress_locale: \"$WP_LOCALE\"\\nwordpress_db_prefix: \"$WP_DB_PREFIX\"\\nssl_email: \"$SSL_EMAIL\"\\nphp_version: \"$PHP_VERSION\"\\nlinux_username: \"$LINUX_USERNAME\"'"
    else # Laravel settings
        dialog --title "Basic Settings for $domain (Laravel)" --form "Enter basic configuration details for $domain:" 15 60 8 \
               "App Name:" 1 1 "${LARAVEL_APP_NAME:-$domain}" 1 20 30 50 \
               "App Environment:" 2 1 "${LARAVEL_APP_ENV:-production}" 2 20 30 50 \
               "Admin Email:" 3 1 "${LARAVEL_ADMIN_EMAIL:-admin@$domain}" 3 20 30 255 \
               "SSL Email:" 4 1 "${SSL_EMAIL:-admin@$domain}" 4 20 30 255 \
               "PHP Version:" 5 1 "${PHP_VERSION:-8.3}" 5 20 10 10 \
               "Laravel Version:" 6 1 "${LARAVEL_VERSION:-10.*}" 6 20 10 10 \
               "Linux Username:" 7 1 "${LINUX_USERNAME:-ubuntu}" 7 20 30 50 \
               2>"$TEMP_FILE"

        IFS=$'\n' read -r -d '' LARAVEL_APP_NAME LARAVEL_APP_ENV LARAVEL_ADMIN_EMAIL SSL_EMAIL PHP_VERSION LARAVEL_VERSION LINUX_USERNAME < "$TEMP_FILE"

        MYSQL_ROOT_PASSWORD=$(generate_password)
        MYSQL_DB_NAME="laravel_$(echo "$domain" | tr -d '.' | tr '[:upper:]' '[:lower:]')"
        MYSQL_DB_USER="lrvuser_$(echo "$domain" | tr -d '.' | tr '[:upper:]' '[:lower:]')"
        MYSQL_DB_PASSWORD=$(generate_password)
        LARAVEL_APP_KEY=$(openssl rand -base64 32)

        eval "DOMAIN_${domain//./_}_SETTINGS='platform: \"laravel\"\\nmysql_root_password: \"$MYSQL_ROOT_PASSWORD\"\\nmysql_db_name: \"$MYSQL_DB_NAME\"\\nmysql_db_user: \"$MYSQL_DB_USER\"\\nmysql_db_password: \"$MYSQL_DB_PASSWORD\"\\ndomain: \"$domain\"\\nlaravel_app_name: \"$LARAVEL_APP_NAME\"\\nlaravel_app_env: \"$LARAVEL_APP_ENV\"\\nlaravel_admin_email: \"$LARAVEL_ADMIN_EMAIL\"\\nlaravel_app_key: \"$LARAVEL_APP_KEY\"\\nlaravel_version: \"$LARAVEL_VERSION\"\\nssl_email: \"$SSL_EMAIL\"\\nphp_version: \"$PHP_VERSION\"\\nlinux_username: \"$LINUX_USERNAME\"'"
    fi
}

# Security Settings
security_settings() {
    local func_platform_context=$(get_functional_platform_context)

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

    if [ "$func_platform_context" == "laravel" ]; then
        dialog --title "Laravel Security" --checklist "Select Laravel security options:" 15 60 5 \
               "secure_api" "Secure API endpoints" off \
               "rate_limiting" "API rate limiting" off \
               "csrf_protection" "CSRF protection" on \
               "secure_headers" "HTTP security headers" on \
               "xss_protection" "XSS protection" on 2>"$TEMP_FILE"

        LARAVEL_SECURITY_OPTIONS=$(cat "$TEMP_FILE")
        ENABLE_SECURE_API=$(echo "$LARAVEL_SECURITY_OPTIONS" | grep -q "secure_api" && echo "true" || echo "false")
        ENABLE_RATE_LIMITING=$(echo "$LARAVEL_SECURITY_OPTIONS" | grep -q "rate_limiting" && echo "true" || echo "false")
        ENABLE_CSRF_PROTECTION=$(echo "$LARAVEL_SECURITY_OPTIONS" | grep -q "csrf_protection" && echo "true" || echo "false")
        ENABLE_SECURE_HEADERS=$(echo "$LARAVEL_SECURITY_OPTIONS" | grep -q "secure_headers" && echo "true" || echo "false")
        ENABLE_XSS_PROTECTION=$(echo "$LARAVEL_SECURITY_OPTIONS" | grep -q "xss_protection" && echo "true" || echo "false")
    fi
}

# Performance Settings
performance_settings() {
    local func_platform_context=$(get_functional_platform_context)
    common_options="\"php_opcache\" \"PHP OPcache\" off \\
           \"redis\" \"Redis caching\" off \\
           \"browser_caching\" \"Browser caching\" off \\
           \"db_optimization\" \"Database optimization\" off"

    if [ "$func_platform_context" == "wordpress" ]; then
        dialog --title "Performance Settings (WordPress Context)" --checklist "Select performance options:" 20 60 12 \
           $common_options \
           "advanced_caching" "Advanced caching (e.g., Memcached)" off \
           "cdn" "CDN (e.g., Cloudflare)" off \
           "local_cdn" "Local CDN (e.g., ArvanCloud)" off \
           "lazy_loading" "Lazy loading" off \
           "quic_http3" "QUIC/HTTP3" off \
           "dynamic_caching" "Dynamic caching (e.g., Varnish)" off \
           "performance_report" "Performance report" off 2>"$TEMP_FILE"
    else # Assuming Laravel context or generic if context is unclear
        dialog --title "Performance Settings (Laravel Context/Generic)" --checklist "Select performance options:" 20 60 12 \
           $common_options \
           "queue" "Queue system (Laravel)" off \
           "horizon" "Laravel Horizon" off \
           "cdn" "CDN (e.g., Cloudflare)" off \
           "local_cdn" "Local CDN (e.g., ArvanCloud)" off \
           "octane" "Laravel Octane" off \
           "telescope" "Laravel Telescope" off \
           "performance_report" "Performance report" off 2>"$TEMP_FILE"
    fi

    PERFORMANCE_OPTIONS=$(cat "$TEMP_FILE")

    if [ "$func_platform_context" == "wordpress" ]; then
        dialog --title "WordPress Memory Limits" --form "Set WordPress memory limits:" 10 60 2 \
               "WP_MEMORY_LIMIT (e.g., 128M):" 1 1 "${WP_MEMORY_LIMIT:-128M}" 1 30 10 10 \
               "WP_MAX_MEMORY_LIMIT (e.g., 256M):" 2 1 "${WP_MAX_MEMORY_LIMIT:-256M}" 2 30 10 10 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' WP_MEMORY_LIMIT WP_MAX_MEMORY_LIMIT < "$TEMP_FILE"
    fi

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

    if [ "$func_platform_context" == "wordpress" ] && echo "$PERFORMANCE_OPTIONS" | grep -q "advanced_caching"; then
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

    if [ "$func_platform_context" == "laravel" ]; then
        ENABLE_QUEUE=$(echo "$PERFORMANCE_OPTIONS" | grep -q "queue" && echo "true" || echo "false")
        ENABLE_HORIZON=$(echo "$PERFORMANCE_OPTIONS" | grep -q "horizon" && echo "true" || echo "false")
        ENABLE_OCTANE=$(echo "$PERFORMANCE_OPTIONS" | grep -q "octane" && echo "true" || echo "false")
        ENABLE_TELESCOPE=$(echo "$PERFORMANCE_OPTIONS" | grep -q "telescope" && echo "true" || echo "false")

        if [ "$ENABLE_QUEUE" = "true" ]; then
            dialog --title "Queue Driver" --menu "Select queue driver:" 15 50 4 \
                   "sync" "Synchronous (default)" \
                   "database" "Database" \
                   "redis" "Redis" \
                   "beanstalkd" "Beanstalkd" 2>"$TEMP_FILE"
            QUEUE_DRIVER=$(cat "$TEMP_FILE")
        fi

        if [ "$ENABLE_OCTANE" = "true" ]; then
            dialog --title "Octane Server" --menu "Select Octane server:" 10 50 2 \
                   "swoole" "Swoole" \
                   "roadrunner" "RoadRunner" 2>"$TEMP_FILE"
            OCTANE_SERVER=$(cat "$TEMP_FILE")
        fi
    fi

    ENABLE_BROWSER_CACHING=$(echo "$PERFORMANCE_OPTIONS" | grep -q "browser_caching" && echo "true" || echo "false")
    ENABLE_DB_OPTIMIZATION=$(echo "$PERFORMANCE_OPTIONS" | grep -q "db_optimization" && echo "true" || echo "false")
    ENABLE_PERFORMANCE_REPORT=$(echo "$PERFORMANCE_OPTIONS" | grep -q "performance_report" && echo "true" || echo "false")

    if [ "$func_platform_context" == "wordpress" ]; then
        ENABLE_LAZY_LOADING=$(echo "$PERFORMANCE_OPTIONS" | grep -q "lazy_loading" && echo "true" || echo "false")
        ENABLE_QUIC_HTTP3=$(echo "$PERFORMANCE_OPTIONS" | grep -q "quic_http3" && echo "true" || echo "false")
        ENABLE_DYNAMIC_CACHING=$(echo "$PERFORMANCE_OPTIONS" | grep -q "dynamic_caching" && echo "true" || echo "false")
    fi
}

# Plugins and Themes / Laravel Packages
plugins_themes() {
    local func_platform_context=$(get_functional_platform_context)

    if [ "$func_platform_context" == "wordpress" ]; then
        dialog --title "Plugins and Themes (WordPress)" --checklist "Select options:" 15 60 7 \
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
    elif [ "$func_platform_context" == "laravel" ]; then
        dialog --title "Laravel Packages" --checklist "Select packages to install:" 15 60 10 \
               "debugbar" "Laravel Debugbar" off \
               "ide_helper" "Laravel IDE Helper" off \
               "sanctum" "Laravel Sanctum" off \
               "socialite" "Laravel Socialite" off \
               "spatie_permission" "Spatie Laravel Permission" off \
               "spatie_media" "Spatie Media Library" off \
               "passport" "Laravel Passport" off \
               "custom_packages" "Custom packages" off 2>"$TEMP_FILE"

        LARAVEL_PACKAGES_OPTIONS=$(cat "$TEMP_FILE")

        INSTALL_DEBUGBAR=$(echo "$LARAVEL_PACKAGES_OPTIONS" | grep -q "debugbar" && echo "true" || echo "false")
        INSTALL_IDE_HELPER=$(echo "$LARAVEL_PACKAGES_OPTIONS" | grep -q "ide_helper" && echo "true" || echo "false")
        INSTALL_SANCTUM=$(echo "$LARAVEL_PACKAGES_OPTIONS" | grep -q "sanctum" && echo "true" || echo "false")
        INSTALL_SOCIALITE=$(echo "$LARAVEL_PACKAGES_OPTIONS" | grep -q "socialite" && echo "true" || echo "false")
        INSTALL_SPATIE_PERMISSION=$(echo "$LARAVEL_PACKAGES_OPTIONS" | grep -q "spatie_permission" && echo "true" || echo "false")
        INSTALL_SPATIE_MEDIA=$(echo "$LARAVEL_PACKAGES_OPTIONS" | grep -q "spatie_media" && echo "true" || echo "false")
        INSTALL_PASSPORT=$(echo "$LARAVEL_PACKAGES_OPTIONS" | grep -q "passport" && echo "true" || echo "false")

        if echo "$LARAVEL_PACKAGES_OPTIONS" | grep -q "custom_packages"; then
            INSTALL_CUSTOM_PACKAGES="true"
            dialog --title "Custom Packages" --inputbox "Enter packages (comma-separated):" 10 50 "" 2>"$TEMP_FILE"
            CUSTOM_PACKAGES=$(cat "$TEMP_FILE")
        else
            INSTALL_CUSTOM_PACKAGES="false"
            CUSTOM_PACKAGES=""
        fi
    else
        dialog --title "Information" --msgbox "Platform context for Application Specific Settings is unclear or not WordPress/Laravel. This section will be skipped." 8 70
    fi
}

# Backup and Migration
backup_migration() {
    dialog --title "Backup and Migration" --checklist "Select options:" 15 60 6 \
           "backups" "Automatic backups" off \
           "advanced_backup" "Advanced backup" off \
           "migration" "Migrate existing site" off \
           "rollback" "Automatic rollback" off 2>"$TEMP_FILE"

    BACKUP_OPTIONS=$(cat "$TEMP_FILE")

    if echo "$BACKUP_OPTIONS" | grep -q "backups"; then
        ENABLE_BACKUPS="true"
        dialog --title "Backups" --form "Enter backup details:" 10 60 2 \
               "Directory:" 1 1 "${BACKUP_DIR:-/var/backups}" 1 20 30 255 \
               "Frequency (cron):" 2 1 "${BACKUP_FREQ:-0 2 * * *}" 2 20 20 50 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' BACKUP_DIR BACKUP_FREQ < "$TEMP_FILE"
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
    local func_platform_context=$(get_functional_platform_context)
    common_options="\"monitoring\" \"Monitoring and logging\" off \\
           \"php_versions\" \"Manage PHP versions\" off \\
           \"staging\" \"Staging environment\" off \\
           \"auto_test\" \"Auto-test after install\" off \\
           \"dev_tools\" \"Developer tools (e.g., phpMyAdmin)\" off \\
           \"cloud_monitoring\" \"Cloud monitoring (e.g., UptimeRobot)\" off"

    if [ "$func_platform_context" == "wordpress" ]; then
        dialog --title "Advanced Features (WordPress Context)" --checklist "Select options:" 20 60 12 \
               "multisite" "WordPress Multisite" off \
               "smtp" "SMTP email" off \
               $common_options \
               "image_optimization" "Image optimization" off \
               "add_wp_users" "Add WordPress users" off \
               "headless_cms" "Headless CMS" off 2>"$TEMP_FILE"
    elif [ "$func_platform_context" == "laravel" ]; then
        dialog --title "Advanced Features (Laravel Context)" --checklist "Select options:" 20 60 12 \
               "smtp" "SMTP email" off \
               $common_options \
               "scheduler" "Task Scheduler (Laravel)" off \
               "api" "API Setup (Laravel)" off \
               "websockets" "WebSockets (Laravel)" off 2>"$TEMP_FILE"
    else # Generic
        dialog --title "Advanced Features (Generic Context)" --checklist "Select options:" 20 60 12 \
            "smtp" "SMTP email" off \
            $common_options 2>"$TEMP_FILE"
    fi


    ADVANCED_OPTIONS=$(cat "$TEMP_FILE")

    if [ "$func_platform_context" == "wordpress" ]; then
        if echo "$ADVANCED_OPTIONS" | grep -q "multisite"; then
            ENABLE_MULTISITE="true"
            dialog --title "Multisite" --inputbox "Enter type (subdomain/subdirectory, default: subdomain):" 10 50 "subdomain" 2>"$TEMP_FILE"
            MULTISITE_TYPE=$(cat "$TEMP_FILE")
        else
            ENABLE_MULTISITE="false"
            MULTISITE_TYPE=""
        fi

        if echo "$ADVANCED_OPTIONS" | grep -q "image_optimization"; then
            ENABLE_IMAGE_OPTIMIZATION="true"
        else
            ENABLE_IMAGE_OPTIMIZATION="false"
        fi

        if echo "$ADVANCED_OPTIONS" | grep -q "add_wp_users"; then
            ENABLE_ADD_WP_USERS="true"
            dialog --title "WordPress Users" --inputbox "Enter users (username:email:role, comma-separated):" 10 50 "" 2>"$TEMP_FILE"
            WP_USERS_INPUT=$(cat "$TEMP_FILE")
        else
            ENABLE_ADD_WP_USERS="false"
            WP_USERS_INPUT=""
        fi
        ENABLE_HEADLESS_CMS=$(echo "$ADVANCED_OPTIONS" | grep -q "headless_cms" && echo "true" || echo "false")
    fi

    if [ "$func_platform_context" == "laravel" ]; then
        ENABLE_SCHEDULER=$(echo "$ADVANCED_OPTIONS" | grep -q "scheduler" && echo "true" || echo "false")
        ENABLE_API=$(echo "$ADVANCED_OPTIONS" | grep -q "api" && echo "true" || echo "false")
        ENABLE_WEBSOCKETS=$(echo "$ADVANCED_OPTIONS" | grep -q "websockets" && echo "true" || echo "false")

        if [ "$ENABLE_API" = "true" ]; then
            dialog --title "API Setup" --checklist "Select API options:" 15 60 4 \
                   "api_auth" "API Authentication" on \
                   "api_docs" "API Documentation" off \
                   "api_versioning" "API Versioning" off \
                   "api_rate_limit" "API Rate Limiting" off 2>"$TEMP_FILE"

            API_OPTIONS=$(cat "$TEMP_FILE")
            ENABLE_API_AUTH=$(echo "$API_OPTIONS" | grep -q "api_auth" && echo "true" || echo "false")
            ENABLE_API_DOCS=$(echo "$API_OPTIONS" | grep -q "api_docs" && echo "true" || echo "false")
            ENABLE_API_VERSIONING=$(echo "$API_OPTIONS" | grep -q "api_versioning" && echo "true" || echo "false")
            ENABLE_API_RATE_LIMIT=$(echo "$API_OPTIONS" | grep -q "api_rate_limit" && echo "true" || echo "false")
        fi
    fi

    if echo "$ADVANCED_OPTIONS" | grep -q "smtp"; then
        ENABLE_SMTP="true"
        dialog --title "SMTP" --form "Enter SMTP details:" 15 60 5 \
               "Host:" 1 1 "$SMTP_HOST" 1 20 30 255 \
               "Port:" 2 1 "$SMTP_PORT" 2 20 10 10 \
               "Username:" 3 1 "$SMTP_USERNAME" 3 20 30 50 \
               "Password:" 4 1 "$SMTP_PASSWORD" 4 20 30 50 \
               "Encryption (tls/ssl/none):" 5 1 "${SMTP_ENCRYPTION:-tls}" 5 20 10 10 \
               2>"$TEMP_FILE"
        IFS=$'\n' read -r -d '' SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_ENCRYPTION < "$TEMP_FILE"
    else
        ENABLE_SMTP="false"
        SMTP_HOST=""
        SMTP_PORT=""
        SMTP_USERNAME=""
        SMTP_PASSWORD=""
        SMTP_ENCRYPTION=""
    fi

    ENABLE_MONITORING=$(echo "$ADVANCED_OPTIONS" | grep -q "monitoring" && echo "true" || echo "false")

    if echo "$ADVANCED_OPTIONS" | grep -q "php_versions"; then
        ENABLE_PHP_VERSIONS="true"
        dialog --title "PHP Versions" --inputbox "Enter additional PHP versions (comma-separated, e.g., 7.4,8.0):" 10 50 "" 2>"$TEMP_FILE"
        PHP_ADDITIONAL_VERSIONS=$(cat "$TEMP_FILE")
    else
        ENABLE_PHP_VERSIONS="false"
        PHP_ADDITIONAL_VERSIONS=""
    fi

    if echo "$ADVANCED_OPTIONS" | grep -q "staging"; then
        ENABLE_STAGING="true"
        dialog --title "Staging" --inputbox "Enter staging subdomain (default: staging):" 10 50 "staging" 2>"$TEMP_FILE"
        STAGING_SUBDOMAIN=$(cat "$TEMP_FILE")
    else
        ENABLE_STAGING="false"
        STAGING_SUBDOMAIN=""
    fi

    ENABLE_AUTO_TEST=$(echo "$ADVANCED_OPTIONS" | grep -q "auto_test" && echo "true" || echo "false")
    ENABLE_DEV_TOOLS=$(echo "$ADVANCED_OPTIONS" | grep -q "dev_tools" && echo "true" || echo "false")
    ENABLE_CLOUD_MONITORING=$(echo "$ADVANCED_OPTIONS" | grep -q "cloud_monitoring" && echo "true" || echo "false")
}

# Generate Configuration
generate_config() {
    echo "---" > "$OUTPUT_FILE"
    # Note: Global 'platform' is removed. It's now per-domain.
    # Global settings (like install_redis, enable_smtp etc.) should be written here, once.
    # This part still needs refactoring to separate global from per-domain settings generation more cleanly.
    # For now, we ensure 'platform' is not globally written.
    # The script still repeats many "global" choices under each domain due to its original structure.
    # Addressing that fully is a larger refactor of this function.

    echo "domains:" >> "$OUTPUT_FILE"
    for domain_key in $DOMAINS; do
        domain_var_name="DOMAIN_${domain_key//./_}_SETTINGS"
        domain_specific_settings=${!domain_var_name}

        echo "  $domain_key:" >> "$OUTPUT_FILE"
        # domain_specific_settings already contains the per-domain platform
        echo -e "$domain_specific_settings" | sed 's/^/    /' >> "$OUTPUT_FILE"


        # The following global settings are still being written under each domain.
        # This is a known issue from the original script structure that requires more extensive refactoring
        # of how global choices are collected and then written once to the YAML.
        # My previous advice covered this separation, but for this specific code update,
        # the focus is on per-domain 'platform'.

        echo "    restrict_ip_access: ${RESTRICT_IP_ACCESS:-false}" >> "$OUTPUT_FILE"
        if [ "${RESTRICT_IP_ACCESS:-false}" = "true" ]; then
            echo "    allowed_ips:" >> "$OUTPUT_FILE"
            echo -e "${ALLOWED_IPS:-""}" | sed 's/^/      /' >> "$OUTPUT_FILE" # Adjusted indent for list
        else
            echo "    allowed_ips: []" >> "$OUTPUT_FILE"
        fi

        echo "    enable_basic_auth: ${ENABLE_BASIC_AUTH:-false}" >> "$OUTPUT_FILE"
        if [ "${ENABLE_BASIC_AUTH:-false}" = "true" ]; then
            echo "    basic_auth_user: \"${BASIC_AUTH_USER:-}\"" >> "$OUTPUT_FILE"
            echo "    basic_auth_password: \"${BASIC_AUTH_PASSWORD:-}\"" >> "$OUTPUT_FILE"
        fi

        echo "    enable_ssh_security: ${ENABLE_SSH_SECURITY:-false}" >> "$OUTPUT_FILE"
        echo "    enable_anti_hack: ${ENABLE_ANTI_HACK:-false}" >> "$OUTPUT_FILE"
        echo "    enable_anti_bot: ${ENABLE_ANTI_BOT:-false}" >> "$OUTPUT_FILE"
        echo "    enable_anti_ddos: ${ENABLE_ANTI_DDOS:-false}" >> "$OUTPUT_FILE"
        echo "    enable_waf: ${ENABLE_WAF:-false}" >> "$OUTPUT_FILE"
        echo "    enable_login_limit: ${ENABLE_LOGIN_LIMIT:-false}" >> "$OUTPUT_FILE"

        local current_domain_platform="${DOMAIN_PLATFORMS[$domain_key]}"
        if [ "$current_domain_platform" == "laravel" ]; then
            echo "    enable_secure_api: ${ENABLE_SECURE_API:-false}" >> "$OUTPUT_FILE"
            echo "    enable_rate_limiting: ${ENABLE_RATE_LIMITING:-false}" >> "$OUTPUT_FILE"
            echo "    enable_csrf_protection: ${ENABLE_CSRF_PROTECTION:-true}" >> "$OUTPUT_FILE" # Default based on original
            echo "    enable_secure_headers: ${ENABLE_SECURE_HEADERS:-true}" >> "$OUTPUT_FILE"   # Default based on original
            echo "    enable_xss_protection: ${ENABLE_XSS_PROTECTION:-true}" >> "$OUTPUT_FILE"   # Default based on original
        fi

        if [ "$current_domain_platform" == "wordpress" ]; then
            echo "    wp_memory_limit: \"${WP_MEMORY_LIMIT:-128M}\"" >> "$OUTPUT_FILE"
            echo "    wp_max_memory_limit: \"${WP_MAX_MEMORY_LIMIT:-256M}\"" >> "$OUTPUT_FILE"
        fi

        echo "    install_redis: ${INSTALL_REDIS:-false}" >> "$OUTPUT_FILE"
        if [ "${INSTALL_REDIS:-false}" = "true" ]; then
            echo "    wp_redis_host: \"${WP_REDIS_HOST:-127.0.0.1}\"" >> "$OUTPUT_FILE"
            echo "    wp_redis_port: ${WP_REDIS_PORT:-6379}" >> "$OUTPUT_FILE"
            echo "    wp_redis_password: \"${WP_REDIS_PASSWORD:-}\"" >> "$OUTPUT_FILE"
            echo "    wp_redis_database: ${WP_REDIS_DATABASE:-0}" >> "$OUTPUT_FILE"
        fi

        if [ "${ENABLE_PHP_OPCACHE:-false}" = "true" ]; then
            echo "    enable_php_opcache: ${ENABLE_PHP_OPCACHE:-false}" >> "$OUTPUT_FILE"
            echo "    opcache_memory: ${OPCACHE_MEMORY:-128}" >> "$OUTPUT_FILE"
        fi

        if [ "$current_domain_platform" == "wordpress" ] && [ "${ENABLE_ADVANCED_CACHING:-false}" = "true" ]; then
            echo "    enable_advanced_caching: ${ENABLE_ADVANCED_CACHING:-false}" >> "$OUTPUT_FILE"
            echo "    cache_type: \"${CACHE_TYPE:-memcached}\"" >> "$OUTPUT_FILE"
        fi

        echo "    enable_cdn: ${ENABLE_CDN:-false}" >> "$OUTPUT_FILE"
        if [ "${ENABLE_CDN:-false}" = "true" ]; then
            echo "    cdn_provider: \"${CDN_PROVIDER:-}\"" >> "$OUTPUT_FILE"
            echo "    cdn_api_key: \"${CDN_API_KEY:-}\"" >> "$OUTPUT_FILE"
            echo "    cdn_account: \"${CDN_ACCOUNT:-}\"" >> "$OUTPUT_FILE"
        fi

        echo "    enable_local_cdn: ${ENABLE_LOCAL_CDN:-false}" >> "$OUTPUT_FILE"
        if [ "${ENABLE_LOCAL_CDN:-false}" = "true" ]; then
            echo "    local_cdn_provider: \"${LOCAL_CDN_PROVIDER:-}\"" >> "$OUTPUT_FILE"
            echo "    local_cdn_api_key: \"${LOCAL_CDN_API_KEY:-}\"" >> "$OUTPUT_FILE"
        fi

        if [ "$current_domain_platform" == "laravel" ]; then
            echo "    enable_queue: ${ENABLE_QUEUE:-false}" >> "$OUTPUT_FILE"
            if [ "${ENABLE_QUEUE:-false}" = "true" ]; then
                echo "    queue_driver: \"${QUEUE_DRIVER:-sync}\"" >> "$OUTPUT_FILE"
            fi
            echo "    enable_horizon: ${ENABLE_HORIZON:-false}" >> "$OUTPUT_FILE"
            echo "    enable_octane: ${ENABLE_OCTANE:-false}" >> "$OUTPUT_FILE"
            if [ "${ENABLE_OCTANE:-false}" = "true" ]; then
                echo "    octane_server: \"${OCTANE_SERVER:-swoole}\"" >> "$OUTPUT_FILE"
            fi
            echo "    enable_telescope: ${ENABLE_TELESCOPE:-false}" >> "$OUTPUT_FILE"
        fi

        if [ "$current_domain_platform" == "wordpress" ]; then
            echo "    enable_lazy_loading: ${ENABLE_LAZY_LOADING:-false}" >> "$OUTPUT_FILE"
            echo "    enable_quic_http3: ${ENABLE_QUIC_HTTP3:-false}" >> "$OUTPUT_FILE"
            echo "    enable_dynamic_caching: ${ENABLE_DYNAMIC_CACHING:-false}" >> "$OUTPUT_FILE"
        fi

        echo "    enable_browser_caching: ${ENABLE_BROWSER_CACHING:-false}" >> "$OUTPUT_FILE"
        echo "    enable_db_optimization: ${ENABLE_DB_OPTIMIZATION:-false}" >> "$OUTPUT_FILE"
        echo "    enable_performance_report: ${ENABLE_PERFORMANCE_REPORT:-false}" >> "$OUTPUT_FILE"

        if [ "$current_domain_platform" == "wordpress" ]; then
            echo "    install_plugins: ${INSTALL_PLUGINS:-false}" >> "$OUTPUT_FILE"
            if [ "${INSTALL_PLUGINS:-false}" = "true" ]; then
                echo "    plugins:" >> "$OUTPUT_FILE"
                echo -e "${PLUGINS:-""}" | sed 's/^/      /' >> "$OUTPUT_FILE" # Adjusted indent for list
            fi
            echo "    enable_seo: ${ENABLE_SEO:-false}" >> "$OUTPUT_FILE"
            echo "    enable_woocommerce: ${ENABLE_WOOCOMMERCE:-false}" >> "$OUTPUT_FILE"
            echo "    enable_form_builder: ${ENABLE_FORM_BUILDER:-false}" >> "$OUTPUT_FILE"
            echo "    enable_plugin_categories: ${ENABLE_PLUGIN_CATEGORIES:-false}" >> "$OUTPUT_FILE"
            if [ "${ENABLE_PLUGIN_CATEGORIES:-false}" = "true" ]; then
                echo "    plugin_categories:" >> "$OUTPUT_FILE"
                for category in $(echo "${PLUGIN_CATEGORIES:-}" | tr ',' ' '); do
                    echo "      - \"$category\"" >> "$OUTPUT_FILE"
                done
            fi
        fi

        if [ "$current_domain_platform" == "laravel" ]; then
            echo "    install_debugbar: ${INSTALL_DEBUGBAR:-false}" >> "$OUTPUT_FILE"
            echo "    install_ide_helper: ${INSTALL_IDE_HELPER:-false}" >> "$OUTPUT_FILE"
            echo "    install_sanctum: ${INSTALL_SANCTUM:-false}" >> "$OUTPUT_FILE"
            echo "    install_socialite: ${INSTALL_SOCIALITE:-false}" >> "$OUTPUT_FILE"
            echo "    install_spatie_permission: ${INSTALL_SPATIE_PERMISSION:-false}" >> "$OUTPUT_FILE"
            echo "    install_spatie_media: ${INSTALL_SPATIE_MEDIA:-false}" >> "$OUTPUT_FILE"
            echo "    install_passport: ${INSTALL_PASSPORT:-false}" >> "$OUTPUT_FILE"
            echo "    install_custom_packages: ${INSTALL_CUSTOM_PACKAGES:-false}" >> "$OUTPUT_FILE"
            if [ "${INSTALL_CUSTOM_PACKAGES:-false}" = "true" ]; then
                echo "    custom_packages:" >> "$OUTPUT_FILE"
                for package in $(echo "${CUSTOM_PACKAGES:-}" | tr ',' ' '); do
                    echo "      - \"$package\"" >> "$OUTPUT_FILE"
                done
            fi
        fi

        echo "    enable_backups: ${ENABLE_BACKUPS:-false}" >> "$OUTPUT_FILE"
        if [ "${ENABLE_BACKUPS:-false}" = "true" ]; then
            echo "    backup_dir: \"${BACKUP_DIR:-/var/backups}\"" >> "$OUTPUT_FILE"
            echo "    backup_freq: \"${BACKUP_FREQ:-0 2 * * *}\"" >> "$OUTPUT_FILE"
        fi
        echo "    enable_advanced_backup: ${ENABLE_ADVANCED_BACKUP:-false}" >> "$OUTPUT_FILE"
        echo "    enable_migration: ${ENABLE_MIGRATION:-false}" >> "$OUTPUT_FILE"
        if [ "${ENABLE_MIGRATION:-false}" = "true" ]; then
            echo "    migration_db_path: \"${MIGRATION_DB_PATH:-}\"" >> "$OUTPUT_FILE"
            echo "    migration_files_path: \"${MIGRATION_FILES_PATH:-}\"" >> "$OUTPUT_FILE"
        fi
        echo "    enable_rollback: ${ENABLE_ROLLBACK:-false}" >> "$OUTPUT_FILE"

        if [ "$current_domain_platform" == "wordpress" ]; then
            echo "    enable_multisite: ${ENABLE_MULTISITE:-false}" >> "$OUTPUT_FILE"
            if [ "${ENABLE_MULTISITE:-false}" = "true" ]; then
                echo "    multisite_type: \"${MULTISITE_TYPE:-subdomain}\"" >> "$OUTPUT_FILE"
            fi
            echo "    enable_image_optimization: ${ENABLE_IMAGE_OPTIMIZATION:-false}" >> "$OUTPUT_FILE"
            echo "    enable_add_wp_users: ${ENABLE_ADD_WP_USERS:-false}" >> "$OUTPUT_FILE"
            if [ "${ENABLE_ADD_WP_USERS:-false}" = "true" ]; then
                echo "    wp_users:" >> "$OUTPUT_FILE"
                for user_detail in $(echo "$WP_USERS_INPUT" | tr ',' ' '); do
                    IFS=':' read -r username email role <<< "$user_detail"
                    echo "      - { username: \"$username\", email: \"$email\", role: \"$role\" }" >> "$OUTPUT_FILE"
                done
            fi
            echo "    enable_headless_cms: ${ENABLE_HEADLESS_CMS:-false}" >> "$OUTPUT_FILE"
        fi

        if [ "$current_domain_platform" == "laravel" ]; then
            echo "    enable_scheduler: ${ENABLE_SCHEDULER:-false}" >> "$OUTPUT_FILE"
            echo "    enable_api: ${ENABLE_API:-false}" >> "$OUTPUT_FILE"
            if [ "${ENABLE_API:-false}" = "true" ]; then
                echo "    enable_api_auth: ${ENABLE_API_AUTH:-true}" >> "$OUTPUT_FILE"
                echo "    enable_api_docs: ${ENABLE_API_DOCS:-false}" >> "$OUTPUT_FILE"
                echo "    enable_api_versioning: ${ENABLE_API_VERSIONING:-false}" >> "$OUTPUT_FILE"
                echo "    enable_api_rate_limit: ${ENABLE_API_RATE_LIMIT:-false}" >> "$OUTPUT_FILE"
            fi
            echo "    enable_websockets: ${ENABLE_WEBSOCKETS:-false}" >> "$OUTPUT_FILE"
        fi

        echo "    enable_smtp: ${ENABLE_SMTP:-false}" >> "$OUTPUT_FILE"
        if [ "${ENABLE_SMTP:-false}" = "true" ]; then
            echo "    smtp_host: \"${SMTP_HOST:-}\"" >> "$OUTPUT_FILE"
            echo "    smtp_port: ${SMTP_PORT:-587}" >> "$OUTPUT_FILE"
            echo "    smtp_username: \"${SMTP_USERNAME:-}\"" >> "$OUTPUT_FILE"
            echo "    smtp_password: \"${SMTP_PASSWORD:-}\"" >> "$OUTPUT_FILE"
            echo "    smtp_encryption: \"${SMTP_ENCRYPTION:-tls}\"" >> "$OUTPUT_FILE"
        fi

        echo "    enable_monitoring: ${ENABLE_MONITORING:-false}" >> "$OUTPUT_FILE"
        echo "    enable_php_versions: ${ENABLE_PHP_VERSIONS:-false}" >> "$OUTPUT_FILE"
        if [ "${ENABLE_PHP_VERSIONS:-false}" = "true" ]; then
            echo "    php_additional_versions:" >> "$OUTPUT_FILE" # This should ideally be global
            for version in $(echo "${PHP_ADDITIONAL_VERSIONS:-}" | tr ',' ' '); do
                echo "      - \"$version\"" >> "$OUTPUT_FILE"
            done
        fi
        echo "    enable_staging: ${ENABLE_STAGING:-false}" >> "$OUTPUT_FILE"
        if [ "${ENABLE_STAGING:-false}" = "true" ]; then
            echo "    staging_subdomain: \"${STAGING_SUBDOMAIN:-staging}\"" >> "$OUTPUT_FILE"
        fi
        echo "    enable_auto_test: ${ENABLE_AUTO_TEST:-false}" >> "$OUTPUT_FILE"
        echo "    enable_dev_tools: ${ENABLE_DEV_TOOLS:-false}" >> "$OUTPUT_FILE"
        echo "    enable_cloud_monitoring: ${ENABLE_CLOUD_MONITORING:-false}" >> "$OUTPUT_FILE"
        echo "" >> $OUTPUT_FILE # Add a newline for readability between domain entries
    done

    dialog --title "Configuration Generated" --msgbox "Configuration has been saved to $OUTPUT_FILE" 8 50
}


# Main execution
# Platform selection is now done per domain in basic_settings

while true; do
    main_menu
    CHOICE_RTN_CODE=$?
    if [ $CHOICE_RTN_CODE -ne 0 ]; then # Handle Cancel/ESC in main menu
        cleanup
        echo "Configuration cancelled by user."
        exit 1
    fi

    case $CHOICE in
        1) domain_settings ;;
        2)
            if [ -z "$DOMAINS" ]; then
                dialog --title "Error" --msgbox "Please configure domains first (Option 1)." 8 50
            else
                for domain_item in $DOMAINS; do
                    basic_settings "$domain_item"
                    # Check if basic_settings was cancelled
                    # This needs $? check right after basic_settings if it can be cancelled
                done
            fi
            ;;
        3) security_settings ;;
        4) performance_settings ;;
        5) plugins_themes ;;
        6) backup_migration ;;
        7) advanced_features ;;
        8)
            if [ -z "$DOMAINS" ]; then
                 dialog --title "Error" --msgbox "No domains configured. Please add domains via 'Domain Settings' first." 8 60
            else
                generate_config; break
            fi
            ;;
        *) # Also handles Cancel/ESC if not caught by CHOICE_RTN_CODE (e.g. if dialog uses different exit code for empty choice)
            cleanup
            echo "Exiting configuration."
            exit 1
            ;;
    esac
done

echo "Configuration generated successfully in $OUTPUT_FILE"

# Clean up temporary files is handled by trap

# Display a summary of the configuration
echo "Configuration Summary:"
echo "======================"
# echo "Platform: $PLATFORM" # Global platform is removed
echo "Domains configured: $DOMAINS"

for domain_key_summary in $DOMAINS; do
    echo ""
    echo "Domain: $domain_key_summary"
    echo "  Platform: ${DOMAIN_PLATFORMS[$domain_key_summary]}"
    # To display more summary details, you'd parse the DOMAIN_..._SETTINGS string or store more structured data.
    # For now, just platform is shown.
    # Example: domain_settings_summary=${!DOMAIN_${domain_key_summary//./_}_SETTINGS}
    # echo -e "  Settings (raw snippet):\n    $domain_settings_summary"
done

echo ""
echo "======================"
echo "Configuration file has been saved to: $OUTPUT_FILE"
echo "Remember to review and secure any sensitive data in this file (e.g., using Ansible Vault)."
echo "You may need to adjust your Ansible playbooks to work with the per-domain platform structure if they relied on a global 'platform' variable."
echo "Thank you for using the Web Platform Configuration Generator!"