#!/bin/bash
#
# Script Author: Sayyed Jamal Ghasemi
# Full Stack Developer
# Email: jamal13647850@gmail.com
# LinkedIn: https://www.linkedin.com/in/jamal1364/
# Instagram: https://www.instagram.com/jamal13647850
# Telegram: https://t.me/jamaldev
# Website: https://jamalghasemi.com
#
# Date: 2025-06-04
# Description: Ansible playbook runner script for server deployment and configuration.
#

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat pipe failures as errors.
set -o pipefail

# Check if running as root
if [ "$EUID" -ne 0 ];
then
  echo "Please run as root or with sudo"
  exit 1
fi

# Configuration
CONFIG_FILE="group_vars/all.yml"
LOG_DIR="logs"
CURRENT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAIN_LOG_FILE="$LOG_DIR/deployment_$CURRENT_TIMESTAMP.log"
INVENTORY_FILE="inventory"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Prints a message with a specified color.
# $1: color (green, yellow, red, blue)
# $2: message string
print_message() {
    local color=$1
    local message=$2

    case $color in
        "green") echo -e "${GREEN}${message}${NC}" ;;
        "yellow") echo -e "${YELLOW}${message}${NC}" ;;
        "red") echo -e "${RED}${message}${NC}" ;;
        "blue") echo -e "${BLUE}${message}${NC}" ;;
        *) echo -e "${message}" ;;
    esac
}

# Checks for required command-line dependencies.
check_dependencies() {
    if ! command -v python3 &> /dev/null;
    then
        print_message "red" "Python 3 is required but not installed. Please install it."
        exit 1
    fi

    if ! python3 -c "import yaml" &> /dev/null;
    then
        print_message "yellow" "PyYAML is not installed. Attempting to install..."
        if command -v apt-get &> /dev/null;
        then
            apt-get update -qq && apt-get install -y python3-yaml ||
            {
                print_message "yellow" "Failed to install python3-yaml via apt. Trying pip3..."
                pip3 install PyYAML ||
                {
                    print_message "red" "Failed to install PyYAML using both apt and pip3. Please install it manually."
                    exit 1
                }
            }
        elif command -v yum &> /dev/null;
        then
             yum install -y python3-pyyaml ||
             {
                print_message "yellow" "Failed to install python3-pyyaml via yum. Trying pip3..."
                pip3 install PyYAML ||
                {
                    print_message "red" "Failed to install PyYAML using both yum and pip3. Please install it manually."
                    exit 1
                }
            }
        else
            print_message "yellow" "Package manager not identified (apt/yum). Trying pip3 to install PyYAML..."
            pip3 install PyYAML ||
            {
                print_message "red" "Failed to install PyYAML using pip3. Please install it manually."
                exit 1
            }
        fi
        print_message "green" "PyYAML installed successfully."
    fi

    if ! command -v ansible-playbook &> /dev/null;
    then
        print_message "red" "Ansible is not installed. Please install it."
        exit 1
    fi

    if [ ! -f "$INVENTORY_FILE" ];
    then
        print_message "red" "Inventory file '$INVENTORY_FILE' not found."
        print_message "yellow" "Please create an inventory file (e.g., with 'localhost ansible_connection=local')."
        # Allow script to continue if inventory is created later, or handle in ansible command
    fi
}

# Parses the main configuration file (group_vars/all.yml) and returns JSON.
parse_config() {
    python3 -c "
import yaml
import sys
import json

try:
    with open('$CONFIG_FILE', 'r') as file:
        config = yaml.safe_load(file)
        print(json.dumps(config if config else {})) # Returns an empty object if the file is empty
except FileNotFoundError:
    print('{}', file=sys.stderr) # Returns an empty object if the file does not exist
    sys.exit(0) # Does not fail, allows script to check config later
except Exception as e:
    print(f'Error parsing YAML: {str(e)}', file=sys.stderr)
    sys.exit(1)
"
}

# Gets domain platforms from the configuration file.
get_domain_platforms() {
    python3 -c "
import yaml
import sys
import json

try:
    with open('$CONFIG_FILE', 'r') as file:
        config = yaml.safe_load(file)
        result = {}
        if config and 'domains' in config: # Check if config is not None
            for domain, settings in config['domains'].items():
                if isinstance(settings, dict) and 'platform' in settings: # Check if settings is a dict
                    result[domain] = settings['platform']
        print(json.dumps(result))
except FileNotFoundError:
    print('{}', file=sys.stderr)
    sys.exit(0)
except Exception as e:
    print(f'Error parsing domains: {str(e)}', file=sys.stderr)
    sys.exit(1)
"
}

