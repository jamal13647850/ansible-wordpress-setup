#!/bin/bash
#
# ansible_playbook_runner.sh
# Ansible Playbook Runner for Global and Domain-Specific Deployments
#
# Author: Sayyed Jamal Ghasemi
# Full Stack Developer
# Email: jamal13647850@gmail.com
#
# Date: 2024-06-18
#
# Description:
# This script manages and runs Ansible playbooks for system-wide and domain-specific deployments.
# It verifies dependencies, parses configuration,
# allows selective or full-run of playbooks,
# and supports resume on failure with state saving.
#
# Usage:
# Run as root or via sudo.
# Follow interactive prompts to select deployment options.
#
# Logs:
# Main logs go to logs/deployment_main_<timestamp>.log
# Detail logs are created per playbook run in logs/playbook_detail_*.log
#


set -e
set -o pipefail

# Ensure the script is executed with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

CONFIG_FILE="group_vars/all.yml"
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
CURRENT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAIN_LOG_FILE="$LOG_DIR/deployment_main_$CURRENT_TIMESTAMP.log"
PLAYBOOK_LOG_FILE_PREFIX="$LOG_DIR/playbook_detail"
INVENTORY_FILE="inventory"
STATE_FILE=".ansible_run_state"

# Color codes for terminal output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

declare -a PLAYBOOKS_CATALOG

# Catalog of playbooks with path:description:type (type: global, domain, domain-wordpress, domain-laravel, local)
# Uncomment or customize entries as needed
# PLAYBOOKS_CATALOG+=("09-setup-monitoring.yml:Basic Monitoring Tools Global Installation:global")
# PLAYBOOKS_CATALOG+=("15-generate-docs.yml:Generate Multilingual Docs (runs on localhost):local")
# ...

PLAYBOOKS_CATALOG+=("00-update-upgrade.yml:Base System Update and Upgrade:global")
PLAYBOOKS_CATALOG+=("01-install-mysql-global.yml:MySQL Global Installation:global")
PLAYBOOKS_CATALOG+=("02-install-nginx-global.yml:Nginx Global Installation:global")
PLAYBOOKS_CATALOG+=("03-install-php-composer-wpcli.yml:PHP, Composer & WP-CLI Global Installation:global")
PLAYBOOKS_CATALOG+=("06-install-redis.yml:Redis Global Installation:global")
PLAYBOOKS_CATALOG+=("23-install-fail2ban-global.yml:Fail2Ban Global Installation & SSHD Jail:global")
PLAYBOOKS_CATALOG+=("25-secure-database-global.yml:MySQL Server Security Hardening (General - Global):global")
PLAYBOOKS_CATALOG+=("14-setup-docker.yml:Docker Support Global Installation:global")
PLAYBOOKS_CATALOG+=("19-manage-php.yml:Additional PHP Versions Management:global")

PLAYBOOKS_CATALOG+=("01-install-mysql-domain.yml:MySQL Domain-Specific Configuration:domain")
PLAYBOOKS_CATALOG+=("16-setup-rollback.yml:Pre-action Backup for Domain:domain")
PLAYBOOKS_CATALOG+=("23-install-fail2ban-domain.yml:Fail2Ban Domain-Specific Configuration:domain")
PLAYBOOKS_CATALOG+=("05-obtain-ssl.yml:SSL Certificate Setup for Domain:domain")
PLAYBOOKS_CATALOG+=("24-secure-file-permissions.yml:Secure File Permissions for Domain:domain")
PLAYBOOKS_CATALOG+=("20-multi-domain.yml:Multi-domain/Parked Domain Notice for Domain:domain")
PLAYBOOKS_CATALOG+=("21-staging.yml:Staging Environment Setup for Domain:domain")

PLAYBOOKS_CATALOG+=("02-install-nginx-domain.yml:Nginx Configuration for WordPress Domain:domain-wordpress")
PLAYBOOKS_CATALOG+=("04-install-wordpress.yml:WordPress Core Installation:domain-wordpress")
PLAYBOOKS_CATALOG+=("08-configure-smtp.yml:WordPress SMTP Configuration:domain-wordpress")
PLAYBOOKS_CATALOG+=("11-advanced-security.yml:WordPress Advanced Security (Wordfence):domain-wordpress")
PLAYBOOKS_CATALOG+=("13-setup-cdn.yml:WordPress CDN Setup:domain-wordpress")
PLAYBOOKS_CATALOG+=("17-advanced-caching.yml:WordPress Advanced Caching:domain-wordpress")
PLAYBOOKS_CATALOG+=("22-anti-hack.yml:WordPress Anti-Hack Measures:domain-wordpress")
PLAYBOOKS_CATALOG+=("25-secure-database-domain.yml:WordPress MySQL Server Security Hardening Measures:domain-wordpress")
PLAYBOOKS_CATALOG+=("26-setup-wp-cron.yml:WordPress System Cron Setup:domain-wordpress")


