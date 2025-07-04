#!/bin/bash
# generate_config.sh
#
# Script to generate the group_vars/all.yml configuration file for Ansible projects
#
# Author: Sayyed Jamal Ghasemi
# Full Stack Developer
# Email: jamal13647850@gmail.com
# LinkedIn: https://www.linkedin.com/in/jamal1364/
# Instagram: https://www.instagram.com/jamal13647850
# Telegram: https://t.me/jamaldev
# Website: https://jamalghasemi.com
# Date: 2025-06-22
#
# This script interactively collects global and domain-specific settings,
# validates inputs, and outputs a structured YAML configuration file
# for use in Ansible automation.

set -e

# Terminal colors for enhanced output readability
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m' # Reset to no color

# Configuration output directory and file
CONFIG_DIRECTORY="group_vars"
CONFIG_FILE_PATH="${CONFIG_DIRECTORY}/all.yml"

# Ensure the configuration directory exists
mkdir -p "${CONFIG_DIRECTORY}"

# Associative arrays to hold domain platforms and settings
declare -A domain_platforms
declare -A domain_settings
domains_list=()

################################################################################
# Function: print_colored_message
# Purpose : Print a message in a specified color to the terminal.
# Arguments:
#   $1 - Color name (green, yellow, red, blue)
#   $2 - Message text
################################################################################
print_colored_message() {
    local color_name="$1"
    local message_text="$2"
    case "$color_name" in
        green) echo -e "${COLOR_GREEN}${message_text}${COLOR_RESET}" ;;
        yellow) echo -e "${COLOR_YELLOW}${message_text}${COLOR_RESET}" ;;
        red) echo -e "${COLOR_RED}${message_text}${COLOR_RESET}" ;;
        blue) echo -e "${COLOR_BLUE}${message_text}${COLOR_RESET}" ;;
        *) echo -e "${message_text}" ;;
    esac
}

################################################################################
# Function: generate_secure_password
# Purpose : Generate a secure 32-character hexadecimal password using OpenSSL.
# Returns : Generated password string.
################################################################################
generate_secure_password() {
    openssl rand -hex 16
}

################################################################################
# Function: validate_email
# Purpose : Validate if a string is a properly formatted email address.
# Arguments:
#   $1 - Email string to validate
# Returns : 0 if valid, 1 otherwise
################################################################################
validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