# Checks if a specific feature is enabled for a domain or globally.
# $1: domain_or_global_scope (domain name or empty for global)
# $2: feature_key
# $3: default_value (optional, defaults to "false")
is_feature_enabled() {
    local domain_or_global_scope="$1"
    local feature_key="$2"
    local default_value="${3:-false}"

    python3 -c "
import yaml
import sys
import json

config_file = '$CONFIG_FILE'
domain_or_global_scope = '$domain_or_global_scope'
feature_key = '$feature_key'
default_value = '$default_value'.lower() == 'true'

try:
    with open(config_file, 'r') as file:
        config = yaml.safe_load(file)
        if not config: # Empty YAML file
            print(str(default_value).lower())
            sys.exit(0)

        value_found = None

        if domain_or_global_scope and 'domains' in config and domain_or_global_scope in config['domains'] and isinstance(config['domains'][domain_or_global_scope], dict):
            # Check domain-specific configuration
            if feature_key in config['domains'][domain_or_global_scope]:
                value_found = config['domains'][domain_or_global_scope][feature_key]

        if value_found is None:
            # If not found in domain or if scope is global, check global settings
            # Transforms 'feature_key' to 'GLOBAL_FEATURE_KEY' (e.g., 'enable_ssl' -> 'GLOBAL_ENABLE_SSL')
            global_feature_key_parts = feature_key.split('_')
            if len(global_feature_key_parts) > 0:
                 # e.g.: enable_ssl -> GLOBAL_ENABLE_SSL;
                 # install_redis -> GLOBAL_INSTALL_REDIS
                if global_feature_key_parts[0] in ['enable', 'install', 'secure', 'use', 'manage']:
                    global_key_name = 'GLOBAL_' + feature_key.upper()
                else: # More generic case, like 'fail2ban_enabled' -> GLOBAL_FAIL2BAN_ENABLED
                    global_key_name = 'GLOBAL_' + feature_key.upper()

                # Special global naming cases:
                if feature_key == 'enable_advanced_caching': global_key_name = 'GLOBAL_ENABLE_ADVANCED_CACHING'
                elif feature_key == 'enable_image_optimization': global_key_name = 'GLOBAL_ENABLE_IMAGE_OPTIMIZATION'
                elif feature_key == 'enable_advanced_security': global_key_name = 'GLOBAL_ENABLE_ADVANCED_SECURITY'
                elif feature_key == 'enable_cdn': global_key_name = 'GLOBAL_ENABLE_CDN'
                elif feature_key == 'enable_local_cdn': global_key_name = 'GLOBAL_ENABLE_LOCAL_CDN'
                elif feature_key == 'enable_docker': global_key_name = 'GLOBAL_ENABLE_DOCKER_SUPPORT'
                elif feature_key == 'enable_multilingual_docs': global_key_name = 'GLOBAL_ENABLE_MULTILINGUAL_DOCS'
                elif feature_key == 'enable_rollback': global_key_name = 'GLOBAL_ENABLE_ROLLBACK_POLICY'
                elif feature_key == 'enable_waf': global_key_name = 'GLOBAL_ENABLE_WAF_DEFAULT'
                elif feature_key == 'enable_php_versions': global_key_name = 'GLOBAL_ENABLE_PHP_VERSIONS_MANAGEMENT'
                elif feature_key == 'enable_multi_domain': global_key_name = 'GLOBAL_ENABLE_MULTI_DOMAIN_POLICY'
                elif feature_key == 'enable_parked_domains': global_key_name = 'GLOBAL_ENABLE_PARKED_DOMAINS_POLICY'
                elif feature_key == 'enable_staging': global_key_name = 'GLOBAL_ENABLE_STAGING_POLICY'
                elif feature_key == 'enable_anti_hack': global_key_name = 'GLOBAL_ENABLE_ANTI_HACK_POLICY'
                elif feature_key == 'fail2ban_enabled': global_key_name = 'GLOBAL_FAIL2BAN_ENABLED' # Already the default
                elif feature_key == 'secure_file_permissions': global_key_name = 'GLOBAL_SECURE_FILE_PERMISSIONS_POLICY'
                elif feature_key == 'secure_database': global_key_name = 'GLOBAL_SECURE_DATABASE_POLICY'
                elif feature_key == 'security_audit': global_key_name = 'GLOBAL_SECURITY_AUDIT_POLICY'
                elif feature_key == 'enable_smtp': global_key_name = 'GLOBAL_ENABLE_SMTP_MASTER_SWITCH'
                elif feature_key == 'enable_backups': global_key_name = 'GLOBAL_ENABLE_BACKUPS_MASTER_SWITCH'
                elif feature_key == 'enable_monitoring': global_key_name = 'GLOBAL_ENABLE_MONITORING_TOOLS'
                # Laravel specific global fallbacks might not be common, usually domain-specific first
                elif feature_key == 'enable_scheduler': global_key_name = 'GLOBAL_LARAVEL_ENABLE_SCHEDULER'
                elif feature_key == 'enable_queue': global_key_name = 'GLOBAL_LARAVEL_ENABLE_QUEUE'
                elif feature_key == 'enable_horizon': global_key_name = 'GLOBAL_LARAVEL_ENABLE_HORIZON'
                elif feature_key == 'enable_octane': global_key_name = 'GLOBAL_LARAVEL_ENABLE_OCTANE'
                elif feature_key == 'enable_websockets': global_key_name = 'GLOBAL_LARAVEL_ENABLE_WEBSOCKETS'
                elif feature_key == 'enable_telescope': global_key_name = 'GLOBAL_LARAVEL_ENABLE_TELESCOPE' # Assuming a global for Telescope
                elif feature_key == 'enable_api': global_key_name = 'GLOBAL_LARAVEL_ENABLE_API'

                if global_key_name in config:
                    value_found = config[global_key_name]

        if value_found is not None:
            print(str(value_found).lower())
        else:
            print(str(default_value).lower())

except FileNotFoundError: # If config file doesn't exist, use default
    print(str(default_value).lower())
except Exception as e:
    # In case of parsing error, return default to avoid breaking the script
    # print(f'Python error in is_feature_enabled: {str(e)}', file=sys.stderr)
    print(str(default_value).lower())
"
}

