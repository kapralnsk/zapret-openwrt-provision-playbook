# Zapret Windows Installer
# This script uses Docker to run Ansible and install zapret on OpenWrt routers

# Check if Docker is installed
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker Desktop is not installed. Please install Docker Desktop from https://www.docker.com/products/docker-desktop"
    Write-Host "After installation, please restart this script."
    exit 1
}

# Check if Docker is running
try {
    $null = docker info
} catch {
    Write-Host "Docker is not running. Please start Docker Desktop and try again."
    exit 1
}

# Check if config file exists
if (-not (Test-Path "config")) {
    Write-Host "Error: config file not found. Please make sure it exists in the same directory as this script."
    exit 1
}

# Create a temporary directory for our Ansible files
$tempDir = Join-Path $env:TEMP "zapret-install"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# Create the Ansible playbook
@'
---
- name: Install and configure zapret
  hosts: 192.168.1.1
  remote_user: root
  vars:
    zapret_github_repo: "bol-van/zapret"
    zapret_install_dir: "/opt/zapret"
    zapret_temp_dir: "/tmp"
    ansible_ssh_pass: "{{ lookup('env', 'ROUTER_ROOT_PASSWORD') }}"

  gather_facts: no

  tasks:
    - name: Get latest release tag from GitHub API
      raw: |
        curl -s https://api.github.com/repos/{{ zapret_github_repo }}/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4
      register: github_response
      delegate_to: localhost
      changed_when: false

    - name: Set latest tag name
      set_fact:
        latest_tag: "{{ github_response.stdout.strip() }}"

    - name: Download latest zapret release
      raw: |
        cd {{ zapret_temp_dir }} && \
        wget -q https://github.com/{{ zapret_github_repo }}/archive/refs/tags/{{ latest_tag }}.tar.gz -O zapret-{{ latest_tag }}.tar.gz
      register: download_result
      changed_when: download_result.rc == 0

    - name: Extract zapret archive
      raw: |
        cd {{ zapret_temp_dir }} && \
        tar xzf zapret-{{ latest_tag }}.tar.gz && \
        cp -r zapret-{{ latest_tag }}/* {{ zapret_install_dir }}/
      register: extract_result
      changed_when: extract_result.rc == 0

    - name: Create VERSION file with tag name
      raw: |
        echo "{{ latest_tag }}" > {{ zapret_install_dir }}/VERSION
      register: version_result
      changed_when: version_result.rc == 0

    - name: Copy config file to zapret directory
      raw: |
        cat > {{ zapret_install_dir }}/config << 'EOL'
        {{ lookup('file', 'config') }}
        EOL
      register: config_result
      changed_when: config_result.rc == 0

    - name: Copy Discord configuration file
      raw: |
        cp {{ zapret_install_dir }}/init.d/custom.d.examples.linux/50-discord {{ zapret_install_dir }}/init.d/openwrt/custom.d/
      register: discord_result
      changed_when: discord_result.rc == 0

    - name: Run install_easy.sh script
      raw: |
        cd {{ zapret_install_dir }} && ./install_easy.sh
      register: install_result
      changed_when: install_result.rc == 0

    - name: Run get_antizapret_domains.sh script
      raw: |
        cd {{ zapret_install_dir }} && ./get_antizapret_domains.sh
      register: domains_result
      changed_when: domains_result.rc == 0

    - name: Check if zapret service exists
      raw: |
        /etc/init.d/zapret enabled
      register: service_check
      changed_when: false

    - name: Restart zapret service
      raw: |
        /etc/init.d/zapret restart
      when: service_check.rc == 0
      register: restart_result
      changed_when: restart_result.rc == 0

    - name: Enable zapret service
      raw: |
        /etc/init.d/zapret enable
      when: service_check.rc != 0
      register: enable_result
      changed_when: enable_result.rc == 0
'@ | Out-File -FilePath (Join-Path $tempDir "playbook.yml") -Encoding UTF8

# Copy config file to temp directory
Copy-Item -Path "config" -Destination (Join-Path $tempDir "config") -Force

# Create inventory file
@'
[zapret]
192.168.1.1
'@ | Out-File -FilePath (Join-Path $tempDir "inventory") -Encoding UTF8

# Create ansible.cfg
@'
[defaults]
inventory = inventory
host_key_checking = False
'@ | Out-File -FilePath (Join-Path $tempDir "ansible.cfg") -Encoding UTF8

# Create Dockerfile
@'
FROM willhallonline/ansible:latest

WORKDIR /ansible
COPY . .

CMD ["ansible-playbook", "playbook.yml"]
'@ | Out-File -FilePath (Join-Path $tempDir "Dockerfile") -Encoding UTF8

# Build and run the Docker container
Write-Host "Building Docker container..."
docker build -t zapret-installer $tempDir

# Get router password
$routerPassword = Read-Host -Prompt "Enter your router's root password"

# Run the container with the password
Write-Host "Running zapret installation..."
docker run --rm -e ROUTER_ROOT_PASSWORD=$routerPassword zapret-installer

# Cleanup
Write-Host "Cleaning up..."
Remove-Item -Path $tempDir -Recurse -Force

Write-Host "Installation complete! Please check the output above for any errors." 
