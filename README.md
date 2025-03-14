# Ansible WordPress Deployment with Optimized Nginx Configuration

This repository provides a comprehensive set of Ansible playbooks to automate the deployment of a secure, optimized WordPress site on an Ubuntu server. It includes an advanced Nginx configuration tailored for WordPress, with support for Cloudflare and ArvanCloud CDNs, FastCGI caching, security enhancements, and performance optimizations. A Bash script (`generate_config.sh`) simplifies configuration with interactive prompts, generating secure credentials and settings, while additional server management tools are installed for convenience.

---

## **Features**
- **Automated Deployment:** Installs and configures MySQL, Nginx, PHP, Composer, WP-CLI, WordPress, Redis (optional), and SSL certificates via Certbot.
- **Optimized Nginx Configuration:**
  - FastCGI caching with a custom alias (e.g., `cleancachemysitecom`) for easy cache management.
  - Security headers, Gzip compression, keepalive settings, and WordPress-specific rules.
  - IP restriction and Basic Authentication support for sensitive paths (e.g., `/fm/` and recovery URLs).
- **CDN Integration:** Syncs IP lists for Cloudflare and ArvanCloud, sets real IP headers, and whitelists IPs in CSF firewall.
- **Security Enhancements:**
  - CSF firewall with CDN IP whitelisting and auto-blocking.
  - Blocks malicious User-Agents via iThemes Security rules.
  - Installs `clamav` (antivirus) and `rkhunter` (rootkit detection).
  - Optional IP restrictions and HTTP Basic Authentication configurable via `generate_config.sh`.
- **Performance Features:**
  - Optional Redis caching with secure configuration in `wp-config.php`.
  - PHP OPcache enabled by default with optimized settings.
  - Support for multiple domains and custom redirects.
- **WordPress Customization:**
  - Installs unlimited plugins from WordPress.org (via slugs) or local ZIP files (deactivated by default).
  - Configurable settings: `WP_MEMORY_LIMIT`, `WP_MAX_MEMORY_LIMIT`, `FORCE_SSL_LOGIN`, `FORCE_SSL_ADMIN`, `DISALLOW_FILE_EDIT`, `FS_METHOD`, and `DISABLE_WP_CRON`.
  - Optional system cron for `wp-cron.php` instead of WordPress’s built-in cron.
- **Server Management Tools:** Installs `bashtop`, `tmux`, `wget`, `curl`, `nano`, `tar`, `clamav`, `rkhunter`, and `rsync`.
- **Flexibility:** Uses Ansible variables for customization, with a script to generate secure passwords and settings.

---

## **Prerequisites**
Before using this project, ensure the following are met:

1. **Ansible:** Version 2.9+ installed on the control machine.
   - Install: `pip install ansible` or `sudo apt install ansible`.
2. **Ubuntu Server:** Target server running Ubuntu 20.04 or 22.04.
3. **SSH Access:** Root or sudo privileges with SSH key-based authentication.
4. **Domain Name:** A registered domain pointing to the server’s IP.
5. **Dependencies on Control Machine:**
   - OpenSSL: `sudo apt install openssl` (for `generate_config.sh`).
   - Python `passlib`: `pip install passlib` (for `.htpasswd` generation).
6. **Dialog (Optional):** For interactive `generate_config.sh` prompts.
   - Install: `sudo apt install dialog`.

---