# Gets domain-specific configuration, with fallbacks to global settings.
# $1: domain name
get_domain_config() {
    local domain="$1"

    python3 -c "
import yaml
import sys
import json

config_file = '$CONFIG_FILE'
domain_name = '$domain'

try:
    with open(config_file, 'r') as file:
        config = yaml.safe_load(file)
        if config and 'domains' in config and domain_name in config['domains'] and isinstance(config['domains'][domain_name], dict):
            domain_config = config['domains'][domain_name].copy() # Make a copy to avoid modifying the original
            domain_config['domain'] = domain_name # Add the domain name to the returned dict

            # Add global configurations as fallback if not defined in the domain
            # This is useful for templates that might use GLOBAL_X or domain_config.X
            if 'GLOBAL_LINUX_USERNAME' in config: domain_config.setdefault('linux_username', config['GLOBAL_LINUX_USERNAME'])
            if 'GLOBAL_PHP_DEFAULT_VERSION' in config: domain_config.setdefault('php_version', config['GLOBAL_PHP_DEFAULT_VERSION'])
            if 'GLOBAL_MYSQL_ROOT_PASSWORD' in config: domain_config.setdefault('mysql_root_password', config['GLOBAL_MYSQL_ROOT_PASSWORD'])
            # ... add other global fallbacks as needed ...

            print(json.dumps(domain_config))
        else:
            # Returns a basic domain config if not found, to avoid errors in ansible
            print(json.dumps({'domain': domain_name, 'platform': 'unknown'}))
except FileNotFoundError:
    print(json.dumps({'domain': domain_name, 'platform': 'unknown', 'error': 'config_file_not_found'}))
except Exception as e:
    # print(f'Python error in get_domain_config: {str(e)}', file=sys.stderr)
    print(json.dumps({'domain': domain_name, 'platform': 'unknown', 'error': str(e)}))
"
}