PLAYBOOKS_CATALOG+=("laravel/01-install-laravel.yml:Laravel Project Creation:domain-laravel")
PLAYBOOKS_CATALOG+=("laravel/02-configure-laravel.yml:Laravel Base Configuration & Nginx Setup:domain-laravel")
PLAYBOOKS_CATALOG+=("laravel/03-laravel-scheduler.yml:Laravel Scheduler Setup:domain-laravel")
PLAYBOOKS_CATALOG+=("laravel/04-laravel-queue.yml:Laravel Queue Worker Setup:domain-laravel")
PLAYBOOKS_CATALOG+=("laravel/05-laravel-horizon.yml:Laravel Horizon Setup:domain-laravel")
PLAYBOOKS_CATALOG+=("laravel/06-laravel-octane.yml:Laravel Octane Setup:domain-laravel")
PLAYBOOKS_CATALOG+=("laravel/07-laravel-websockets.yml:Laravel WebSockets Setup:domain-laravel")
PLAYBOOKS_CATALOG+=("laravel/08-laravel-telescope.yml:Laravel Telescope Setup:domain-laravel")
PLAYBOOKS_CATALOG+=("laravel/09-laravel-api.yml:Laravel API (Sanctum, Scribe) Setup:domain-laravel")

# Print colorful messages and append to main log
print_message() {
    local color=$1
    local message=$2
    case $color in
        "green") echo -e "${GREEN}${message}${NC}" ;;
        "yellow") echo -e "${YELLOW}${message}${NC}" ;;
        "red") echo -e "${RED}${message}${NC}" ;;
        "blue") echo -e "${BLUE}${message}${NC}" ;;
        *) echo -e "${message}" ;;
    esac | tee -a "$MAIN_LOG_FILE"
}

# Check and install dependencies: python3, PyYAML, ansible-playbook, inventory file
check_dependencies() {
    print_message "blue" "Checking dependencies..."
    if ! command -v python3 &> /dev/null; then
        print_message "red" "Python 3 is required but not installed. Please install it."
        exit 1
    fi
    if ! python3 -c "import yaml" &> /dev/null; then
        print_message "yellow" "PyYAML not installed. Attempting installation..."
        if command -v apt-get &> /dev/null; then
            apt-get update -qq && apt-get install -y python3-yaml -qq || {
                print_message "yellow" "Failed apt install. Trying pip3..."
                pip3 install PyYAML --quiet || {
                    print_message "red" "PyYAML install failed. Please install manually."
                    exit 1
                }
            }
        elif command -v yum &> /dev/null; then
            yum install -y python3-pyyaml || {
                print_message "yellow" "Failed yum install. Trying pip3..."
                pip3 install PyYAML --quiet || {
                    print_message "red" "PyYAML install failed. Please install manually."
                    exit 1
                }
            }
        else
            print_message "yellow" "Unknown package manager. Trying pip3..."
            pip3 install PyYAML --quiet || {
                print_message "red" "PyYAML install failed. Please install manually."
                exit 1
            }
        fi
        print_message "green" "PyYAML installed."
    fi
    if ! command -v ansible-playbook &> /dev/null; then
        print_message "red" "Ansible is not installed. Please install it."
        exit 1
    fi
    if [ ! -f "$INVENTORY_FILE" ]; then
        print_message "yellow" "Inventory file '$INVENTORY_FILE' missing. Creating default for localhost."
        echo "localhost ansible_connection=local" > "$INVENTORY_FILE"
        print_message "green" "Default inventory created. Please review."
    fi
    print_message "green" "Dependencies are all present."
}

# Parse YAML config and output JSON; used by other utilities
parse_config() {
    python3 -c "
import yaml, sys, json
try:
    with open('$CONFIG_FILE', 'r') as file:
        config = yaml.safe_load(file)
        print(json.dumps(config if config else {}))
except FileNotFoundError:
    print('{}', file=sys.stderr)
    sys.exit(0)
except Exception as e:
    print(f'Error parsing YAML: {str(e)}', file=sys.stderr)
    sys.exit(1)
"
}