## **Directory Structure**
```
project/
├── examplehelper/
│   ├── arvancloud-ip-sync.sh  # Syncs ArvanCloud IPs
│   └── cloudflare-ip-sync.sh  # Syncs Cloudflare IPs
├── group_vars/
│   └── all.yml                # Configuration variables (generated)
├── templates/
│   ├── cache.j2              # Caching rules
│   ├── cloudflare.j2         # Cloudflare IP settings
│   ├── docker-compose.yml.j2 # Docker Compose template
│   ├── filemanager.j2        # File manager access control
│   ├── general.j2           # General Nginx rules
│   ├── gzip.j2              # Gzip compression
│   ├── keepalive.j2         # Keepalive settings
│   ├── nginx.conf.j2        # Main Nginx configuration
│   ├── redirects.j2         # URL redirects
│   ├── securityheaders.j2   # Security headers
│   ├── wordpress.j2         # WordPress-specific rules
├── .gitignore
├── 00-update-upgrade.yml     # System updates and tools
├── 01-install-mysql.yml      # MySQL installation
├── 02-install-nginx.yml      # Nginx and CSF setup
├── 03-install-php-composer-wpcli.yml # PHP, Composer, WP-CLI
├── 04-install-wordpress.yml  # WordPress installation
├── 05-obtain-ssl.yml         # SSL via Certbot
├── 06-install-redis.yml      # Redis installation (optional)
├── 07-setup-backups.yml      # Backup configuration
├── 08-configure-smtp.yml     # SMTP setup
├── 09-setup-monitoring.yml   # Monitoring tools
├── 10-optimize-images.yml    # Image optimization
├── 11-advanced-security.yml  # Advanced security (e.g., Wordfence)
├── 12-migrate-wordpress.yml  # Migration support
├── 13-setup-cdn.yml          # CDN configuration
├── 14-setup-docker.yml       # Docker setup
├── 15-generate-docs.yml      # Documentation generation
├── 16-setup-rollback.yml     # Rollback setup
├── 17-advanced-caching.yml   # Advanced caching (e.g., Memcached)
├── 18-setup-waf.yml          # Web Application Firewall
├── 19-manage-php.yml         # PHP version management
├── 20-multi-domain.yml       # Multi-domain support
├── 21-staging.yml            # Staging environment
├── 22-anti-hack.yml          # Anti-hack measures
├── generate_config.sh        # Configuration generator
├── LICENSE                   # MIT License
└── README.md                 # This file
```

---

## **Installation and Usage**

### **Step 1: Clone the Repository**
```bash
git clone https://github.com/jamal13647850/ansible-wordpress-setup.git
cd ansible-wordpress-setup
```

### **Step 2: Install Dependencies**
On the control machine:
```bash
pip install ansible passlib
sudo apt install openssl dialog
```

### **Step 3: Generate Configuration**
Run the configuration script to create `group_vars/all.yml`:
```bash
chmod +x generate_config.sh
./generate_config.sh
```
- **Prompts Include:**
  - Domain name (e.g., `mysite.com`)
  - WordPress admin details (username, email, site title, locale)
  - SSL email (for Certbot)
  - PHP version (e.g., `8.3`)
  - Linux username (e.g., `ubuntu`)
  - IP restrictions (optional, with allowed IPs)
  - Basic Authentication (optional, with username/password)
  - Redis setup (optional, with database number and secure password)
  - Plugin installation (slugs or ZIP paths)
  - WordPress settings (memory limits, SSL, cron, etc.)
- **Output:** Generates secure passwords and settings. Optionally encrypts the file with Ansible Vault.
- **Example Output:**
  ```
  MySQL Root Password: Kj9mPx2vL8nQ7rT4wY6c
  WordPress Admin Password: H7kL4mP9vR2tQ8wX5nYc
  IP Restriction Enabled: Yes (192.168.1.1, 10.0.0.2)
  Basic Auth Enabled: Yes (myuser:[hidden])
  ```

### **Step 4: Set Up Inventory**
Create an `inventory` file:
```
[wordpress]
your_server_ip ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my_vps_key ansible_port=2222
```
Replace `your_server_ip` with your VPS IP (e.g., `185.82.164.15`).

### **Step 5: Run the Playbooks**
Execute all playbooks with a single command:
```bash
ansible-playbook -i inventory site.yml --ask-become-pass
```
- Use `--ask-vault-pass` if `all.yml` is encrypted.
- For selective deployment, run individual playbooks (e.g., `00-update-upgrade.yml`).

### **Step 6: Verify**
- Visit `https://yourdomain.com` to confirm WordPress is running.
- Log in with credentials from `generate_config.sh`.
- Test restricted paths (`/fm/` or recovery URLs) with IP or Basic Auth if enabled.
- Check logs: `tail -f /var/www/yourdomain.com/logs/error.log`.
- Clear cache: `source ~/.bashrc && cleancacheyourdomaincom`.

---

## **Deploying on a VPS**

