#!/bin/bash
# run_playbooks.sh
# Responsável por executar os playbooks Ansible com base na configuração.

set -e

# Verifica se o script está sendo executado como root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

# Definições de variáveis
CONFIG_FILE="group_vars/all.yml"
LOG_DIR="logs"
CURRENT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAIN_LOG_FILE="$LOG_DIR/deployment_$CURRENT_TIMESTAMP.log"
INVENTORY_FILE="inventory" # Nome do arquivo de inventário

# Cria o diretório de logs se não existir
mkdir -p "$LOG_DIR"

# Cores para mensagens
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para imprimir mensagens coloridas
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

# Função para verificar dependências
check_dependencies() {
    if ! command -v python3 &> /dev/null; then
        print_message "red" "Python 3 is required but not installed. Please install it."
        exit 1
    fi

    if ! python3 -c "import yaml" &> /dev/null; then
        print_message "yellow" "PyYAML is not installed. Attempting to install..."
        if command -v apt-get &> /dev/null; then
            apt-get update -qq && apt-get install -y python3-yaml || {
                print_message "yellow" "Failed to install python3-yaml via apt. Trying pip3..."
                pip3 install PyYAML || {
                    print_message "red" "Failed to install PyYAML using both apt and pip3. Please install it manually."
                    exit 1
                }
            }
        elif command -v yum &> /dev/null; then
             yum install -y python3-pyyaml || {
                print_message "yellow" "Failed to install python3-pyyaml via yum. Trying pip3..."
                pip3 install PyYAML || {
                    print_message "red" "Failed to install PyYAML using both yum and pip3. Please install it manually."
                    exit 1
                }
            }
        else
            print_message "yellow" "Package manager not identified (apt/yum). Trying pip3 to install PyYAML..."
            pip3 install PyYAML || {
                print_message "red" "Failed to install PyYAML using pip3. Please install it manually."
                exit 1
            }
        fi
        print_message "green" "PyYAML installed successfully."
    fi

    if ! command -v ansible-playbook &> /dev/null; then
        print_message "red" "Ansible is not installed. Please install it."
        exit 1
    fi

    if [ ! -f "$INVENTORY_FILE" ]; then
        print_message "red" "Inventory file '$INVENTORY_FILE' not found."
        print_message "yellow" "Please create an inventory file (e.g., with 'localhost ansible_connection=local')."
        # exit 1 # Comentado para permitir a criação manual ou um inventário dinâmico no futuro
    fi
}

# Função para parsear o arquivo de configuração YAML e retornar JSON
parse_config() {
    python3 -c "
import yaml
import sys
import json

try:
    with open('$CONFIG_FILE', 'r') as file:
        config = yaml.safe_load(file)
        print(json.dumps(config if config else {})) # Retorna objeto vazio se o arquivo for vazio
except FileNotFoundError:
    print('{}', file=sys.stderr) # Retorna objeto vazio se o arquivo não existir
    sys.exit(0) # Não falha, permite que o script verifique a configuração mais tarde
except Exception as e:
    print(f'Error parsing YAML: {str(e)}', file=sys.stderr)
    sys.exit(1)
"
}