# Get domain-platform mapping from config
get_domain_platforms() {
    python3 -c "
import yaml, sys, json
try:
    with open('$CONFIG_FILE', 'r') as file:
        config = yaml.safe_load(file)
        result = {}
        if config and 'domains' in config:
            for domain, settings in config['domains'].items():
                if isinstance(settings, dict) and 'platform' in settings:
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

# Check if a feature is enabled in domain or globally
is_feature_enabled() {
    local domain_or_global_scope="$1"
    local feature_key="$2"
    local default_value="${3:-false}"

    python3 -c "
import yaml
import sys

config_file = '$CONFIG_FILE'
domain_or_global_scope = '$domain_or_global_scope'
feature_key = '$feature_key'
default_value = '$default_value'.lower() == 'true'

try:
    with open(config_file, 'r') as file:
        config = yaml.safe_load(file)
        if not config:
            print(str(default_value).lower())
            sys.exit(0)

        value_found = None

        if domain_or_global_scope and 'domains' in config and domain_or_global_scope in config['domains'] and isinstance(config['domains'][domain_or_global_scope], dict):
            if feature_key in config['domains'][domain_or_global_scope]:
                value_found = config['domains'][domain_or_global_scope][feature_key]

        if value_found is None:
            global_key_name = 'GLOBAL_' + feature_key.upper()
            if global_key_name in config:
                value_found = config[global_key_name]

        print(str(value_found).lower() if value_found is not None else str(default_value).lower())

except Exception:
    print(str(default_value).lower())
"
}

# Get configuration dict for a specific domain with global fallbacks
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
            domain_config = config['domains'][domain_name].copy()
            domain_config['domain'] = domain_name

            if 'GLOBAL_LINUX_USERNAME' in config: domain_config.setdefault('linux_username', config['GLOBAL_LINUX_USERNAME'])
            if 'GLOBAL_PHP_DEFAULT_VERSION' in config: domain_config.setdefault('php_version', config['GLOBAL_PHP_DEFAULT_VERSION'])
            if 'GLOBAL_MYSQL_ROOT_PASSWORD' in config: domain_config.setdefault('mysql_root_password', config['GLOBAL_MYSQL_ROOT_PASSWORD'])

            print(json.dumps(domain_config))
        else:
            print(json.dumps({'domain': domain_name, 'platform': 'unknown', 'error': 'domain_not_found_in_config'}))
except Exception as e:
    print(json.dumps({'domain': domain_name, 'platform': 'unknown', 'error': str(e)}))
"
}

# Save playbook run state for resume capability
save_run_state() {
    local playbook_path="$1"
    local description="$2"
    local domain_context="$3"
    {
        echo "SAVED_PLAYBOOK_PATH=\"${playbook_path}\""
        echo "SAVED_DESCRIPTION=\"${description}\""
        echo "SAVED_DOMAIN_CONTEXT=\"${domain_context}\""
    } > "$STATE_FILE"
}

# Clear saved run state file
clear_run_state() {
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
    fi
}

# Run given ansible playbook with optional user confirmation
run_playbook() {
    local playbook_path="$1"
    local description="$2"
    local ask_confirmation="${3:-true}"
    local domain_context="$4"
    local is_resume_attempt="${5:-false}"

    local playbook_log_file="${PLAYBOOK_LOG_FILE_PREFIX}_$(basename "${playbook_path%.*}")_${CURRENT_TIMESTAMP}.log"

    print_message "blue" "Preparing to run: $description (Domain: ${domain_context:-Global})" | tee -a "$playbook_log_file"

    local extra_vars_json="{}"
    local domain_config_json
    if [ -n "$domain_context" ]; then
        domain_config_json=$(get_domain_config "$domain_context")
        if [[ -z "$domain_config_json" || "$domain_config_json" == "{}" || "$domain_config_json" == *"error"* ]]; then
            print_message "red" "Error fetching domain config for $domain_context: $domain_config_json. Skipping $description."
            echo "Error fetching domain config for $domain_context: $domain_config_json" >> "$playbook_log_file"
            return 1
        fi
    fi

    local full_config_json
    local extra_vars_payload
    full_config_json=$(parse_config)

    if [[ -n "$full_config_json" && "$full_config_json" != "{}" ]]; then
        if [ -n "$domain_context" ] && [[ -n "$domain_config_json" && "$domain_config_json" != "{}" ]]; then
            extra_vars_payload="{\"ansible_global_vars\": $full_config_json, \"domain_config\": $domain_config_json }"
        else
            extra_vars_payload="{\"ansible_global_vars\": $full_config_json}"
        fi
    elif [ -n "$domain_context" ] && [[ -n "$domain_config_json" && "$domain_config_json" != "{}" ]]; then
        extra_vars_payload="{\"domain_config\": $domain_config_json}"
    else
        extra_vars_payload="{}"
    fi

    if [ "$ask_confirmation" == "true" ] && [ "$is_resume_attempt" == "false" ]; then
        read -p "$(echo -e "${YELLOW}Do you want to run '$description'? (Y/n): ${NC}")" -n 1 -r REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ && -n "$REPLY" ]]; then
            print_message "yellow" "Skipping $description"
            echo "User skipped $description" >> "$playbook_log_file"
            return 0
        fi
    fi

    save_run_state "$playbook_path" "$description" "$domain_context"

    print_message "blue" "Running playbook: $playbook_path for '$description'..."
    echo "Running playbook: $playbook_path with extra_vars: $extra_vars_payload" >> "$playbook_log_file"

    local cmd_args=()
    cmd_args+=("-i" "$INVENTORY_FILE")
    cmd_args+=("$playbook_path")
    if [[ -n "$extra_vars_payload" && "$extra_vars_payload" != "{}" ]]; then
        cmd_args+=("--extra-vars" "$extra_vars_payload")
    fi
    cmd_args+=("-v")

    if ansible-playbook "${cmd_args[@]}" 2>&1 | tee -a "$MAIN_LOG_FILE" | tee -a "$playbook_log_file"; then
        print_message "green" "$description completed successfully!"
        clear_run_state
        return 0
    else
        local exit_code=${PIPESTATUS[0]}
        print_message "red" "$description FAILED with exit code $exit_code!"
        print_message "yellow" "Check logs: $MAIN_LOG_FILE and $playbook_log_file"

        if [ "$is_resume_attempt" == "false" ]; then
            read -p "$(echo -e "${RED}The playbook '$description' failed. Continue with rest of deployment? (y/N): ${NC}")" -n 1 -r REPLY_CONTINUE_DEPLOYMENT
            echo
            if [[ ! $REPLY_CONTINUE_DEPLOYMENT =~ ^[Yy]$ ]]; then
                print_message "red" "Deployment aborted by user due to failure. State saved."
                exit "$exit_code"
            fi
        else
            print_message "red" "Resumed playbook '$description' FAILED again. State preserved."
        fi
        return "$exit_code"
    fi
}