# Runs an Ansible playbook.
# $1: playbook_path
# $2: description of the playbook
# $3: ask_confirmation (true/false, optional, default: true)
# $4: domain_context (optional, domain name for domain-specific vars)
run_playbook() {
    local playbook_path="$1"
    local description="$2"
    local ask_confirmation="${3:-true}"
    local domain_context="$4"

    print_message "blue" "Attempting to run: $description"

    local extra_vars_json="{}"
    local domain_config_json # Will store JSON for the specific domain
    if [ -n "$domain_context" ];
    then
        domain_config_json=$(get_domain_config "$domain_context")

        if [[ -z "$domain_config_json" || "$domain_config_json" == "{}" || "$domain_config_json" == *"error"* ]];
        then
             print_message "red" "Error fetching domain config for $domain_context: $domain_config_json. Skipping $description."
             return 1
        fi
    fi

    local full_config_json # Will store JSON for all global vars
    local extra_vars_payload # Will store the final JSON string for --extra-vars

    full_config_json=$(parse_config)

    # Construct the payload for --extra-vars
    if [[ -n "$full_config_json" && "$full_config_json" != "{}" ]];
    then
        if [ -n "$domain_context" ] && [[ -n "$domain_config_json" && "$domain_config_json" != "{}" ]]; then
             # Both global and specific domain configs are present
             extra_vars_payload="{\"ansible_global_vars\": $full_config_json, \"domain_config\": $domain_config_json }"
        else
             # Only global config is present (or domain_context was not provided)
             extra_vars_payload="{\"ansible_global_vars\": $full_config_json}"
        fi
    elif [ -n "$domain_context" ] && [[ -n "$domain_config_json" && "$domain_config_json" != "{}" ]]; then
         # Only specific domain_config (full_config_json was empty)
         extra_vars_payload="{\"domain_config\": $domain_config_json}"
    else
         # No variables to pass
         extra_vars_payload="{}"
    fi

    if [ "$ask_confirmation" == "true" ];
    then
        read -p "$(echo -e "${YELLOW}Do you want to run $description? (Y/n): ${NC}")" -n 1 -r REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ && -n "$REPLY" ]]; then
            print_message "yellow" "Skipping $description"
            return 0
        fi
    fi

    print_message "blue" "Running $description..."

    local cmd_args=()
    cmd_args+=("-i" "$INVENTORY_FILE")
    cmd_args+=("$playbook_path")

    if [[ -n "$extra_vars_payload" && "$extra_vars_payload" != "{}" ]]; then
        cmd_args+=("--extra-vars" "$extra_vars_payload")
    fi
    cmd_args+=("-v") # Add verbosity flag

    # For debugging the exact command being run:
    # print_message "yellow" "Executing: ansible-playbook ${cmd_args[*]}"

    if ansible-playbook "${cmd_args[@]}" | tee -a "$MAIN_LOG_FILE"; then
        print_message "green" "$description completed successfully!"
    else
        local exit_code=${PIPESTATUS[0]}
        print_message "red" "$description failed with exit code $exit_code!"
        print_message "yellow" "Check $MAIN_LOG_FILE for details."

        read -p "$(echo -e "${RED}Continue with deployment? (y/N): ${NC}")" -n 1 -r REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "red" "Deployment aborted by user."
            exit 1
        fi
        return $exit_code
    fi
    return 0
}