################################################################################
# Function: validate_domain_name
# Purpose : Validate the format of a domain name string.
# Arguments:
#   $1 - Domain name string to validate
# Returns : 0 if valid, 1 otherwise
################################################################################
validate_domain_name() {
    local domain="$1"
    [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

################################################################################
# Function: ask_yes_no
# Purpose : Prompt user for a yes/no choice and return accordingly.
# Arguments:
#   $1 - Prompt text
#   $2 - Default answer (y/n), default is 'y'
# Returns : 0 for yes, 1 for no
################################################################################
ask_yes_no() {
    local prompt_message="$1"
    local default_answer="${2:-y}"
    local prompt_display

    if [[ "$default_answer" == "y" ]]; then
        prompt_display="$prompt_message [Y/n]: "
    else
        prompt_display="$prompt_message [y/N]: "
    fi

    while true; do
        read -p "$(echo -e "${COLOR_YELLOW}${prompt_display}${COLOR_RESET}")" user_response
        user_response=${user_response:-$default_answer}

        case "$user_response" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) print_colored_message "red" "Please answer y or n." ;;
        esac
    done
}

################################################################################
# Function: store_domain_setting
# Purpose : Store a key-value pair for a specified domain in the settings array.
# Arguments:
#   $1 - Domain name
#   $2 - Setting key
#   $3 - Setting value
################################################################################
store_domain_setting() {
    local domain="$1"
    local key="$2"
    local value="$3"
    domain_settings["${domain}___${key}"]="$value"
}

################################################################################
# Function: get_domain_setting
# Purpose : Retrieve a stored setting value for a domain, or return a default.
# Arguments:
#   $1 - Domain name
#   $2 - Setting key
#   $3 - Default value (optional)
# Returns : The setting value or the default
################################################################################
get_domain_setting() {
    local domain="$1"
    local key="$2"
    local default_value="${3:-}"
    local value="${domain_settings["${domain}___${key}"]}"
    [[ -z "$value" ]] && echo "$default_value" || echo "$value"
}

################################################################################
# Function: configure_global_server_settings
# Purpose : Interactively collect and store global server configuration settings.
################################################################################
configure_global_server_settings() {
    print_colored_message "blue" "\n--- Configuring Global Server Settings ---"

    read -p "Enter default Linux username for server operations (e.g., ubuntu, admin): " GLOBAL_LINUX_USERNAME
    GLOBAL_LINUX_USERNAME=${GLOBAL_LINUX_USERNAME:-ubuntu}

    read -p "Enter default PHP version for new sites (e.g., 8.1, 8.2, 8.3): " GLOBAL_PHP_DEFAULT_VERSION
    GLOBAL_PHP_DEFAULT_VERSION=${GLOBAL_PHP_DEFAULT_VERSION:-8.2}

    print_colored_message "yellow" "Enter a strong MySQL root password. This will be set on the server."
    while true; do
        read -s -p "MySQL Root Password: " GLOBAL_MYSQL_ROOT_PASSWORD
        echo
        if [[ -n "$GLOBAL_MYSQL_ROOT_PASSWORD" ]]; then
            break
        else
            print_colored_message "red" "MySQL root password cannot be empty."
        fi
    done

    if ask_yes_no "Enable management of additional PHP versions globally?" "n"; then
        GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT="true"
        read -p "Enter additional PHP versions to install, comma-separated (e.g., 7.4,8.0): " GLOBAL_PHP_ADDITIONAL_VERSIONS_STRING
    else
        GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT="false"
    fi

    read -p "Default Let's Encrypt email for SSL (required for SSL generation): " GLOBAL_LETSENCRYPT_DEFAULT_EMAIL
    while ! validate_email "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" && [[ -n "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" ]]; do
        print_colored_message "red" "Invalid email format."
        read -p "Default Let's Encrypt email for SSL: " GLOBAL_LETSENCRYPT_DEFAULT_EMAIL
    done

    if ask_yes_no "Use Let's Encrypt staging server for testing certificates globally (not for production)?" "n"; then
        GLOBAL_LETSENCRYPT_TEST_CERT="true"
    else
        GLOBAL_LETSENCRYPT_TEST_CERT="false"
    fi
}

################################################################################
# Function: configure_global_services
# Purpose : Collect global service configurations, including Redis and SMTP.
################################################################################
configure_global_services() {
    print_colored_message "blue" "\n--- Configuring Global Service Settings ---"

    if ask_yes_no "Install Redis server globally (can be used by WordPress/Laravel)?" "n"; then
        GLOBAL_INSTALL_REDIS="true"

        read -p "Global Redis host (default: 127.0.0.1): " GLOBAL_REDIS_HOST
        GLOBAL_REDIS_HOST=${GLOBAL_REDIS_HOST:-127.0.0.1}

        read -p "Global Redis port (default: 6379): " GLOBAL_REDIS_PORT
        GLOBAL_REDIS_PORT=${GLOBAL_REDIS_PORT:-6379}

        read -p "Global Redis password (leave empty for none, or 'generate'): " redis_pass_input
        if [[ "$redis_pass_input" == "generate" ]]; then
            GLOBAL_REDIS_PASSWORD=$(generate_secure_password)
            print_colored_message "green" "Generated Redis password: $GLOBAL_REDIS_PASSWORD (save this)"
        elif [[ -n "$redis_pass_input" ]]; then
            GLOBAL_REDIS_PASSWORD="$redis_pass_input"
        else
            GLOBAL_REDIS_PASSWORD=""
        fi
    else
        GLOBAL_INSTALL_REDIS="false"
    fi

    if ask_yes_no "Configure global SMTP settings (master switch for SMTP relay, e.g. MailHog, Postfix, or external service)?" "n"; then
        GLOBAL_ENABLE_SMTP_MASTER_SWITCH="true"

        read -p "Global SMTP Host (e.g., smtp.example.com, localhost for local relay): " GLOBAL_SMTP_HOST
        GLOBAL_SMTP_HOST=${GLOBAL_SMTP_HOST:-localhost}

        read -p "Global SMTP Port (e.g., 587, 465, 1025): " GLOBAL_SMTP_PORT
        GLOBAL_SMTP_PORT=${GLOBAL_SMTP_PORT:-587}

        read -p "Global SMTP Username (leave empty if none): " GLOBAL_SMTP_USERNAME

        read -s -p "Global SMTP Password (leave empty if none): " GLOBAL_SMTP_PASSWORD
        echo

        read -p "Global SMTP Encryption (tls, ssl, or none): " GLOBAL_SMTP_ENCRYPTION
        GLOBAL_SMTP_ENCRYPTION=${GLOBAL_SMTP_ENCRYPTION:-tls}
    else
        GLOBAL_ENABLE_SMTP_MASTER_SWITCH="false"
    fi
}

################################################################################
# Function: configure_global_security_features
# Purpose : Configure global security and firewall settings.
################################################################################
configure_global_security_features() {
    print_colored_message "blue" "\n--- Configuring Global Security Features ---"

    if ask_yes_no "Enable Fail2Ban globally (for SSH and other services)?" "y"; then
        GLOBAL_FAIL2BAN_ENABLED="true"

        read -p "Global Fail2Ban default maxretry (default: 5): " GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY
        GLOBAL_FAIL2Ban_DEFAULT_MAXRETRY=${GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY:-5}

        read -p "Global Fail2Ban default findtime (e.g., 10m, 1h, default: 10m): " GLOBAL_FAIL2BAN_DEFAULT_FINDTIME
        GLOBAL_FAIL2BAN_DEFAULT_FINDTIME=${GLOBAL_FAIL2BAN_DEFAULT_FINDTIME:-10m}

        read -p "Global Fail2Ban default bantime (e.g., 1h, 1d, -1 for permanent, default: 1h): " GLOBAL_FAIL2BAN_DEFAULT_BANTIME
        GLOBAL_FAIL2BAN_DEFAULT_BANTIME=${GLOBAL_FAIL2BAN_DEFAULT_BANTIME:-1h}
    else
        GLOBAL_FAIL2BAN_ENABLED="false"
    fi

    if ask_yes_no "Enable WAF (ModSecurity with Nginx) base installation globally?" "n"; then
        GLOBAL_ENABLE_WAF_DEFAULT="true"
    else
        GLOBAL_ENABLE_WAF_DEFAULT="false"
    fi

    if ask_yes_no "Apply a global policy for securing file permissions on webroots (can be overridden per domain)?" "y"; then
        GLOBAL_SECURE_FILE_PERMISSIONS_POLICY="true"
    else
        GLOBAL_SECURE_FILE_PERMISSIONS_POLICY="false"
    fi

    if ask_yes_no "Apply a global policy for securing database user privileges (can be overridden per domain)?" "y"; then
        GLOBAL_SECURE_DATABASE_POLICY="true"
    else
        GLOBAL_SECURE_DATABASE_POLICY="false"
    fi

    if ask_yes_no "Enable system security auditing tools (Lynis, Rkhunter) globally?" "y"; then
        GLOBAL_SECURITY_AUDIT_POLICY="true"
    else
        GLOBAL_SECURITY_AUDIT_POLICY="false"
    fi

    if ask_yes_no "Enable global advanced security measures (e.g., some CSF hardening if installed by Nginx playbook)?" "n"; then
        GLOBAL_ENABLE_ADVANCED_SECURITY="true"
    else
        GLOBAL_ENABLE_ADVANCED_SECURITY="false"
    fi
}

################################################################################
# Function: configure_global_operational_features
# Purpose : Set global operational options like backups and monitoring.
################################################################################
configure_global_operational_features() {
    print_colored_message "blue" "\n--- Configuring Global Operational Features ---"

    if ask_yes_no "Enable automated backups globally (master switch, can be configured per domain)?" "n"; then
        GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH="true"

        read -p "Global base directory for backups (default: /var/backups/ansible_managed): " GLOBAL_BACKUP_BASE_DIR
        GLOBAL_BACKUP_BASE_DIR=${GLOBAL_BACKUP_BASE_DIR:-/var/backups/ansible_managed}

        read -p "Global default backup frequency (cron format, e.g., '0 2 * * *' for daily at 2 AM): " GLOBAL_BACKUP_DEFAULT_FREQ
        GLOBAL_BACKUP_DEFAULT_FREQ=${GLOBAL_BACKUP_DEFAULT_FREQ:-"0 2 * * *"}
    else
        GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH="false"
    fi

    if ask_yes_no "Install basic system monitoring tools (htop, logrotate) globally?" "y"; then
        GLOBAL_ENABLE_MONITORING_TOOLS="true"
    else
        GLOBAL_ENABLE_MONITORING_TOOLS="false"
    fi

    if ask_yes_no "Enable Docker support on the server (install Docker engine and Compose)?" "n"; then
        GLOBAL_ENABLE_DOCKER_SUPPORT="true"
    else
        GLOBAL_ENABLE_DOCKER_SUPPORT="false"
    fi

    if ask_yes_no "Enable pre-action backups for rollback capability globally (can be configured per domain)?" "y"; then
        GLOBAL_ENABLE_ROLLBACK_POLICY="true"

        read -p "Global base directory for pre-action backups (default: /var/backups/ansible_pre_action): " GLOBAL_PRE_ACTION_BACKUP_DIR
        GLOBAL_PRE_ACTION_BACKUP_DIR=${GLOBAL_PRE_ACTION_BACKUP_DIR:-/var/backups/ansible_pre_action}
    else
        GLOBAL_ENABLE_ROLLBACK_POLICY="false"
    fi

    if ask_yes_no "Enable generation of multilingual project documentation (Ansible project itself, runs on localhost)?" "n"; then
        GLOBAL_ENABLE_MULTILINGUAL_DOCS="true"

        read -p "Languages for documentation, comma-separated (e.g., en,fa): " GLOBAL_DOC_LANGUAGES_LIST
        GLOBAL_DOC_LANGUAGES_LIST=${GLOBAL_DOC_LANGUAGES_LIST:-en,fa}
    else
        GLOBAL_ENABLE_MULTILINGUAL_DOCS="false"
    fi
}

################################################################################
# Function: configure_domain_basics
# Purpose : Gather basic domain-specific configuration from the user.
# Arguments:
#   $1 - Domain name
#   $2 - Platform (wordpress or laravel)
################################################################################
configure_domain_basics() {
    local domain="$1"
    local platform="$2"

    print_colored_message "blue" "\n--- Configuring Basic Settings for Domain: $domain ($platform) ---"

    # ✅ بخش جدید برای مدیریت سناریوی انتقال سرور
    print_colored_message "yellow" "\nThis next question is important for installing SSL certificates."
    if ask_yes_no "Is this a server migration (i.e., the domain's DNS is NOT pointing to this new server yet)?" "n"; then
        store_domain_setting "$domain" "skip_dns_check_for_migration" "true"
        print_colored_message "green" "-> Migration mode enabled. SSL will be configured using the DNS-01 challenge method."
    else
        store_domain_setting "$domain" "skip_dns_check_for_migration" "false"
        print_colored_message "green" "-> Standard mode enabled. SSL will be configured using the HTTP-01 challenge."
    fi

    print_colored_message "yellow" "\nSet CDN IP source for $domain to support real IP in Nginx."
    print_colored_message "yellow" "If Cloudflare, enter: cloudflare"
    print_colored_message "yellow" "If ArvanCloud, enter: arvancloud"
    print_colored_message "yellow" "If none (direct), enter: none"

    local cdn_source

    while true; do
        read -p "CDN IP source for $domain [cloudflare/arvancloud/none] (default: none): " cdn_source
        cdn_source="${cdn_source,,}"  # to lowercase
        cdn_source="${cdn_source:-none}"
        if [[ "$cdn_source" == "cloudflare" || "$cdn_source" == "arvancloud" || "$cdn_source" == "none" ]]; then
            break
        fi
        print_colored_message "red" "Value must be one of: cloudflare, arvancloud, none"
    done

    store_domain_setting "$domain" "cdn_ip_source" "$cdn_source"

    read -p "Admin email for $domain (default: $GLOBAL_LETSENCRYPT_DEFAULT_EMAIL): " admin_email
    admin_email="${admin_email:-$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL}"

    while ! validate_email "$admin_email"; do
        print_colored_message "red" "Invalid email format for $domain."
        read -p "Admin email for $domain: " admin_email
    done

    store_domain_setting "$domain" "admin_email" "$admin_email"

    # Handling SSL email preference per domain
    if [[ -n "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" && "$admin_email" == "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" ]]; then
        store_domain_setting "$domain" "ssl_email" "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL"
    elif [[ -n "$admin_email" ]]; then
        if ask_yes_no "Use '$admin_email' as the Let's Encrypt SSL email for $domain?" "y"; then
            store_domain_setting "$domain" "ssl_email" "$admin_email"
        else
            read -p "Enter specific Let's Encrypt SSL email for $domain (leave empty to skip SSL): " specific_ssl_email
            if [[ -n "$specific_ssl_email" ]]; then
                while ! validate_email "$specific_ssl_email"; do
                    print_colored_message "red" "Invalid SSL email format."
                    read -p "Specific Let's Encrypt SSL email for $domain: " specific_ssl_email
                done
                store_domain_setting "$domain" "ssl_email" "$specific_ssl_email"
            else
                store_domain_setting "$domain" "ssl_email" ""
            fi
        fi
    else
        store_domain_setting "$domain" "ssl_email" ""
    fi

    read -p "PHP version for $domain (default: $GLOBAL_PHP_DEFAULT_VERSION): " php_version
    php_version="${php_version:-$GLOBAL_PHP_DEFAULT_VERSION}"
    store_domain_setting "$domain" "php_version" "$php_version"

    local db_name_default="${domain//[.-]/_}_db"
    read -p "MySQL database name for $domain (default: $db_name_default): " db_name
    db_name="${db_name:-$db_name_default}"
    store_domain_setting "$domain" "mysql_db_name" "$db_name"

    local db_user_default="${domain//[.-]/_}_user"
    read -p "MySQL username for $domain (default: $db_user_default): " db_user
    db_user="${db_user:-$db_user_default}"
    store_domain_setting "$domain" "mysql_db_user" "$db_user"

    read -p "MySQL password for $domain (or 'generate'): " db_password_input
    if [[ "$db_password_input" == "generate" ]]; then
        db_password=$(generate_secure_password)
        print_colored_message "green" "Generated MySQL password for $domain: $db_password (save this)"
    elif [[ -n "$db_password_input" ]]; then
        db_password="$db_password_input"
    else
        db_password=$(generate_secure_password)
        print_colored_message "green" "Generated MySQL password for $domain (empty input): $db_password (save this)"
    fi
    store_domain_setting "$domain" "mysql_db_password" "$db_password"

    read -p "Nginx client_max_body_size for $domain (e.g., 64M, default: 10M): " nginx_client_max_body_size
    store_domain_setting "$domain" "nginx_client_max_body_size" "${nginx_client_max_body_size:-10M}"

    read -p "PHP upload_max_filesize for $domain (e.g., 64M, default: 64M): " php_upload_max_filesize
    store_domain_setting "$domain" "php_upload_max_filesize" "${php_upload_max_filesize:-64M}"

    read -p "PHP post_max_size for $domain (e.g., 64M, default: 64M): " php_post_max_size
    store_domain_setting "$domain" "php_post_max_size" "${php_post_max_size:-64M}"

    read -p "PHP memory_limit for $domain (e.g., 256M, default: 256M): " php_memory_limit
    store_domain_setting "$domain" "php_memory_limit" "${php_memory_limit:-256M}"

    read -p "PHP max_execution_time for $domain (seconds, default: 300): " php_max_execution_time
    store_domain_setting "$domain" "php_max_execution_time" "${php_max_execution_time:-300}"

    store_domain_setting "$domain" "platform" "$platform"
    store_domain_setting "$domain" "domain_name_explicit" "$domain"

    if ask_yes_no "Configure additional domain aliases (parked/multi-domain) for $domain?" "n"; then
        store_domain_setting "$domain" "enable_multi_domain" "true"
        read -p "Enter additional domain names, comma-separated (e.g., alias1.com,www.alias2.net): " extra_domains_str
        store_domain_setting "$domain" "extra_domains_list_str" "$extra_domains_str"
    else
        store_domain_setting "$domain" "enable_multi_domain" "false"
    fi

    if [[ "$GLOBAL_ENABLE_ROLLBACK_POLICY" == "true" ]]; then
        if ask_yes_no "Enable pre-action backups (rollback) for $domain (Global policy is ON)?" "y"; then
            store_domain_setting "$domain" "enable_rollback" "true"
        else
            store_domain_setting "$domain" "enable_rollback" "false"
        fi
    else
        if ask_yes_no "Enable pre-action backups (rollback) for $domain (Global policy is OFF)?" "n"; then
            store_domain_setting "$domain" "enable_rollback" "true"
        else
            store_domain_setting "$domain" "enable_rollback" "false"
        fi
    fi

    if [[ "$GLOBAL_ENABLE_DOCKER_SUPPORT" == "true" ]]; then
        if ask_yes_no "Enable Docker container deployment for $domain (Docker support is globally ON)?" "n"; then
            store_domain_setting "$domain" "enable_docker_domain" "true"
            read -p "Host port to map to container's port 80 for $domain (e.g., 8080, must be unique): " docker_host_port
            store_domain_setting "$domain" "docker_host_port" "${docker_host_port:-}"
        else
            store_domain_setting "$domain" "enable_docker_domain" "false"
        fi
    fi

    if ask_yes_no "Enable a staging environment for $domain?" "n"; then
        store_domain_setting "$domain" "enable_staging" "true"
        read -p "Subdomain prefix for staging (default: staging): " staging_subdomain_prefix
        store_domain_setting "$domain" "staging_subdomain_prefix" "${staging_subdomain_prefix:-staging}"
    else
        store_domain_setting "$domain" "enable_staging" "false"
    fi

    if [[ "$GLOBAL_SECURE_FILE_PERMISSIONS_POLICY" == "true" ]]; then
        if ask_yes_no "Enforce secure file permissions for $domain (Global policy is ON)?" "y"; then
            store_domain_setting "$domain" "secure_file_permissions" "true"
        else
            store_domain_setting "$domain" "secure_file_permissions" "false"
        fi
    else
        if ask_yes_no "Enforce secure file permissions for $domain (Global policy is OFF)?" "n"; then
            store_domain_setting "$domain" "secure_file_permissions" "true"
        else
            store_domain_setting "$domain" "secure_file_permissions" "false"
        fi
    fi

    if [[ "$GLOBAL_SECURE_DATABASE_POLICY" == "true" ]]; then
        if ask_yes_no "Enforce secure database user privileges for $domain (Global policy is ON)?" "y"; then
            store_domain_setting "$domain" "secure_database" "true"
        else
            store_domain_setting "$domain" "secure_database" "false"
        fi
    else
        if ask_yes_no "Enforce secure database user privileges for $domain (Global policy is OFF)?" "n"; then
            store_domain_setting "$domain" "secure_database" "true"
        else
            store_domain_setting "$domain" "secure_database" "false"
        fi
    fi
}

################################################################################
# Function: configure_wordpress_settings
# Purpose : Collect WordPress-specific settings for a given domain.
# Arguments:
#   $1 - Domain name
################################################################################
configure_wordpress_settings() {
    local domain="$1"

    print_colored_message "blue" "\n--- Configuring WordPress Specific Settings for: $domain ---"

    read -p "WordPress site title for $domain (default: $domain): " wp_title
    store_domain_setting "$domain" "wordpress_title" "${wp_title:-$domain}"

    read -p "WordPress admin username for $domain (default: admin): " wp_admin_user
    store_domain_setting "$domain" "wordpress_admin_user" "${wp_admin_user:-admin}"

    read -p "WordPress admin password for $domain (or 'generate'): " wp_admin_pass_input
    if [[ "$wp_admin_pass_input" == "generate" ]]; then
        wp_admin_password=$(generate_secure_password)
        print_colored_message "green" "Generated WP Admin password: $wp_admin_password (save this)"
    elif [[ -n "$wp_admin_pass_input" ]]; then
        wp_admin_password="$wp_admin_pass_input"
    else
        wp_admin_password=$(generate_secure_password)
        print_colored_message "green" "Generated WP Admin password (empty input): $wp_admin_password (save this)"
    fi
    store_domain_setting "$domain" "wordpress_admin_password" "$wp_admin_password"

    store_domain_setting "$domain" "wordpress_admin_email" "$(get_domain_setting "$domain" "admin_email")"

    read -p "WordPress database table prefix for $domain (default: wp_): " wp_db_prefix
    store_domain_setting "$domain" "wordpress_db_prefix" "${wp_db_prefix:-wp_}"

    read -p "WordPress locale (e.g. en_US, fa_IR, default: en_US): " wp_locale
    store_domain_setting "$domain" "wordpress_locale" "${wp_locale:-en_US}"

    print_colored_message "yellow" "Generating WordPress security keys and salts for $domain..."
    # Generate random base64 strings with newlines removed
    store_domain_setting "$domain" "wordpress_auth_key" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain" "wordpress_secure_auth_key" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain" "wordpress_logged_in_key" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain" "wordpress_nonce_key" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain" "wordpress_auth_salt" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain" "wordpress_secure_auth_salt" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain" "wordpress_logged_in_salt" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain" "wordpress_nonce_salt" "$(openssl rand -base64 64 | tr -d '\n\r')"

    if ask_yes_no "Enable SMTP for $domain (using WP Mail SMTP plugin)?" "n"; then
        store_domain_setting "$domain" "enable_smtp" "true"

        if [[ "$GLOBAL_ENABLE_SMTP_MASTER_SWITCH" == "true" ]]; then
            if ask_yes_no "Use global SMTP settings for $domain?" "y"; then
                # Use global SMTP settings; no further input required
                :
            else
                read -p "Domain SMTP Host for $domain: " domain_smtp_host
                store_domain_setting "$domain" "smtp_host" "$domain_smtp_host"
            fi
        else
            print_colored_message "yellow" "Global SMTP is OFF. You'll need to provide all SMTP details for $domain."
            read -p "Domain SMTP Host for $domain: " domain_smtp_host
            store_domain_setting "$domain" "smtp_host" "$domain_smtp_host"
        fi
    else
        store_domain_setting "$domain" "enable_smtp" "false"
    fi

    if ask_yes_no "Enable image optimization for $domain (WP Smush plugin)?" "n"; then
        store_domain_setting "$domain" "enable_image_optimization" "true"
    else
        store_domain_setting "$domain" "enable_image_optimization" "false"
    fi

    if [[ "$GLOBAL_ENABLE_ADVANCED_SECURITY" == "true" ]]; then
        if ask_yes_no "Enable WordPress advanced security for $domain (Wordfence, if Global Adv. Security is ON)?" "y"; then
            store_domain_setting "$domain" "enable_advanced_security_domain" "true"
        else
            store_domain_setting "$domain" "enable_advanced_security_domain" "false"
        fi
    else
        if ask_yes_no "Enable WordPress advanced security for $domain (Wordfence, Global Adv. Security is OFF)?" "n"; then
            store_domain_setting "$domain" "enable_advanced_security_domain" "true"
        else
            store_domain_setting "$domain" "enable_advanced_security_domain" "false"
        fi
    fi

    if ask_yes_no "Do you plan to migrate an existing WordPress site to $domain later (enables migration playbook)?" "n"; then
        store_domain_setting "$domain" "enable_migration_placeholder" "true"
    fi

    if ask_yes_no "Enable CDN for $domain (CDN Enabler plugin)?" "n"; then
        store_domain_setting "$domain" "enable_cdn" "true"
        read -p "CDN URL for $domain (e.g., https://cdn.example.com): " cdn_enabler_url
        store_domain_setting "$domain" "cdn_enabler_url" "$cdn_enabler_url"
    else
        store_domain_setting "$domain" "enable_cdn" "false"
    fi

    if [[ "$GLOBAL_INSTALL_REDIS" == "true" ]]; then
        if ask_yes_no "Enable advanced caching with Redis for $domain (Memcached/Redis Object Cache, Global Redis ON)?" "y"; then
            store_domain_setting "$domain" "enable_advanced_caching" "true"
            store_domain_setting "$domain" "cache_type" "redis"
        else
            store_domain_setting "$domain" "enable_advanced_caching" "false"
        fi
    else
        if ask_yes_no "Enable advanced caching with Memcached for $domain (Global Redis OFF)?" "n"; then
            store_domain_setting "$domain" "enable_advanced_caching" "true"
            store_domain_setting "$domain" "cache_type" "memcached"
        else
            store_domain_setting "$domain" "enable_advanced_caching" "false"
        fi
    fi

    if ask_yes_no "Enable basic anti-hack measures for $domain (remove readme.html, etc.)?" "y"; then
        store_domain_setting "$domain" "enable_anti_hack" "true"
    else
        store_domain_setting "$domain" "enable_anti_hack" "false"
    fi

    if ask_yes_no "Clone WP Backup script (github.com/jamal13647850/wpbackup.git) for $domain?" "n"; then
        store_domain_setting "$domain" "enable_wpbackup_clone" "true"
    else
        store_domain_setting "$domain" "enable_wpbackup_clone" "false"
    fi
}

################################################################################
# Function: configure_laravel_settings
# Purpose : Collect Laravel-specific settings for a given domain.
# Arguments:
#   $1 - Domain name
################################################################################
configure_laravel_settings() {
    local domain="$1"

    print_colored_message "blue" "\n--- Configuring Laravel Specific Settings for: $domain ---"

    read -p "Laravel App Name for $domain (default: $domain): " laravel_app_name
    store_domain_setting "$domain" "laravel_app_name" "${laravel_app_name:-$domain}"

    read -p "Laravel App Environment (production, development, local, default: production): " laravel_app_env
    store_domain_setting "$domain" "laravel_app_env" "${laravel_app_env:-production}"

    store_domain_setting "$domain" "laravel_admin_email" "$(get_domain_setting "$domain" "admin_email")"

    if ask_yes_no "Generate APP_KEY now (recommended) or let the playbook handle it for $domain?" "y"; then
        local app_key="base64:$(openssl rand -base64 32)"
        store_domain_setting "$domain" "laravel_app_key" "$app_key"
    else
        store_domain_setting "$domain" "laravel_app_key" ""
    fi

    if [[ "$GLOBAL_INSTALL_REDIS" == "true" ]]; then
        if ask_yes_no "Use Redis for Laravel caching/session/queue for $domain (Global Redis ON)?" "y"; then
            store_domain_setting "$domain" "laravel_use_redis" "true"
        else
            store_domain_setting "$domain" "laravel_use_redis" "false"
        fi
    else
        store_domain_setting "$domain" "laravel_use_redis" "false"
    fi

    if ask_yes_no "Enable Laravel Scheduler for $domain?" "n"; then
        store_domain_setting "$domain" "enable_scheduler" "true"
    else
        store_domain_setting "$domain" "enable_scheduler" "false"
    fi

    if ask_yes_no "Enable Laravel Queue Workers for $domain?" "n"; then
        store_domain_setting "$domain" "enable_queue" "true"
        read -p "Default queue driver for $domain (database, redis, sync, default: database): " queue_driver
        store_domain_setting "$domain" "queue_driver" "${queue_driver:-database}"
    else
        store_domain_setting "$domain" "enable_queue" "false"
    fi

    if [[ "$(get_domain_setting "$domain" "enable_queue")" == "true" ]]; then
        if ask_yes_no "Enable Laravel Horizon for $domain (requires Redis for queue)?" "n"; then
            store_domain_setting "$domain" "enable_horizon" "true"
            if [[ "$(get_domain_setting "$domain" "laravel_use_redis")" != "true" && "$(get_domain_setting "$domain" "queue_driver")" != "redis" ]]; then
                print_colored_message "yellow" "Warning: Horizon works best with Redis. Ensure your queue connection is Redis."
            fi
        else
            store_domain_setting "$domain" "enable_horizon" "false"
        fi
    else
        store_domain_setting "$domain" "enable_horizon" "false"
    fi

    if ask_yes_no "Enable Laravel Octane for $domain?" "n"; then
        store_domain_setting "$domain" "enable_octane" "true"

        read -p "Octane server for $domain (swoole, roadrunner, default: swoole): " octane_server
        store_domain_setting "$domain" "octane_server" "${octane_server:-swoole}"

        read -p "Octane service host (default: 127.0.0.1): " octane_service_host
        store_domain_setting "$domain" "octane_service_host" "${octane_service_host:-127.0.0.1}"

        read -p "Octane service port (default: 8000): " octane_service_port
        store_domain_setting "$domain" "octane_service_port" "${octane_service_port:-8000}"
    else
        store_domain_setting "$domain" "enable_octane" "false"
    fi

    if ask_yes_no "Enable Laravel WebSockets for $domain (beyondcode/laravel-websockets)?" "n"; then
        store_domain_setting "$domain" "enable_websockets" "true"

        read -p "WebSockets service host (e.g., 0.0.0.0, default: 0.0.0.0): " websockets_service_host
        store_domain_setting "$domain" "websockets_service_host" "${websockets_service_host:-0.0.0.0}"

        read -p "WebSockets service port (default: 6001): " websockets_service_port
        store_domain_setting "$domain" "websockets_service_port" "${websockets_service_port:-6001}"
    else
        store_domain_setting "$domain" "enable_websockets" "false"
    fi

    if ask_yes_no "Enable Laravel Telescope for $domain (development tool)?" "n"; then
        store_domain_setting "$domain" "enable_telescope" "true"

        read -p "Telescope dashboard path for $domain (default: telescope): " telescope_path
        store_domain_setting "$domain" "telescope_path" "${telescope_path:-telescope}"

        if [[ "$(get_domain_setting "$domain" "laravel_app_env")" == "production" ]]; then
            if ask_yes_no "Allow Telescope in production for $domain (SECURITY RISK: exposes data)?" "n"; then
                store_domain_setting "$domain" "telescope_allow_in_production" "true"
            else
                store_domain_setting "$domain" "telescope_allow_in_production" "false"
            fi
        fi
    else
        store_domain_setting "$domain" "enable_telescope" "false"
    fi

    if ask_yes_no "Enable API features for $domain (Sanctum for auth, Scribe for docs)?" "n"; then
        store_domain_setting "$domain" "enable_api" "true"

        if ask_yes_no "Enable API authentication (Laravel Sanctum) for $domain?" "y"; then
            store_domain_setting "$domain" "enable_api_auth" "true"
        else
            store_domain_setting "$domain" "enable_api_auth" "false"
        fi

        if ask_yes_no "Enable API documentation (Scribe) for $domain?" "n"; then
            store_domain_setting "$domain" "enable_api_docs" "true"
        else
            store_domain_setting "$domain" "enable_api_docs" "false"
        fi
    else
        store_domain_setting "$domain" "enable_api" "false"
    fi
}

################################################################################
# Function: generate_yaml_config
# Purpose : Construct the YAML content from collected settings for output file.
# Returns : YAML formatted string.
################################################################################
generate_yaml_config() {
    local yaml_content=""
    yaml_content+="---\n"
    yaml_content+="# Ansible Group Vars - Generated by generate_config.sh\n\n"

    # Global Server Settings
    yaml_content+="# Global Server Settings\n"
    yaml_content+="GLOBAL_LINUX_USERNAME: \"${GLOBAL_LINUX_USERNAME}\"\n"
    yaml_content+="GLOBAL_PHP_DEFAULT_VERSION: \"${GLOBAL_PHP_DEFAULT_VERSION}\"\n"
    yaml_content+="GLOBAL_MYSQL_ROOT_PASSWORD: \"${GLOBAL_MYSQL_ROOT_PASSWORD}\"\n"
    yaml_content+="GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT: ${GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT}\n"
    if [[ "$GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT" == "true" ]]; then
        yaml_content+="GLOBAL_PHP_ADDITIONAL_VERSIONS_STRING: \"${GLOBAL_PHP_ADDITIONAL_VERSIONS_STRING}\"\n"
    fi
    yaml_content+="GLOBAL_LETSENCRYPT_DEFAULT_EMAIL: \"${GLOBAL_LETSENCRYPT_DEFAULT_EMAIL}\"\n"
    yaml_content+="GLOBAL_LETSENCRYPT_TEST_CERT: ${GLOBAL_LETSENCRYPT_TEST_CERT}\n\n"

    # Global Service Settings
    yaml_content+="# Global Service Settings\n"
    yaml_content+="GLOBAL_INSTALL_REDIS: ${GLOBAL_INSTALL_REDIS}\n"
    if [[ "$GLOBAL_INSTALL_REDIS" == "true" ]]; then
        yaml_content+="GLOBAL_REDIS_HOST: \"${GLOBAL_REDIS_HOST}\"\n"
        yaml_content+="GLOBAL_REDIS_PORT: ${GLOBAL_REDIS_PORT}\n"
        [[ -n "$GLOBAL_REDIS_PASSWORD" ]] && yaml_content+="GLOBAL_REDIS_PASSWORD: \"${GLOBAL_REDIS_PASSWORD}\"\n"
    fi
    yaml_content+="GLOBAL_ENABLE_SMTP_MASTER_SWITCH: ${GLOBAL_ENABLE_SMTP_MASTER_SWITCH}\n"
    if [[ "$GLOBAL_ENABLE_SMTP_MASTER_SWITCH" == "true" ]]; then
        yaml_content+="GLOBAL_SMTP_HOST: \"${GLOBAL_SMTP_HOST}\"\n"
        yaml_content+="GLOBAL_SMTP_PORT: ${GLOBAL_SMTP_PORT}\n"
        [[ -n "$GLOBAL_SMTP_USERNAME" ]] && yaml_content+="GLOBAL_SMTP_USERNAME: \"${GLOBAL_SMTP_USERNAME}\"\n"
        [[ -n "$GLOBAL_SMTP_PASSWORD" ]] && yaml_content+="GLOBAL_SMTP_PASSWORD: \"${GLOBAL_SMTP_PASSWORD}\"\n"
        yaml_content+="GLOBAL_SMTP_ENCRYPTION: \"${GLOBAL_SMTP_ENCRYPTION}\"\n"
    fi
    yaml_content+="\n"

    # Global Security Features
    yaml_content+="# Global Security Features\n"
    yaml_content+="GLOBAL_FAIL2BAN_ENABLED: ${GLOBAL_FAIL2BAN_ENABLED}\n"
    if [[ "$GLOBAL_FAIL2BAN_ENABLED" == "true" ]]; then
        yaml_content+="GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY: ${GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY}\n"
        yaml_content+="GLOBAL_FAIL2BAN_DEFAULT_FINDTIME: \"${GLOBAL_FAIL2BAN_DEFAULT_FINDTIME}\"\n"
        yaml_content+="GLOBAL_FAIL2BAN_DEFAULT_BANTIME: \"${GLOBAL_FAIL2BAN_DEFAULT_BANTIME}\"\n"
    fi
    yaml_content+="GLOBAL_ENABLE_WAF_DEFAULT: ${GLOBAL_ENABLE_WAF_DEFAULT}\n"
    yaml_content+="GLOBAL_SECURE_FILE_PERMISSIONS_POLICY: ${GLOBAL_SECURE_FILE_PERMISSIONS_POLICY}\n"
    yaml_content+="GLOBAL_SECURE_DATABASE_POLICY: ${GLOBAL_SECURE_DATABASE_POLICY}\n"
    yaml_content+="GLOBAL_SECURITY_AUDIT_POLICY: ${GLOBAL_SECURITY_AUDIT_POLICY}\n"
    yaml_content+="GLOBAL_ENABLE_ADVANCED_SECURITY: ${GLOBAL_ENABLE_ADVANCED_SECURITY}\n\n"

    # Global Operational Features
    yaml_content+="# Global Operational Features\n"
    yaml_content+="GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH: ${GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH}\n"
    if [[ "$GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH" == "true" ]]; then
        yaml_content+="GLOBAL_BACKUP_BASE_DIR: \"${GLOBAL_BACKUP_BASE_DIR}\"\n"
        yaml_content+="GLOBAL_BACKUP_DEFAULT_FREQ: \"${GLOBAL_BACKUP_DEFAULT_FREQ}\"\n"
    fi
    yaml_content+="GLOBAL_ENABLE_MONITORING_TOOLS: ${GLOBAL_ENABLE_MONITORING_TOOLS}\n"
    yaml_content+="GLOBAL_ENABLE_DOCKER_SUPPORT: ${GLOBAL_ENABLE_DOCKER_SUPPORT}\n"
    yaml_content+="GLOBAL_ENABLE_ROLLBACK_POLICY: ${GLOBAL_ENABLE_ROLLBACK_POLICY}\n"
    if [[ "$GLOBAL_ENABLE_ROLLBACK_POLICY" == "true" ]]; then
        yaml_content+="GLOBAL_PRE_ACTION_BACKUP_DIR: \"${GLOBAL_PRE_ACTION_BACKUP_DIR}\"\n"
    fi
    yaml_content+="GLOBAL_ENABLE_MULTILINGUAL_DOCS: ${GLOBAL_ENABLE_MULTILINGUAL_DOCS}\n"
    if [[ "$GLOBAL_ENABLE_MULTILINGUAL_DOCS" == "true" ]]; then
        yaml_content+="GLOBAL_DOC_LANGUAGES_LIST: [${GLOBAL_DOC_LANGUAGES_LIST//,/\",\"}]\n"
    fi
    yaml_content+="\n"

    # Domain-specific settings under 'domains'
    yaml_content+="domains:\n"
    for domain_name in "${domains_list[@]}"; do
        yaml_content+="  ${domain_name}:\n"
        for key in "${!domain_settings[@]}"; do
            if [[ "$key" == "${domain_name}___"* ]]; then
                local setting_key="${key#*___}"
                local setting_value="${domain_settings[$key]}"

                # Detect boolean, numeric or empty values for proper YAML formatting
                if [[ "$setting_value" == "true" || "$setting_value" == "false" || "$setting_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    yaml_content+="    ${setting_key}: ${setting_value}\n"
                elif [[ -z "$setting_value" ]]; then
                    yaml_content+="    ${setting_key}: \"\"\n"
                else
                    yaml_content+="    ${setting_key}: \"${setting_value}\"\n"
                fi
            fi
        done
    done

    # Output generated YAML content
    echo -e "$yaml_content"
}

################################################################################
# Function: main
# Purpose : Main execution flow to run the interactive configuration.
################################################################################
main() {
    print_colored_message "green" "=== Ansible Configuration Generator ==="
    print_colored_message "yellow" "This script will guide you through setting up global and per-domain configurations."

    # Backup existing configuration if present
    if [[ -f "$CONFIG_FILE_PATH" ]]; then
        if ! ask_yes_no "Configuration file '$CONFIG_FILE_PATH' already exists. Overwrite it?" "n"; then
            print_colored_message "red" "Configuration generation aborted by user."
            exit 0
        else
            print_colored_message "yellow" "Backing up existing configuration to ${CONFIG_FILE_PATH}.bak"
            cp "$CONFIG_FILE_PATH" "${CONFIG_FILE_PATH}.bak"
        fi
    fi

    # Configure global settings
    configure_global_server_settings
    configure_global_services
    configure_global_security_features
    configure_global_operational_features

    print_colored_message "blue" "\n--- Domain Configuration ---"

    local first_domain=true
    while true; do
        if [[ "$first_domain" == "true" ]]; then
            read -p "Enter the primary domain name for your first site (e.g., example.com): " domain_name
        else
            read -p "Enter another domain name, or leave empty to finish adding domains: " domain_name
        fi

        if [[ -z "$domain_name" && "$first_domain" == "false" ]]; then
            break
        elif [[ -z "$domain_name" && "$first_domain" == "true" ]]; then
            print_colored_message "red" "You must configure at least one domain."
            continue
        fi

        if ! validate_domain_name "$domain_name"; then
            print_colored_message "red" "Invalid domain name format. Please try again."
            continue
        fi

        local domain_already_exists=false
        for existing_domain in "${domains_list[@]}"; do
            if [[ "$existing_domain" == "$domain_name" ]]; then
                domain_already_exists=true
                break
            fi
        done

        if [[ "$domain_already_exists" == "true" ]]; then
            print_colored_message "red" "Domain '$domain_name' has already been configured. Enter a different domain."
            continue
        fi

        echo "Select platform for $domain_name:"
        echo "  1) WordPress"
        echo "  2) Laravel"

        read -p "Platform choice [1-2] (default: 1): " platform_choice
        local platform

        case "$platform_choice" in
            1) platform="wordpress" ;;
            2) platform="laravel" ;;
            *) platform="wordpress" ;;
        esac

        # Append domain and store platform
        domains_list+=("$domain_name")
        domain_platforms["$domain_name"]="$platform"

        # Collect domain-specific configuration based on platform
        configure_domain_basics "$domain_name" "$platform"

        if [[ "$platform" == "wordpress" ]]; then
            configure_wordpress_settings "$domain_name"
        elif [[ "$platform" == "laravel" ]]; then
            configure_laravel_settings "$domain_name"
        fi

        print_colored_message "green" "Configuration for domain '$domain_name' completed."

        first_domain=false
    done

    if [[ ${#domains_list[@]} -eq 0 ]]; then
        print_colored_message "red" "No domains were configured. Exiting."
        exit 1
    fi

    print_colored_message "blue" "\nGenerating YAML configuration file..."
    local generated_yaml
    generated_yaml=$(generate_yaml_config)

    echo "$generated_yaml" > "$CONFIG_FILE_PATH"

    print_colored_message "green" "\nConfiguration generation complete!"
    print_colored_message "green" "File saved to: $CONFIG_FILE_PATH"
    print_colored_message "blue" "You can now review '$CONFIG_FILE_PATH' and then run './run_playbooks.sh' to apply the configuration."
}

main