# Prompt user to resume if previous run was incomplete
prompt_resume_if_needed() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        if [ -z "${SAVED_PLAYBOOK_PATH:-}" ] || [ -z "${SAVED_DESCRIPTION:-}" ]; then
            print_message "red" "State file corrupted or incomplete. Clearing."
            clear_run_state
            return
        fi

        print_message "yellow" "------------------------------------------------------------"
        print_message "yellow" " ATTENTION: Previous Run Incomplete!"
        print_message "yellow" "------------------------------------------------------------"
        print_message "yellow" "Playbook '${SAVED_DESCRIPTION}' (Path: ${SAVED_PLAYBOOK_PATH})"
        if [ -n "${SAVED_DOMAIN_CONTEXT}" ]; then
            print_message "yellow" "for domain '${SAVED_DOMAIN_CONTEXT}' failed or was interrupted."
        else
            print_message "yellow" "which is a global playbook failed or was interrupted."
        fi
        print_message "yellow" "------------------------------------------------------------"

        read -p "$(echo -e "${YELLOW}Options: (R)etry / (S)kip / (C)lear state & start fresh: ${NC}")" -n 1 -r REPLY_RESUME
        echo
        case "$REPLY_RESUME" in
            [Rr])
                print_message "blue" "Retrying playbook: ${SAVED_DESCRIPTION}..."
                run_playbook "$SAVED_PLAYBOOK_PATH" "$SAVED_DESCRIPTION" "false" "$SAVED_DOMAIN_CONTEXT" "true"
                local resume_exit_code=$?
                if [ $resume_exit_code -eq 0 ]; then
                    print_message "green" "Resumed playbook completed."
                else
                    print_message "red" "Resumed playbook failed again. State preserved."
                fi
                ;;
            [Ss])
                print_message "blue" "Skipping resume. Proceeding."
                ;;
            [Cc])
                print_message "yellow" "Clearing state and starting fresh."
                clear_run_state
                ;;
            *)
                print_message "yellow" "Invalid choice. Proceeding without resume."
                ;;
        esac
    fi
}

