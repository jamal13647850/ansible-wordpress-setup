# Ansible WordPress Deployment with Optimized Nginx Configuration

This repository provides a set of Ansible playbooks to automate the deployment of a WordPress site on an Ubuntu server. It includes an optimized Nginx configuration tailored for WordPress, with support for Cloudflare, ArvanCloud, FastCGI caching, security enhancements, and performance optimizations. A Bash script (`generate_config.sh`) simplifies configuration with options for IP restrictions and Basic Authentication, and additional tools are installed for server management.

---

## **Features**
- **Automated Setup:** Installs and configures MySQL, Nginx, PHP, Composer, WP-CLI, WordPress, and SSL certificates.
- **Optimized Nginx:** Includes configurations for caching, security headers, Gzip, keepalive, and WordPress-specific rules.
- **CDN Support:** Integrates with Cloudflare and ArvanCloud by syncing IP lists and setting real IP headers.
- **Security:**
  - Implements CSF firewall rules, blocks malicious User-Agents, and restricts access to sensitive files.
  - Supports IP-based access restrictions for WordPress recovery and file manager (configurable via `generate_config.sh`).
  - Optional Basic Authentication (HTTP Basic Auth) for additional access control, with `.htpasswd` file generation via Ansible.
  - Includes antivirus (`clamav`) and rootkit detection (`rkhunter`).
- **Flexibility:** Uses variables to avoid hardcoding, with a script to generate secure passwords and settings.
- **Server Tools:** Installs `bashtop`, `tmux`, `wget`, `curl`, `nano`, `tar`, `clamav`, `rkhunter`, and `rsync` for enhanced server management.
- **Cache Management:** Adds a custom alias to clear Nginx cache (e.g., `cleancachemysitecom`).
- **Custom WordPress Configurations:** Allows setting `WP_MEMORY_LIMIT`, `WP_MAX_MEMORY_LIMIT`, `FORCE_SSL_LOGIN`, `FORCE_SSL_ADMIN`, `DISALLOW_FILE_EDIT`, `FS_METHOD`, and `DISABLE_WP_CRON` via `generate_config.sh`.
- **System Cron for WP-Cron:** Optionally disables WordPress's built-in cron and sets up a system cron job to run `wp-cron.php` every minute.
- **Optional Redis Integration:** Installs and configures Redis for caching, with customizable settings (`WP_REDIS_HOST`, `WP_REDIS_PORT`, `WP_REDIS_PASSWORD`, `WP_REDIS_DATABASE`) in `wp-config.php`.


---

## **Prerequisites**
Before using this project, ensure you have the following:
1. **Ansible Installed:** Version 2.9 or higher on your control machine.
   - Install with: `pip install ansible` or `sudo apt install ansible`.
2. **Ubuntu Server:** A target server running Ubuntu 20.04 or 22.04.
3. **SSH Access:** Root or sudo access to the target server with SSH key-based authentication.
4. **Domain Name:** A registered domain pointing to your server's IP address.
5. **OpenSSL:** Required for the `generate_config.sh` script to generate secure passwords.
   - Install with: `sudo apt install openssl`.
6. **Python passlib:** Required for generating `.htpasswd` files with Ansible.
   - Install with: `pip install passlib`.

---