# Runs global system playbooks.
run_global_playbooks() {
    print_message "blue" "--- Running Global System Playbooks ---"

    run_playbook "00-update-upgrade.yml" "Base System Update and Upgrade" "false" ""
    run_playbook "01-install-mysql.yml" "MySQL Installation" "false" ""
    run_playbook "02-install-nginx.yml" "Nginx Installation" "false" ""
    run_playbook "03-install-php-composer-wpcli.yml" "PHP, Composer & WP-CLI Installation" "false" "" # Assume global default PHP here

    if [[ "$(is_feature_enabled "" "install_redis" "false")" == "true" ]];
    then
        run_playbook "06-install-redis.yml" "Redis Installation" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_smtp" "false")" == "true" ]];
    then
        print_message "yellow" "Global SMTP configuration needs a dedicated playbook or manual setup if not using a per-domain WordPress SMTP plugin."
    fi
    if [[ "$(is_feature_enabled "" "enable_backups" "false")" == "true" ]];
    then
        print_message "yellow" "Global backup configuration needs a dedicated playbook. 07-setup-backups.yml is per-domain."
    fi
     if [[ "$(is_feature_enabled "" "fail2ban_enabled" "false")" == "true" ]];
     then
        run_playbook "23-install-fail2ban.yml" "Fail2Ban Installation & SSHD Jail" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_monitoring" "false")" == "true" ]];
    then
        run_playbook "09-setup-monitoring.yml" "Basic Monitoring Tools Installation" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "secure_file_permissions" "false")" == "true" ]];
    then
        print_message "yellow" "Global secure file permissions policy needs careful consideration and potentially a dedicated playbook. 24-secure-file-permissions.yml is per-domain."
    fi
    if [[ "$(is_feature_enabled "" "secure_database" "false")" == "true" ]];
    then
        run_playbook "25-secure-database.yml" "MySQL Server Security Hardening (General)" "false" "" # Adapted to be more global
    fi
     if [[ "$(is_feature_enabled "" "security_audit" "false")" == "true" ]];
     then
        run_playbook "26-security-audit.yml" "System Security Audit Tools (Lynis, Rkhunter)" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_docker" "false")" == "true" ]];
    then
        run_playbook "14-setup-docker.yml" "Docker Support Installation" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_waf" "false")" == "true" ]];
    then
        run_playbook "18-setup-waf.yml" "WAF (ModSecurity with Nginx) Base Installation" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_php_versions" "false")" == "true" ]];
    then
        run_playbook "19-manage-php.yml" "Additional PHP Versions Management" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_multilingual_docs" "false")" == "true" ]];
    then
        print_message "yellow" "Running '15-generate-docs.yml' for project documentation (runs on localhost)."
        ansible-playbook -i "$INVENTORY_FILE" "15-generate-docs.yml" --connection=local | tee -a "$MAIN_LOG_FILE"
    fi

    print_message "blue" "--- Global System Playbooks COMPLETED ---"
}