# List all playbooks and let user select one to run
list_and_run_single_playbook() {
    print_message "blue" "--- Run a Single Specific Playbook ---"
    if [ ${#PLAYBOOKS_CATALOG[@]} -eq 0 ]; then
        print_message "red" "Playbook catalog empty. Cannot select playbook."
        return 1
    fi

    print_message "blue" "Available playbooks:"
    local i=1
    for entry in "${PLAYBOOKS_CATALOG[@]}"; do
        local p_path=$(echo "$entry" | cut -d':' -f1)
        local p_desc=$(echo "$entry" | cut -d':' -f2)
        local p_type=$(echo "$entry" | cut -d':' -f3)
        print_message "yellow" "$i) $p_desc ($p_path) - Type: $p_type"
        i=$((i+1))
    done

    read -p "Enter the number of the playbook to run: " playbook_choice
    if ! [[ "$playbook_choice" =~ ^[0-9]+$ ]] || [ "$playbook_choice" -lt 1 ] || [ "$playbook_choice" -gt "${#PLAYBOOKS_CATALOG[@]}" ]; then
        print_message "red" "Invalid playbook choice."
        return 1
    fi

    local selected_entry="${PLAYBOOKS_CATALOG[$((playbook_choice-1))]}"
    local playbook_path_selected=$(echo "$selected_entry" | cut -d':' -f1)
    local description_selected=$(echo "$selected_entry" | cut -d':' -f2)
    local type_selected=$(echo "$selected_entry" | cut -d':' -f3)
    local domain_context_selected=""

    if [ ! -f "$playbook_path_selected" ]; then
        print_message "red" "Playbook file '$playbook_path_selected' not found!"
        return 1
    fi

    if [[ "$type_selected" == "domain" || "$type_selected" == "domain-wordpress" || "$type_selected" == "domain-laravel" ]]; then
        local platforms_json_data_single
        platforms_json_data_single=$(get_domain_platforms)
        if [[ -z "$platforms_json_data_single" || "$platforms_json_data_single" == "{}" ]]; then
            print_message "red" "No domains found in config for domain-specific playbook."
            return 1
        fi

        print_message "blue" "Select a domain for '$description_selected':"
        mapfile -t domain_names_single < <(echo "$platforms_json_data_single" | python3 -c "import json, sys; data=json.load(sys.stdin); [print(k) for k in data.keys()]")

        if [ ${#domain_names_single[@]} -eq 0 ]; then
            print_message "red" "No domains available for selection."
            return 1
        fi

        declare -a selectable_domains_display
        declare -a selectable_domains_internal

        local k_display=1
        for domain_name_item in "${domain_names_single[@]}"; do
            local platform_item=$(echo "$platforms_json_data_single" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('$domain_name_item', 'unknown'))")

            local should_display=true
            if [[ "$type_selected" == "domain-wordpress" && "$platform_item" != "wordpress" ]]; then
                should_display=false
            elif [[ "$type_selected" == "domain-laravel" && "$platform_item" != "laravel" ]]; then
                should_display=false
            fi

            if [ "$should_display" == "true" ]; then
                selectable_domains_display+=("$k_display) $domain_name_item ($platform_item)")
                selectable_domains_internal+=("$domain_name_item")
                k_display=$((k_display+1))
            fi
        done

        if [ ${#selectable_domains_internal[@]} -eq 0 ]; then
            print_message "red" "No suitable domains for playbook type '$type_selected'."
            return 1
        fi

        for display_item in "${selectable_domains_display[@]}"; do
            echo "$display_item"
        done

        read -p "Enter the number of the domain: " domain_num_choice
        if ! [[ "$domain_num_choice" =~ ^[0-9]+$ ]] || [ "$domain_num_choice" -lt 1 ] || [ "$domain_num_choice" -gt "${#selectable_domains_internal[@]}" ]; then
            print_message "red" "Invalid domain choice."
            return 1
        fi
        domain_context_selected="${selectable_domains_internal[$((domain_num_choice-1))]}"
    fi

    if [ "$type_selected" == "local" ]; then
        print_message "blue" "Running $description_selected on localhost..."
        local full_config_json_local
        full_config_json_local=$(parse_config)
        local extra_vars_local_payload="{\"ansible_global_vars\": $full_config_json_local}"
        local playbook_log_local="${PLAYBOOK_LOG_FILE_PREFIX}_$(basename "${playbook_path_selected%.*}")_local_${CURRENT_TIMESTAMP}.log"

        local cmd_args_local=("-i" "$INVENTORY_FILE" "$playbook_path_selected" "--connection=local")
        if [[ -n "$extra_vars_local_payload" && "$extra_vars_local_payload" != "{}" ]]; then
            cmd_args_local+=("--extra-vars" "$extra_vars_local_payload")
        fi
        cmd_args_local+=("-v")

        if ansible-playbook "${cmd_args_local[@]}" 2>&1 | tee -a "$MAIN_LOG_FILE" | tee -a "$playbook_log_local"; then
            print_message "green" "$description_selected completed successfully!"
        else
            local exit_code_local=${PIPESTATUS[0]}
            print_message "red" "$description_selected failed with exit code $exit_code_local!"
        fi
        return $?
    fi

    run_playbook "$playbook_path_selected" "$description_selected" "false" "$domain_context_selected" "false"
    return $?
}

# Run global playbooks with optional feature checks
run_global_playbooks() {
    print_message "blue" "--- Running Global System Playbooks ---"
    local overall_success=true

    _run_global_playbook() {
        run_playbook "$1" "$2" "false" "" "false" || {
            overall_success=false
            print_message "red" "Global playbook '$2' failed. Check logs."
        }
    }
    _run_global_playbook_conditional() {
        if [[ "$(is_feature_enabled "" "$3" "${4:-false}")" == "true" ]]; then
            _run_global_playbook "$1" "$2"
        else
            print_message "yellow" "Skipping '$2' because feature '$3' not enabled globally."
        fi
    }

    _run_global_playbook "00-update-upgrade.yml" "Base System Update and Upgrade"
    _run_global_playbook "01-install-mysql-global.yml" "MySQL Global Installation"
    _run_global_playbook "02-install-nginx-global.yml" "Nginx Global Installation"
    _run_global_playbook "03-install-php-composer-wpcli.yml" "PHP, Composer & WP-CLI Global Installation"

    _run_global_playbook_conditional "06-install-redis.yml" "Redis Global Installation" "install_redis" "false"

    if [[ "$(is_feature_enabled "" "enable_smtp" "false")" == "true" ]]; then
        print_message "yellow" "Global SMTP enabled. Usually configured per-domain."
    fi

    if [[ "$(is_feature_enabled "" "enable_backups" "false")" == "true" ]]; then
        print_message "yellow" "Global Backups enabled. Per-domain backups may require separate playbook."
    fi

    _run_global_playbook_conditional "23-install-fail2ban-global.yml" "Fail2Ban Global Installation & SSHD Jail" "fail2ban_enabled" "false"

    if [[ "$(is_feature_enabled "" "secure_file_permissions" "false")" == "true" ]]; then
        print_message "yellow" "Global Secure File Permissions enabled; domain-specific safer."
    fi

    _run_global_playbook_conditional "25-secure-database-global.yml" "MySQL Server Security Hardening (General)" "secure_database" "false"
    _run_global_playbook_conditional "14-setup-docker.yml" "Docker Support Global Installation" "enable_docker" "false"
    _run_global_playbook_conditional "19-manage-php.yml" "Additional PHP Versions Management" "enable_php_versions" "false"

    # Removed multilingual docs playbook execution per user comments

    if [ "$overall_success" = true ]; then
        print_message "green" "--- Global System Playbooks COMPLETED SUCCESSFULLY ---"
        return 0
    else
        print_message "red" "--- Global System Playbooks COMPLETED WITH ERRORS ---"
        return 1
    fi
}

# Run domain-specific playbooks for given domain and platform
run_domain_specific_playbooks() {
    local domain_name="$1"
    local platform="$2"
    print_message "blue" "--- Running Playbooks for Domain: $domain_name (Platform: $platform) ---"
    local overall_success=true

    _run_domain_playbook() {
        run_playbook "$1" "$2" "false" "$3" "false" || { overall_success=false; print_message "red" "Playbook '$2' for domain '$3' failed."; }
    }
    _run_domain_playbook_conditional() {
        if [[ "$(is_feature_enabled "$3" "$4" "${5:-false}")" == "true" ]]; then
            _run_domain_playbook "$1" "$2" "$3"
        else
            print_message "yellow" "Skipping '$2' for domain '$3' as feature '$4' not enabled."
        fi
    }

    _run_domain_playbook "01-install-mysql-domain.yml" "MySQL Configuration for $domain_name" "$domain_name"
    _run_domain_playbook_conditional "16-setup-rollback.yml" "Pre-action Backup for $domain_name" "$domain_name" "enable_rollback" "false"

    if [ "$platform" == "wordpress" ]; then
        _run_domain_playbook "02-install-nginx-domain.yml" "Nginx Configuration for WordPress $domain_name" "$domain_name"
        _run_domain_playbook "04-install-wordpress.yml" "WordPress Core Installation for $domain_name" "$domain_name"
        _run_domain_playbook "25-secure-database-domain.yml" "WordPress Secure DataBase for $domain_name" "$domain_name"
        _run_domain_playbook "26-setup-wp-cron.yml" "WordPress System Cron Setup for $domain_name" "$domain_name"

    elif [ "$platform" == "laravel" ]; then
        _run_domain_playbook "laravel/01-install-laravel.yml" "Laravel Project Creation for $domain_name" "$domain_name"
        _run_domain_playbook "laravel/02-configure-laravel.yml" "Laravel Base Configuration & Nginx Setup for $domain_name" "$domain_name"
    else
        print_message "red" "Unknown platform '$platform' for $domain_name. Skipping platform-specific setup."
    fi

    _run_domain_playbook_conditional "23-install-fail2ban-domain.yml" "Fail2Ban Domain Configuration for $domain_name" "$domain_name" "fail2ban_enabled" "false"

    local ssl_email_value
    ssl_email_value=$(python3 -c "import yaml; config=yaml.safe_load(open('$CONFIG_FILE')); print(config.get('domains',{}).get('$domain_name',{}).get('ssl_email',''))")
    if [[ -n "$ssl_email_value" ]]; then
        _run_domain_playbook "05-obtain-ssl.yml" "SSL Certificate Setup for $domain_name" "$domain_name"
    else
        print_message "yellow" "Skipping SSL setup for $domain_name; 'ssl_email' not defined."
    fi

    if [[ "$platform" == "wordpress" ]] && [[ "$(is_feature_enabled "$domain_name" "fail2ban_enabled" "false")" == "true" ]]; then
        _run_domain_playbook "23-install-fail2ban-domain.yml" "Fail2Ban WordPress Jail for $domain_name" "$domain_name"
    fi

    _run_domain_playbook_conditional "24-secure-file-permissions.yml" "Secure File Permissions for $domain_name" "$domain_name" "secure_file_permissions" "false"
    _run_domain_playbook_conditional "25-secure-database.yml" "Secure Database User Privileges for $domain_name" "$domain_name" "secure_database" "false"

    if [ "$platform" == "wordpress" ]; then
        _run_domain_playbook_conditional "08-configure-smtp.yml" "WordPress SMTP Configuration for $domain_name" "$domain_name" "enable_smtp" "false"
        if [[ "$(is_feature_enabled "$domain_name" "enable_advanced_security" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_advanced_security_domain" "false")" == "true" ]]; then
            _run_domain_playbook "11-advanced-security.yml" "WordPress Advanced Security (Wordfence) for $domain_name" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_cdn" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_local_cdn" "false")" == "true" ]]; then
            _run_domain_playbook "13-setup-cdn.yml" "WordPress CDN Setup for $domain_name" "$domain_name"
        fi
        _run_domain_playbook_conditional "17-advanced-caching.yml" "WordPress Advanced Caching for $domain_name" "$domain_name" "enable_advanced_caching" "false"
        _run_domain_playbook_conditional "22-anti-hack.yml" "WordPress Anti-Hack Measures for $domain_name" "$domain_name" "enable_anti_hack" "false"
    fi

    if [ "$platform" == "laravel" ]; then
        _run_domain_playbook_conditional "laravel/03-laravel-scheduler.yml" "Laravel Scheduler for $domain_name" "$domain_name" "enable_scheduler" "false"
        _run_domain_playbook_conditional "laravel/04-laravel-queue.yml" "Laravel Queue Workers for $domain_name" "$domain_name" "enable_queue" "false"
        _run_domain_playbook_conditional "laravel/05-laravel-horizon.yml" "Laravel Horizon for $domain_name" "$domain_name" "enable_horizon" "false"
        _run_domain_playbook_conditional "laravel/06-laravel-octane.yml" "Laravel Octane for $domain_name" "$domain_name" "enable_octane" "false"
        _run_domain_playbook_conditional "laravel/07-laravel-websockets.yml" "Laravel WebSockets for $domain_name" "$domain_name" "enable_websockets" "false"
        _run_domain_playbook_conditional "laravel/08-laravel-telescope.yml" "Laravel Telescope for $domain_name" "$domain_name" "enable_telescope" "false"
        _run_domain_playbook_conditional "laravel/09-laravel-api.yml" "Laravel API (Sanctum, Scribe) for $domain_name" "$domain_name" "enable_api" "false"
    fi

    if [[ "$(is_feature_enabled "" "enable_docker" "false")" == "true" && "$(is_feature_enabled "$domain_name" "enable_docker_domain" "false")" == "true" ]]; then
        print_message "yellow" "Domain-specific Docker setup for $domain_name may need separate logic."
    fi

    _run_domain_playbook_conditional "21-staging.yml" "Staging Environment Setup for $domain_name" "$domain_name" "enable_staging" "false"

    if [[ "$(is_feature_enabled "$domain_name" "enable_multi_domain" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_parked_domains" "false")" == "true" ]]; then
        _run_domain_playbook "20-multi-domain.yml" "Multi-domain/Parked Domain Notice for $domain_name" "$domain_name"
    fi

    if [ "$overall_success" = true ]; then
        print_message "green" "--- Playbooks for Domain $domain_name COMPLETED SUCCESSFULLY ---"
        return 0
    else
        print_message "red" "--- Playbooks for Domain $domain_name COMPLETED WITH ERRORS ---"
        return 1
    fi
}

# Main interactive script
main() {
    print_message "green" "=== Ansible Playbook Runner ==="
    echo "Full deployment log: $MAIN_LOG_FILE"
    echo "Detailed logs: $LOG_DIR/playbook_detail_*.log"
    echo

    check_dependencies

    if [ ! -f "$CONFIG_FILE" ]; then
        print_message "red" "Configuration file $CONFIG_FILE not found."
        print_message "yellow" "Run ./generate_config.sh or create the config manually."
        exit 1
    fi

    print_message "blue" "Validating configuration file..."
    local config_json
    config_json=$(parse_config)
    if [ $? -ne 0 ] || { [[ "$config_json" == "{}" ]] && [[ "$(wc -c < "$CONFIG_FILE")" -gt 5 ]]; }; then
        print_message "red" "Invalid or empty config file. Please check $CONFIG_FILE."
        exit 1
    fi
    print_message "green" "Configuration file validated."
    echo

    prompt_resume_if_needed

    print_message "blue" "Select deployment mode:"
    echo "1) Full deployment (global + all domains)"
    echo "2) Global playbooks only"
    echo "3) Domain-specific playbooks only (all domains)"
    echo "4) Specific domain only"
    echo "5) Run a single specific playbook"
    echo "Q) Quit"
    read -p "Enter choice [1-5, Q]: " deployment_mode

    local platforms_json_data

    case $deployment_mode in
        1)
            print_message "blue" "Running FULL deployment..."
            run_global_playbooks || { print_message "red" "Global playbooks failed. Aborting full deployment."; exit 1; }

            platforms_json_data=$(get_domain_platforms)
            if [[ -z "$platforms_json_data" || "$platforms_json_data" == "{}" ]]; then
                print_message "yellow" "No domains found in config to process domain playbooks."
            else
                mapfile -t domain_list < <(echo "$platforms_json_data" | python3 -c "import json, sys; data=json.load(sys.stdin); [print(k) for k in data.keys()]")
                for domain_item in "${domain_list[@]}"; do
                    local platform_item
                    platform_item=$(echo "$platforms_json_data" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('$domain_item', 'unknown'))")
                    run_domain_specific_playbooks "$domain_item" "$platform_item" || print_message "red" "Domain playbooks for $domain_item encountered errors."
                done
            fi
            ;;
        2)
            print_message "blue" "Running GLOBAL playbooks only..."
            run_global_playbooks
            ;;
        3)
            print_message "blue" "Running DOMAIN-SPECIFIC playbooks for ALL domains..."
            platforms_json_data=$(get_domain_platforms)
            if [[ -z "$platforms_json_data" || "$platforms_json_data" == "{}" ]]; then
                print_message "yellow" "No domains found in config."
            else
                mapfile -t domain_list < <(echo "$platforms_json_data" | python3 -c "import json, sys; data=json.load(sys.stdin); [print(k) for k in data.keys()]")
                for domain_item in "${domain_list[@]}"; do
                    local platform_item
                    platform_item=$(echo "$platforms_json_data" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('$domain_item', 'unknown'))")
                    run_domain_specific_playbooks "$domain_item" "$platform_item" || print_message "red" "Domain playbooks for $domain_item errors."
                done
            fi
            ;;
        4)
            print_message "blue" "Running playbooks for a SPECIFIC domain..."
            platforms_json_data=$(get_domain_platforms)
            if [[ -z "$platforms_json_data" || "$platforms_json_data" == "{}" ]]; then
                print_message "red" "No domains found in config."
                exit 1
            fi

            print_message "blue" "Available domains:"
            mapfile -t domain_names_spec < <(echo "$platforms_json_data" | python3 -c "import json, sys; data=json.load(sys.stdin); [print(k) for k in data.keys()]")

            local j=1
            for name_spec in "${domain_names_spec[@]}"; do
                local platform_spec
                platform_spec=$(echo "$platforms_json_data" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('$name_spec', 'unknown'))")
                echo "$j) $name_spec ($platform_spec)"
                j=$((j+1))
            done

            read -p "Enter domain number to deploy: " domain_choice
            if ! [[ "$domain_choice" =~ ^[0-9]+$ ]] || [ "$domain_choice" -lt 1 ] || [ "$domain_choice" -gt "${#domain_names_spec[@]}" ]; then
                print_message "red" "Invalid domain choice."
                exit 1
            fi
            local selected_domain_name="${domain_names_spec[$((domain_choice-1))]}"
            local selected_platform
            selected_platform=$(echo "$platforms_json_data" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('$selected_domain_name', 'unknown'))")
            run_domain_specific_playbooks "$selected_domain_name" "$selected_platform"
            ;;
        5)
            list_and_run_single_playbook
            ;;
        [Qq])
            print_message "blue" "Exiting script."
            exit 0
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
    print_message "yellow" "1. Review main log file and playbook-specific logs for warnings/errors."
    print_message "yellow" "2. Test nginx configuration: sudo nginx -t"
    print_message "yellow" "3. Verify critical services: systemctl status nginx mysql php<version>-fpm redis-server"
    print_message "yellow" "4. Thoroughly test your websites and applications."
}

main
