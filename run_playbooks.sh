#!/bin/bash

# Check if running with sudo/root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

CONFIG_FILE="group_vars/all.yml"
LOG_DIR="logs"
CURRENT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAIN_LOG_FILE="$LOG_DIR/deployment_$CURRENT_TIMESTAMP.log"

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to display colorful messages
print_message() {
    local color=$1
    local message=$2
    
    case $color in
        "green") echo -e "\e[32m$message\e[0m" ;;
        "red") echo -e "\e[31m$message\e[0m" ;;
        "yellow") echo -e "\e[33m$message\e[0m" ;;
        "blue") echo -e "\e[34m$message\e[0m" ;;
        *) echo "$message" ;;
    esac
}

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    print_message "red" "Error: Configuration file $CONFIG_FILE not found!"
    print_message "yellow" "Please run ./generate_config.sh first to create the configuration."
    exit 1
fi

# Detect platform from config file
PLATFORM=$(grep -m 1 "platform:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')

if [ -z "$PLATFORM" ]; then
    print_message "red" "Error: Could not detect platform in $CONFIG_FILE"
    exit 1
fi

print_message "blue" "Detected platform: ${PLATFORM^}"
print_message "blue" "Deployment logs will be saved to: $MAIN_LOG_FILE"

# Function to run a playbook with logging
run_playbook() {
    local playbook=$1
    local description=$2
    local is_mandatory=$3
    local condition=$4
    
    # If condition is provided and evaluates to false, skip this playbook
    if [ -n "$condition" ] && ! eval "$condition"; then
        print_message "yellow" "Skipping $playbook: condition not met"
        return 0
    fi
    
    # For optional playbooks, ask for confirmation
    if [ "$is_mandatory" != "true" ]; then
        read -p "Do you want to run $description? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "yellow" "Skipping $playbook"
            return 0
        fi
    fi
    
    print_message "blue" "Running $description..."
    
    # Run the playbook with ansible-playbook
    ansible-playbook "$playbook" -v | tee -a "$MAIN_LOG_FILE"
    
    local exit_code=${PIPESTATUS[0]}
    if [ $exit_code -eq 0 ]; then
        print_message "green" "$description completed successfully!"
    else
        print_message "red" "$description failed with exit code $exit_code!"
        print_message "yellow" "Check $MAIN_LOG_FILE for details."
        
        read -p "Continue with deployment? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "red" "Deployment aborted by user."
            exit 1
        fi
    fi
}

# Common mandatory playbooks for both platforms
print_message "blue" "Starting server preparation and common setup..."
run_playbook "00-update-upgrade.yml" "System Update and Upgrade" "true"
run_playbook "01-install-mysql.yml" "MySQL Installation" "true"
run_playbook "02-install-nginx.yml" "Nginx Installation" "true"
run_playbook "03-install-php-composer-wpcli.yml" "PHP Installation" "true"

# Platform-specific mandatory playbooks
if [ "$PLATFORM" == "wordpress" ]; then
    print_message "blue" "Starting WordPress installation..."
    run_playbook "04-install-wordpress.yml" "WordPress Installation" "true"
    run_playbook "05-obtain-ssl.yml" "SSL Certificate Setup" "true"
    run_playbook "06-install-redis.yml" "Redis Installation" "false" "grep -q 'install_redis: true' $CONFIG_FILE"
elif [ "$PLATFORM" == "laravel" ]; then
    print_message "blue" "Starting Laravel installation..."
    run_playbook "laravel/01-install-laravel.yml" "Laravel Installation" "true"
    run_playbook "05-obtain-ssl.yml" "SSL Certificate Setup" "true"
    run_playbook "06-install-redis.yml" "Redis Installation" "false" "grep -q 'install_redis: true' $CONFIG_FILE"
    run_playbook "laravel/02-configure-laravel.yml" "Laravel Configuration" "true"
fi

# Optional playbooks - common for both platforms
print_message "blue" "Optional features setup..."

# Security
run_playbook "11-advanced-security.yml" "Advanced Security" "false" 
run_playbook "23-install-fail2ban.yml" "Fail2ban Installation" "false"
run_playbook "24-secure-file-permissions.yml" "Secure File Permissions" "false"
run_playbook "25-secure-database.yml" "Secure Database" "false"
run_playbook "26-security-audit.yml" "Security Audit" "false"

# Backups
run_playbook "07-setup-backups.yml" "Backup Configuration" "false" "grep -q 'enable_backups: true' $CONFIG_FILE"

# Email
run_playbook "08-configure-smtp.yml" "SMTP Configuration" "false" "grep -q 'enable_smtp: true' $CONFIG_FILE"

# Monitoring
run_playbook "09-setup-monitoring.yml" "Monitoring Setup" "false" "grep -q 'enable_monitoring: true' $CONFIG_FILE"

# Performance
run_playbook "17-advanced-caching.yml" "Advanced Caching" "false" "grep -q 'enable_advanced_caching: true' $CONFIG_FILE"

# CDN
run_playbook "13-setup-cdn.yml" "CDN Setup" "false" "grep -q 'enable_cdn: true\\|enable_local_cdn: true' $CONFIG_FILE"

# Docker
run_playbook "14-setup-docker.yml" "Docker Setup" "false" "grep -q 'enable_docker: true' $CONFIG_FILE"

# Staging
run_playbook "21-staging.yml" "Staging Environment" "false" "grep -q 'enable_staging: true' $CONFIG_FILE"

# Platform-specific optional playbooks
if [ "$PLATFORM" == "wordpress" ]; then
    run_playbook "10-optimize-images.yml" "Image Optimization" "false" "grep -q 'enable_image_optimization: true' $CONFIG_FILE"
    run_playbook "12-migrate-wordpress.yml" "WordPress Migration" "false" "grep -q 'enable_migration: true' $CONFIG_FILE"
    run_playbook "20-multi-domain.yml" "Multi-domain Setup" "false" "grep -q 'enable_multi_domain: true\\|enable_parked_domains: true' $CONFIG_FILE"
    run_playbook "22-anti-hack.yml" "Anti-hack Measures" "false" "grep -q 'enable_anti_hack: true' $CONFIG_FILE"
elif [ "$PLATFORM" == "laravel" ]; then
    run_playbook "laravel/03-laravel-scheduler.yml" "Laravel Scheduler" "false" "grep -q 'enable_scheduler: true' $CONFIG_FILE"
    run_playbook "laravel/04-laravel-queue.yml" "Laravel Queue" "false" "grep -q 'enable_queue: true' $CONFIG_FILE"
    run_playbook "laravel/05-laravel-horizon.yml" "Laravel Horizon" "false" "grep -q 'enable_horizon: true' $CONFIG_FILE"
    run_playbook "laravel/06-laravel-octane.yml" "Laravel Octane" "false" "grep -q 'enable_octane: true' $CONFIG_FILE"
    run_playbook "laravel/07-laravel-websockets.yml" "Laravel WebSockets" "false" "grep -q 'enable_websockets: true' $CONFIG_FILE"
    run_playbook "laravel/08-laravel-telescope.yml" "Laravel Telescope" "false" "grep -q 'enable_telescope: true' $CONFIG_FILE"
    run_playbook "laravel/09-laravel-api.yml" "Laravel API Setup" "false" "grep -q 'enable_api: true' $CONFIG_FILE"
fi

# Documentation
run_playbook "15-generate-docs.yml" "Documentation Generation" "false" "grep -q 'enable_multilingual_docs: true' $CONFIG_FILE"

# Rollback
run_playbook "16-setup-rollback.yml" "Rollback Configuration" "false" "grep -q 'enable_rollback: true' $CONFIG_FILE"

print_message "green" "Deployment completed successfully!"
print_message "blue" "Deployment logs are available at: $MAIN_LOG_FILE"

# Print summary of installed components
print_message "blue" "=== Deployment Summary ==="
echo "Platform: ${PLATFORM^}"
echo "Domains configured:"
grep -A 1 "^  [a-zA-Z0-9]" "$CONFIG_FILE" | grep -v "^--" | sed 's/://'

if [ "$PLATFORM" == "wordpress" ]; then
    echo -e "\nWordPress admin URLs:"
    for domain in $(grep -A 1 "^  [a-zA-Z0-9]" "$CONFIG_FILE" | grep -v "^--" | sed 's/://' | tr -d ' '); do
        echo "https://$domain/wp-admin/"
    done
elif [ "$PLATFORM" == "laravel" ]; then
    echo -e "\nLaravel application URLs:"
    for domain in $(grep -A 1 "^  [a-zA-Z0-9]" "$CONFIG_FILE" | grep -v "^--" | sed 's/://' | tr -d ' '); do
        echo "https://$domain/"
    done
fi

echo -e "\nThank you for using the deployment script!"

