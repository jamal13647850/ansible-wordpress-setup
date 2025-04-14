# WordPress & Laravel Server Deployment System

This repository contains an automated deployment system for setting up WordPress and Laravel applications on a Linux server using Ansible. The system is designed to be flexible, secure, and optimized for performance.

## Features

### General Features
- Support for multiple domains on a single server
- Automatic SSL certificate installation via Let's Encrypt
- Advanced security configurations
- Performance optimizations with Redis caching
- Automated backups
- Monitoring setup
- CDN integration (Cloudflare, ArvanCloud)
- Fail2ban integration for security
- Comprehensive documentation generation

### WordPress-specific Features
- Automated WordPress installation and configuration
- WordPress security hardening
- WordPress performance optimization
- Image optimization for WordPress
- WordPress migration tools
- Plugin and theme management

### Laravel-specific Features
- Automated Laravel installation and configuration
- Laravel scheduler setup
- Laravel queue worker configuration
- Laravel Horizon integration
- Laravel Octane support (with Swoole)
- Laravel WebSockets support
- Laravel Telescope integration
- API setup with Laravel Sanctum
- API documentation with Scribe

## Requirements

- Ubuntu 20.04 LTS or newer
- SSH access with sudo privileges
- Domain names pointed to your server's IP address

## Quick Start

1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/jamal13647850/ansible-wordpress-setup
   cd ansible-wordpress-setup
   ```

2. Run the configuration generator script:
   ```bash
   ./generate_config.sh
   ```

3. Follow the prompts to configure your domains and applications.

4. Run the deployment script:
   ```bash
   sudo ./run_playbooks.sh
   ```

## Configuration Options

### Domain Configuration

Each domain can be configured with the following options:

```yaml
domains:
  example.com:
    # Database configuration
    mysql_root_password: "secure_password"
    mysql_db_name: "wp_example"
    mysql_db_user: "example_user"
    mysql_db_password: "secure_password"
    
    # Domain settings
    domain: "example.com"
    
    # WordPress/Laravel settings
    wordpress_admin_user: "admin"
    wordpress_admin_password: "secure_password"
    wordpress_admin_email: "admin@example.com"
    wordpress_title: "My Website"
    wordpress_locale: "en_US"
    wordpress_db_prefix: "wp_"
    
    # Laravel settings (if using Laravel)
    laravel_app_name: "My Laravel App"
    laravel_app_env: "production"
    laravel_admin_email: "admin@example.com"
    laravel_version: "10.*"
    
    # SSL configuration
    ssl_email: "admin@example.com"
    
    # PHP configuration
    php_version: "8.3"
    
    # Security settings
    linux_username: "ubuntu"
    restrict_ip_access: false
    allowed_ips: []
    enable_basic_auth: false
    basic_auth_user: "admin"
    basic_auth_password: "secure_password"
    
    # Redis configuration
    install_redis: true
    wp_redis_host: "127.0.0.1"
    wp_redis_port: 6379
    wp_redis_password: "redis_password"
    wp_redis_database: 0
    
    # Laravel specific features
    enable_scheduler: true
    enable_queue: true
    queue_driver: "database"
    enable_horizon: false
    enable_octane: false
    octane_server: "swoole"
    enable_websockets: false
    enable_telescope: false
    enable_api: false
    enable_api_auth: false
    enable_api_docs: false
    enable_api_versioning: false
    enable_api_rate_limit: false