# Função para obter as plataformas dos domínios
get_domain_platforms() {
    python3 -c "
import yaml
import sys
import json

try:
    with open('$CONFIG_FILE', 'r') as file:
        config = yaml.safe_load(file)
        result = {}
        if config and 'domains' in config: # Verifica se config não é None
            for domain, settings in config['domains'].items():
                if isinstance(settings, dict) and 'platform' in settings: # Verifica se settings é um dict
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

# Função para verificar se uma feature está habilitada para um domínio ou globalmente
is_feature_enabled() {
    local domain_or_global_scope="$1" # Pode ser nome do domínio ou string vazia para global
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
        if not config: # Arquivo YAML vazio
            print(str(default_value).lower())
            sys.exit(0)

        value_found = None

        if domain_or_global_scope and 'domains' in config and domain_or_global_scope in config['domains'] and isinstance(config['domains'][domain_or_global_scope], dict):
            # Verifica a configuração específica do domínio
            if feature_key in config['domains'][domain_or_global_scope]:
                value_found = config['domains'][domain_or_global_scope][feature_key]
        
        if value_found is None:
            # Se não encontrado no domínio ou se o escopo é global, verifica as configurações globais
            # Transforma 'feature_key' em 'GLOBAL_FEATURE_KEY' (ex: 'enable_ssl' -> 'GLOBAL_ENABLE_SSL')
            global_feature_key_parts = feature_key.split('_')
            if len(global_feature_key_parts) > 0:
                 # ex: enable_ssl -> GLOBAL_ENABLE_SSL ; install_redis -> GLOBAL_INSTALL_REDIS
                if global_feature_key_parts[0] in ['enable', 'install', 'secure', 'use', 'manage']:
                    global_key_name = 'GLOBAL_' + feature_key.upper()
                else: # Caso mais genérico, como 'fail2ban_enabled' -> GLOBAL_FAIL2BAN_ENABLED
                    global_key_name = 'GLOBAL_' + feature_key.upper()
                
                # Casos especiais de nomenclatura global:
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
                elif feature_key == 'fail2ban_enabled': global_key_name = 'GLOBAL_FAIL2BAN_ENABLED' # Já é o padrão
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
                elif feature_key == 'enable_telescope': global_key_name = 'GLOBAL_LARAVEL_ENABLE_TELESCOPE' # Assumindo um global para Telescope
                elif feature_key == 'enable_api': global_key_name = 'GLOBAL_LARAVEL_ENABLE_API'


                if global_key_name in config:
                    value_found = config[global_key_name]

        if value_found is not None:
            print(str(value_found).lower())
        else:
            print(str(default_value).lower())

except FileNotFoundError:
    print(str(default_value).lower()) # Se o arquivo de config não existe, usa o default
except Exception as e:
    # Em caso de erro de parsing, retorna o default para não quebrar o script
    # print(f'Python error in is_feature_enabled: {str(e)}', file=sys.stderr) 
    print(str(default_value).lower())
"
}

# Função para obter a configuração de um domínio específico
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
            domain_config = config['domains'][domain_name].copy() # Faz uma cópia para não modificar o original
            domain_config['domain'] = domain_name # Adiciona o nome do domínio ao dict retornado
            
            # Adiciona configurações globais como fallback se não estiverem definidas no domínio
            # Isso é útil para templates que podem usar GLOBAL_X ou domain_config.X
            if 'GLOBAL_LINUX_USERNAME' in config: domain_config.setdefault('linux_username', config['GLOBAL_LINUX_USERNAME'])
            if 'GLOBAL_PHP_DEFAULT_VERSION' in config: domain_config.setdefault('php_version', config['GLOBAL_PHP_DEFAULT_VERSION'])
            if 'GLOBAL_MYSQL_ROOT_PASSWORD' in config: domain_config.setdefault('mysql_root_password', config['GLOBAL_MYSQL_ROOT_PASSWORD'])
            # ... adicione outros fallbacks globais conforme necessário ...

            print(json.dumps(domain_config))
        else:
            # Retorna um config de domínio básico se não encontrado, para evitar erros no ansible
            print(json.dumps({'domain': domain_name, 'platform': 'unknown'}))
except FileNotFoundError:
    print(json.dumps({'domain': domain_name, 'platform': 'unknown', 'error': 'config_file_not_found'}))
except Exception as e:
    # print(f'Python error in get_domain_config: {str(e)}', file=sys.stderr)
    print(json.dumps({'domain': domain_name, 'platform': 'unknown', 'error': str(e)}))
"
}

