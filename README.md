# WordPress Deployment with Ansible

This project provides an automated way to deploy and manage WordPress instances using Ansible playbooks. It supports single-domain and multi-domain setups, allowing you to configure multiple WordPress sites on a single server with ease.

## Features

- **Multi-Domain Support**: Deploy and manage multiple WordPress sites on a single server.
- **Automated Setup**: Installs Nginx, MySQL, PHP, WordPress, and optional tools like Redis with minimal manual intervention.
- **Security**: Options for IP restriction, Basic Authentication, SSL via Let's Encrypt, and more.
- **Performance**: Configurable caching with Redis, PHP OPcache, and Nginx FastCGI cache.
- **Customization**: Generate configurations via a Bash script (`generate_config.sh`) with an interactive interface.
- **Extensibility**: Add plugins, themes, backups, and advanced features like multisite or SMTP.

## Prerequisites

Before running the playbooks, ensure the following are installed on your local machine:

- **Ansible**: Version 2.9 or higher (`pip install ansible` or `sudo apt install ansible`).
- **dialog**: For the configuration generator (`sudo apt install dialog`).
- **OpenSSL**: For generating secure passwords (`sudo apt install openssl`).
- **SSH Access**: Configure SSH keys or password-based access to the target server.
- **Python 3**: Required on the target server for Ansible.

On the target server:
- A supported Linux distribution (e.g., Ubuntu 20.04 or 22.04).
- Root or sudo privileges.

## Project Structure

```
├── group_vars/
│   └── all.yml              # Configuration file for all domains
├── templates/
│   ├── nginx.conf.j2        # Nginx configuration template
│   ├── wp-config.php.j2     # WordPress configuration template
│   └── ...                  # Additional helper templates
├── inventory                # Inventory file for target servers
├── site.yml                 # Main playbook to orchestrate deployment
├── 00-update-upgrade.yml    # System update playbook
├── 01-install-mysql.yml     # MySQL installation playbook
├── 02-install-nginx.yml     # Nginx installation playbook
├── 03-install-php-composer-wpcli.yml # PHP, Composer, and WP-CLI playbook
├── 04-install-wordpress.yml  # WordPress installation playbook
├── 05-obtain-ssl.yml        # SSL certificate playbook
├── 06-install-redis.yml     # Redis installation playbook
├── generate_config.sh       # Script to generate configuration
└── README.md                # This file
```

## Setup Instructions

### Step 1: Clone the Repository
```bash
git clone <repository-url>
cd <repository-directory>
```

### Step 2: Generate Configuration
Run the configuration generator to create `group_vars/all.yml`:

```bash
chmod +x generate_config.sh
./generate_config.sh
```

- **Domain Settings**: Enter one or more domains (e.g., `mysite.com,newsite.com` for multi-domain).
- **Basic Settings**: Configure admin credentials, database, and site details for each domain.
- **Security/Performance**: Enable optional features like IP restriction, Redis, or Basic Auth.
- **Advanced Features**: Add multisite, SMTP, backups, etc.
- Save the configuration and optionally encrypt it with Ansible Vault.

The generated `group_vars/all.yml` will look like this for a multi-domain setup:

```yaml
---
domains:
  mysite.com:
    mysql_db_name: "wp_mysite"
    domain: "mysite.com"
    wordpress_admin_user: "admin1"
    wordpress_admin_email: "admin1@mysite.com"
    install_redis: true
    wp_redis_database: "0"
  newsite.com:
    mysql_db_name: "wp_newsite"
    domain: "newsite.com"
    wordpress_admin_user: "admin2"
    wordpress_admin_email: "admin2@newsite.com"
    install_redis: true
    wp_redis_database: "1"
```

### Step 3: Configure Inventory
Edit the `inventory` file to specify your target server(s):

```ini
[wordpress]
<server-ip-or-hostname> ansible_user=<ssh-user> ansible_ssh_private_key_file=<path-to-key>
```

Example:
```ini
[wordpress]
192.168.1.100 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
```

### Step 4: Run the Playbook
Deploy the configuration to the server:

```bash
ansible-playbook -i inventory site.yml --ask-become-pass
```

- `--ask-become-pass`: Prompts for the sudo password.
- If `group_vars/all.yml` is encrypted, add `--ask-vault-pass` or use a vault password file.

The playbook will:
1. Update the system.
2. Install MySQL and configure databases for each domain.
3. Install and configure Nginx with separate configurations per domain.
4. Install PHP, Composer, and WP-CLI.
5. Install WordPress for each domain.
6. Obtain SSL certificates via Let's Encrypt (if enabled).
7. Install and configure Redis (if enabled).

### Step 5: Verify Deployment
- Visit each domain (e.g., `https://mysite.com`, `https://newsite.com`) to ensure WordPress is running.
- Check logs in `/var/www/<domain>/logs/` for troubleshooting.

## Customization

### Adding Domains
Edit `group_vars/all.yml` and add new domains under the `domains` key with their settings.

### Enabling Features
Modify `group_vars/all.yml` to enable features like:
- `install_redis: true` for Redis caching.
- `restrict_ip_access: true` and `allowed_ips` for IP restrictions.
- `enable_basic_auth: true` for Basic Authentication.

### Running Specific Playbooks
To run a single playbook (e.g., update Nginx):
```bash
ansible-playbook -i inventory 02-install-nginx.yml --ask-become-pass
```

## Security Notes
- Save generated passwords from `group_vars/all.yml` securely.
- Use Ansible Vault to encrypt sensitive data:
  ```bash
  ansible-vault encrypt group_vars/all.yml
  ```
- Restrict SSH access to the server after deployment.

## Troubleshooting
- **Nginx Errors**: Check `/var/www/<domain>/logs/error.log`.
- **MySQL Issues**: Verify database credentials in `group_vars/all.yml`.
- **Ansible Failures**: Increase verbosity with `-v` or `-vvv`:
  ```bash
  ansible-playbook -i inventory site.yml -v --ask-become-pass
  ```

## Contributing
Feel free to submit pull requests or open issues for improvements or bug fixes.

## License
This project is licensed under the MIT License.