## **Directory Structure**
```
project/
├── group_vars/
│   └── all.yml             # Variables file (generated by generate_config.sh)
├── templates/
│   ├── arvancloud-ip-sync.sh.j2  # ArvanCloud IP sync script
│   ├── cache.j2           # Caching rules
│   ├── cloudflare-ip-sync.sh.j2  # Cloudflare IP sync script
│   ├── cloudflare.j2      # Cloudflare IP list
│   ├── filemanager.j2     # File manager settings
│   ├── general.j2         # General Nginx rules
│   ├── gzip.j2            # Gzip compression settings
│   ├── keepalive.j2       # Keepalive settings
│   ├── nginx.conf.j2      # Nginx configuration template
│   ├── redirects.j2       # URL redirects
│   ├── securityheaders.j2 # Security headers
│   ├── wordpress.j2       # WordPress-specific rules
├── .gitignore
├── 00-update-upgrade.yml   # Updates system and installs tools
├── 01-install-mysql.yml    # Installs MySQL
├── 02-install-nginx.yml    # Installs Nginx and helper files
├── 03-install-php-composer-wpcli.yml # Installs PHP, Composer, and WP-CLI
├── 04-install-wordpress.yml # Installs and configures WordPress
├── 05-obtain-ssl.yml       # Obtains SSL certificate with Certbot
├── generate_config.sh      # Script to generate group_vars/all.yml
├── LICENSE
└── README.md
```

---

## **Installation and Usage**

### **Step 1: Clone the Repository**
Clone this repository to your control machine:
```bash
git clone https://github.com/jamal13647850/ansible-wordpress-setup.git
cd ansible-wordpress-setup
```

### **Step 2: Install Dependencies**
Ensure required tools are installed on your control machine:
```bash
pip install ansible passlib
sudo apt install openssl
```

### **Step 3: Generate Configuration**
Run the `generate_config.sh` script to create or update `group_vars/all.yml` with secure, auto-generated values:
```bash
chmod +x generate_config.sh
./generate_config.sh
```

- **Prompts:** The script will ask for:
  - **Redis (Optional):** Option to install Redis, with prompts for database number and auto-generated secure password.
  - **WordPress Configurations:** Options to set memory limits, SSL enforcement, file editing restrictions, filesystem method, and cron behavior.
  - Domain name (e.g., `mysite.com`)
  - WordPress admin username (e.g., `admin`)
  - WordPress admin email (e.g., `admin@mysite.com`)
  - WordPress site title (e.g., `My Site`)
  - WordPress locale (e.g., `en_US` or `fa_IR`)
  - SSL email for Certbot (e.g., `your@email.com`)
  - PHP version (e.g., `8.3`)
  - Linux username (e.g., `ubuntu`)
  - **IP Restriction:** Whether to restrict access to specific IPs for WordPress recovery and file manager, with an option to enter multiple IPs.
  - **Basic Authentication:** Whether to enable Basic Auth, with prompts for username and password.
- **Generated Values:** Automatically creates secure passwords, database settings, and optional security configurations.
- **Encryption Option:** You can choose to encrypt the file with Ansible Vault (recommended for security).

**Example Output:**
```
Configuration file 'group_vars/all.yml' has been created with the following values:
------------------------------------------------
MySQL Root Password: Kj9mPx2vL8nQ7rT4wY6c
MySQL Database Name: wp_mysitecom
MySQL Database User: wpuser_mysitecom
MySQL Database Password: B5tZ8pW3qX9vM2rJ6nYk
WordPress Admin Password: H7kL4mP9vR2tQ8wX5nYc
WordPress Database Prefix: kh_
IP Restriction Enabled: Yes
Allowed IPs:
  - "192.168.1.1"
  - "10.0.0.2"
Basic Authentication Enabled: Yes
Basic Auth Username: myuser
Basic Auth Password: [hidden for security]
------------------------------------------------
Please save these values in a secure place!
```

If encrypted, note the Vault password for later use.

### **Step 4: Set Up Inventory**
Create an `inventory` file with your target server’s IP or hostname:
```
[wordpress]
your_server_ip ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my_vps_key ansible_port=2222
```

Replace `your_server_ip` with your VPS IP (e.g., `185.82.164.15`) and adjust the key path if needed.

### **Step 5: Run the Playbooks**
Execute the playbooks in sequence:
```bash
ansible-playbook -i inventory \
  00-update-upgrade.yml \
  01-install-mysql.yml \
  02-install-nginx.yml \
  03-install-php-composer-wpcli.yml \
  04-install-wordpress.yml \
  05-obtain-ssl.yml \
  --ask-become-pass
```