# Função para executar um playbook Ansible
run_playbook() {
    local playbook_path="$1"
    local description="$2"
    local ask_confirmation="${3:-true}" # Por padrão pergunta, a menos que 'false' seja passado
    local domain_context="$4" # Nome do domínio, ou vazio para playbooks globais
    # O quinto parâmetro 'condition_string' foi removido, a lógica de condição agora está no is_feature_enabled

    print_message "blue" "Attempting to run: $description"

    # Constrói extra_vars
    local extra_vars_json="{}"
    if [ -n "$domain_context" ]; then
        domain_config_json=$(get_domain_config "$domain_context")
        # Verifica se domain_config_json é um JSON válido e não vazio
        if [[ -n "$domain_config_json" && "$domain_config_json" != "{}" && "$domain_config_json" != *"error"* ]]; then
            extra_vars_json="{\"domain_config\": $domain_config_json}"
        elif [[ "$domain_config_json" == *"error"* ]]; then
             print_message "red" "Error fetching domain config for $domain_context: $domain_config_json. Skipping $description."
             return 1 # Falha se não conseguir config do domínio
        else
            print_message "yellow" "Domain config for $domain_context is empty or not found. Playbook $description might not run as expected."
            # Continuar com extra_vars vazio ou um domain_config mínimo pode ser uma opção dependendo do playbook
            # Para segurança, vamos pular se a configuração do domínio for essencial e não encontrada.
            # Se o playbook puder lidar com um domain_config vazio, remova o return 1.
            # extra_vars_json="{\"domain_config\": {\"domain\": \"$domain_context\"}}" # Exemplo de fallback mínimo
        fi
    fi
    
    # Adiciona configurações globais ao extra_vars para que estejam sempre disponíveis nos playbooks
    # Isso é útil se um playbook precisar de uma config global que não está no domain_config
    # global_config_json=$(parse_config) # Pega todo o config
    # extra_vars_json=$(echo "$extra_vars_json" "$global_config_json" | jq -s '.[0] * .[1]') # Merge JSONs (requer jq)
    # Alternativa sem jq: passar todo o config como uma variável global e domain_config separadamente
    full_config_json=$(parse_config)
    if [[ -n "$full_config_json" && "$full_config_json" != "{}" ]]; then
      extra_vars_payload="{\"ansible_global_vars\": $full_config_json, \"domain_config\": $(echo "$extra_vars_json" | cut -d ':' -f 2- | rev | cut -d '}' -f 2- | rev ) }"
    else
      extra_vars_payload="$extra_vars_json"
    fi


    if [ "$ask_confirmation" == "true" ]; then
        read -p "$(echo -e "${YELLOW}Do you want to run $description? (Y/n): ${NC}")" -n 1 -r REPLY
        echo
        if [[ ! $REPLY =~ ^[Yy]$ && -n "$REPLY" ]]; then
            print_message "yellow" "Skipping $description"
            return 0
        fi
    fi

    print_message "blue" "Running $description..."

    # Converte o JSON para string para extra-vars
    local extra_vars_string=""
    if [[ -n "$extra_vars_payload" && "$extra_vars_payload" != "{}" ]]; then
        extra_vars_string=" --extra-vars '$extra_vars_payload' "
    fi
    
    # Executa o playbook
    if ansible-playbook -i "$INVENTORY_FILE" "$playbook_path" $extra_vars_string -v | tee -a "$MAIN_LOG_FILE"; then
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
        return $exit_code # Retorna o código de erro para possível tratamento futuro
    fi
    return 0
}