### **Step 1: Prepare Control Machine**
```bash
sudo apt update
sudo apt install python3-pip git openssl dialog -y
pip3 install ansible passlib
git clone https://github.com/jamal13647850/ansible-wordpress-setup.git
cd ansible-wordpress-setup
```

### **Step 2: Prepare VPS**
1. **Enable SSH with Custom Port (e.g., 2222):**
   ```bash
   sudo apt install openssh-server -y
   sudo nano /etc/ssh/sshd_config  # Set "Port 2222"
   sudo systemctl restart sshd
   ```
2. **Create Sudo User:**
   ```bash
   adduser ubuntu
   usermod -aG sudo ubuntu
   ```
3. **Set Up SSH Key:**
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/my_vps_key
   ssh-copy-id -i ~/.ssh/my_vps_key.pub -p 2222 ubuntu@your_vps_ip
   ```
4. **Configure Firewall:**
   ```bash
   sudo ufw allow 2222
   sudo ufw deny 22
   sudo ufw allow 80
   sudo ufw allow 443
   sudo ufw enable
   ```

### **Step 3: Configure Ansible**
- Create `inventory` as above.
- Test connection:
  ```bash
  ansible -i inventory wordpress -m ping
  ```

### **Step 4: Deploy**
Run `generate_config.sh` and then:
```bash
ansible-playbook -i inventory site.yml --ask-become-pass
```

### **Step 5: Verify**
Follow the verification steps above.

---

## **Playbook Details**
- **`00-update-upgrade.yml`:** Updates system, installs tools, adds cache alias.
- **`01-install-mysql.yml`:** Installs and configures MySQL.
- **`02-install-nginx.yml`:** Sets up Nginx, CSF, and CDN IP sync.
- **`03-install-php-composer-wpcli.yml`:** Installs PHP, Composer, WP-CLI.
- **`04-install-wordpress.yml`:** Installs WordPress with custom settings.
- **`05-obtain-ssl.yml`:** Obtains SSL certificates.
- **`06-install-redis.yml`:** Installs Redis (optional).
- **Additional Playbooks:** Support backups, SMTP, monitoring, image optimization, security, migration, CDN, Docker, and more.

---

## **Nginx Configuration**
- **FastCGI Caching:** Configured with a 100MB cache and 60-minute inactivity timeout.
- **Security Headers:** Protects against XSS, clickjacking, etc.
- **CDN Support:** Integrates Cloudflare/ArvanCloud with real IP headers.
- **WordPress Rules:** Blocks sensitive files, throttles `wp-login.php`.
- **Access Control:** IP restrictions and Basic Auth for `/fm/` and recovery paths.

---

## **Security Notes**
- **Credentials:** Store passwords from `generate_config.sh` securely.
- **Encryption:** Use Ansible Vault for `all.yml` (optional).
- **Firewall:** CSF whitelists CDN IPs; `clamav` and `rkhunter` enhance security.
- **Permissions:** Files set to `0644`, directories to `0755`, owned by `www-data`.
- **Basic Auth:** `.htpasswd` generated with `0640` permissions.

---

## **Troubleshooting**
- **SSH Issues:** Check port (`netstat -tuln | grep 2222`) and `~/.ssh/authorized_keys`.
- **Sudo Prompt:** Use `--ask-become-pass`.
- **Nginx Errors:** View `/var/www/yourdomain.com/logs/error.log`.
- **Certbot Failure:** Verify DNS (`dig yourdomain.com`).
- **Permissions:** Fix with `sudo chown -R www-data:www-data /var/www/yourdomain.com`.
- **Basic Auth:** Confirm `.htpasswd` contents (`cat /etc/nginx/sites-available/yourdomain.comhelper/.htpasswd`).

---

## **Customization**
- **PHP Version:** Set via `generate_config.sh`.
- **Redirects:** Edit `templates/redirects.j2`.
- **Security Headers:** Modify `templates/securityheaders.j2`.
- **Plugins:** Add slugs or ZIP paths in `generate_config.sh`.
- **Cron:** Enable system cron in `generate_config.sh` to replace WP-Cron.

---

## **Contributing**
Feel free to submit issues or pull requests to enhance this project!

---

## **License**
MIT License - See `LICENSE` for details.