- Use `--ask-become-pass` (or `-K`) to provide the sudo password for the VPS user if required.
- If `all.yml` is encrypted, add both flags:
  ```bash
  ansible-playbook -i inventory --ask-vault-pass --ask-become-pass ...
  ```

### **Step 6: Verify**
- Visit `https://yourdomain.com` to ensure WordPress is running.
- Log in with the admin credentials displayed by `generate_config.sh`.
- Access `https://yourdomain.com/fm/` or WordPress recovery paths; if Basic Auth is enabled, enter the username and password from `generate_config.sh`.
- Check Nginx logs at `/var/www/yourdomain.com/logs/`.
- Use the alias to clear Nginx cache (e.g., `cleancachemysitecom`) after logging into the server via SSH and running `source ~/.bashrc`.

---

## **Deploying on a VPS**

This section guides you through setting up WordPress on a VPS using this repository with a custom SSH port (e.g., 2222).

### **Step 1: Prepare the Control Machine**
1. **Install Ansible and Dependencies:**
   ```bash
   sudo apt update
   sudo apt install python3-pip -y
   pip3 install ansible passlib
   ansible --version  # Ensure version >= 2.9
   ```
2. **Install Git:**
   ```bash
   sudo apt install git -y
   git --version
   ```
3. **Clone the Repository:**
   ```bash
   git clone https://github.com/jamal13647850/ansible-wordpress-setup.git
   cd ansible-wordpress-setup
   ```

### **Step 2: Prepare the VPS**
1. **Enable SSH:**
   - Connect to your VPS (e.g., via root):
     ```bash
     sudo systemctl status ssh
     sudo apt install openssh-server -y
     sudo systemctl enable ssh
     sudo systemctl start ssh
     ```
2. **Change SSH Port to 2222:**
   - Edit SSH config:
     ```bash
     sudo nano /etc/ssh/sshd_config
     ```
     Add or modify:
     ```
     Port 2222
     ```
     Restart SSH:
     ```bash
     sudo systemctl restart sshd
     ```
3. **Create a Sudo User (Optional):**
   ```bash
   adduser ubuntu
   usermod -aG sudo ubuntu
   ```
4. **Generate SSH Key:**
   - On your local machine:
     ```bash
     ssh-keygen -t rsa -b 4096 -C "your.email@example.com"
     ```
     When prompted for a file, enter:
     ```
     /home/user/.ssh/my_vps_key
     ```
5. **Transfer SSH Key to VPS:**
   ```bash
   ssh-copy-id -i ~/.ssh/my_vps_key.pub -p 2222 ubuntu@your_vps_ip
   ```
   Test connection:
   ```bash
   ssh -i ~/.ssh/my_vps_key -p 2222 ubuntu@your_vps_ip
   ```
6. **Configure Firewall:**
   ```bash
   sudo ufw allow 2222
   sudo ufw deny 22
   sudo ufw allow 80
   sudo ufw allow 443
   sudo ufw enable
   ```

### **Step 3: Configure Ansible**
1. **Create Inventory File:**
   ```bash
   nano inventory
   ```
   Add:
   ```
   [wordpress]
   your_vps_ip ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my_vps_key ansible_port=2222
   ```
   Replace `your_vps_ip` with your VPS IP (e.g., `185.82.164.15`).
2. **Test Connection:**
   ```bash
   ansible -i inventory wordpress -m ping
   ```
   Expected output:
   ```
   your_vps_ip | SUCCESS => {"changed": false, "ping": "pong"}
   ```

### **Step 4: Generate Configuration**
```bash
chmod +x generate_config.sh
./generate_config.sh
```
Answer prompts and save generated credentials, including IP restrictions and Basic Auth details if enabled.