# Função para executar playbooks globais (nível de servidor)
run_global_playbooks() {
    print_message "blue" "--- Running Global System Playbooks ---"

    run_playbook "00-update-upgrade.yml" "Base System Update and Upgrade" "false" ""
    run_playbook "01-install-mysql.yml" "MySQL Installation" "false" ""
    run_playbook "02-install-nginx.yml" "Nginx Installation" "false" ""
    run_playbook "03-install-php-composer-wpcli.yml" "PHP, Composer & WP-CLI Installation" "false" "" # Assume PHP padrão global aqui

    if [[ "$(is_feature_enabled "" "install_redis" "false")" == "true" ]]; then
        run_playbook "06-install-redis.yml" "Redis Installation" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_smtp" "false")" == "true" ]]; then
        # SMTP global pode ser configurado por um playbook dedicado ou integrado em outros (ex: Postfix)
        # 08-configure-smtp.yml é específico para WordPress, então não é chamado globalmente aqui.
        print_message "yellow" "Global SMTP configuration needs a dedicated playbook or manual setup if not using a per-domain WordPress SMTP plugin."
    fi
    if [[ "$(is_feature_enabled "" "enable_backups" "false")" == "true" ]]; then
        # 07-setup-backups.yml é por domínio. Um playbook de backup global precisaria de lógica diferente.
        print_message "yellow" "Global backup configuration needs a dedicated playbook. 07-setup-backups.yml is per-domain."
    fi
     if [[ "$(is_feature_enabled "" "fail2ban_enabled" "false")" == "true" ]]; then
        run_playbook "23-install-fail2ban.yml" "Fail2Ban Installation & SSHD Jail" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_monitoring" "false")" == "true" ]]; then
        run_playbook "09-setup-monitoring.yml" "Basic Monitoring Tools Installation" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "secure_file_permissions" "false")" == "true" ]]; then
        # 24-secure-file-permissions.yml é por domínio. Um playbook global precisaria de escopo diferente.
        print_message "yellow" "Global secure file permissions policy needs careful consideration and potentially a dedicated playbook. 24-secure-file-permissions.yml is per-domain."
    fi
    if [[ "$(is_feature_enabled "" "secure_database" "false")" == "true" ]]; then
        # 25-secure-database.yml é por domínio. Um playbook global para MySQL hardening (e.g. mysql_secure_installation) é diferente.
        run_playbook "25-secure-database.yml" "MySQL Server Security Hardening (General)" "false" "" # Adaptado para ser mais global
    fi
     if [[ "$(is_feature_enabled "" "security_audit" "false")" == "true" ]]; then
        run_playbook "26-security-audit.yml" "System Security Audit Tools (Lynis, Rkhunter)" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_docker" "false")" == "true" ]]; then
        # 14-setup-docker.yml instala Docker, que é global. Configurações de container são por domínio.
        run_playbook "14-setup-docker.yml" "Docker Support Installation" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_waf" "false")" == "true" ]]; then
        run_playbook "18-setup-waf.yml" "WAF (ModSecurity with Nginx) Base Installation" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_php_versions" "false")" == "true" ]]; then
        run_playbook "19-manage-php.yml" "Additional PHP Versions Management" "false" ""
    fi
    if [[ "$(is_feature_enabled "" "enable_multilingual_docs" "false")" == "true" ]]; then
        # 15-generate-docs.yml é localhost e para o projeto ansible em si
        print_message "yellow" "Running '15-generate-docs.yml' for project documentation (runs on localhost)."
        ansible-playbook -i "$INVENTORY_FILE" "15-generate-docs.yml" --connection=local | tee -a "$MAIN_LOG_FILE"
    fi

    print_message "blue" "--- Global System Playbooks COMPLETED ---"
}