# Runs domain-specific playbooks based on platform (WordPress, Laravel, etc.).
# $1: domain_name
# $2: platform
run_domain_specific_playbooks() {
    local domain_name="$1"
    local platform="$2"

    print_message "blue" "--- Running Playbooks for Domain: $domain_name (Platform: $platform) ---"

    if [[ "$(is_feature_enabled "$domain_name" "enable_rollback" "false")" == "true" ]];
    then
        run_playbook "16-setup-rollback.yml" "Pre-action Backup for $domain_name" "false" "$domain_name"
    fi

    if [ "$platform" == "wordpress" ];
    then
        run_playbook "04-install-wordpress.yml" "WordPress Core Installation for $domain_name" "false" "$domain_name"
    elif [ "$platform" == "laravel" ];
    then
        run_playbook "laravel/01-install-laravel.yml" "Laravel Project Creation for $domain_name" "false" "$domain_name"
        run_playbook "laravel/02-configure-laravel.yml" "Laravel Base Configuration & Nginx Setup for $domain_name" "false" "$domain_name"
    else
        print_message "red" "Unknown platform '$platform' for domain $domain_name. Skipping platform-specific core setup."
        return
    fi

    # Check if ssl_email is defined and not empty for the domain to run SSL setup
    local ssl_email_value
    ssl_email_value=$(python3 -c "import yaml, sys, json; config=yaml.safe_load(open('$CONFIG_FILE')); print(config.get('domains',{}).get('$domain_name',{}).get('ssl_email',''))")

    if [[ -n "$ssl_email_value" ]];
    then
         run_playbook "05-obtain-ssl.yml" "SSL Certificate Setup for $domain_name" "false" "$domain_name"
    fi

    if [[ "$(is_feature_enabled "" "fail2ban_enabled" "false")" == "true" && "$platform" == "wordpress" ]];
    then
         run_playbook "23-install-fail2ban.yml" "Fail2Ban WordPress Jail for $domain_name" "false" "$domain_name"
    fi
    if [[ "$(is_feature_enabled "$domain_name" "secure_file_permissions" "false")" == "true" ]];
    then
        run_playbook "24-secure-file-permissions.yml" "Secure File Permissions for $domain_name" "false" "$domain_name"
    fi
     if [[ "$(is_feature_enabled "$domain_name" "secure_database" "false")" == "true" ]];
     then
        run_playbook "25-secure-database.yml" "Secure Database User Privileges for $domain_name" "false" "$domain_name"
    fi

    if [ "$platform" == "wordpress" ];
    then
        if [[ "$(is_feature_enabled "$domain_name" "enable_smtp" "false")" == "true" ]];
        then
            run_playbook "08-configure-smtp.yml" "WordPress SMTP Configuration for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_image_optimization" "false")" == "true" ]];
        then
            run_playbook "10-optimize-images.yml" "WordPress Image Optimization for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_advanced_security" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_advanced_security_domain" "false")" == "true" ]];
        then
            run_playbook "11-advanced-security.yml" "WordPress Advanced Security (Wordfence) for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_migration" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_migration_placeholder" "false")" == "true" ]];
        then
            run_playbook "12-migrate-wordpress.yml" "WordPress Migration for $domain_name" "true" "$domain_name" # Ask for confirmation for migration
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_cdn" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_local_cdn" "false")" == "true" ]]; then
            run_playbook "13-setup-cdn.yml" "WordPress CDN Setup for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_advanced_caching" "false")" == "true" ]];
        then
            run_playbook "17-advanced-caching.yml" "WordPress Advanced Caching (Memcached/Redis) for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_anti_hack" "false")" == "true" ]];
        then
            run_playbook "22-anti-hack.yml" "WordPress Anti-Hack Measures for $domain_name" "false" "$domain_name"
        fi
    fi

    if [ "$platform" == "laravel" ];
    then
        if [[ "$(is_feature_enabled "$domain_name" "enable_scheduler" "false")" == "true" ]];
        then
            run_playbook "laravel/03-laravel-scheduler.yml" "Laravel Scheduler for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_queue" "false")" == "true" ]];
        then
            run_playbook "laravel/04-laravel-queue.yml" "Laravel Queue Workers for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_horizon" "false")" == "true" ]];
        then
            run_playbook "laravel/05-laravel-horizon.yml" "Laravel Horizon for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_octane" "false")" == "true" ]];
        then
            run_playbook "laravel/06-laravel-octane.yml" "Laravel Octane for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_websockets" "false")" == "true" ]];
        then
            run_playbook "laravel/07-laravel-websockets.yml" "Laravel WebSockets for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_telescope" "false")" == "true" ]];
        then
            run_playbook "laravel/08-laravel-telescope.yml" "Laravel Telescope for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_api" "false")" == "true" ]];
        then
            run_playbook "laravel/09-laravel-api.yml" "Laravel API (Sanctum, Scribe) for $domain_name" "false" "$domain_name"
        fi
    fi

    if [[ "$(is_feature_enabled "" "enable_docker" "false")" == "true" && "$(is_feature_enabled "$domain_name" "enable_docker_domain" "false")" == "true" ]];
    then
        print_message "yellow" "Domain-specific Docker container setup for $domain_name (using 14-setup-docker.yml) needs review. This playbook primarily installs Docker."
    fi

    if [[ "$(is_feature_enabled "$domain_name" "enable_staging" "false")" == "true" ]];
    then
        run_playbook "21-staging.yml" "Staging Environment Setup for $domain_name" "false" "$domain_name"
    fi

    if [[ "$(is_feature_enabled "$domain_name" "enable_multi_domain" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_parked_domains" "false")" == "true"  ]]; then
        run_playbook "20-multi-domain.yml" "Multi-domain/Parked Domain Notice for $domain_name" "false" "$domain_name"
    fi

    if [[ "$(is_feature_enabled "" "security_audit" "false")" == "true" && "$platform" == "wordpress" ]];
    then
         print_message "yellow" "WordPress site security scan (part of global 26-security-audit.yml) covers $domain_name."
    fi

    print_message "green" "--- Playbooks for Domain $domain_name COMPLETED ---"
}

# Main execution block of the script.
main() {
    print_message "green" "=== Ansible Playbook Runner ==="
    print_message "blue" "Log file: $MAIN_LOG_FILE"

    check_dependencies

    if [ ! -f "$CONFIG_FILE" ]; then
        print_message "red" "Configuration file $CONFIG_FILE not found."
        print_message "yellow" "Please run ./generate_config.sh first to create the configuration, or create it manually."
        exit 1
    fi

    print_message "blue" "Validating configuration file..."
    local config_json
    config_json=$(parse_config)
    if [ $? -ne 0 ] || [[ "$config_json" == "{}" && "$(wc -l < $CONFIG_FILE)" -gt 1 ]]; then # Check if parsing failed or file is non-empty but parsed as empty
        print_message "red" "Failed to parse configuration file or file is empty/invalid. Please check $CONFIG_FILE."
        exit 1
    fi
    print_message "green" "Configuration file validated successfully."
    echo
    print_message "blue" "Select deployment mode:"
    echo "1) Full deployment (global + all domain-specific playbooks)"
    echo "2) Global playbooks only"
    echo "3) Domain-specific playbooks only (for all configured domains)"
    echo "4) Specific domain only"
    read -p "Enter choice [1-4]: " deployment_mode

    local platforms_json_data

    case $deployment_mode in
        1)
            print_message "blue" "Running FULL deployment..."
            run_global_playbooks

            platforms_json_data=$(get_domain_platforms)
            if [[ -z "$platforms_json_data" || "$platforms_json_data" == "{}" ]]; then
                print_message "yellow" "No domains found in configuration to process for domain-specific playbooks."
            else
                python3 -c "
