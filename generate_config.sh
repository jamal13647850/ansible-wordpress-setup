#!/bin/bash
# generate_config.sh
# Script para gerar o arquivo de configuração group_vars/all.yml para os playbooks Ansible.

set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Diretório e arquivo de configuração
CONFIG_DIR="group_vars"
CONFIG_FILE="${CONFIG_DIR}/all.yml"

# Cria o diretório se não existir
mkdir -p "${CONFIG_DIR}"

# Arrays para armazenar configurações de domínio
declare -A DOMAIN_PLATFORMS
declare -A DOMAIN_CONFIGS # Usado para armazenar configurações específicas de cada domínio
DOMAINS=()              # Array simples para manter a ordem dos domínios adicionados

# Variáveis globais (prefixadas com GLOBAL_ para clareza no YAML)
# Estas serão preenchidas pelas funções de configuração global

# --- Funções Utilitárias ---

print_message() {
    local color="$1"
    local message="$2"
    case $color in
        "green") echo -e "${GREEN}${message}${NC}" ;;
        "yellow") echo -e "${YELLOW}${message}${NC}" ;;
        "red") echo -e "${RED}${message}${NC}" ;;
        "blue") echo -e "${BLUE}${message}${NC}" ;;
        *) echo -e "${message}" ;;
    esac
}

generate_secure_password() {
    # Gera uma senha de 32 caracteres hexadecimais (16 bytes)
    openssl rand -hex 16
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_domain_name() {
    local domain="$1"
    # Regex simples para validação de nome de domínio
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
        return 1
    fi
    return 0
}

ask_yes_no() {
    local prompt_message="$1"
    local default_answer="${2:-y}" # 'y' ou 'n'
    local full_prompt

    if [[ "$default_answer" == "y" ]]; then
        full_prompt="$prompt_message [Y/n]: "
    else
        full_prompt="$prompt_message [y/N]: "
    fi

    while true; do
        read -p "$(echo -e "${YELLOW}${full_prompt}${NC}")" response
        response=${response:-$default_answer} # Usa o padrão se a resposta for vazia
        case "$response" in
            [Yy]*) return 0 ;; # true
            [Nn]*) return 1 ;; # false
            *) print_message "red" "Please answer yes (y) or no (n)." ;;
        esac
    done
}

# Armazena uma configuração para um domínio específico
# Ex: store_domain_setting "example.com" "php_version" "8.1"
store_domain_setting() {
    local domain_name="$1"
    local key="$2"
    local value="$3"
    DOMAIN_CONFIGS["${domain_name}___${key}"]="$value" # Usar ___ para evitar conflito com '.' em nomes de chaves
}