# Função para executar playbooks específicos de um domínio
run_domain_specific_playbooks() {
    local domain_name="$1"
    local platform="$2"

    print_message "blue" "--- Running Playbooks for Domain: $domain_name (Platform: $platform) ---"

    # Rollback (Pre-action Backup)
    if [[ "$(is_feature_enabled "$domain_name" "enable_rollback" "false")" == "true" ]]; then
        run_playbook "16-setup-rollback.yml" "Pre-action Backup for $domain_name" "false" "$domain_name"
    fi

    # Platform specific installation & base configuration
    if [ "$platform" == "wordpress" ]; then
        run_playbook "04-install-wordpress.yml" "WordPress Core Installation for $domain_name" "false" "$domain_name"
    elif [ "$platform" == "laravel" ]; then
        run_playbook "laravel/01-install-laravel.yml" "Laravel Project Creation for $domain_name" "false" "$domain_name"
        run_playbook "laravel/02-configure-laravel.yml" "Laravel Base Configuration & Nginx Setup for $domain_name" "false" "$domain_name"
    else
        print_message "red" "Unknown platform '$platform' for domain $domain_name. Skipping platform-specific core setup."
        return
    fi

    # SSL Certificate
    if [[ "$(is_feature_enabled "$domain_name" "ssl_email" "skip")" != "skip" ]]; then # Assumindo que ssl_email não vazio ativa SSL
         run_playbook "05-obtain-ssl.yml" "SSL Certificate Setup for $domain_name" "false" "$domain_name"
    fi
    
    # Common per-domain features (Fail2ban WordPress jail, File Permissions)
    if [[ "$(is_feature_enabled "" "fail2ban_enabled" "false")" == "true" && "$platform" == "wordpress" ]]; then
         # A jail do WordPress é específica do domínio e só faz sentido se o Fail2Ban global estiver ativo.
         run_playbook "23-install-fail2ban.yml" "Fail2Ban WordPress Jail for $domain_name" "false" "$domain_name" # O playbook precisa de lógica interna para apenas adicionar a jail do WP
    fi
    if [[ "$(is_feature_enabled "$domain_name" "secure_file_permissions" "false")" == "true" ]]; then
        run_playbook "24-secure-file-permissions.yml" "Secure File Permissions for $domain_name" "false" "$domain_name"
    fi
     if [[ "$(is_feature_enabled "$domain_name" "secure_database" "false")" == "true" ]]; then
        run_playbook "25-secure-database.yml" "Secure Database User Privileges for $domain_name" "false" "$domain_name"
    fi


    # WordPress Specific Features
    if [ "$platform" == "wordpress" ]; then
        if [[ "$(is_feature_enabled "$domain_name" "enable_smtp" "false")" == "true" ]]; then
            run_playbook "08-configure-smtp.yml" "WordPress SMTP Configuration for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_image_optimization" "false")" == "true" ]]; then
            run_playbook "10-optimize-images.yml" "WordPress Image Optimization for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_advanced_security" "false")" == "true" ]]; then
            run_playbook "11-advanced-security.yml" "WordPress Advanced Security (Wordfence) for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_migration" "false")" == "true" ]]; then
            run_playbook "12-migrate-wordpress.yml" "WordPress Migration for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_cdn" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_local_cdn" "false")" == "true" ]]; then
            run_playbook "13-setup-cdn.yml" "WordPress CDN Setup for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_advanced_caching" "false")" == "true" ]]; then
            run_playbook "17-advanced-caching.yml" "WordPress Advanced Caching (Memcached) for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_anti_hack" "false")" == "true" ]]; then
            run_playbook "22-anti-hack.yml" "WordPress Anti-Hack Measures for $domain_name" "false" "$domain_name"
        fi
    fi

    # Laravel Specific Features
    if [ "$platform" == "laravel" ]; then
        if [[ "$(is_feature_enabled "$domain_name" "enable_scheduler" "false")" == "true" ]]; then
            run_playbook "laravel/03-laravel-scheduler.yml" "Laravel Scheduler for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_queue" "false")" == "true" ]]; then
            run_playbook "laravel/04-laravel-queue.yml" "Laravel Queue Workers for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_horizon" "false")" == "true" ]]; then
            run_playbook "laravel/05-laravel-horizon.yml" "Laravel Horizon for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_octane" "false")" == "true" ]]; then
            run_playbook "laravel/06-laravel-octane.yml" "Laravel Octane for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_websockets" "false")" == "true" ]]; then
            run_playbook "laravel/07-laravel-websockets.yml" "Laravel WebSockets for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_telescope" "false")" == "true" ]]; then
            run_playbook "laravel/08-laravel-telescope.yml" "Laravel Telescope for $domain_name" "false" "$domain_name"
        fi
        if [[ "$(is_feature_enabled "$domain_name" "enable_api" "false")" == "true" ]]; then
            run_playbook "laravel/09-laravel-api.yml" "Laravel API (Sanctum, Scribe) for $domain_name" "false" "$domain_name"
        fi
    fi
    
    # Docker per-domain (if Docker support is globally enabled)
    if [[ "$(is_feature_enabled "" "enable_docker" "false")" == "true" && "$(is_feature_enabled "$domain_name" "enable_docker_domain" "false")" == "true" ]]; then
        # Aqui assumimos uma flag 'enable_docker_domain' por domínio se Docker global está ativo
        # 14-setup-docker.yml pode precisar de adaptação para rodar containers específicos do domínio
        print_message "yellow" "Domain-specific Docker container setup for $domain_name (using 14-setup-docker.yml) needs review. This playbook primarily installs Docker."
        # run_playbook "14-setup-docker.yml" "Docker Container Setup for $domain_name" "false" "$domain_name" # Precisa de lógica no playbook
    fi
    
    # Staging per-domain
    if [[ "$(is_feature_enabled "$domain_name" "enable_staging" "false")" == "true" ]]; then
        run_playbook "21-staging.yml" "Staging Environment Setup for $domain_name" "false" "$domain_name"
    fi

    # Multi-domain/Parked-domain (este playbook é mais um placeholder, a config é no template Nginx)
    if [[ "$(is_feature_enabled "$domain_name" "enable_multi_domain" "false")" == "true" || "$(is_feature_enabled "$domain_name" "enable_parked_domains" "false")" == "true"  ]]; then
        run_playbook "20-multi-domain.yml" "Multi-domain/Parked Domain Notice for $domain_name" "false" "$domain_name"
    fi
    
    # Per-domain security audit (custom WP scan script is part of 26-security-audit.yml)
    if [[ "$(is_feature_enabled "" "security_audit" "false")" == "true" && "$platform" == "wordpress" ]]; then
         # O script de scan do WP em 26-security-audit.yml é executado globalmente mas escaneia todos os sites WP.
         # Se uma ação específica por domínio for necessária, um novo playbook ou tag seria útil.
         print_message "yellow" "WordPress site security scan (part of global 26-security-audit.yml) covers $domain_name."
    fi


    print_message "green" "--- Playbooks for Domain $domain_name COMPLETED ---"
}