```

## Directory Structure

```
├── group_vars/
│   └── all.yml                  # Main configuration file
├── laravel/                     # Laravel-specific playbooks
│   ├── 01-install-laravel.yml
│   ├── 02-configure-laravel.yml
│   ├── 03-laravel-scheduler.yml
│   ├── 04-laravel-queue.yml
│   ├── 05-laravel-horizon.yml
│   ├── 06-laravel-octane.yml
│   ├── 07-laravel-websockets.yml
│   ├── 08-laravel-telescope.yml
│   └── 09-laravel-api.yml
├── templates/                   # Configuration templates
│   ├── arvancloud-ip-sync.sh.j2
│   ├── cache.j2
│   ├── cloudflare-ip-sync.sh.j2
│   ├── cloudflare.j2
│   ├── docker-compose.yml.j2
│   ├── filemanager.j2
│   ├── general.j2
│   ├── gzip.j2
│   ├── keepalive.j2
│   ├── laravel-horizon.service.j2
│   ├── laravel-nginx.conf.j2
│   ├── laravel-octane-nginx.conf.j2
│   ├── laravel-octane.service.j2
│   ├── laravel-websockets-nginx.conf.j2
│   ├── laravel-websockets.service.j2
│   ├── laravel-worker.service.j2
│   ├── nginx.conf.j2
│   ├── redirects.j2
│   ├── securityheaders.j2
│   ├── wordpress.j2
│   └── wp-config.php.j2
├── 00-update-upgrade.yml        # System update playbook
├── 01-install-mysql.yml         # MySQL installation playbook
├── 02-install-nginx.yml         # Nginx installation playbook
├── 03-install-php-composer-wpcli.yml  # PHP installation playbook
├── 04-install-wordpress.yml     # WordPress installation playbook
├── 05-obtain-ssl.yml            # SSL certificate playbook
├── 06-install-redis.yml         # Redis installation playbook
├── 07-setup-backups.yml         # Backup configuration playbook
├── 08-configure-smtp.yml        # SMTP configuration playbook
├── 09-setup-monitoring.yml      # Monitoring setup playbook
├── 10-optimize-images.yml       # Image optimization playbook
├── 11-advanced-security.yml     # Security hardening playbook
├── 12-migrate-wordpress.yml     # WordPress migration playbook
├── 13-setup-cdn.yml             # CDN integration playbook
├── 14-setup-docker.yml          # Docker setup playbook
├── 15-generate-docs.yml         # Documentation generation playbook
├── 16-setup-rollback.yml        # Rollback mechanism playbook
├── 17-advanced-caching.yml      # Advanced caching playbook
├── 18-setup-waf.yml             # Web Application Firewall playbook
├── 19-manage-php.yml            # PHP version management playbook
├── 20-multi-domain.yml          # Multi-domain setup playbook
├── 21-staging.yml               # Staging environment playbook
├── 22-anti-hack.yml             # Anti-hacking measures playbook
├── 23-install-fail2ban.yml      # Fail2ban installation playbook
├── 24-secure-file-permissions.yml  # File permissions playbook
├── 25-secure-database.yml       # Database security playbook
├── 26-security-audit.yml        # Security audit playbook
├── generate_config.sh           # Configuration generator script
└── site.yml                     # Main Ansible playbook
```

## Laravel-specific Features

### Laravel Installation
The system automatically installs Laravel with the specified version and sets appropriate file permissions.

### Laravel Configuration
Configures Laravel environment variables, generates application keys, runs migrations, and sets up Nginx.

### Laravel Scheduler
Sets up a cron job for Laravel's scheduler to run tasks.

### Laravel Queue Workers
Configures systemd services for Laravel queue workers with configurable options.

### Laravel Horizon
Installs and configures Laravel Horizon for queue monitoring and management.

### Laravel Octane
Installs Laravel Octane with Swoole for improved performance.

### Laravel WebSockets
Sets up Laravel WebSockets for real-time communication.

### Laravel Telescope
Installs Laravel Telescope for application debugging and monitoring.

### Laravel API Setup
Configures Laravel for API development with Sanctum authentication and Scribe documentation.

## WordPress-specific Features

### WordPress Installation
Automatically installs and configures WordPress with security best practices.

### WordPress Optimization
Implements various performance optimizations including Redis object caching.

### WordPress Security
Applies security hardening measures to protect your WordPress installation.

## Security Features

- SSL/TLS configuration with modern cipher suites
- Fail2ban integration for blocking malicious attempts
- IP restriction options
- Basic authentication options
- Web Application Firewall setup
- File permission hardening
- Database security measures
- Security headers configuration

## Performance Optimizations

- Nginx configuration optimized for performance
- PHP-FPM tuning
- Redis caching
- Gzip compression
- Browser caching headers
- Laravel Octane support for high-performance PHP applications

## Maintenance

### Backups
The system can be configured to automatically create and manage backups of your websites and databases.

### Monitoring
Monitoring can be set up to alert you of any issues with your server or applications.

### Documentation
The system can generate comprehensive documentation about your server configuration.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.