# Obtém uma configuração de um domínio, com fallback para um valor padrão
# Ex: php_version=$(get_domain_setting "example.com" "php_version" "8.2")
get_domain_setting() {
    local domain_name="$1"
    local key="$2"
    local default_value="${3:-}"
    local value="${DOMAIN_CONFIGS["${domain_name}___${key}"]}"
    if [[ -z "$value" ]]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# --- Funções de Configuração Global ---

configure_global_server_settings() {
    print_message "blue" "\n--- Configuring Global Server Settings ---"

    read -p "Enter default Linux username for server operations (e.g., ubuntu, admin): " GLOBAL_LINUX_USERNAME
    GLOBAL_LINUX_USERNAME=${GLOBAL_LINUX_USERNAME:-ubuntu}

    read -p "Enter default PHP version for new sites (e.g., 8.1, 8.2, 8.3): " GLOBAL_PHP_DEFAULT_VERSION
    GLOBAL_PHP_DEFAULT_VERSION=${GLOBAL_PHP_DEFAULT_VERSION:-8.2}

    print_message "yellow" "Enter a strong MySQL root password. This will be set on the server."
    read -s -p "MySQL Root Password: " GLOBAL_MYSQL_ROOT_PASSWORD
    echo
    while [[ -z "$GLOBAL_MYSQL_ROOT_PASSWORD" ]]; do
        print_message "red" "MySQL root password cannot be empty."
        read -s -p "MySQL Root Password: " GLOBAL_MYSQL_ROOT_PASSWORD
        echo
    done

    if ask_yes_no "Enable management of additional PHP versions globally?" "n"; then
        GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT="true"
        read -p "Enter additional PHP versions to install, comma-separated (e.g., 7.4,8.0): " GLOBAL_PHP_ADDITIONAL_VERSIONS_STRING
    else
        GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT="false"
    fi
    
    read -p "Default Let's Encrypt email for SSL (required for SSL generation): " GLOBAL_LETSENCRYPT_DEFAULT_EMAIL
    while ! validate_email "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" && [[ -n "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" ]]; do # Permite vazio se SSL não for usado globalmente
        print_message "red" "Invalid email format."
        read -p "Default Let's Encrypt email for SSL: " GLOBAL_LETSENCRYPT_DEFAULT_EMAIL
    done
    if ask_yes_no "Use Let's Encrypt staging server for testing certificates globally (not for production)?" "n"; then
        GLOBAL_LETSENCRYPT_TEST_CERT="true"
    else
        GLOBAL_LETSENCRYPT_TEST_CERT="false"
    fi

}

configure_global_services() {
    print_message "blue" "\n--- Configuring Global Service Settings ---"
    # Redis
    if ask_yes_no "Install Redis server globally (can be used by WordPress/Laravel)?" "n"; then
        GLOBAL_INSTALL_REDIS="true"
        read -p "Global Redis host (default: 127.0.0.1): " GLOBAL_REDIS_HOST
        GLOBAL_REDIS_HOST=${GLOBAL_REDIS_HOST:-127.0.0.1}
        read -p "Global Redis port (default: 6379): " GLOBAL_REDIS_PORT
        GLOBAL_REDIS_PORT=${GLOBAL_REDIS_PORT:-6379}
        read -p "Global Redis password (leave empty for none, or 'generate'): " redis_pass_input
        if [[ "$redis_pass_input" == "generate" ]]; then
            GLOBAL_REDIS_PASSWORD=$(generate_secure_password)
            print_message "green" "Generated Redis password: $GLOBAL_REDIS_PASSWORD (save this)"
        elif [[ -n "$redis_pass_input" ]]; then
            GLOBAL_REDIS_PASSWORD="$redis_pass_input"
        else
            GLOBAL_REDIS_PASSWORD="" # Explicitamente vazio
        fi
    else
        GLOBAL_INSTALL_REDIS="false"
    fi

    # SMTP
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

configure_global_security_features() {
    print_message "blue" "\n--- Configuring Global Security Features ---"
    # Fail2Ban
    if ask_yes_no "Enable Fail2Ban globally (for SSH and other services)?" "y"; then
        GLOBAL_FAIL2BAN_ENABLED="true"
        read -p "Global Fail2Ban default maxretry (default: 5): " GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY
        GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY=${GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY:-5}
        read -p "Global Fail2Ban default findtime (e.g., 10m, 1h, default: 10m): " GLOBAL_FAIL2BAN_DEFAULT_FINDTIME
        GLOBAL_FAIL2BAN_DEFAULT_FINDTIME=${GLOBAL_FAIL2BAN_DEFAULT_FINDTIME:-10m}
        read -p "Global Fail2Ban default bantime (e.g., 1h, 1d, -1 for permanent, default: 1h): " GLOBAL_FAIL2BAN_DEFAULT_BANTIME
        GLOBAL_FAIL2BAN_DEFAULT_BANTIME=${GLOBAL_FAIL2BAN_DEFAULT_BANTIME:-1h}
    else
        GLOBAL_FAIL2BAN_ENABLED="false"
    fi

    # WAF (ModSecurity)
    if ask_yes_no "Enable WAF (ModSecurity with Nginx) base installation globally?" "n"; then
        GLOBAL_ENABLE_WAF_DEFAULT="true"
        # Configurações mais detalhadas do WAF (regras, etc.) são complexas para este script
        # e devem ser feitas nos playbooks ou manualmente.
    else
        GLOBAL_ENABLE_WAF_DEFAULT="false"
    fi

    # General Security Policies
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
        GLOBAL_ENABLE_ADVANCED_SECURITY="true" # Relacionado ao playbook 11-advanced-security.yml
    else
        GLOBAL_ENABLE_ADVANCED_SECURITY="false"
    fi

}

configure_global_operational_features() {
    print_message "blue" "\n--- Configuring Global Operational Features ---"
    # Backups
    if ask_yes_no "Enable automated backups globally (master switch, can be configured per domain)?" "n"; then
        GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH="true"
        read -p "Global base directory for backups (default: /var/backups/ansible_managed): " GLOBAL_BACKUP_BASE_DIR
        GLOBAL_BACKUP_BASE_DIR=${GLOBAL_BACKUP_BASE_DIR:-/var/backups/ansible_managed}
        read -p "Global default backup frequency (cron format, e.g., '0 2 * * *' for daily at 2 AM): " GLOBAL_BACKUP_DEFAULT_FREQ
        GLOBAL_BACKUP_DEFAULT_FREQ=${GLOBAL_BACKUP_DEFAULT_FREQ:-"0 2 * * *"}
    else
        GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH="false"
    fi

    # Monitoring
    if ask_yes_no "Install basic system monitoring tools (htop, logrotate) globally?" "y"; then
        GLOBAL_ENABLE_MONITORING_TOOLS="true"
    else
        GLOBAL_ENABLE_MONITORING_TOOLS="false"
    fi

    # Docker Support
    if ask_yes_no "Enable Docker support on the server (install Docker engine and Compose)?" "n"; then
        GLOBAL_ENABLE_DOCKER_SUPPORT="true"
    else
        GLOBAL_ENABLE_DOCKER_SUPPORT="false"
    fi

    # Rollback Policy
    if ask_yes_no "Enable pre-action backups for rollback capability globally (can be configured per domain)?" "y"; then
        GLOBAL_ENABLE_ROLLBACK_POLICY="true"
        read -p "Global base directory for pre-action backups (default: /var/backups/ansible_pre_action): " GLOBAL_PRE_ACTION_BACKUP_DIR
        GLOBAL_PRE_ACTION_BACKUP_DIR=${GLOBAL_PRE_ACTION_BACKUP_DIR:-/var/backups/ansible_pre_action}
    else
        GLOBAL_ENABLE_ROLLBACK_POLICY="false"
    fi
    
    # Project Documentation Generation
    if ask_yes_no "Enable generation of multilingual project documentation (Ansible project itself, runs on localhost)?" "n"; then
        GLOBAL_ENABLE_MULTILINGUAL_DOCS="true"
        read -p "Languages for documentation, comma-separated (e.g., en,fa): " GLOBAL_DOC_LANGUAGES_LIST
        GLOBAL_DOC_LANGUAGES_LIST=${GLOBAL_DOC_LANGUAGES_LIST:-en,fa}
    else
        GLOBAL_ENABLE_MULTILINGUAL_DOCS="false"
    fi
}


# --- Funções de Configuração por Domínio ---

configure_domain_basics() {
    local domain_name="$1"
    local platform="$2"
    print_message "blue" "\n--- Configuring Basic Settings for Domain: $domain_name ($platform) ---"

    # Email, PHP Version (pode usar globais como fallback)
    read -p "Admin email for $domain_name (default: $GLOBAL_LETSENCRYPT_DEFAULT_EMAIL): " admin_email
    admin_email=${admin_email:-$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL}
    while ! validate_email "$admin_email"; do
        print_message "red" "Invalid email format for $domain_name."
        read -p "Admin email for $domain_name: " admin_email
    done
    store_domain_setting "$domain_name" "admin_email" "$admin_email"
    
    if [[ -n "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" && "$admin_email" == "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" ]]; then
         store_domain_setting "$domain_name" "ssl_email" "$GLOBAL_LETSENCRYPT_DEFAULT_EMAIL" # Usa o global se for o mesmo
    elif [[ -n "$admin_email" ]]; then
        if ask_yes_no "Use '$admin_email' as the Let's Encrypt SSL email for $domain_name?" "y"; then
            store_domain_setting "$domain_name" "ssl_email" "$admin_email"
        else
            read -p "Enter specific Let's Encrypt SSL email for $domain_name (leave empty to skip SSL): " specific_ssl_email
            if [[ -n "$specific_ssl_email" ]]; then
                 while ! validate_email "$specific_ssl_email"; do
                    print_message "red" "Invalid SSL email format."
                    read -p "Specific Let's Encrypt SSL email for $domain_name: " specific_ssl_email
                done
                store_domain_setting "$domain_name" "ssl_email" "$specific_ssl_email"
            else
                store_domain_setting "$domain_name" "ssl_email" "" # Sem SSL para este domínio
            fi
        fi
    else
        store_domain_setting "$domain_name" "ssl_email" "" # Sem SSL
    fi


    read -p "PHP version for $domain_name (default: $GLOBAL_PHP_DEFAULT_VERSION): " php_version
    php_version=${php_version:-$GLOBAL_PHP_DEFAULT_VERSION}
    store_domain_setting "$domain_name" "php_version" "$php_version"

    # Database
    db_name_default="${domain_name//[.-]/_}_db"
    read -p "MySQL database name for $domain_name (default: $db_name_default): " db_name
    db_name=${db_name:-$db_name_default}
    store_domain_setting "$domain_name" "mysql_db_name" "$db_name"

    db_user_default="${domain_name//[.-]/_}_user"
    read -p "MySQL username for $domain_name (default: $db_user_default): " db_user
    db_user=${db_user:-$db_user_default}
    store_domain_setting "$domain_name" "mysql_db_user" "$db_user"

    read -p "MySQL password for $domain_name (or 'generate'): " db_password_input
    if [[ "$db_password_input" == "generate" ]]; then
        db_password=$(generate_secure_password)
        print_message "green" "Generated MySQL password for $domain_name: $db_password (save this)"
    elif [[ -n "$db_password_input" ]]; then
        db_password="$db_password_input"
    else
        db_password=$(generate_secure_password) # Gera se vazio também
        print_message "green" "Generated MySQL password for $domain_name (empty input): $db_password (save this)"
    fi
    store_domain_setting "$domain_name" "mysql_db_password" "$db_password"

    # Nginx settings
    read -p "Nginx client_max_body_size for $domain_name (e.g., 64M, default: 10M): " nginx_client_max_body_size
    store_domain_setting "$domain_name" "nginx_client_max_body_size" "${nginx_client_max_body_size:-10M}"

    # PHP-FPM settings
    read -p "PHP upload_max_filesize for $domain_name (e.g., 64M, default: 64M): " php_upload_max_filesize
    store_domain_setting "$domain_name" "php_upload_max_filesize" "${php_upload_max_filesize:-64M}"
    read -p "PHP post_max_size for $domain_name (e.g., 64M, default: 64M): " php_post_max_size
    store_domain_setting "$domain_name" "php_post_max_size" "${php_post_max_size:-64M}"
    read -p "PHP memory_limit for $domain_name (e.g., 256M, default: 256M): " php_memory_limit
    store_domain_setting "$domain_name" "php_memory_limit" "${php_memory_limit:-256M}"
    read -p "PHP max_execution_time for $domain_name (seconds, default: 300): " php_max_execution_time
    store_domain_setting "$domain_name" "php_max_execution_time" "${php_max_execution_time:-300}"

    # Store platform and domain name itself
    store_domain_setting "$domain_name" "platform" "$platform"
    # domain_config.domain é adicionado pelo run_playbooks.sh, mas podemos adicionar aqui também
    store_domain_setting "$domain_name" "domain_name_explicit" "$domain_name"


    # Multi-domain / Parked Domains
    if ask_yes_no "Configure additional domain aliases (parked/multi-domain) for $domain_name?" "n"; then
        store_domain_setting "$domain_name" "enable_multi_domain" "true" # Ou parked_domains
        read -p "Enter additional domain names, comma-separated (e.g., alias1.com,www.alias2.net): " extra_domains_str
        store_domain_setting "$domain_name" "extra_domains_list_str" "$extra_domains_str" # O playbook irá splitar
    else
        store_domain_setting "$domain_name" "enable_multi_domain" "false"
    fi

    # Rollback
    if [[ "$GLOBAL_ENABLE_ROLLBACK_POLICY" == "true" ]]; then
        if ask_yes_no "Enable pre-action backups (rollback) for $domain_name (Global policy is ON)?" "y"; then
            store_domain_setting "$domain_name" "enable_rollback" "true"
        else
            store_domain_setting "$domain_name" "enable_rollback" "false"
        fi
    else
         if ask_yes_no "Enable pre-action backups (rollback) for $domain_name (Global policy is OFF)?" "n"; then
            store_domain_setting "$domain_name" "enable_rollback" "true"
        else
            store_domain_setting "$domain_name" "enable_rollback" "false"
        fi
    fi
    
    # Docker per domain
    if [[ "$GLOBAL_ENABLE_DOCKER_SUPPORT" == "true" ]]; then
        if ask_yes_no "Enable Docker container deployment for $domain_name (Docker support is globally ON)?" "n"; then
            store_domain_setting "$domain_name" "enable_docker_domain" "true"
            read -p "Host port to map to container's port 80 for $domain_name (e.g., 8080, must be unique): " docker_host_port
            store_domain_setting "$domain_name" "docker_host_port" "${docker_host_port:-}" # Deixar para o usuário preencher
        else
            store_domain_setting "$domain_name" "enable_docker_domain" "false"
        fi
    fi

    # Staging
    if ask_yes_no "Enable a staging environment for $domain_name?" "n"; then
        store_domain_setting "$domain_name" "enable_staging" "true"
        read -p "Subdomain prefix for staging (default: staging): " staging_subdomain_prefix
        store_domain_setting "$domain_name" "staging_subdomain_prefix" "${staging_subdomain_prefix:-staging}"
    else
        store_domain_setting "$domain_name" "enable_staging" "false"
    fi

    # Secure file permissions per domain
    if [[ "$GLOBAL_SECURE_FILE_PERMISSIONS_POLICY" == "true" ]]; then
         if ask_yes_no "Enforce secure file permissions for $domain_name (Global policy is ON)?" "y"; then
            store_domain_setting "$domain_name" "secure_file_permissions" "true"
        else
            store_domain_setting "$domain_name" "secure_file_permissions" "false"
        fi
    else
        if ask_yes_no "Enforce secure file permissions for $domain_name (Global policy is OFF)?" "n"; then
            store_domain_setting "$domain_name" "secure_file_permissions" "true"
        else
            store_domain_setting "$domain_name" "secure_file_permissions" "false"
        fi
    fi
    # Secure database per domain
    if [[ "$GLOBAL_SECURE_DATABASE_POLICY" == "true" ]]; then
         if ask_yes_no "Enforce secure database user privileges for $domain_name (Global policy is ON)?" "y"; then
            store_domain_setting "$domain_name" "secure_database" "true"
        else
            store_domain_setting "$domain_name" "secure_database" "false"
        fi
    else
        if ask_yes_no "Enforce secure database user privileges for $domain_name (Global policy is OFF)?" "n"; then
            store_domain_setting "$domain_name" "secure_database" "true"
        else
            store_domain_setting "$domain_name" "secure_database" "false"
        fi
    fi

}

configure_wordpress_settings() {
    local domain_name="$1"
    print_message "blue" "\n--- Configuring WordPress Specific Settings for: $domain_name ---"

    read -p "WordPress site title for $domain_name (default: $domain_name): " wp_title
    store_domain_setting "$domain_name" "wordpress_title" "${wp_title:-$domain_name}"

    read -p "WordPress admin username for $domain_name (default: admin): " wp_admin_user
    store_domain_setting "$domain_name" "wordpress_admin_user" "${wp_admin_user:-admin}"

    read -p "WordPress admin password for $domain_name (or 'generate'): " wp_admin_pass_input
    if [[ "$wp_admin_pass_input" == "generate" ]]; then
        wp_admin_password=$(generate_secure_password)
        print_message "green" "Generated WP Admin password: $wp_admin_password (save this)"
    elif [[ -n "$wp_admin_pass_input" ]]; then
        wp_admin_password="$wp_admin_pass_input"
    else
        wp_admin_password=$(generate_secure_password) # Gera se vazio
        print_message "green" "Generated WP Admin password (empty input): $wp_admin_password (save this)"
    fi
    store_domain_setting "$domain_name" "wordpress_admin_password" "$wp_admin_password"
    # wordpress_admin_email já foi pego em configure_domain_basics e armazenado como admin_email
    store_domain_setting "$domain_name" "wordpress_admin_email" "$(get_domain_setting "$domain_name" "admin_email")"

    read -p "WordPress database table prefix for $domain_name (default: wp_): " wp_db_prefix
    store_domain_setting "$domain_name" "wordpress_db_prefix" "${wp_db_prefix:-wp_}"
    
    read -p "WordPress locale (e.g. en_US, fa_IR, default: en_US): " wp_locale
    store_domain_setting "$domain_name" "wordpress_locale" "${wp_locale:-en_US}"

    # Gerar chaves de segurança do WordPress
    print_message "yellow" "Generating WordPress security keys and salts for $domain_name..."
    store_domain_setting "$domain_name" "wordpress_auth_key" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain_name" "wordpress_secure_auth_key" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain_name" "wordpress_logged_in_key" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain_name" "wordpress_nonce_key" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain_name" "wordpress_auth_salt" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain_name" "wordpress_secure_auth_salt" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain_name" "wordpress_logged_in_salt" "$(openssl rand -base64 64 | tr -d '\n\r')"
    store_domain_setting "$domain_name" "wordpress_nonce_salt" "$(openssl rand -base64 64 | tr -d '\n\r')"

    # WordPress Features
    if ask_yes_no "Enable SMTP for $domain_name (using WP Mail SMTP plugin)?" "n"; then
        store_domain_setting "$domain_name" "enable_smtp" "true"
        # As configurações de SMTP (host, user, pass) podem ser as globais ou específicas do domínio
        if [[ "$GLOBAL_ENABLE_SMTP_MASTER_SWITCH" == "true" ]]; then
            if ask_yes_no "Use global SMTP settings for $domain_name?" "y"; then
                 # Não precisa armazenar nada aqui, o playbook irá usar os fallbacks para globais
                 : # No-op
            else
                read -p "Domain SMTP Host for $domain_name: " domain_smtp_host
                store_domain_setting "$domain_name" "smtp_host" "$domain_smtp_host"
                # ... (perguntar por port, user, pass, encryption específicos do domínio)
            fi
        else
            print_message "yellow" "Global SMTP is OFF. You'll need to provide all SMTP details for $domain_name."
            read -p "Domain SMTP Host for $domain_name: " domain_smtp_host
            store_domain_setting "$domain_name" "smtp_host" "$domain_smtp_host"
            # ...
        fi
    else
        store_domain_setting "$domain_name" "enable_smtp" "false"
    fi

    if ask_yes_no "Enable image optimization for $domain_name (WP Smush plugin)?" "n"; then
        store_domain_setting "$domain_name" "enable_image_optimization" "true"
    else
        store_domain_setting "$domain_name" "enable_image_optimization" "false"
    fi

    if [[ "$GLOBAL_ENABLE_ADVANCED_SECURITY" == "true" ]]; then
        if ask_yes_no "Enable WordPress advanced security for $domain_name (Wordfence, if Global Adv. Security is ON)?" "y"; then
            store_domain_setting "$domain_name" "enable_advanced_security_domain" "true" # Flag específica do domínio
        else
            store_domain_setting "$domain_name" "enable_advanced_security_domain" "false"
        fi
    else
         if ask_yes_no "Enable WordPress advanced security for $domain_name (Wordfence, Global Adv. Security is OFF)?" "n"; then
            store_domain_setting "$domain_name" "enable_advanced_security_domain" "true"
        else
            store_domain_setting "$domain_name" "enable_advanced_security_domain" "false"
        fi
    fi


    if ask_yes_no "Do you plan to migrate an existing WordPress site to $domain_name later (this enables the migration playbook option)?" "n"; then
        store_domain_setting "$domain_name" "enable_migration_placeholder" "true" # Apenas um placeholder para o run_playbooks
        # O playbook de migração real (12-migrate-wordpress.yml) requer paths locais para os arquivos de backup
        # que não são práticos de serem coletados aqui. Eles devem ser passados como extra-vars no momento da execução.
        print_message "yellow" "Note: For actual migration, paths to DB and files backups must be provided as extra_vars when running the migration playbook."
    fi

    if ask_yes_no "Enable CDN for $domain_name (CDN Enabler plugin)?" "n"; then
        store_domain_setting "$domain_name" "enable_cdn" "true"
        read -p "CDN URL for $domain_name (e.g., https://cdn.example.com): " cdn_enabler_url
        store_domain_setting "$domain_name" "cdn_enabler_url" "$cdn_enabler_url"
    else
        store_domain_setting "$domain_name" "enable_cdn" "false"
    fi

    if [[ "$GLOBAL_INSTALL_REDIS" == "true" ]]; then
        if ask_yes_no "Enable advanced caching with Redis for $domain_name (Memcached/Redis Object Cache, Global Redis is ON)?" "y"; then
            store_domain_setting "$domain_name" "enable_advanced_caching" "true"
            store_domain_setting "$domain_name" "cache_type" "redis" # Ou permitir escolha
            # Configurações de WP Redis como host/port/password podem usar os globais se não especificados aqui
        else
            store_domain_setting "$domain_name" "enable_advanced_caching" "false"
        fi
    else
        # Poderia perguntar por Memcached aqui se Redis global não estiver ativo
        if ask_yes_no "Enable advanced caching with Memcached for $domain_name (Global Redis is OFF)?" "n"; then
            store_domain_setting "$domain_name" "enable_advanced_caching" "true"
            store_domain_setting "$domain_name" "cache_type" "memcached"
        else
            store_domain_setting "$domain_name" "enable_advanced_caching" "false"
        fi
    fi


    if ask_yes_no "Enable basic anti-hack measures for $domain_name (remove readme.html, etc.)?" "y"; then
        store_domain_setting "$domain_name" "enable_anti_hack" "true"
    else
        store_domain_setting "$domain_name" "enable_anti_hack" "false"
    fi
}

configure_laravel_settings() {
    local domain_name="$1"
    print_message "blue" "\n--- Configuring Laravel Specific Settings for: $domain_name ---"

    read -p "Laravel App Name for $domain_name (default: $domain_name): " laravel_app_name
    store_domain_setting "$domain_name" "laravel_app_name" "${laravel_app_name:-$domain_name}"

    read -p "Laravel App Environment (production, development, local, default: production): " laravel_app_env
    store_domain_setting "$domain_name" "laravel_app_env" "${laravel_app_env:-production}"
    store_domain_setting "$domain_name" "laravel_admin_email" "$(get_domain_setting "$domain_name" "admin_email")"

    # APP_KEY será gerado pelo playbook se não fornecido ou vazio
    if ask_yes_no "Generate APP_KEY now (recommended) or let the playbook handle it for $domain_name?" "y"; then
        app_key="base64:$(openssl rand -base64 32)"
        store_domain_setting "$domain_name" "laravel_app_key" "$app_key"
        print_message "green" "Generated APP_KEY for $domain_name: $app_key (save this)"
    else
        store_domain_setting "$domain_name" "laravel_app_key" "" # Playbook irá gerar
    fi
    
    if [[ "$GLOBAL_INSTALL_REDIS" == "true" ]]; then
        if ask_yes_no "Use Redis for Laravel caching/session/queue for $domain_name (Global Redis is ON)?" "y"; then
            store_domain_setting "$domain_name" "laravel_use_redis" "true" # Flag para o playbook de config do Laravel
        else
            store_domain_setting "$domain_name" "laravel_use_redis" "false"
        fi
    else
        store_domain_setting "$domain_name" "laravel_use_redis" "false" # Não pode usar se não estiver instalado
    fi


    # Laravel Features
    if ask_yes_no "Enable Laravel Scheduler for $domain_name?" "n"; then
        store_domain_setting "$domain_name" "enable_scheduler" "true"
    else
        store_domain_setting "$domain_name" "enable_scheduler" "false"
    fi

    if ask_yes_no "Enable Laravel Queue Workers for $domain_name?" "n"; then
        store_domain_setting "$domain_name" "enable_queue" "true"
        read -p "Default queue driver for $domain_name (database, redis, sync, default: database): " queue_driver
        store_domain_setting "$domain_name" "queue_driver" "${queue_driver:-database}"
    else
        store_domain_setting "$domain_name" "enable_queue" "false"
    fi

    if [[ "$(get_domain_setting "$domain_name" "enable_queue")" == "true" ]]; then
        if ask_yes_no "Enable Laravel Horizon for $domain_name (requires Redis for queue)?" "n"; then
            store_domain_setting "$domain_name" "enable_horizon" "true"
            if [[ "$(get_domain_setting "$domain_name" "laravel_use_redis")" != "true" && "$(get_domain_setting "$domain_name" "queue_driver")" != "redis" ]]; then
                 print_message "yellow" "Warning: Horizon works best with Redis. Ensure your queue connection is Redis."
            fi
        else
            store_domain_setting "$domain_name" "enable_horizon" "false"
        fi
    else
        store_domain_setting "$domain_name" "enable_horizon" "false" # Não pode habilitar Horizon sem queue
    fi

    if ask_yes_no "Enable Laravel Octane for $domain_name?" "n"; then
        store_domain_setting "$domain_name" "enable_octane" "true"
        read -p "Octane server for $domain_name (swoole, roadrunner, default: swoole): " octane_server
        store_domain_setting "$domain_name" "octane_server" "${octane_server:-swoole}"
        read -p "Octane service host (default: 127.0.0.1): " octane_service_host
        store_domain_setting "$domain_name" "octane_service_host" "${octane_service_host:-127.0.0.1}"
        read -p "Octane service port (default: 8000): " octane_service_port
        store_domain_setting "$domain_name" "octane_service_port" "${octane_service_port:-8000}"
    else
        store_domain_setting "$domain_name" "enable_octane" "false"
    fi

    if ask_yes_no "Enable Laravel WebSockets for $domain_name (beyondcode/laravel-websockets)?" "n"; then
        store_domain_setting "$domain_name" "enable_websockets" "true"
        read -p "WebSockets service host (e.g., 0.0.0.0, default: 0.0.0.0): " websockets_service_host
        store_domain_setting "$domain_name" "websockets_service_host" "${websockets_service_host:-0.0.0.0}"
        read -p "WebSockets service port (default: 6001): " websockets_service_port
        store_domain_setting "$domain_name" "websockets_service_port" "${websockets_service_port:-6001}"
    else
        store_domain_setting "$domain_name" "enable_websockets" "false"
    fi

    if ask_yes_no "Enable Laravel Telescope for $domain_name (development tool)?" "n"; then
        store_domain_setting "$domain_name" "enable_telescope" "true"
        read -p "Telescope dashboard path for $domain_name (default: telescope): " telescope_path
        store_domain_setting "$domain_name" "telescope_path" "${telescope_path:-telescope}"
        if [[ "$(get_domain_setting "$domain_name" "laravel_app_env")" == "production" ]]; then
            if ask_yes_no "Allow Telescope in production for $domain_name (SECURITY RISK: exposes data)?" "n"; then
                store_domain_setting "$domain_name" "telescope_allow_in_production" "true"
            else
                store_domain_setting "$domain_name" "telescope_allow_in_production" "false"
            fi
        fi
    else
        store_domain_setting "$domain_name" "enable_telescope" "false"
    fi

    if ask_yes_no "Enable API features for $domain_name (Sanctum for auth, Scribe for docs)?" "n"; then
        store_domain_setting "$domain_name" "enable_api" "true"
        if ask_yes_no "Enable API authentication (Laravel Sanctum) for $domain_name?" "y"; then
            store_domain_setting "$domain_name" "enable_api_auth" "true"
        else
            store_domain_setting "$domain_name" "enable_api_auth" "false"
        fi
        if ask_yes_no "Enable API documentation (Scribe) for $domain_name?" "n"; then
            store_domain_setting "$domain_name" "enable_api_docs" "true"
        else
            store_domain_setting "$domain_name" "enable_api_docs" "false"
        fi
    else
        store_domain_setting "$domain_name" "enable_api" "false"
    fi
}

# --- Geração do YAML ---
generate_yaml_config() {
    local yaml_output=""
    yaml_output+="---\n"
    yaml_output+="# Ansible Group Vars - Generated by generate_config.sh\n\n"

    # Global settings
    yaml_output+="# Global Server Settings\n"
    yaml_output+="GLOBAL_LINUX_USERNAME: \"${GLOBAL_LINUX_USERNAME}\"\n"
    yaml_output+="GLOBAL_PHP_DEFAULT_VERSION: \"${GLOBAL_PHP_DEFAULT_VERSION}\"\n"
    yaml_output+="GLOBAL_MYSQL_ROOT_PASSWORD: \"${GLOBAL_MYSQL_ROOT_PASSWORD}\"\n" # Será usado por playbooks
    yaml_output+="GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT: ${GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT}\n"
    if [[ "$GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT" == "true" ]]; then
        yaml_output+="GLOBAL_PHP_ADDITIONAL_VERSIONS_STRING: \"${GLOBAL_PHP_ADDITIONAL_VERSIONS_STRING}\"\n"
    fi
    yaml_output+="GLOBAL_LETSENCRYPT_DEFAULT_EMAIL: \"${GLOBAL_LETSENCRYPT_DEFAULT_EMAIL}\"\n"
    yaml_output+="GLOBAL_LETSENCRYPT_TEST_CERT: ${GLOBAL_LETSENCRYPT_TEST_CERT}\n\n"


    yaml_output+="# Global Service Settings\n"
    yaml_output+="GLOBAL_INSTALL_REDIS: ${GLOBAL_INSTALL_REDIS}\n"
    if [[ "$GLOBAL_INSTALL_REDIS" == "true" ]]; then
        yaml_output+="GLOBAL_REDIS_HOST: \"${GLOBAL_REDIS_HOST}\"\n"
        yaml_output+="GLOBAL_REDIS_PORT: ${GLOBAL_REDIS_PORT}\n"
        [[ -n "$GLOBAL_REDIS_PASSWORD" ]] && yaml_output+="GLOBAL_REDIS_PASSWORD: \"${GLOBAL_REDIS_PASSWORD}\"\n"
    fi
    yaml_output+="GLOBAL_ENABLE_SMTP_MASTER_SWITCH: ${GLOBAL_ENABLE_SMTP_MASTER_SWITCH}\n"
    if [[ "$GLOBAL_ENABLE_SMTP_MASTER_SWITCH" == "true" ]]; then
        yaml_output+="GLOBAL_SMTP_HOST: \"${GLOBAL_SMTP_HOST}\"\n"
        yaml_output+="GLOBAL_SMTP_PORT: ${GLOBAL_SMTP_PORT}\n"
        [[ -n "$GLOBAL_SMTP_USERNAME" ]] && yaml_output+="GLOBAL_SMTP_USERNAME: \"${GLOBAL_SMTP_USERNAME}\"\n"
        [[ -n "$GLOBAL_SMTP_PASSWORD" ]] && yaml_output+="GLOBAL_SMTP_PASSWORD: \"${GLOBAL_SMTP_PASSWORD}\"\n"
        yaml_output+="GLOBAL_SMTP_ENCRYPTION: \"${GLOBAL_SMTP_ENCRYPTION}\"\n"
    fi
    yaml_output+="\n"

    yaml_output+="# Global Security Features\n"
    yaml_output+="GLOBAL_FAIL2BAN_ENABLED: ${GLOBAL_FAIL2BAN_ENABLED}\n"
    if [[ "$GLOBAL_FAIL2BAN_ENABLED" == "true" ]]; then
        yaml_output+="GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY: ${GLOBAL_FAIL2BAN_DEFAULT_MAXRETRY}\n"
        yaml_output+="GLOBAL_FAIL2BAN_DEFAULT_FINDTIME: \"${GLOBAL_FAIL2BAN_DEFAULT_FINDTIME}\"\n"
        yaml_output+="GLOBAL_FAIL2BAN_DEFAULT_BANTIME: \"${GLOBAL_FAIL2BAN_DEFAULT_BANTIME}\"\n"
    fi
    yaml_output+="GLOBAL_ENABLE_WAF_DEFAULT: ${GLOBAL_ENABLE_WAF_DEFAULT}\n"
    yaml_output+="GLOBAL_SECURE_FILE_PERMISSIONS_POLICY: ${GLOBAL_SECURE_FILE_PERMISSIONS_POLICY}\n"
    yaml_output+="GLOBAL_SECURE_DATABASE_POLICY: ${GLOBAL_SECURE_DATABASE_POLICY}\n"
    yaml_output+="GLOBAL_SECURITY_AUDIT_POLICY: ${GLOBAL_SECURITY_AUDIT_POLICY}\n"
    yaml_output+="GLOBAL_ENABLE_ADVANCED_SECURITY: ${GLOBAL_ENABLE_ADVANCED_SECURITY}\n\n"


    yaml_output+="# Global Operational Features\n"
    yaml_output+="GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH: ${GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH}\n"
    if [[ "$GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH" == "true" ]]; then
        yaml_output+="GLOBAL_BACKUP_BASE_DIR: \"${GLOBAL_BACKUP_BASE_DIR}\"\n"
        yaml_output+="GLOBAL_BACKUP_DEFAULT_FREQ: \"${GLOBAL_BACKUP_DEFAULT_FREQ}\"\n"
    fi
    yaml_output+="GLOBAL_ENABLE_MONITORING_TOOLS: ${GLOBAL_ENABLE_MONITORING_TOOLS}\n"
    yaml_output+="GLOBAL_ENABLE_DOCKER_SUPPORT: ${GLOBAL_ENABLE_DOCKER_SUPPORT}\n"
    yaml_output+="GLOBAL_ENABLE_ROLLBACK_POLICY: ${GLOBAL_ENABLE_ROLLBACK_POLICY}\n"
    if [[ "$GLOBAL_ENABLE_ROLLBACK_POLICY" == "true" ]]; then
        yaml_output+="GLOBAL_PRE_ACTION_BACKUP_DIR: \"${GLOBAL_PRE_ACTION_BACKUP_DIR}\"\n"
    fi
    yaml_output+="GLOBAL_ENABLE_MULTILINGUAL_DOCS: ${GLOBAL_ENABLE_MULTILINGUAL_DOCS}\n"
    if [[ "$GLOBAL_ENABLE_MULTILINGUAL_DOCS" == "true" ]]; then
        yaml_output+="GLOBAL_DOC_LANGUAGES_LIST: [${GLOBAL_DOC_LANGUAGES_LIST//,/\",\"}]\n" # Converte para lista YAML
    fi
    yaml_output+="\n"


    # Domain configurations
    yaml_output+="domains:\n"
    for domain_item in "${DOMAINS[@]}"; do
        yaml_output+="  ${domain_item}:\n"
        # Iterar sobre todas as chaves armazenadas para este domínio
        for key_full in "${!DOMAIN_CONFIGS[@]}"; do
            if [[ "$key_full" == "${domain_item}___"* ]]; then
                local setting_key="${key_full#*___}" # Remove o prefixo "dominio___"
                local setting_value="${DOMAIN_CONFIGS[$key_full]}"
                
                # Determinar se o valor precisa de aspas
                if [[ "$setting_value" == "true" || "$setting_value" == "false" || "$setting_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    yaml_output+="    ${setting_key}: ${setting_value}\n"
                elif [[ -z "$setting_value" ]]; then # Valor vazio, pode ser 'null' ou string vazia
                    yaml_output+="    ${setting_key}: \"\"\n" # Ou null, dependendo da necessidade
                else
                    # Escapar aspas simples dentro do valor se estiver usando aspas simples para string YAML
                    # setting_value_escaped="${setting_value//\'/\'\'}"
                    # yaml_output+="    ${setting_key}: '${setting_value_escaped}'\n"
                    # É mais seguro usar aspas duplas e escapar caracteres especiais se necessário, mas para este script,
                    # assumimos que valores complexos não são inseridos diretamente ou são tratados pelos playbooks.
                    yaml_output+="    ${setting_key}: \"${setting_value}\"\n"
                fi
            fi
        done
    done

    echo -e "$yaml_output"
}

# --- Função Principal ---
main() {
    print_message "green" "=== Ansible Configuration Generator ==="
    print_message "yellow" "This script will guide you through setting up global and per-domain configurations."

    if [ -f "$CONFIG_FILE" ]; then
        if ! ask_yes_no "Configuration file '$CONFIG_FILE' already exists. Overwrite it?" "n"; then
            print_message "red" "Configuration generation aborted by user."
            exit 0
        else
            print_message "yellow" "Backing up existing configuration to ${CONFIG_FILE}.bak"
            cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        fi
    fi

    # Coletar configurações globais primeiro
    configure_global_server_settings
    configure_global_services
    configure_global_security_features
    configure_global_operational_features

    # Coletar configurações por domínio
    print_message "blue" "\n--- Domain Configuration ---"
    local first_domain=true
    while true; do
        if [[ "$first_domain" == "true" ]]; then
            read -p "Enter the primary domain name for your first site (e.g., example.com): " domain_name
        else
            read -p "Enter another domain name, or leave empty to finish adding domains: " domain_name
        fi

        if [[ -z "$domain_name" && "$first_domain" == "false" ]]; then
            break # Termina se o nome do domínio for vazio e não for o primeiro domínio
        elif [[ -z "$domain_name" && "$first_domain" == "true" ]]; then
            print_message "red" "You must configure at least one domain."
            continue
        fi
        
        if ! validate_domain_name "$domain_name"; then
            print_message "red" "Invalid domain name format. Please try again."
            continue
        fi

        # Verifica se o domínio já foi adicionado
        local domain_exists=false
        for existing_domain in "${DOMAINS[@]}"; do
            if [[ "$existing_domain" == "$domain_name" ]]; then
                domain_exists=true
                break
            fi
        done
        if [[ "$domain_exists" == "true" ]]; then
            print_message "red" "Domain '$domain_name' has already been configured. Enter a different domain."
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
            *) platform="wordpress" ;; # Padrão para WordPress
        esac

        DOMAINS+=("$domain_name") # Adiciona à lista de domínios
        DOMAIN_PLATFORMS["$domain_name"]="$platform" # Armazena a plataforma (não usado diretamente no YAML final, mas útil durante o script)

        configure_domain_basics "$domain_name" "$platform"
        if [[ "$platform" == "wordpress" ]]; then
            configure_wordpress_settings "$domain_name"
        elif [[ "$platform" == "laravel" ]]; then
            configure_laravel_settings "$domain_name"
        fi
        
        print_message "green" "Configuration for domain '$domain_name' completed."
        first_domain=false
    done
    
    if [ ${#DOMAINS[@]} -eq 0 ]; then
        print_message "red" "No domains were configured. Exiting."
        exit 1
    fi

    # Gerar e salvar o arquivo YAML
    print_message "blue" "\nGenerating YAML configuration file..."
    generated_yaml=$(generate_yaml_config)
    echo "$generated_yaml" > "$CONFIG_FILE"

    print_message "green" "\nConfiguration generation complete!"
    print_message "green" "File saved to: $CONFIG_FILE"
    print_message "blue" "You can now review '$CONFIG_FILE' and then run './run_playbooks.sh' to apply the configuration."
}

# Executar a função principal
main