# Função principal
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
    config_json=$(parse_config)
    if [ $? -ne 0 ] || [[ "$config_json" == "{}" && "$(wc -l < $CONFIG_FILE)" -gt 1 ]]; then # Checa se parse falhou ou se retornou vazio para arquivo não-vazio
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

    case $deployment_mode in
        1)
            print_message "blue" "Running FULL deployment..."
            run_global_playbooks
            
            platforms_json_data=$(get_domain_platforms)
            if [[ -z "$platforms_json_data" || "$platforms_json_data" == "{}" ]]; then
                print_message "yellow" "No domains found in configuration to process for domain-specific playbooks."
            else
                # Use python para iterar sobre as chaves do JSON (nomes dos domínios)
                python3 -c "
import json, sys
data = json.loads('''$platforms_json_data''')
for domain_key in data.keys():
    print(domain_key)
" | while read -r domain_item; do
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
" | while read -r domain_item; do
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
            
            selected_domain_name=$(python3 -c "
import json, sys
data = json.loads('''$platforms_json_data''')
domains_list = list(data.keys())
try:
    choice_index = int('$domain_choice') - 1
    if 0 <= choice_index < len(domains_list):
        print(domains_list[choice_index])
    else:
        sys.exit(1) # Saída silenciosa para erro, o shell irá tratar
except (ValueError, IndexError):
    sys.exit(1) # Saída silenciosa
")
            if [ -z "$selected_domain_name" ]; then
                print_message "red" "Invalid domain choice. Exiting."
                exit 1
            fi
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

# Executa a função principal
main