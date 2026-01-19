#!/bin/bash

# WSL Hadoop Ecosystem Installation Script!!
# Installs: Hadoop, YARN, Spark, Kafka (KRaft), Pig

set -Eeuo pipefail

# Configuration
INSTALL_DIR="$HOME/bigdata"
HADOOP_VERSION="${HADOOP_VERSION:-3.4.2}"
SPARK_VERSION="${SPARK_VERSION:-3.5.3}"
KAFKA_VERSION="${KAFKA_VERSION:-4.1.1}"
PIG_VERSION="${PIG_VERSION:-0.17.0}"
JAVA_11_VERSION="11"
JAVA_17_VERSION="17"
HIVE_VERSION="${HIVE_VERSION:-3.1.3}"

STATE_FILE="$HOME/.hadoop_install_state"
LOG_FILE="$HOME/hadoop_install.log"
LOCK_FILE="$HOME/.hadoop_install.lock"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Progress
SPINNER_CHARS='---------------------------------------------------------------'
PROGRESS_BAR_WIDTH=50

# Display Functions
spinner() {
    local pid=$1
    local message=$2
    local spin_index=0
    
    while kill -0 $pid 2>/dev/null; do
        local char=${SPINNER_CHARS:$spin_index:1}
        printf "\r${CYAN}${char}${NC} ${message}..."
        spin_index=$(( (spin_index + 1) % ${#SPINNER_CHARS} ))
        sleep 0.1
    done
    
    wait $pid
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        printf "\r${GREEN}[OK]${NC} ${message}... ${GREEN}Done${NC}\n"
    else
        printf "\r${RED}[FAILED]${NC} ${message}... ${RED}Failed${NC}\n"
    fi
    
    return $exit_code
}

progress_bar() {
    local current=$1
    local total=$2
    local message=$3
    
    local percentage=$((current * 100 / total))
    local filled=$((current * PROGRESS_BAR_WIDTH / total))
    local empty=$((PROGRESS_BAR_WIDTH - filled))
    
    printf "\r${CYAN}[${NC}"
    printf "%${filled}s" | tr ' ' '-------'
    printf "%${empty}s" | tr ' ' '--------'
    printf "${CYAN}]${NC} ${percentage}%% - ${message}"
    
    if [ $current -eq $total ]; then
        printf " ${GREEN}-------${NC}\n"
    fi
}

step_header() {
    local step_num=$1
    local total_steps=$2
    local message=$3
    
    echo ""
    echo -e "${BOLD}${MAGENTA}---------------------------${NC}"
    echo -e "${BOLD}${YELLOW}Step ${step_num}/${total_steps}:${NC} ${BOLD}${message}${NC}"
    echo -e "${BOLD}${MAGENTA}---------------------------${NC}"
    echo ""
}

# Logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

# State management
mark_done() {
    echo "$1" >> "$STATE_FILE"
}

is_done() {
    [ -f "$STATE_FILE" ] && grep -Fxq "$1" "$STATE_FILE" 2>/dev/null
}

safe_exec() {
    if "$@"; then
        return 0
    else
        warn "Command failed (non-critical): $*"
        return 1
    fi
}

# Pre-flight checks
preflight_checks() {
    # Detect non-interactive mode
    if [ ! -t 0 ]; then
        AUTO_YES=true
        log "Running in non-interactive mode (piped from curl)"
    else
        AUTO_YES=false
    fi
    
    echo ""
    echo -e "${GREEN}--*-----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
    echo -e "${GREEN}--*---                                                                                         --*---${NC}"
    echo -e "${GREEN}--*---       ${BOLD}Hadoop WSL Installer by www.github.com/darshan-gowdaa${NC}${GREEN}                   --*---${NC}"
    echo -e "${GREEN}--*---                                                                                         --*---${NC}"
    echo -e "${GREEN}--*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*---${NC}"
    echo ""
    
    # Check required commands
    log "Checking required commands..."
    local missing_cmds=()
    local total_cmds=6
    local current_cmd=0
    
    for cmd in wget tar ssh-keygen awk grep sed; do
        current_cmd=$((current_cmd + 1))
        if command -v "$cmd" &>/dev/null; then
            progress_bar $current_cmd $total_cmds "Checking: $cmd"
        else
            missing_cmds+=("$cmd")
            progress_bar $current_cmd $total_cmds "Missing: $cmd"
        fi
        sleep 0.1
    done
    
    if [ ${#missing_cmds[@]} -gt 0 ]; then
        error "Missing required commands: ${missing_cmds[*]}
        
Install with: sudo apt-get install -y ${missing_cmds[*]}"
    fi
    
    echo ""
    
    # Check filesystem location
    local real_path
    real_path=$(readlink -f "$PWD")
    if [[ "$real_path" == /mnt/* ]] || [[ "$real_path" == *"/mnt/"* ]]; then
        echo -e "${RED}*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*---${NC}"
        echo -e "${RED}----*---  [!]  WARNING: You're in Windows filesystem!                     ----*---${NC}"
        echo -e "${RED}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
        echo ""
        echo -e "  Current location: ${YELLOW}$real_path${NC}"
        echo -e "  ${RED}Hadoop will be 10-20x SLOWER here!${NC}"
        echo ""
        echo -e "${GREEN}Fix:${NC} Move to Linux home directory:"
        echo -e "  ${CYAN}cd ~${NC}"
        echo -e "  ${CYAN}bash ./$(basename "$0")${NC}"
        echo ""
        exit 1
    fi
    
    # Verify WSL
    if ! grep -qi microsoft /proc/version 2>/dev/null; then
        echo -e "${YELLOW}*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*---${NC}"
        echo -e "${YELLOW}----*---  [!]  WARNING: Not running on WSL                                     ----*---${NC}"
        echo -e "${YELLOW}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
        echo ""
        echo "This script is optimized for Windows Subsystem for Linux (WSL)."
        echo ""
        
        if [ "$AUTO_YES" = true ]; then
            warn "Auto-continuing in non-interactive mode..."
        else
            echo -ne "Continue anyway? (y/n): "
            read -r choice
            [[ "$choice" != "y" ]] && exit 0
        fi
    fi
    
    # Check WSL version
    if ! grep -q "WSL2" /proc/version 2>/dev/null; then
        echo -e "${YELLOW}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
        echo -e "${YELLOW}----*---  [!]  WARNING: Detected WSL1                                          ----*---${NC}"
        echo -e "${YELLOW}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
        echo ""
        echo -e "${RED}Hadoop will be EXTREMELY SLOW on WSL1!${NC}"
        echo ""
        echo "Recommended: Upgrade to WSL2 by running in PowerShell (as admin):"
        echo -e "  ${CYAN}wsl --set-version <distro-name> 2${NC}"
        echo ""
        
        if [ "$AUTO_YES" = true ]; then
            warn "Auto-continuing in non-interactive mode..."
        else
            echo -ne "Continue with WSL1 anyway? ${YELLOW}(not recommended)${NC} (y/n): "
            read -r choice
            [[ "$choice" != "y" ]] && exit 0
        fi
    else
        echo -e "${GREEN}[OK] Running on WSL2${NC}"
    fi
    
    echo ""
    
    # Memory check
    local total_mem_mb
    total_mem_mb=$(free -m | awk '/^Mem:/{print $2}')
    local total_mem_gb=$((total_mem_mb / 1024))
    
    if [ "$total_mem_gb" -lt 6 ]; then
        echo -e "${YELLOW}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
        echo -e "${YELLOW}----*---  [!]  WARNING: Low Memory                                             ----*---${NC}"
        echo -e "${YELLOW}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
        echo ""
        echo -e "WSL has only ${RED}${total_mem_gb}GB RAM${NC} allocated."
        echo ""
        echo "For Hadoop learning, you need at least ${GREEN}8GB${NC} allocated to WSL."
        echo ""
        echo "To increase WSL memory, edit ${CYAN}C:\\Users\\<YourUsername>\\.wslconfig${NC}:"
        echo -e "${CYAN}[wsl2]${NC}"
        echo -e "${CYAN}memory=8GB${NC}"
        echo ""
        
        if [ "$AUTO_YES" = true ]; then
            warn "Auto-continuing with limited memory in non-interactive mode..."
        else
            echo -ne "Continue with limited memory? ${YELLOW}(not recommended)${NC} (y/n): "
            read -r choice
            [[ "$choice" != "y" ]] && exit 0
        fi
    else
        echo -e "${GREEN}[OK] WSL has ${total_mem_gb}GB RAM allocated${NC}"
    fi
    
    echo ""
    
    # Sudo test
    echo -e "${CYAN}Testing sudo access...${NC}"
    if ! sudo -v; then
        error "Sudo authentication failed. Please enter your password."
    fi
    echo -e "${GREEN}[OK] Sudo access confirmed${NC}"
    
    echo ""
    
    # Firewall warning
    echo -e "${RED}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
    echo -e "${RED}----*---  !! IMPORTANT: Windows Firewall Action Required !!                     ----*---${NC}"
    echo -e "${RED}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
    echo ""
    echo "During installation, Windows will show firewall popup dialogs for:"
    echo ""
    echo -e "  ${YELLOW}-------${NC} Java Platform SE binary"
    echo -e "  ${YELLOW}-------${NC} OpenSSH SSH Server"
    echo ""
    echo -e "${GREEN}ACTION REQUIRED:${NC}"
    echo -e "  -------- Click ${GREEN}'Allow access'${NC} on ${CYAN}Private networks${NC}"
    echo -e "  -------- Do NOT block these or Hadoop won't work!"
    echo ""
    echo -e "----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--"
    echo ""
    
    if [ "$AUTO_YES" = true ]; then
        log "Auto-continuing in 3 seconds..."
        sleep 3
    else
        echo -e "Press ${CYAN}Ctrl+C${NC} to cancel, or ${GREEN}Enter${NC} to continue..."
        read -r
    fi
    
    echo ""
    echo -e "${GREEN}Starting installation...${NC}"
    echo ""
}


# Cleanup handlers
cleanup_on_exit() {
    local exit_code=$?
    rm -f "$LOCK_FILE"
    if [ $exit_code -ne 0 ]; then
        warn "Installation failed. Check logs: $LOG_FILE"
    fi
}

trap cleanup_on_exit EXIT
trap 'error "Script failed at line $LINENO"' ERR

check_disk_space() {
    local required_gb=12
    
    echo ""
    log "Checking disk space..."
    
    # Get WSL filesystem space (where files will be installed)
    local wsl_info
    wsl_info=$(df -BG "$HOME" | awk 'NR==2 {print $2, $3, $4}')
    local wsl_total=$(echo "$wsl_info" | awk '{print $1}' | sed 's/G//')
    local wsl_used=$(echo "$wsl_info" | awk '{print $2}' | sed 's/G//')
    local wsl_avail=$(echo "$wsl_info" | awk '{print $3}' | sed 's/G//')
    
    # Get actual Windows C: drive space (where VHD lives)
    local c_drive_info
    if [ -d "/mnt/c" ]; then
        c_drive_info=$(df -BG /mnt/c 2>/dev/null | awk 'NR==2 {print $2, $3, $4}')
        local c_total=$(echo "$c_drive_info" | awk '{print $1}' | sed 's/G//')
        local c_used=$(echo "$c_drive_info" | awk '{print $2}' | sed 's/G//')
        local c_avail=$(echo "$c_drive_info" | awk '{print $3}' | sed 's/G//')
    fi
    
    echo ""
    echo -e "${CYAN}-------------------------------${NC}"
    echo -e "${BOLD}Disk Space Report:            |${NC}"
    echo -e "${CYAN}-------------------------------${NC}"
    echo ""
    echo -e "${YELLOW}WSL Filesystem (Virtual):${NC}"
    echo -e "  Total:     ${wsl_total}GB"
    echo -e "  Used:      ${wsl_used}GB"
    echo -e "  Available: ${GREEN}${wsl_avail}GB${NC}"
    echo ""
    
    if [ -d "/mnt/c" ]; then
        echo -e "${YELLOW}Windows C: Drive (Physical):${NC}"
        echo -e "  Total:     ${c_total}GB"
        echo -e "  Used:      ${c_used}GB"
        echo -e "  Available: ${GREEN}${c_avail}GB${NC}"
        echo ""
        echo -e "${CYAN}Note:${NC} WSL VHD grows dynamically using C: drive space"
    fi
    
    echo -e "${CYAN}-------------------------------${NC}"
    echo ""
    
    # Check if we have enough space
    # In WSL, check both VHD available space AND Windows C: drive space
    local actual_available=$wsl_avail
    
    if [ -d "/mnt/c" ] && [ "$c_avail" -lt "$wsl_avail" ]; then
        actual_available=$c_avail
        warn "[!] Real available space is limited by Windows C: drive: ${c_avail}GB"
    fi
    
    if [ "$actual_available" -lt "$required_gb" ]; then
        echo ""
        echo -e "${RED}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
        echo -e "${RED}----*---  [!] ERROR: Insufficient Disk Space                                   --*---${NC}"
        echo -e "${RED}----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*----*--${NC}"
        echo ""
        echo -e "  Required: ${GREEN}${required_gb}GB${NC}"
        echo -e "  Available: ${RED}${actual_available}GB${NC}"
        echo ""
        echo -e "${YELLOW}Solutions:${NC}"
        echo -e "  1. Free up space on Windows C: drive"
        echo -e "  2. Clean up WSL: ${CYAN}sudo apt clean && sudo apt autoremove${NC}"
        echo -e "  3. Remove unused Docker images/containers if installed"
        echo ""
        exit 1
    fi
    
    echo -e "${GREEN}[OK] Disk space check passed${NC}"
    echo -e "  Installation requires: ${required_gb}GB"
    echo -e "  You have available: ${GREEN}${actual_available}GB${NC}"
    echo ""
}


acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_age
        lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
        if [ "$lock_age" -gt 3600 ]; then
            warn "Stale lock file detected, removing..."
            rm -f "$LOCK_FILE"
        else
            error "Another installation is running."
        fi
    fi
    touch "$LOCK_FILE"
}


# Download with progress
download_with_retry() {
    local url=$1
    local output=$2
    
    local filename=$(basename "$output")
    
    # Mirrors
    local MIRRORS=(
        "$url"
        "https://dlcdn.apache.org/$(echo $url | sed 's|https://[^/]*/||')"
        "https://downloads.apache.org/$(echo $url | sed 's|https://[^/]*/||')"
        "https://archive.apache.org/dist/$(echo $url | sed 's|https://[^/]*/||')"
    )
    
    local downloaded=false
    
    for mirror in "${MIRRORS[@]}"; do
        echo -e "${BLUE}->${NC}  Trying: $mirror"
        
        if wget --progress=bar:force --timeout=60 --tries=2 \
                -O "$output" "$mirror" 2>&1; then
            
            # Verify file size
            if [ -f "$output" ] && [ $(stat -c%s "$output" 2>/dev/null || echo 0) -gt 1000000 ]; then
                echo -e "${GREEN}[OK]${NC} Download successful!"
                downloaded=true
                break
            else
                warn "File too small, trying next mirror..."
                rm -f "$output"
            fi
        else
            warn "Mirror failed, trying next..."
            rm -f "$output"
        fi
        
        sleep 2
    done
    
    if [ "$downloaded" = false ]; then
        error "Failed to download ${filename} from all mirrors."
    fi
    
    return 0
}


# System setup
setup_system() {
    if is_done "system_setup"; then
        log "System setup already done, skipping..."
        return
    fi
    
    step_header 1 11 "System Setup"
    
    log "Updating package lists..."
    (sudo apt-get update -qq) &
    spinner $! "Updating packages"
    
    log "Installing dependencies..."
    
    echo -e "${YELLOW}Note: Installing both Java 11 (for Hadoop) and Java 17 (for Kafka)${NC}"
    
    # Package list
    local packages=(openjdk-11-jdk openjdk-17-jdk wget curl ssh netcat-openbsd vim net-tools rsync tar gzip unzip util-linux file mysql-server)
    
    (sudo apt-get install -y "${packages[@]}" -qq) &
    spinner $! "Installing Java 11, Java 17, and dependencies"
    
    # Set Java 11 as default
    log "Setting Java 11 as default..."
    (sudo update-alternatives --set java /usr/lib/jvm/java-11-openjdk-amd64/bin/java 2>/dev/null || true) &
    spinner $! "Configuring default Java version"
    
    # IPv6 fix
    if ! grep -q "net.ipv6.conf.all.disable_ipv6" /etc/sysctl.conf 2>/dev/null; then
        log "Applying WSL2 IPv6 fix..."
        echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf >/dev/null
        echo "net.ipv6.conf.default.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf >/dev/null
        sudo sysctl -p >/dev/null 2>&1 || true
    fi
    
    # SSH setup
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        log "Creating SSH keys..."
        (ssh-keygen -t rsa -P '' -f "$HOME/.ssh/id_rsa" -q) &
        spinner $! "Generating SSH keys"
        cat "$HOME/.ssh/id_rsa.pub" >> "$HOME/.ssh/authorized_keys"
    fi

    # Fix SSH permissions
    log "Setting SSH permissions..."
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_rsa
    chmod 644 ~/.ssh/id_rsa.pub
    chmod 600 ~/.ssh/authorized_keys

    # Add localhost to known_hosts
    log "Adding localhost to known_hosts..."
    mkdir -p ~/.ssh
    ssh-keyscan -H localhost >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H 0.0.0.0 >> ~/.ssh/known_hosts 2>/dev/null || true
    ssh-keyscan -H 127.0.0.1 >> ~/.ssh/known_hosts 2>/dev/null || true

    # Configure SSH to skip host key checking for localhost
    log "Configuring SSH client..."
    if ! grep -q "StrictHostKeyChecking no" ~/.ssh/config 2>/dev/null; then
        cat >> ~/.ssh/config <<'SSHCONFIG'
Host localhost
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

Host 127.0.0.1
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

Host 0.0.0.0
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
SSHCONFIG
        chmod 600 ~/.ssh/config
    fi

    # Start MySQL service
    if ! pgrep -x mysqld >/dev/null; then
        log "Starting MySQL service..."
        if sudo service mysql start 2>/dev/null; then
            echo -e "${GREEN}-------${NC} MySQL started"
            sleep 2
        else
            warn "MySQL service start failed - will retry during Hive setup"
        fi
    else
        echo -e "${GREEN}[OK]${NC} MySQL already running"
    fi

    # Start SSH service
    if ! pgrep -x sshd >/dev/null; then
        log "Starting SSH service..."
        if sudo service ssh start 2>/dev/null; then
            echo -e "${GREEN}-------${NC} SSH started"
            sleep 1
        else
            warn "SSH service start failed - may affect Hadoop startup later"
        fi
    else
        echo -e "${GREEN}[OK]${NC} SSH already running"
    fi
    
    mark_done "system_setup"
    echo -e "${GREEN}[OK] System setup completed${NC}"
}

# Java configuration
setup_java() {
    if is_done "java_setup"; then
        log "Java setup already done, skipping..."
        return
    fi
    
    step_header 2 11 "Java Configuration"
    
    # Detect JAVA_HOME
    local temp_file="/tmp/java_home_$$"
    
    {
        local detected_path=""
        if command -v update-alternatives >/dev/null 2>&1; then
            detected_path=$(update-alternatives --query java 2>/dev/null | grep 'Value:' | cut -d' ' -f2 | sed 's|/bin/java||')
        fi
        
        # Fallback
        if [ -z "$detected_path" ] || [ ! -d "$detected_path" ]; then
            if command -v java >/dev/null 2>&1; then
                local java_bin=$(which java)
                detected_path=$(dirname "$(dirname "$(readlink -f "$java_bin")")")
            fi
        fi
        
        echo "$detected_path" > "$temp_file"
    } &
    
    local detect_pid=$!
    spinner $detect_pid "Detecting JAVA_HOME"
    
    # Read result
    local java_home=""
    if [ -f "$temp_file" ]; then
        java_home=$(cat "$temp_file")
        rm -f "$temp_file"
    fi
    
    if [ -z "$java_home" ] || [ ! -d "$java_home" ]; then
        error "JAVA_HOME detection failed. Please install OpenJDK 17:
    sudo apt-get install -y openjdk-17-jdk"
    fi
    
    export JAVA_HOME="$java_home"
    
    # Add to bashrc
    if ! grep -q "JAVA_HOME" "$HOME/.bashrc"; then
        log "Adding JAVA_HOME to .bashrc..."
        cat >> "$HOME/.bashrc" <<EOF

# Java Environment
export JAVA_HOME=$JAVA_HOME
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    fi
    
    mark_done "java_setup"
    echo -e "${GREEN}[OK] Java configured: $JAVA_HOME${NC}"
}

# Hadoop installation
install_hadoop() {
    if is_done "hadoop_install"; then
        log "Hadoop already installed, skipping..."
        return
    fi
    
    step_header 3 11 "Hadoop ${HADOOP_VERSION} Installation"
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    if [ ! -d "hadoop-${HADOOP_VERSION}" ]; then
        rm -f "hadoop-${HADOOP_VERSION}.tar.gz"
        
        download_with_retry \
            "https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" \
            "hadoop-${HADOOP_VERSION}.tar.gz"
        
        log "Extracting Hadoop..."
        (tar -xzf "hadoop-${HADOOP_VERSION}.tar.gz") &
        spinner $! "Extracting Hadoop archive"
    fi
    
    rm -f hadoop
    ln -s "hadoop-${HADOOP_VERSION}" hadoop
    
    mark_done "hadoop_install"
    echo -e "${GREEN}[OK] Hadoop installed successfully${NC}"
}

# Hadoop configuration
configure_hadoop() {
    if is_done "hadoop_config"; then
        log "Hadoop already configured, skipping..."
        return
    fi
    
    step_header 4 11 "Hadoop Configuration"
    
    export HADOOP_HOME="$INSTALL_DIR/hadoop"
    export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
    
    # Calculate memory
    local total_mem
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
    local yarn_mem=$((total_mem * 70 / 100))
    local container_mem=$((yarn_mem / 2))
    
    if [ "$yarn_mem" -gt 4096 ]; then
        yarn_mem=4096
        container_mem=2048
    fi
    
    log "Configuring Hadoop (YARN Memory: ${yarn_mem}MB)..."
    
    local config_files=("hadoop-env.sh" "core-site.xml" "hdfs-site.xml" "mapred-site.xml" "yarn-site.xml")
    local total=${#config_files[@]}
    
    # hadoop-env.sh
    cat > "$HADOOP_CONF_DIR/hadoop-env.sh" <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export HADOOP_CONF_DIR=$HADOOP_CONF_DIR
export HADOOP_LOG_DIR=\${HADOOP_HOME}/logs
export HADOOP_OPTS="-Djava.net.preferIPv4Stack=true"
export HDFS_NAMENODE_USER="$USER"
export HDFS_DATANODE_USER="$USER"
export HDFS_SECONDARYNAMENODE_USER="$USER"
export YARN_RESOURCEMANAGER_USER="$USER"
export YARN_NODEMANAGER_USER="$USER"
EOF
    progress_bar 1 $total "Creating hadoop-env.sh"
    
    # core-site.xml
    cat > "$HADOOP_CONF_DIR/core-site.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:9000</value>
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>/home/USER_PLACEHOLDER/bigdata/hadoop/tmp</value>
    </property>
</configuration>
EOF
    sed -i "s|USER_PLACEHOLDER|$USER|g" "$HADOOP_CONF_DIR/core-site.xml"
    progress_bar 2 $total "Creating core-site.xml"
    
    # Create directories
    mkdir -p "$INSTALL_DIR/hadoop/dfs/namenode" "$INSTALL_DIR/hadoop/dfs/datanode" "$INSTALL_DIR/hadoop/tmp"
    
    # hdfs-site.xml
    cat > "$HADOOP_CONF_DIR/hdfs-site.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file:///home/USER_PLACEHOLDER/bigdata/hadoop/dfs/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file:///home/USER_PLACEHOLDER/bigdata/hadoop/dfs/datanode</value>
    </property>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>localhost:9870</value>
    </property>
    <property>
        <name>dfs.permissions.enabled</name>
        <value>false</value>
    </property>
</configuration>
EOF
    sed -i "s|USER_PLACEHOLDER|$USER|g" "$HADOOP_CONF_DIR/hdfs-site.xml"
    progress_bar 3 $total "Creating hdfs-site.xml"
    
    # mapred-site.xml
    cat > "$HADOOP_CONF_DIR/mapred-site.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.application.classpath</name>
        <value>/home/USER_PLACEHOLDER/bigdata/hadoop/share/hadoop/mapreduce/*:/home/USER_PLACEHOLDER/bigdata/hadoop/share/hadoop/mapreduce/lib/*</value>
    </property>
    <property>
        <name>yarn.app.mapreduce.am.env</name>
        <value>HADOOP_MAPRED_HOME=/home/USER_PLACEHOLDER/bigdata/hadoop</value>
    </property>
    <property>
        <name>mapreduce.map.env</name>
        <value>HADOOP_MAPRED_HOME=/home/USER_PLACEHOLDER/bigdata/hadoop</value>
    </property>
    <property>
        <name>mapreduce.reduce.env</name>
        <value>HADOOP_MAPRED_HOME=/home/USER_PLACEHOLDER/bigdata/hadoop</value>
    </property>
</configuration>
EOF
    sed -i "s|USER_PLACEHOLDER|$USER|g" "$HADOOP_CONF_DIR/mapred-site.xml"
    progress_bar 4 $total "Creating mapred-site.xml"
    
    # yarn-site.xml
    cat > "$HADOOP_CONF_DIR/yarn-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>localhost</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>${yarn_mem}</value>
    </property>
    <property>
        <name>yarn.nodemanager.vmem-check-enabled</name>
        <value>false</value>
    </property>
</configuration>
EOF
    progress_bar 5 $total "Creating yarn-site.xml"
    
    echo "localhost" > "$HADOOP_CONF_DIR/workers"
    
    mark_done "hadoop_config"
    echo -e "${GREEN}[OK] Hadoop configuration completed${NC}"
}

# Spark Installation
install_spark() {
    if is_done "spark_install"; then
        log "Spark already installed, skipping..."
        return
    fi
    
    step_header 5 11 "Spark 3.5.8 Installation"
    
    cd "$INSTALL_DIR"
    
    # Hardcoded Spark 3.5.8
    local SPARK_VERSION_ACTUAL="3.5.8"
    
    if [ ! -d "spark-${SPARK_VERSION_ACTUAL}-bin-hadoop3" ]; then
        rm -f "spark-${SPARK_VERSION_ACTUAL}-bin-hadoop3.tgz"
        
        # Direct hardcoded URL for Spark 3.5.8
    local SPARK_URL="https://downloads.apache.org/spark/spark-3.5.8/spark-3.5.8-bin-hadoop3.tgz"
        
        echo -e "${BLUE}->${NC}  Downloading: spark-3.5.8-bin-hadoop3.tgz"
        log "Using hardcoded URL: ${SPARK_URL}"
        
        local output="spark-${SPARK_VERSION_ACTUAL}-bin-hadoop3.tgz"
        
        # Download with progress
        echo -e "${CYAN}Downloading from Apache servers... (This process is slow and might look stuck, be patient)${NC}"
        
        if wget --progress=dot:giga --timeout=120 --tries=2 \
                --dns-timeout=30 --connect-timeout=60 --read-timeout=120 \
                -O "$output" "$SPARK_URL" 2>&1 | \
                grep --line-buffered "%" | \
                sed -u 's/\.//g' | \
                while IFS= read -r line; do
                    if [[ $line =~ ([0-9]+)% ]]; then
                        local percent="${BASH_REMATCH[1]}"
                        local filled=$((percent * PROGRESS_BAR_WIDTH / 100))
                        local empty=$((PROGRESS_BAR_WIDTH - filled))
                        
                        printf "\r${CYAN}[${NC}"
                        printf "%${filled}s" | tr ' ' '='
                        printf "%${empty}s" | tr ' ' '-'
                        printf "${CYAN}]${NC} ${percent}%%"
                    fi
                done; then
            
            printf "\n"
            
            local file_size
            file_size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null || echo 0)
            
            if [ "$file_size" -lt 1000000 ]; then
                error "Downloaded file too small. Check your internet connection."
            fi
            
            if ! tar -tzf "$output" >/dev/null 2>&1; then
                error "Downloaded file is corrupted. Please try again."
            fi
            
            echo -e "${GREEN}[OK]${NC} Downloaded: $(echo $file_size | awk '{print int($1/1024/1024)"MB"}')"
        else
            error "Failed to download Spark. Please check your internet connection."
        fi
        
        log "Extracting Spark..."
        (tar -xzf "spark-${SPARK_VERSION_ACTUAL}-bin-hadoop3.tgz") &
        spinner $! "Extracting Spark archive"
    fi
    
    rm -f spark
    ln -s "spark-${SPARK_VERSION_ACTUAL}-bin-hadoop3" spark
    
    # Setup Spark Env
    cp "$INSTALL_DIR/spark/conf/spark-env.sh.template" "$INSTALL_DIR/spark/conf/spark-env.sh" 2>/dev/null || touch "$INSTALL_DIR/spark/conf/spark-env.sh"
    
    cat >> "$INSTALL_DIR/spark/conf/spark-env.sh" <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_CONF_DIR=$INSTALL_DIR/hadoop/etc/hadoop
export SPARK_DIST_CLASSPATH=\$($INSTALL_DIR/hadoop/bin/hadoop classpath)
export YARN_CONF_DIR=$INSTALL_DIR/hadoop/etc/hadoop
export SPARK_MASTER=yarn
EOF
    
    cat > "$INSTALL_DIR/spark/conf/spark-defaults.conf" <<EOF
spark.master                     yarn
spark.submit.deployMode          client
spark.eventLog.enabled           true
spark.eventLog.dir               hdfs://localhost:9000/spark-logs
spark.history.fs.logDirectory    hdfs://localhost:9000/spark-logs
EOF
    
    mark_done "spark_install"
    echo -e "${GREEN}[OK] Spark 3.5.8 installed successfully${NC}"
}

# Kafka Installation
install_kafka() {
    if is_done "kafka_install"; then
        log "Kafka already installed, skipping..."
        return
    fi
    
    step_header 6 11 "Kafka ${KAFKA_VERSION} Installation"
    
    if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
        export JAVA_17_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    else
        error "Java 17 not found! Cannot install Kafka. Install with: sudo apt-get install -y openjdk-17-jdk"
    fi
    
    log "Using Java 17 for Kafka: $JAVA_17_HOME"
    
    cd "$INSTALL_DIR"
    local kafka_scala="2.13"
    
    if [ ! -d "kafka_${kafka_scala}-${KAFKA_VERSION}" ]; then
        rm -f "kafka_${kafka_scala}-${KAFKA_VERSION}.tgz"
        
        download_with_retry \
            "https://dlcdn.apache.org/kafka/${KAFKA_VERSION}/kafka_${kafka_scala}-${KAFKA_VERSION}.tgz" \
            "kafka_${kafka_scala}-${KAFKA_VERSION}.tgz"
        
        log "Extracting Kafka..."
        (tar -xzf "kafka_${kafka_scala}-${KAFKA_VERSION}.tgz") &
        spinner $! "Extracting Kafka archive"
    fi
    
    rm -f kafka
    ln -s "kafka_${kafka_scala}-${KAFKA_VERSION}" kafka
    mkdir -p "$INSTALL_DIR/kafka/kraft-logs"
    
    log "Configuring Kafka KRaft mode..."
    local kafka_cluster_id
    if [ -f "$INSTALL_DIR/kafka/.cluster-id" ]; then
        kafka_cluster_id=$(cat "$INSTALL_DIR/kafka/.cluster-id")
        log "Using existing Kafka cluster ID: $kafka_cluster_id"
    else
        kafka_cluster_id=$(JAVA_HOME="$JAVA_17_HOME" "$INSTALL_DIR/kafka/bin/kafka-storage.sh" random-uuid)
        echo "$kafka_cluster_id" > "$INSTALL_DIR/kafka/.cluster-id"
        log "Generated new Kafka cluster ID: $kafka_cluster_id"
    fi
    
    cat > "$INSTALL_DIR/kafka/config/kraft-server.properties" <<EOF
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@localhost:9093
listeners=PLAINTEXT://localhost:9092,CONTROLLER://localhost:9093
advertised.listeners=PLAINTEXT://localhost:9092
controller.listener.names=CONTROLLER
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=$INSTALL_DIR/kafka/kraft-logs
num.partitions=1
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
EOF
    
    if [ ! -f "$INSTALL_DIR/kafka/kraft-logs/meta.properties" ]; then
        log "Formatting Kafka storage with Java 17..."
        
        JAVA_HOME="$JAVA_17_HOME" "$INSTALL_DIR/kafka/bin/kafka-storage.sh" format -t "$kafka_cluster_id" \
            -c "$INSTALL_DIR/kafka/config/kraft-server.properties"
    else
        log "Kafka storage already formatted, skipping..."
    fi
    
    # Create Kafka startup wrapper that uses Java 17
    log "Creating Kafka Java 17 wrapper..."
    cat > "$INSTALL_DIR/kafka/bin/kafka-server-start-java17.sh" <<'KAFKAWRAPPER'
#!/bin/bash
# Kafka startup wrapper - Forces Java 17

# Get Java 17 home
if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
elif [ -n "$JAVA_17_HOME" ]; then
    export JAVA_HOME="$JAVA_17_HOME"
else
    echo "Error: Java 17 not found!"
    exit 1
fi

export PATH="$JAVA_HOME/bin:$PATH"

# Run original Kafka startup
exec "$(dirname "$0")/kafka-server-start.sh" "$@"
KAFKAWRAPPER
    
    chmod +x "$INSTALL_DIR/kafka/bin/kafka-server-start-java17.sh"
    
    mark_done "kafka_install"
    echo -e "${GREEN}[OK] Kafka installed successfully${NC}"
}

# Pig Installation
install_pig() {
    if is_done "pig_install"; then
        log "Pig already installed, skipping..."
        return
    fi
    
    step_header 7 11 "Pig 0.17.0 Installation"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "pig-0.17.0" ]; then
        rm -f "pig-0.17.0.tar.gz"
        
        # Multiple mirrors for Pig 0.17.0
        local mirrors=(
            "https://dlcdn.apache.org/pig/pig-0.17.0/pig-0.17.0.tar.gz"
            "https://downloads.apache.org/pig/pig-0.17.0/pig-0.17.0.tar.gz"
            "https://archive.apache.org/dist/pig/pig-0.17.0/pig-0.17.0.tar.gz"
            "https://mirrors.estointernet.in/apache/pig/pig-0.17.0/pig-0.17.0.tar.gz"
        )
        
        local downloaded=false
        
        for mirror in "${mirrors[@]}"; do
            echo -e "${BLUE}->${NC}  Trying: $mirror"
            log "Attempting download from: $mirror"
            
            if wget --progress=bar:force --timeout=60 --tries=2 \
                    --connect-timeout=30 --read-timeout=60 \
                    -O "pig-0.17.0.tar.gz" "$mirror" 2>&1; then
                
                # Verify download
                if [ -f "pig-0.17.0.tar.gz" ] && [ $(stat -c%s "pig-0.17.0.tar.gz" 2>/dev/null || echo 0) -gt 1000000 ]; then
                    echo -e "${GREEN}[OK]${NC} Download successful!"
                    downloaded=true
                    break
                else
                    warn "Downloaded file is too small, trying next mirror..."
                    rm -f "pig-0.17.0.tar.gz"
                fi
            else
                warn "Mirror failed, trying next..."
                rm -f "pig-0.17.0.tar.gz"
            fi
            
            sleep 2
        done
        
        if [ "$downloaded" = false ]; then
            error "Failed to download Pig from all mirrors. Please check your internet connection."
        fi
        
        log "Extracting Pig..."
        (tar -xzf "pig-0.17.0.tar.gz") &
        spinner $! "Extracting Pig archive"
    fi
    
    rm -f pig
    ln -s "pig-0.17.0" pig
    
    mark_done "pig_install"
    echo -e "${GREEN}[OK] Pig 0.17.0 installed successfully${NC}"
}

# Hive Installation
install_hive() {
    if is_done "hive_install"; then
        log "Hive already installed, skipping..."
        return
    fi
    
    step_header 8 11 "Hive ${HIVE_VERSION} Installation"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "apache-hive-${HIVE_VERSION}-bin" ]; then
        rm -f "apache-hive-${HIVE_VERSION}-bin.tar.gz"
        
        local output="apache-hive-${HIVE_VERSION}-bin.tar.gz"
        local HIVE_URL="https://apache.root.lu/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz"
        
        echo -e "${BLUE}->${NC}  Downloading: apache-hive-${HIVE_VERSION}-bin.tar.gz"
        log "Using URL: ${HIVE_URL}"
        echo -e "${CYAN}Downloading from Apache servers...${NC}"
        
        # Simple wget with progress bar
        if wget --progress=bar:force --timeout=300 --tries=3 \
                --dns-timeout=30 --connect-timeout=60 --read-timeout=300 \
                -O "$output" "$HIVE_URL"; then
            
            local file_size
            file_size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null || echo 0)
            
            if [ "$file_size" -lt 1000000 ]; then
                error "Downloaded file too small. Check your internet connection."
            fi
            
            if ! tar -tzf "$output" >/dev/null 2>&1; then
                error "Downloaded file is corrupted. Please try again."
            fi
            
            echo -e "${GREEN}[OK]${NC} Downloaded: $(echo $file_size | awk '{print int($1/1024/1024)"MB"}')"
        else
            error "Failed to download Hive. Please check your internet connection."
        fi
        
        log "Extracting Hive..."
        tar -xzf "apache-hive-${HIVE_VERSION}-bin.tar.gz"
        echo -e "${GREEN}[OK]${NC} Extracted successfully"
    fi
    
    rm -f hive
    ln -s "apache-hive-${HIVE_VERSION}-bin" hive
    
    mark_done "hive_install"
    echo -e "${GREEN}[OK] Hive installed successfully${NC}"
}



configure_hive() {
    if is_done "hive_config"; then
        log "Hive already configured, skipping..."
        return
    fi
    
    step_header 9 11 "Hive Configuration"
    
    export HIVE_HOME="$INSTALL_DIR/hive"
    export HADOOP_HOME="$INSTALL_DIR/hadoop"
    
    log "Configuring MySQL for Hive metastore..."
    
    # Ensure MySQL is running
    if ! pgrep -x mysqld >/dev/null; then
        log "Starting MySQL service..."
        
        # WSL Fix: Ensure mysql-server is actually installed
        if ! dpkg -l | grep -q "mysql-server" || ! command -v mysqld >/dev/null; then
             warn "MySQL server appears to be missing. Installing..."
             sudo apt-get update -qq
             sudo apt-get install -y mysql-server -qq
        fi
        
        # WSL Fix: Ensure MySQL runtime directory exists
        if [ ! -d "/var/run/mysqld" ]; then
            log "Creating missing /var/run/mysqld directory..."
            sudo mkdir -p /var/run/mysqld
            sudo chown mysql:mysql /var/run/mysqld
        fi
        
        # WSL Fix: Ensure mysql user has a home directory (fixes some startup issues)
        sudo usermod -d /var/lib/mysql mysql 2>/dev/null || true
        
        # Try service command
        if sudo service mysql start 2>/dev/null; then
             echo -e "${GREEN}-------${NC} MySQL started successfully"
        elif sudo /etc/init.d/mysql start 2>/dev/null; then
             echo -e "${GREEN}-------${NC} MySQL started via init.d"
        else
            warn "Standard service start failed, trying to initialize directories and retry..."
            
            # Attempt to initialize directories if they are missing
            sudo mysqld --initialize-insecure --user=mysql 2>/dev/null || true
            
            if sudo service mysql start 2>/dev/null; then
                echo -e "${GREEN}-------${NC} MySQL started after initialization"
            else
                # Fallback to direct mysqld start
                warn "Still failing, trying direct mysqld execution..."
                sudo mysqld --user=mysql --daemonize --pid-file=/var/run/mysqld/mysqld.pid 2>/dev/null || true
            fi
        fi
        
        sleep 5
        
        # Final verification
        if ! pgrep -x mysqld >/dev/null; then
             # One last desperate attempt - manually safe start
             sudo mysqld_safe --skip-grant-tables &
             sleep 5
             
             if ! pgrep -x mysqld >/dev/null; then
                error "Failed to start MySQL. 
    Try manually: 
    1. sudo mkdir -p /var/run/mysqld && sudo chown mysql:mysql /var/run/mysqld
    2. sudo service mysql start"
             fi
        fi
    else
        echo -e "${GREEN}[OK]${NC} MySQL already running"
    fi
    
    # Wait for MySQL to be fully ready
    log "Waiting for MySQL to be ready..."
    local mysql_ready=false
    for i in {1..30}; do
        if sudo mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
            mysql_ready=true
            echo -e "${GREEN}-------${NC} MySQL is ready"
            break
        fi
        sleep 1
    done
    
    if [ "$mysql_ready" = false ]; then
        error "MySQL didn't become ready in time"
    fi
    
    log "Creating Hive metastore database..."
    if ! sudo mysql -u root <<MYSQL_SCRIPT 2>/dev/null; then
CREATE DATABASE IF NOT EXISTS metastore;
CREATE USER IF NOT EXISTS 'hiveuser'@'localhost' IDENTIFIED BY 'hivepassword';
GRANT ALL PRIVILEGES ON metastore.* TO 'hiveuser'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
        error "Failed to create Hive database. Check MySQL connection."
    fi

    
    echo -e "${GREEN}-------${NC} Metastore database created"
    
    log "Downloading MySQL JDBC connector..."
    cd "$HIVE_HOME/lib"
    if [ ! -f "mysql-connector-java-8.0.30.jar" ]; then
        wget -q https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.30/mysql-connector-java-8.0.30.jar
    fi
    
    rm -f "$HIVE_HOME/lib/guava-19.0.jar" 2>/dev/null || true
    cp "$HADOOP_HOME/share/hadoop/common/lib/guava-"*.jar "$HIVE_HOME/lib/" 2>/dev/null || true
    
    log "Creating Hive configuration files..."
    mkdir -p "$HIVE_HOME/conf"
    
    cat > "$HIVE_HOME/conf/hive-site.xml" <<'HIVESITE'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:mysql://localhost:3306/metastore?createDatabaseIfNotExist=true&amp;useSSL=false</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>com.mysql.cj.jdbc.Driver</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>hiveuser</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>hivepassword</value>
    </property>
    <property>
        <name>hive.metastore.warehouse.dir</name>
        <value>/user/hive/warehouse</value>
    </property>
    <property>
        <name>hive.metastore.uris</name>
        <value>thrift://localhost:9083</value>
    </property>
    <property>
        <name>hive.server2.thrift.port</name>
        <value>10000</value>
    </property>
    <property>
        <name>hive.server2.thrift.bind.host</name>
        <value>localhost</value>
    </property>
    <property>
        <name>hive.server2.enable.doAs</name>
        <value>false</value>
    </property>
    <property>
        <name>hive.metastore.schema.verification</name>
        <value>false</value>
    </property>
    <property>
        <name>datanucleus.schema.autoCreateAll</name>
        <value>true</value>
    </property>
    <property>
        <name>hive.exec.scratchdir</name>
        <value>/tmp/hive</value>
    </property>
</configuration>
HIVESITE
    
    cat > "$HIVE_HOME/conf/hive-env.sh" <<EOF
export HADOOP_HOME=$HADOOP_HOME
export HIVE_CONF_DIR=$HIVE_HOME/conf
export HIVE_AUX_JARS_PATH=$HIVE_HOME/lib
EOF
    
    chmod +x "$HIVE_HOME/conf/hive-env.sh"
    
    mark_done "hive_config"
    echo -e "${GREEN}[OK] Hive configured successfully${NC}"
}


# Environment Setup
setup_environment() {
    if is_done "env_setup"; then
        log "Environment already configured, skipping..."
        return
    fi
    
    step_header 10 11 "Environment Configuration"
    
    export HADOOP_HOME="$INSTALL_DIR/hadoop"
    export SPARK_HOME="$INSTALL_DIR/spark"
    export KAFKA_HOME="$INSTALL_DIR/kafka"
    export PIG_HOME="$INSTALL_DIR/pig"
    export HIVE_HOME="$INSTALL_DIR/hive"
    
    # Ensure Java 17 is available for Kafka
    if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
        export JAVA_17_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    fi
    
    if ! grep -q "HADOOP_HOME" "$HOME/.bashrc"; then
        log "Adding environment variables to .bashrc..."
        cat >> "$HOME/.bashrc" <<'BASHRC_EOF'

# Hadoop Ecosystem Environment
export HADOOP_HOME=$HOME/bigdata/hadoop
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export SPARK_HOME=$HOME/bigdata/spark
export KAFKA_HOME=$HOME/bigdata/kafka
export PIG_HOME=$HOME/bigdata/pig
export HIVE_HOME=$HOME/bigdata/hive

# Java Configuration
# Java 11 for Hadoop ecosystem
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

# Java 17 for Kafka
export JAVA_17_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Add tool directories to PATH
export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$KAFKA_HOME/bin:$PIG_HOME/bin:$HIVE_HOME/bin:$PATH

# Wrapper functions for Kafka (needs Java 17)

kafka-topics() {
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 PATH=/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH kafka-topics.sh "$@"
}

kafka-console-producer() {
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 PATH=/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH kafka-console-producer.sh "$@"
}

kafka-console-consumer() {
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 PATH=/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH kafka-console-consumer.sh "$@"
}

kafka-server-start() {
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 PATH=/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH kafka-server-start.sh "$@"
}

kafka-server-stop() {
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 PATH=/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH kafka-server-stop.sh "$@"
}

kafka-configs() {
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 PATH=/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH kafka-configs.sh "$@"
}

kafka-consumer-groups() {
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 PATH=/usr/lib/jvm/java-17-openjdk-amd64/bin:$PATH kafka-consumer-groups.sh "$@"
}

# Export functions so they're available in subshells
export -f kafka-topics kafka-console-producer kafka-console-consumer kafka-server-start kafka-server-stop kafka-configs kafka-consumer-groups
BASHRC_EOF
fi
    
    mark_done "env_setup"
    echo -e "${GREEN}[OK] Environment configured${NC}"
}


# HDFS Format
format_hdfs() {
    if is_done "hdfs_format"; then
        log "HDFS already formatted, skipping..."
        return
    fi
    
    step_header 11 11 "HDFS Initialization"
    
    export HADOOP_HOME="${HADOOP_HOME:-$INSTALL_DIR/hadoop}"
    
    log "Testing SSH connectivity..."
    (ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 localhost exit) &
    spinner $! "Testing SSH"
    
    log "Formatting HDFS NameNode..."
    ("$HADOOP_HOME/bin/hdfs" namenode -format -force -nonInteractive) &
    spinner $! "Formatting HDFS NameNode"
    
    mark_done "hdfs_format"
    echo -e "${GREEN}[OK] HDFS formatted successfully${NC}"
}

# Helper Scripts
create_helper_scripts() {
    if is_done "helper_scripts"; then
        log "Helper scripts already created, skipping..."
        return
    fi
    
    log "Creating service management scripts..."
    
    # Start script
    cat > "$HOME/start-hadoop.sh" <<STARTSCRIPT
#!/bin/bash
set -e

INSTALL_DIR="$INSTALL_DIR"

echo -e "\033[0;32mStarting Hadoop Ecosystem...\033[0m"
echo ""

# Start MySQL
if ! pgrep -x mysqld > /dev/null; then
    echo "Starting MySQL service..."
    sudo service mysql start
    sleep 2
fi

# Start SSH
if ! pgrep -x sshd > /dev/null; then
    echo "Starting SSH service..."
    sudo service ssh start
fi

# Start HDFS
if ! jps 2>/dev/null | grep -q "NameNode"; then
    echo "Starting HDFS..."
    "\$INSTALL_DIR/hadoop/sbin/start-dfs.sh"
    sleep 3
else
    echo "HDFS already running"
fi

# Start YARN
if ! jps 2>/dev/null | grep -q "ResourceManager"; then
    echo "Starting YARN..."
    "\$INSTALL_DIR/hadoop/sbin/start-yarn.sh"
    sleep 5
else
    echo "YARN already running"
fi

# Create user directory if it doesn't exist
if ! "\$INSTALL_DIR/hadoop/bin/hdfs" dfs -test -d /user/\$USER 2>/dev/null; then
    echo "Creating HDFS user directory..."
    "\$INSTALL_DIR/hadoop/bin/hdfs" dfs -mkdir -p /user/\$USER 2>/dev/null || true
    "\$INSTALL_DIR/hadoop/bin/hdfs" dfs -chmod 755 /user/\$USER 2>/dev/null || true
fi

# Create Hive warehouse directory
if ! "\$INSTALL_DIR/hadoop/bin/hdfs" dfs -test -d /user/hive/warehouse 2>/dev/null; then
    echo "Creating Hive warehouse directory..."
    "\$INSTALL_DIR/hadoop/bin/hdfs" dfs -mkdir -p /user/hive/warehouse 2>/dev/null || true
    "\$INSTALL_DIR/hadoop/bin/hdfs" dfs -mkdir -p /tmp/hive 2>/dev/null || true
    "\$INSTALL_DIR/hadoop/bin/hdfs" dfs -chmod 777 /user/hive/warehouse 2>/dev/null || true
    "\$INSTALL_DIR/hadoop/bin/hdfs" dfs -chmod 777 /tmp/hive 2>/dev/null || true
fi

# Start Hive Metastore
if ! pgrep -f "HiveMetaStore" > /dev/null; then
    echo "Starting Hive Metastore..."
    nohup "\$INSTALL_DIR/hive/bin/hive" --service metastore \\
        > "\$INSTALL_DIR/hive/metastore.log" 2>&1 &
    echo \$! > "\$INSTALL_DIR/hive/metastore.pid"
    sleep 3
else
    echo "Hive Metastore already running"
fi

# Start Kafka
if ! pgrep -f "kafka.Kafka" > /dev/null; then
    echo "Starting Kafka (with Java 17)..."
    nohup "\$INSTALL_DIR/kafka/bin/kafka-server-start-java17.sh" \\
        "\$INSTALL_DIR/kafka/config/kraft-server.properties" \\
        > "\$INSTALL_DIR/kafka/kafka.log" 2>&1 &
    echo \$! > "\$INSTALL_DIR/kafka/kafka.pid"
    sleep 3
else
    echo "Kafka already running"
fi

echo ""
echo -e "\033[0;32m[OK] Services started\033[0m"
echo ""
echo "Web UIs:"
echo "  HDFS:    http://localhost:9870"
echo "  YARN:    http://localhost:8088"
echo ""
STARTSCRIPT

    # Stop script
    cat > "$HOME/stop-hadoop.sh" <<STOPSCRIPT
#!/bin/bash

INSTALL_DIR="$INSTALL_DIR"

echo -e "\033[0;33mStopping Hadoop Ecosystem...\033[0m"
echo ""

"\$INSTALL_DIR/hadoop/sbin/stop-yarn.sh" 2>/dev/null || true
"\$INSTALL_DIR/hadoop/sbin/stop-dfs.sh" 2>/dev/null || true

if pgrep -f "HiveMetaStore" > /dev/null; then
    pkill -f HiveMetaStore
    rm -f "\$INSTALL_DIR/hive/metastore.pid"
fi

if pgrep -f "kafka.Kafka" > /dev/null; then
    pkill -f kafka.Kafka
    rm -f "\$INSTALL_DIR/kafka/kafka.pid"
fi

echo -e "\033[0;32m[OK] All services stopped\033[0m"
STOPSCRIPT

    # Check script
    cat > "$HOME/check-hadoop.sh" <<'CHECKSCRIPT'
#!/bin/bash

INSTALL_DIR="$INSTALL_DIR"

echo "Hadoop Status"
echo "============="
echo ""

echo "Java Processes:"
jps 2>/dev/null || echo "jps not found"

echo ""
echo "Service Status:"
services=("NameNode:9870" "DataNode:9864" "ResourceManager:8088" "NodeManager:8042" "Kafka:9092" "HiveMetaStore:9083")
for service in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service"
    if nc -z localhost "$port" 2>/dev/null; then
        printf "  [OK] %-20s (port %s)\n" "$name" "$port"
    else
        printf "  [X]  %-20s (port %s)\n" "$name" "$port"
    fi
done

echo ""
echo "HDFS:"
"$INSTALL_DIR/hadoop/bin/hdfs" dfsadmin -report 2>/dev/null | head -10

echo ""
echo "Versions:"
echo "  Hadoop: $("$INSTALL_DIR/hadoop/bin/hadoop" version | head -1)"
echo "  Spark: $("$INSTALL_DIR/spark/bin/spark-submit" --version 2>&1 | grep version | head -1)"
[ -f "$INSTALL_DIR/kafka/.cluster-id" ] && echo "  Kafka: $(cat "$INSTALL_DIR/kafka/.cluster-id")"
CHECKSCRIPT

    # Restart script
    cat > "$HOME/restart-hadoop.sh" <<'RESTARTSCRIPT'
#!/bin/bash

echo "Restarting..."
~/stop-hadoop.sh
sleep 3
~/start-hadoop.sh
RESTARTSCRIPT

    chmod +x "$HOME/start-hadoop.sh"
    chmod +x "$HOME/stop-hadoop.sh"
    chmod +x "$HOME/check-hadoop.sh"
    chmod +x "$HOME/restart-hadoop.sh"
    
    mark_done "helper_scripts"
    echo -e "${GREEN}[OK] Helper scripts created${NC}"
}

# Start Services
start_services() {
    step_header "Run" 11 "Starting Services"
    
    export HADOOP_HOME="${HADOOP_HOME:-$INSTALL_DIR/hadoop}"
    export HADOOP_CONF_DIR="${HADOOP_CONF_DIR:-$HADOOP_HOME/etc/hadoop}"
    export KAFKA_HOME="${KAFKA_HOME:-$INSTALL_DIR/kafka}"
    
    log "Stopping any existing services..."
    (safe_exec "$HADOOP_HOME/sbin/stop-dfs.sh" 2>/dev/null
     safe_exec "$HADOOP_HOME/sbin/stop-yarn.sh" 2>/dev/null
     pkill -f "kafka.Kafka" 2>/dev/null || true) &
    spinner $! "Cleaning up old processes"
    sleep 3
    
    log "Starting HDFS..."
    ("$HADOOP_HOME/sbin/start-dfs.sh") &
    spinner $! "Starting NameNode and DataNode"
    sleep 3
    
    log "Starting YARN..."
    ("$HADOOP_HOME/sbin/start-yarn.sh") &
    spinner $! "Starting ResourceManager and NodeManager"
    sleep 5
    
    log "Waiting for HDFS to exit safe mode..."
    local max_wait=60
    local safemode_exited=false
    
    for i in $(seq 1 $max_wait); do
        if "$HADOOP_HOME/bin/hdfs" dfsadmin -safemode get 2>/dev/null | grep -q "OFF"; then
            progress_bar $max_wait $max_wait "HDFS ready"
            safemode_exited=true
            break
        fi
        progress_bar $i $max_wait "Waiting for safe mode"
        sleep 1
    done
    
    if [ "$safemode_exited" = false ]; then
        warn "HDFS safe mode timeout after ${max_wait}s - forcing exit"
        "$HADOOP_HOME/bin/hdfs" dfsadmin -safemode leave 2>/dev/null || true
        sleep 2
    fi
    
    log "Creating Spark directory..."
    sleep 2
    
    local retries=3
    for attempt in $(seq 1 $retries); do
        if "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /spark-logs 2>/dev/null; then
            "$HADOOP_HOME/bin/hdfs" dfs -chmod 777 /spark-logs 2>/dev/null || true
            echo -e "${GREEN}[OK]${NC} Spark directory created"
            break
        else
            if [ $attempt -lt $retries ]; then
                sleep 2
            else
                warn "Failed to create /spark-logs directory - will retry on next start"
            fi
        fi
    done

    log "Creating Hive warehouse directory..."
    sleep 1

    for attempt in $(seq 1 3); do
        if "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/hive/warehouse 2>/dev/null; then
            "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /tmp/hive 2>/dev/null || true
            "$HADOOP_HOME/bin/hdfs" dfs -chmod 777 /user/hive/warehouse 2>/dev/null || true
            "$HADOOP_HOME/bin/hdfs" dfs -chmod 777 /tmp/hive 2>/dev/null || true
            echo -e "${GREEN}[OK]${NC} Hive directories created"
            break
        else
            if [ $attempt -lt 3 ]; then
                sleep 2
            fi
        fi
    done

    log "Initializing Hive Metastore schema..."
    if ! "$INSTALL_DIR/hive/bin/schematool" -dbType mysql -info 2>/dev/null | grep -q "schemaTool completed"; then
        "$INSTALL_DIR/hive/bin/schematool" -dbType mysql -initSchema 2>/dev/null || true
    fi

    log "Starting Hive Metastore..."
    nohup "$INSTALL_DIR/hive/bin/hive" --service metastore \
        > "$INSTALL_DIR/hive/metastore.log" 2>&1 &
    metastore_pid=$!
    echo $metastore_pid > "$INSTALL_DIR/hive/metastore.pid"
    echo -e "${GREEN}-------${NC} Starting Hive Metastore... ${GREEN}Done${NC}"
    sleep 2

    log "Creating user HDFS directory..."
    sleep 1
    
    # Create user directory in HDFS
    for attempt in $(seq 1 3); do
        if "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/$USER 2>/dev/null; then
            "$HADOOP_HOME/bin/hdfs" dfs -chmod 755 /user/$USER 2>/dev/null || true
            echo -e "${GREEN}[OK]${NC} User directory /user/$USER created"
            break
        else
            if [ $attempt -lt 3 ]; then
                sleep 2
            else
                warn "Failed to create /user/$USER directory - create manually with: hdfs dfs -mkdir -p /user/$USER"
            fi
        fi
    done
    
    log "Starting Kafka..."
    
    # Ensure Java 17 is set for Kafka
    if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
        KAFKA_JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    else
        KAFKA_JAVA_HOME="${JAVA_17_HOME:-$JAVA_HOME}"
    fi
    
    # Start Kafka in background
    JAVA_HOME="$KAFKA_JAVA_HOME" nohup "$KAFKA_HOME/bin/kafka-server-start-java17.sh" \
        "$KAFKA_HOME/config/kraft-server.properties" \
        > "$INSTALL_DIR/kafka/kafka.log" 2>&1 &
    
    kafka_pid=$!
    echo $kafka_pid > "$INSTALL_DIR/kafka/kafka.pid"
    
    echo -e "${GREEN}-------${NC} Starting Kafka broker... ${GREEN}Done${NC}"
    
    # Wait and verify Kafka started
    sleep 3
    if ! kill -0 $kafka_pid 2>/dev/null; then
        warn "Kafka may have failed to start - check $INSTALL_DIR/kafka/kafka.log"
    fi
    
    echo -e "${GREEN}------- All services started successfully${NC}"
}


# Verification
verify_installation() {
    echo ""
    step_header "Final" "Final" "Installation Verification"

    export HADOOP_HOME="${HADOOP_HOME:-$INSTALL_DIR/hadoop}"
    export HADOOP_CONF_DIR="${HADOOP_CONF_DIR:-$HADOOP_HOME/etc/hadoop}"
    
    echo -e "${BOLD}Running Processes:${NC}"
    jps 2>/dev/null || warn "jps failed"
    echo ""
    
    echo -e "${BOLD}Service Health Check:${NC}"
    local services=("NameNode:9870" "DataNode:9864" "ResourceManager:8088" "NodeManager:8042" "Kafka:9092" "HiveMetaStore:9083")
    for service in "${services[@]}"; do
        IFS=':' read -r name port <<< "$service"
        if nc -z localhost "$port" 2>/dev/null; then
            echo -e "  ${GREEN}-------${NC} $name (port $port)"
        else
            echo -e "  ${RED}-------${NC} $name (port $port)"
        fi
    done
    echo ""
    
    echo -e "${BOLD}HDFS Status:${NC}"
    safe_exec "$HADOOP_HOME/bin/hdfs" dfsadmin -report 2>&1 | head -10
    echo ""
    
    echo -e "${BOLD}YARN Status:${NC}"
    safe_exec "$HADOOP_HOME/bin/yarn" node -list
    echo ""
}

# Guide
print_guide() {    
    cat <<EOF
${BOLD}${YELLOW}Quick Start Commands:${NC}

  ${CYAN}~/start-hadoop.sh${NC}     # Start all services
  ${CYAN}~/stop-hadoop.sh${NC}      # Stop all services
  ${CYAN}~/check-hadoop.sh${NC}     # Check status
  ${CYAN}~/restart-hadoop.sh${NC}   # Restart services

${BOLD}${YELLOW}Web UIs:${NC}
  HDFS:    ${CYAN}http://localhost:9870${NC}
  YARN:    ${CYAN}http://localhost:8088${NC}

${BOLD}${YELLOW}Quick Tests:${NC}

  ${CYAN}# HDFS${NC}
  hdfs dfs -ls /
  hdfs dfs -put file.txt /user/$USER/

  ${CYAN}# MapReduce${NC}
  hadoop jar \$HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 2 10

  ${CYAN}# Spark${NC}
  spark-shell --master yarn
  pyspark --master yarn

  ${CYAN}# Kafka${NC}
  kafka-topics.sh --create --topic test --bootstrap-server localhost:9092

  ${CYAN}# Hive${NC}
  hive
  beeline -u jdbc:hive2://localhost:10000

${BOLD}${YELLOW}Next Steps:${NC}
  1. ${CYAN}source ~/.bashrc${NC}
  2. ${CYAN}~/start-hadoop.sh${NC}
  3. Visit web UIs above

${BOLD}${YELLOW}Installation Details:${NC}
  Location: ${CYAN}$INSTALL_DIR${NC}
  Log file: ${CYAN}$LOG_FILE${NC}

EOF
}

# Main
main() {
    preflight_checks
    
    log "Starting installation..."
    
    acquire_lock
    check_disk_space
    
    setup_system
    setup_java
    install_hadoop
    configure_hadoop
    install_spark
    install_kafka
    install_pig
    install_hive
    configure_hive
    setup_environment
    format_hdfs
    create_helper_scripts
    start_services
    
    verify_installation
    print_guide
    
    echo ""
    echo -e "${BOLD}${GREEN}-----------------Installation Successfully Completed!-----------------${NC}"
    echo ""
    echo -e "   ${CYAN}[Dev] Crafted by  :${NC} ${BOLD}Darshan Gowda${NC}"
    echo -e "   ${CYAN}[Link] GitHub     :${NC} ${BLUE}https://github.com/darshangowdaa${NC}"
    echo ""
    echo -e "   ${YELLOW}-> Action Needed:${NC} Run  | ${BOLD}source ~/.bashrc${NC} | and restart the terminal."
}

main