import json, sys
data = json.loads('''$platforms_json_data''')
for domain_key in data.keys():
    print(domain_key)
" |
                while read -r domain_item; do
                    local platform_item
                    platform_item=$(echo "$platforms_json_data" | python3 -c "import json, sys; d=json.loads(sys.stdin.read()); print(d.get('$domain_item', 'unknown'))")
                    run_domain_specific_playbooks "$domain_item" "$platform_item"
                done
            fi
            ;;
        2)
            print_message "blue" "Running GLOBAL playbooks only..."
            run_global_playbooks
            ;;
        3)
            print_message "blue" "Running DOMAIN-SPECIFIC playbooks for ALL configured domains..."
            platforms_json_data=$(get_domain_platforms)
            if [[ -z "$platforms_json_data" || "$platforms_json_data" == "{}" ]]; then
                print_message "yellow" "No domains found in configuration to process."
            else
                 python3 -c "
import json, sys
data = json.loads('''$platforms_json_data''')
for domain_key in data.keys():
    print(domain_key)
" |
                 while read -r domain_item; do
                    local platform_item
                    platform_item=$(echo "$platforms_json_data" | python3 -c "import json, sys; d=json.loads(sys.stdin.read()); print(d.get('$domain_item', 'unknown'))")
                    run_domain_specific_playbooks "$domain_item" "$platform_item"
                done
            fi
            ;;
        4)
            print_message "blue" "Running for a SPECIFIC domain..."
            platforms_json_data=$(get_domain_platforms)
            if [[ -z "$platforms_json_data" || "$platforms_json_data" == "{}" ]]; then
                print_message "red" "No domains found in configuration."
                exit 1
            fi

            echo "Available domains:"
            python3 -c "
import json, sys
data = json.loads('''$platforms_json_data''')
i = 1
for domain_key, platform_val in data.items():
    print(f'{i}) {domain_key} ({platform_val})')
    i += 1
"
            read -p "Enter the number of the domain to deploy: " domain_choice

            local selected_domain_name
            selected_domain_name=$(python3 -c "
import json, sys
data = json.loads('''$platforms_json_data''')
domains_list = list(data.keys())
try:
    choice_index = int('$domain_choice') - 1
    if 0 <= choice_index < len(domains_list):
        print(domains_list[choice_index])
    else:
        sys.exit(1) # Silent exit for error, shell will handle
except (ValueError, IndexError):
    sys.exit(1) # Silent exit
")
            if [ -z "$selected_domain_name" ];
            then
                print_message "red" "Invalid domain choice. Exiting."
                exit 1
            fi
            local selected_platform
            selected_platform=$(echo "$platforms_json_data" | python3 -c "import json, sys; d=json.loads(sys.stdin.read()); print(d.get('$selected_domain_name', 'unknown'))")

            run_domain_specific_playbooks "$selected_domain_name" "$selected_platform"
            ;;
        *)
            print_message "red" "Invalid choice. Exiting."
            exit 1
            ;;
    esac

    print_message "green" "========================================"
    print_message "green" "  Deployment Script Finished  "
    print_message "green" "========================================"
    print_message "blue" "Main deployment log: $MAIN_LOG_FILE"
    echo
    print_message "yellow" "Recommended next steps:"
    print_message "yellow" "1. Review the main log file for any warnings or errors."
    print_message "yellow" "2. Test Nginx configuration: sudo nginx -t"
    print_message "yellow" "3. Verify critical services are running: systemctl status nginx mysql php<VERSION>-fpm redis-server (if applicable)"
    print_message "yellow" "4. Thoroughly test your website(s) and applications."
}

# Run the main function
main