### **Step 5: Run Playbooks**
```bash
ansible-playbook -i inventory \
  00-update-upgrade.yml \
  01-install-mysql.yml \
  02-install-nginx.yml \
  03-install-php-composer-wpcli.yml \
  04-install-wordpress.yml \
  05-obtain-ssl.yml \
  --ask-become-pass

  ansible-playbook -i inventory 06-install-redis.yml --ask-become-pass
```
- Use `--ask-become-pass` to enter the sudo password if required.
- If encrypted, add `--ask-vault-pass`:
  ```bash
  ansible-playbook -i inventory --ask-vault-pass --ask-become-pass ...
  ```

### **Step 6: Verify**
- Access `https://yourdomain.com`.
- Test restricted paths (e.g., `/fm/` or recovery URLs) with IP or Basic Auth credentials if configured.
- Check logs:
  ```bash
  ssh -i ~/.ssh/my_vps_key -p 2222 ubuntu@your_vps_ip
  sudo tail -f /var/www/yourdomain.com/logs/error.log
  ```
- Clear cache:
  ```bash
  source ~/.bashrc
  cleancacheyourdomaincom
  ```

### **Step 7: Final Notes**
- Ensure DNS points to your VPS IP.
- Secure `group_vars/all.yml` or remove it if not encrypted.
- Update via `git pull` and rerun playbooks as needed.

---

## **Playbook Details**
1. **`00-update-upgrade.yml`**: Updates system, installs tools, adds cache alias.
2. **`01-install-mysql.yml`**: Installs MySQL and configures it.
3. **`02-install-nginx.yml`**: Installs Nginx, CSF, syncs CDN IPs, and generates `.htpasswd` if Basic Auth is enabled.
4. **`03-install-php-composer-wpcli.yml`**: Installs PHP, Composer, WP-CLI.
5. **`04-install-wordpress.yml`**: Configures Nginx, installs WordPress.
6. **`05-obtain-ssl.yml`**: Obtains SSL certificate.
7. **`06-install-redis.yml`**: Installs and configures Redis with secure settings if enabled.

---

## **Nginx Configuration**
- **FastCGI Caching:** Managed via alias (e.g., `cleancachemysitecom`).
- **Security Headers:** Protects against XSS, clickjacking.
- **CDN Integration:** Supports Cloudflare/ArvanCloud.
- **WordPress Rules:** Restricts sensitive files, throttles `wp-login.php`.
- **Access Control:** Configurable IP restrictions and Basic Authentication for file manager and recovery paths.

---

## **Security Notes**
- **Passwords:** Store credentials securely.
- **Encryption:** Use Ansible Vault for `all.yml`.
- **Firewall:** CSF whitelists CDN IPs; `clamav` and `rkhunter` installed.
- **Permissions:** Files set to `664`, directories to `775`, owned by `www-data`.
- **Basic Auth:** `.htpasswd` file is generated with restricted permissions (`0640`).

---

## **Troubleshooting**
- **SSH Issues:** Verify `sudo netstat -tuln | grep 2222` and key in `~/.ssh/authorized_keys`.
- **Sudo Password:** Use `--ask-become-pass` if prompted.
- **Nginx Errors:** Check `/var/www/yourdomain.com/logs/error.log`.
- **Certbot:** Ensure DNS is set (`dig yourdomain.com`).
- **Permissions:** Fix with `sudo chown -R www-data:www-data /var/www/yourdomain.com`.
- **Basic Auth Issues:** Verify `.htpasswd` exists (`cat /etc/nginx/sites-available/yourdomain.comhelper/.htpasswd`) and credentials match.

---

## **Customization**
- **PHP Version:** Set in `generate_config.sh`.
- **Redirects:** Edit `templates/redirects.j2`.
- **Security Headers:** Modify `templates/securityheaders.j2`.
- **Access Control:** Adjust IP restrictions and Basic Auth via `generate_config.sh`.

---

## **Contributing**
Submit issues or pull requests to improve this project!

---

## **License**
MIT License.


