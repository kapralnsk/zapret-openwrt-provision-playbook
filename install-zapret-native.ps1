# Zapret Native Windows Installer
# This script directly uses SSH commands to install zapret on OpenWrt routers

# Function to test SSH connection
function Test-SSHConnection {
    param (
        [string]$Host,
        [string]$Username,
        [string]$Password
    )
    
    try {
        $ssh = New-Object -TypeName SSH.Session
        $ssh.Connect($Host)
        $ssh.Authenticate($Username, $Password)
        $ssh.Disconnect()
        return $true
    }
    catch {
        Write-Host "SSH connection failed: $_"
        return $false
    }
}

# Function to execute SSH command
function Invoke-SSHCommand {
    param (
        [string]$Host,
        [string]$Username,
        [string]$Password,
        [string]$Command
    )
    
    try {
        $ssh = New-Object -TypeName SSH.Session
        $ssh.Connect($Host)
        $ssh.Authenticate($Username, $Password)
        $result = $ssh.ExecuteCommand($Command)
        $ssh.Disconnect()
        return $result
    }
    catch {
        Write-Host "Command execution failed: $_"
        return $null
    }
}

# Check if SSH module is installed
if (-not (Get-Module -ListAvailable -Name SSH)) {
    Write-Host "Installing SSH module..."
    Install-Module -Name SSH -Force -Scope CurrentUser
}

# Import SSH module
Import-Module SSH

# Configuration
$routerIP = "192.168.1.1"
$routerUser = "root"
$zapretDir = "/opt/zapret"
$tempDir = "/tmp"

# Check if config file exists
if (-not (Test-Path "config")) {
    Write-Host "Error: config file not found. Please make sure it exists in the same directory as this script."
    exit 1
}

# Get router password
$routerPassword = Read-Host -Prompt "Enter your router's root password"

# Test SSH connection
Write-Host "Testing SSH connection..."
if (-not (Test-SSHConnection -Host $routerIP -Username $routerUser -Password $routerPassword)) {
    Write-Host "Failed to connect to router. Please check your credentials and network connection."
    exit 1
}

# Get latest release from GitHub
Write-Host "Getting latest zapret release..."
$githubResponse = Invoke-RestMethod -Uri "https://api.github.com/repos/bol-van/zapret/releases/latest"
$latestTag = $githubResponse.tag_name

# Download and extract zapret
Write-Host "Downloading zapret $latestTag..."
$downloadCommand = "cd $tempDir && wget -q https://github.com/bol-van/zapret/archive/refs/tags/$latestTag.tar.gz -O zapret-$latestTag.tar.gz"
$result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $downloadCommand
if (-not $result) {
    Write-Host "Failed to download zapret."
    exit 1
}

# Extract archive
Write-Host "Extracting archive..."
$extractCommand = "cd $tempDir && tar xzf zapret-$latestTag.tar.gz && mkdir -p $zapretDir && cp -r zapret-$latestTag/* $zapretDir/"
$result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $extractCommand
if (-not $result) {
    Write-Host "Failed to extract archive."
    exit 1
}

# Create VERSION file
Write-Host "Creating VERSION file..."
$versionCommand = "echo '$latestTag' > $zapretDir/VERSION"
$result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $versionCommand
if (-not $result) {
    Write-Host "Failed to create VERSION file."
    exit 1
}

# Copy config file
Write-Host "Copying config file..."
$configContent = Get-Content -Path "config" -Raw
$configCommand = "cat > $zapretDir/config << 'EOL'
$configContent
EOL"
$result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $configCommand
if (-not $result) {
    Write-Host "Failed to create config file."
    exit 1
}

# Copy Discord configuration
Write-Host "Setting up Discord configuration..."
$discordCommand = "mkdir -p $zapretDir/init.d/openwrt/custom.d && cp $zapretDir/init.d/custom.d.examples.linux/50-discord $zapretDir/init.d/openwrt/custom.d/"
$result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $discordCommand
if (-not $result) {
    Write-Host "Failed to copy Discord configuration."
    exit 1
}

# Run installation scripts
Write-Host "Running installation scripts..."
$installCommand = "cd $zapretDir && chmod +x install_easy.sh get_antizapret_domains.sh && ./install_easy.sh && ./get_antizapret_domains.sh"
$result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $installCommand
if (-not $result) {
    Write-Host "Failed to run installation scripts."
    exit 1
}

# Check and manage service
Write-Host "Managing zapret service..."
$serviceCheckCommand = "/etc/init.d/zapret enabled"
$serviceCheck = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $serviceCheckCommand

if ($serviceCheck.ExitCode -eq 0) {
    Write-Host "Restarting zapret service..."
    $restartCommand = "/etc/init.d/zapret restart"
    $result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $restartCommand
}
else {
    Write-Host "Enabling zapret service..."
    $enableCommand = "/etc/init.d/zapret enable"
    $result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $enableCommand
}

if (-not $result) {
    Write-Host "Failed to manage zapret service."
    exit 1
}

# Cleanup
Write-Host "Cleaning up temporary files..."
$cleanupCommand = "rm -rf $tempDir/zapret-$latestTag*"
$result = Invoke-SSHCommand -Host $routerIP -Username $routerUser -Password $routerPassword -Command $cleanupCommand

Write-Host "Installation complete! Please check the output above for any errors." 
