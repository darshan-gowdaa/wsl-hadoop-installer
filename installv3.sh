#!/bin/bash

# WSL Hadoop Ecosystem - Interactive Menu Installer v3 (Optimized)
# by github.com/darshan-gowdaa

set -Ee

# Configuration
INSTALL_DIR="$HOME/bigdata"
HADOOP_VERSION="3.4.2"
SPARK_VERSION="3.5.8"
KAFKA_VERSION="4.1.1"
PIG_VERSION="0.17.0"
HIVE_VERSION="3.1.3"

STATE_FILE="$HOME/.hadoop_install_state"
LOG_FILE="$HOME/hadoop_install.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ==================== UTILITY FUNCTIONS ====================

log() { echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}✗${NC} $1" >&2; exit 1; }
success() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${CYAN}○${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

mark_done() { is_done "$1" || echo "$1" >> "$STATE_FILE"; }
is_done() { [ -f "$STATE_FILE" ] && grep -Fxq "$1" "$STATE_FILE" 2>/dev/null; }

skip_if_installed() {
    local component=$1
    local message=$2
    if is_done "$component"; then
        info "$message already installed"
        return 0
    fi
    return 1
}

configure_dns_server() {
    local dns_name=$1
    local primary_dns=$2
    local secondary_dns=$3
    
    check_and_update() {
        if timeout 2 ping -c 1 "$1" &>/dev/null; then
            printf "nameserver %s\nnameserver %s\n" "$1" "$2" | sudo tee /etc/resolv.conf > /dev/null
            sudo chattr +i /etc/resolv.conf 2>/dev/null || true
            return 0
        fi
        return 1
    }

    if execute_with_spinner "Configuring $dns_name DNS ($primary_dns)" check_and_update "$primary_dns" "$secondary_dns"; then
        success "DNS Configured: $dns_name"
        return 0
    fi
    return 1
}

check_java_version() {
    local version=$1
    local java_path="/usr/lib/jvm/java-$version-openjdk-amd64"
    [ -d "$java_path" ] || error "Java $version not found. Install with: sudo apt-get install -y openjdk-$version-jdk"
}

ensure_service_running() {
    local service_name=$1
    local process_name=$2
    local warn_msg=$3
    
    if ! pgrep -x "$process_name" >/dev/null; then
        if [ "$service_name" = "mysql" ]; then
            sudo mkdir -p /var/run/mysqld 2>/dev/null || true
            sudo chown mysql:mysql /var/run/mysqld 2>/dev/null || true
        fi
        
        if ! sudo service "$service_name" start &>/dev/null; then
            [ -n "$warn_msg" ] && warn "$warn_msg" || warn "$service_name service failed to start"
            return 1
        else
            success "$service_name service started"
        fi
    fi
    return 0
}

setup_hdfs_directories() {
    info "Creating HDFS directories..."
    "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/$USER /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null || true
    "$HADOOP_HOME/bin/hdfs" dfs -chmod 777 /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null || true
}

check_service_port() {
    local name=$1
    local port=$2
    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name (port $port)"
    else
        echo -e "  ${RED}✗${NC} $name (port $port)"
    fi
}

run_install_workflow() {
    local component_name=$1
    shift
    "$@"
    success "$component_name installed"
    echo -e "Run: ${CYAN}source ~/.bashrc${NC}"
    read -p "Press Enter to continue..."
}

safe_execute() {
    if "$@" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
        return 0
    else
        warn "Non-critical error in: $*"
        return 0
    fi
}

spinner() {
    local pid=$1
    local msg=$2
    local sp='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        printf "\r${CYAN}${sp:$i:1}${NC} %s..." "$msg"
        i=$(( (i + 1) % 10 ))
        sleep 0.1
    done
    
    wait $pid
    local code=$?
    [ $code -eq 0 ] && printf "\r${GREEN}✓${NC} %s\n" "$msg" || printf "\r${RED}✗${NC} %s\n" "$msg"
    return $code
}

execute_with_spinner() {
    local msg=$1
    shift
    (
        set +e
        "$@" &>/dev/null
        exit $?
    ) & 
    spinner $! "$msg"
    return $?
}

download_file() {
    local url=$1
    local output=$2
    local mirrors=(
        "$url"
        "https://dlcdn.apache.org/$(echo "$url" | sed 's|https://[^/]*/||')"
        "https://archive.apache.org/dist/$(echo "$url" | sed 's|https://[^/]*/||')"
    )
    
    info "Downloading $(basename $output)..."
    
    for mirror in "${mirrors[@]}"; do
        log "Trying mirror: $mirror"
        if wget --progress=bar:force --timeout=60 --tries=2 -O "$output" "$mirror" 2>&1; then
            local filesize=$(stat -c%s "$output" 2>/dev/null || echo 0)
            if [ -f "$output" ] && [ "$filesize" -gt 1000000 ]; then
                success "Download complete"
                return 0
            fi
        fi
        rm -f "$output"
        warn "Mirror failed, trying next..."
    done
    
    error "All download mirrors failed for $(basename $output)"
    return 1
}

# ==================== PRE-FLIGHT CHECKS ====================

check_command() {
    command -v "$1" &>/dev/null || error "$1 not found. Install with: sudo apt-get install -y $2"
}

preflight_checks() {
    clear
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${MAGENTA}             Hadoop Ecosystem Installer v3              ${NC}"
    echo -e "${BLUE}               github.com/darshan-gowdaa                ${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
    
    # Check sudo first
    if ! sudo -n true 2>/dev/null; then
        info "Sudo access required for installation. Please enter password:"
        sudo -v || error "Sudo authentication failed"
    fi

    # Configure DNS with intelligent fallback
    info "Configuring DNS servers..."
    
    if ! configure_dns_server "Cloudflare" "1.1.1.1" "1.0.0.1" && \
       ! configure_dns_server "Google" "8.8.8.8" "8.8.4.4"; then
        warn "External DNS servers blocked - using default college/network DNS"
        sudo chattr -i /etc/resolv.conf 2>/dev/null || true
        info "DNS will be auto-configured by WSL"
    fi
    
    # Check required commands
    info "Checking system requirements..."
    check_command "wget" "wget"
    check_command "tar" "tar"
    check_command "ssh" "openssh-server"
    check_command "awk" "gawk"
    check_command "nc" "netcat-openbsd"
    
    # Check WSL
    if ! grep -qi microsoft /proc/version 2>/dev/null; then
        warn "Not running on WSL. Some features may not work optimally."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    fi
    
    # Check WSL2
    if ! grep -q "WSL2" /proc/version 2>/dev/null; then
        echo -e "${YELLOW}WARNING: WSL1 detected. Performance will be poor.${NC}"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    fi
    
    # Check location
    local current_path=$(readlink -f "$PWD")
    if [[ "$current_path" == /mnt/* ]]; then
        error "Cannot run from Windows filesystem (/mnt/). Run from Linux home: cd ~ && ./install.sh"
    fi
    
    # Check memory
    local mem_gb=$(free -m 2>/dev/null | awk '/^Mem:/{print int($2/1024)}')
    if [ -z "$mem_gb" ] || [ "$mem_gb" -lt 4 ]; then
        warn "Low memory detected (${mem_gb}GB). Minimum 6GB recommended."
    fi
    
    # Check disk space
    local avail_gb=$(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")
    if [ "$avail_gb" -lt 12 ]; then
        error "Insufficient disk space. Need 12GB+, available: ${avail_gb}GB"
    fi
    
    success "Pre-flight checks passed"
    sleep 1
}

# ==================== INSTALLATION FUNCTIONS ====================

install_system_deps() {
    skip_if_installed "system_setup" "System dependencies" && return
    
    echo -e "\n${BOLD}Installing System Dependencies${NC}"
    
    if ! execute_with_spinner "Updating package lists" sudo apt-get update -qq; then
        warn "Package update had warnings, continuing..."
    fi
    
    local pkgs=(openjdk-11-jdk openjdk-17-jdk wget ssh netcat-openbsd vim mysql-server rsync)
    if ! execute_with_spinner "Installing packages" sudo apt-get install -y "${pkgs[@]}" -qq; then
        error "Package installation failed. Check your internet connection and try again."
    fi
    
    # Verify Java installation
    check_java_version 11
    check_java_version 17
    
    safe_execute sudo update-alternatives --set java /usr/lib/jvm/java-11-openjdk-amd64/bin/java
    
    # SSH setup with error checking
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        mkdir -p "$HOME/.ssh"
        if ! ssh-keygen -t rsa -P '' -f "$HOME/.ssh/id_rsa" -q &>/dev/null; then
            error "SSH key generation failed"
        fi
        cat "$HOME/.ssh/id_rsa.pub" >> "$HOME/.ssh/authorized_keys"
    fi
    
    # Consolidated SSH permissions
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/{id_rsa,authorized_keys,config} 2>/dev/null || true
    chmod 644 ~/.ssh/id_rsa.pub 2>/dev/null || true
    
    # SSH config
    cat > ~/.ssh/config <<'EOF'
Host localhost 127.0.0.1 0.0.0.0
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
    chmod 600 ~/.ssh/config
    
    # Start services with checks
    ensure_service_running "ssh" "sshd" "SSH service failed to start"
    ensure_service_running "mysql" "mysqld" "Hive installation will fail without MySQL. To fix manually run: sudo service mysql start"
    
    # IPv6 fix
    if ! grep -q "disable_ipv6" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf >/dev/null
        sudo sysctl -p >/dev/null 2>&1 || true
    fi
    
    mark_done "system_setup"
    success "System dependencies installed"
}

install_hadoop() {
    skip_if_installed "hadoop_full" "Hadoop" && return
    
    echo -e "\n${BOLD}Installing Hadoop ${HADOOP_VERSION}${NC}"
    
    # Verify Java 11 exists
    check_java_version 11
    
    mkdir -p "$INSTALL_DIR" && cd "$INSTALL_DIR"
    
    if [ ! -d "hadoop-${HADOOP_VERSION}" ]; then
        download_file \
            "https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" \
            "hadoop.tgz" || error "Hadoop download failed"
        
        execute_with_spinner "Extracting Hadoop" tar -xzf hadoop.tgz
        rm hadoop.tgz
    fi
    
    rm -f hadoop && ln -s "hadoop-${HADOOP_VERSION}" hadoop
    
    # Configure
    export HADOOP_HOME="$INSTALL_DIR/hadoop"
    export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
    local conf="$HADOOP_HOME/etc/hadoop"
    
    # hadoop-env.sh
    cat > "$conf/hadoop-env.sh" <<EOF
export JAVA_HOME=$JAVA_HOME
export HADOOP_HOME=$HADOOP_HOME
export HDFS_NAMENODE_USER="$USER"
export HDFS_DATANODE_USER="$USER"
export YARN_RESOURCEMANAGER_USER="$USER"
export YARN_NODEMANAGER_USER="$USER"
EOF
    
    # core-site.xml
    cat > "$conf/core-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
    <property><name>fs.defaultFS</name><value>hdfs://localhost:9000</value></property>
    <property><name>hadoop.tmp.dir</name><value>$INSTALL_DIR/hadoop/tmp</value></property>
</configuration>
EOF
    
    # hdfs-site.xml
    mkdir -p "$INSTALL_DIR/hadoop/dfs/"{namenode,datanode,tmp}
    cat > "$conf/hdfs-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
    <property><name>dfs.replication</name><value>1</value></property>
    <property><name>dfs.namenode.name.dir</name><value>file://$INSTALL_DIR/hadoop/dfs/namenode</value></property>
    <property><name>dfs.datanode.data.dir</name><value>file://$INSTALL_DIR/hadoop/dfs/datanode</value></property>
    <property><name>dfs.permissions.enabled</name><value>false</value></property>
</configuration>
EOF
    
    # yarn-site.xml
    local yarn_mem=$(($(free -m | awk '/^Mem:/{print $2}') * 70 / 100))
    [ $yarn_mem -gt 4096 ] && yarn_mem=4096
    
    cat > "$conf/yarn-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
    <property><name>yarn.nodemanager.aux-services</name><value>mapreduce_shuffle</value></property>
    <property><name>yarn.resourcemanager.hostname</name><value>localhost</value></property>
    <property><name>yarn.nodemanager.resource.memory-mb</name><value>$yarn_mem</value></property>
    <property><name>yarn.nodemanager.vmem-check-enabled</name><value>false</value></property>
</configuration>
EOF
    
    # mapred-site.xml
    cat > "$conf/mapred-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
    <property><name>mapreduce.framework.name</name><value>yarn</value></property>
    <property><name>yarn.app.mapreduce.am.env</name><value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value></property>
    <property><name>mapreduce.map.env</name><value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value></property>
    <property><name>mapreduce.reduce.env</name><value>HADOOP_MAPRED_HOME=$HADOOP_HOME</value></property>
    <property><name>mapreduce.application.classpath</name><value>\$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:\$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*</value></property>
</configuration>
EOF
    
    echo "localhost" > "$conf/workers"
    
    # Format HDFS
    execute_with_spinner "Formatting HDFS" \
        "$HADOOP_HOME/bin/hdfs" namenode -format -force -nonInteractive
    
    mark_done "hadoop_full"
    success "Hadoop installed and configured"
}

install_spark() {
    skip_if_installed "spark_full" "Spark" && return
    
    echo -e "\n${BOLD}Installing Spark ${SPARK_VERSION}${NC}"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "spark-${SPARK_VERSION}-bin-hadoop3" ]; then
        download_file \
            "https://downloads.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz" \
            "spark.tgz" || error "Spark download failed"
        
        execute_with_spinner "Extracting Spark" tar -xzf spark.tgz
        rm spark.tgz
    fi
    
    rm -f spark && ln -s "spark-${SPARK_VERSION}-bin-hadoop3" spark
    
    # Configure
    cat > "$INSTALL_DIR/spark/conf/spark-env.sh" <<EOF
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_CONF_DIR=$INSTALL_DIR/hadoop/etc/hadoop
export SPARK_DIST_CLASSPATH=\$($INSTALL_DIR/hadoop/bin/hadoop classpath)
EOF
    
    cat > "$INSTALL_DIR/spark/conf/spark-defaults.conf" <<EOF
spark.master                     yarn
spark.eventLog.enabled           true
spark.eventLog.dir               hdfs://localhost:9000/spark-logs
EOF
    
    mark_done "spark_full"
    success "Spark installed and configured"
}

install_kafka() {
    skip_if_installed "kafka_full" "Kafka" && return
    
    echo -e "\n${BOLD}Installing Kafka ${KAFKA_VERSION}${NC}"
    
    # Verify Java 17 exists
    check_java_version 17
    
    cd "$INSTALL_DIR" || error "Cannot access $INSTALL_DIR"
    
    if [ ! -d "kafka_2.13-${KAFKA_VERSION}" ]; then
        if ! download_file \
            "https://dlcdn.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz" \
            "kafka.tgz"; then
            error "Kafka download failed after all retries"
        fi
        
        if ! execute_with_spinner "Extracting Kafka" tar -xzf kafka.tgz; then
            rm -f kafka.tgz
            error "Kafka extraction failed"
        fi
        rm kafka.tgz
    fi
    
    rm -f kafka && ln -s "kafka_2.13-${KAFKA_VERSION}" kafka
    mkdir -p "$INSTALL_DIR/kafka/kraft-logs"
    
    # Generate cluster ID
    local cid
    if [ -f "$INSTALL_DIR/kafka/.cluster-id" ]; then
        cid=$(cat "$INSTALL_DIR/kafka/.cluster-id")
    else
        cid=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 "$INSTALL_DIR/kafka/bin/kafka-storage.sh" random-uuid 2>/dev/null)
        if [ -z "$cid" ]; then
            error "Failed to generate Kafka cluster ID"
        fi
        echo "$cid" > "$INSTALL_DIR/kafka/.cluster-id"
    fi
    
    # Config
    cat > "$INSTALL_DIR/kafka/config/kraft-server.properties" <<EOF
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@localhost:9093
listeners=PLAINTEXT://localhost:9092,CONTROLLER://localhost:9093
controller.listener.names=CONTROLLER
log.dirs=$INSTALL_DIR/kafka/kraft-logs
num.partitions=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
EOF
    
    # Format storage
    if [ ! -f "$INSTALL_DIR/kafka/kraft-logs/meta.properties" ]; then
        if ! JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
            "$INSTALL_DIR/kafka/bin/kafka-storage.sh" format -t "$cid" \
            -c "$INSTALL_DIR/kafka/config/kraft-server.properties" &>/dev/null; then
            warn "Kafka storage format had warnings"
        fi
    fi
    
    mark_done "kafka_full"
    success "Kafka installed and configured"
}

install_pig() {
    skip_if_installed "pig_full" "Pig" && return
    
    echo -e "\n${BOLD}Installing Pig ${PIG_VERSION}${NC}"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "pig-${PIG_VERSION}" ]; then
        # Custom mirror logic for Pig (more reliable than generic download_file)
        local mirrors=(
            "https://archive.apache.org/dist/pig/pig-${PIG_VERSION}/pig-${PIG_VERSION}.tar.gz"
            "https://downloads.apache.org/pig/pig-${PIG_VERSION}/pig-${PIG_VERSION}.tar.gz"
        )
        
        local downloaded=false
        for mirror in "${mirrors[@]}"; do
            if wget --progress=bar:force --timeout=60 --tries=2 -O "pig.tgz" "$mirror"; then
                local filesize=$(stat -c%s "pig.tgz" 2>/dev/null || echo 0)
                if [ -f "pig.tgz" ] && [ "$filesize" -gt 1000000 ]; then
                    downloaded=true
                    break
                fi
            fi
        done
        
        if [ "$downloaded" = false ]; then
             error "Pig download failed"
        fi
        
        execute_with_spinner "Extracting Pig" tar -xzf pig.tgz
        rm pig.tgz
    fi
    
    rm -f pig && ln -s "pig-${PIG_VERSION}" pig
    
    mark_done "pig_full"
    success "Pig installed"
}

install_hive() {
    skip_if_installed "hive_full" "Hive" && return
    
    echo -e "\n${BOLD}Installing Hive ${HIVE_VERSION}${NC}"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "apache-hive-${HIVE_VERSION}-bin" ]; then
        download_file \
            "https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" \
            "hive.tgz" || error "Hive download failed"
        
        execute_with_spinner "Extracting Hive" tar -xzf hive.tgz
        rm hive.tgz
    fi
    
    rm -f hive && ln -s "apache-hive-${HIVE_VERSION}-bin" hive
    
    # MySQL setup - with proper error checking
    ensure_service_running "mysql" "mysqld" "MySQL is required for Hive. Run: sudo service mysql start" || \
        error "MySQL is required for Hive but failed to start"
    sleep 3
    
    sudo mysql -u root <<'SQL' 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS metastore;
CREATE USER IF NOT EXISTS 'hiveuser'@'localhost' IDENTIFIED BY 'hivepassword';
GRANT ALL PRIVILEGES ON metastore.* TO 'hiveuser'@'localhost';
FLUSH PRIVILEGES;
SQL
    
    # Download MySQL connector
    cd "$INSTALL_DIR/hive/lib"
    [ ! -f "mysql-connector-java-8.0.30.jar" ] && \
        wget -q https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.30/mysql-connector-java-8.0.30.jar
    
    # Config
    cat > "$INSTALL_DIR/hive/conf/hive-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
    <property><name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:mysql://localhost:3306/metastore?createDatabaseIfNotExist=true&amp;useSSL=false</value></property>
    <property><name>javax.jdo.option.ConnectionDriverName</name><value>com.mysql.cj.jdbc.Driver</value></property>
    <property><name>javax.jdo.option.ConnectionUserName</name><value>hiveuser</value></property>
    <property><name>javax.jdo.option.ConnectionPassword</name><value>hivepassword</value></property>
    <property><name>hive.metastore.uris</name><value>thrift://localhost:9083</value></property>
    <property><name>datanucleus.schema.autoCreateAll</name><value>true</value></property>
</configuration>
EOF
    
    mark_done "hive_full"
    success "Hive installed and configured"
}


configure_eclipse_user_library() {
    local eclipse_config="$HOME/.hadoop-eclipse-config"
    local prefs_file="$eclipse_config/.settings/org.eclipse.jdt.core.prefs"
    mkdir -p "$eclipse_config/.settings"

    info "Generating Eclipse User Library definition for Hadoop..."

    # Directories to include
    local hadoop_dirs=(
        "common"
        "common/lib"
        "hdfs"
        "hdfs/lib"
        "mapreduce"
        "mapreduce/lib"
        "yarn"
        "yarn/lib"
    )

    local xml_content="<?xml version=\"1.0\" encoding=\"UTF-8\"?><userlibrary systemlibrary=\"false\" version=\"2\">"
    
    for subdir in "${hadoop_dirs[@]}"; do
        for jar in "$INSTALL_DIR/hadoop/share/hadoop/$subdir"/*.jar; do
            if [[ -f "$jar" ]] && [[ ! "$jar" == *"tests.jar" ]] && [[ ! "$jar" == *"sources.jar" ]]; then
                # Eclipse needs absolute paths. Escape for XML.
                local jar_path=$(readlink -f "$jar")
                xml_content="${xml_content}<archive path=\"${jar_path}\"/>"
            fi
        done
    done
    xml_content="${xml_content}</userlibrary>"

    # Escape XML for properties file (key=value)
    # 1. Escape backslashes
    # 2. Escape newlines (though we have none here)
    # 3. Escape colons and equals signs (standard properties file)
    # However, Eclipse prefs often store raw XML if it's on one line, but let's be safe and just put it as one line.
    
    # Actually, Eclipse stores it as: org.eclipse.jdt.core.userLibrary.Hadoop=<?xml ...
    # We just need to make sure we append or replace that specific line.
    
    # Remove existing entry if present
    touch "$prefs_file"
    sed -i '/org.eclipse.jdt.core.userLibrary.Hadoop/d' "$prefs_file"
    
    # Append new entry
    echo "org.eclipse.jdt.core.userLibrary.Hadoop=$xml_content" >> "$prefs_file"
    
    success "Eclipse User Library 'Hadoop' configured"
}

install_eclipse() {
    # Always run configuration to ensure wrapper/prefs are current
    # skip_if_installed removed to allow repair/update

    echo -e "\n${BOLD}Installing Eclipse IDE for MapReduce Development${NC}"
    
    # Check if systemd is running, enable if needed
    if ! systemctl is-system-running &>/dev/null && ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
        info "Enabling systemd in WSL..."
        sudo bash -c 'cat >> /etc/wsl.conf <<WSLCONF
[boot]
systemd=true
WSLCONF'
        success "Systemd configuration added to /etc/wsl.conf"
        echo ""
        echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  WSL RESTART REQUIRED - Eclipse installation paused      ║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BOLD}To continue Eclipse installation:${NC}"
        echo -e "  1. Open ${CYAN}PowerShell or CMD${NC} on Windows"
        echo -e "  2. Run: ${CYAN}wsl --shutdown${NC}"
        echo -e "  3. Restart WSL (open Ubuntu/WSL again)"
        echo -e "  4. Re-run this script and select option 6 (Eclipse) again"
        echo ""
        echo -e "${GREEN}The script will detect that systemd is enabled and continue automatically.${NC}"
        echo ""
        exit 0
    fi
    
    # Verify systemd is actually running
    if ! systemctl is-system-running &>/dev/null; then
        error "Systemd is configured but not running. Please restart WSL: wsl --shutdown"
    fi
    
    info "Systemd is active"
    
    # Install snapd
    if ! command -v snap &>/dev/null; then
        if ! execute_with_spinner "Installing snapd" sudo apt-get install -y snapd -qq; then
            error "snapd installation failed"
        fi
        
        # Enable and start snapd service
        if ! execute_with_spinner "Enabling snapd service" sudo systemctl enable --now snapd; then
            error "Failed to enable snapd service"
        fi
        
        if ! execute_with_spinner "Enabling snapd.socket" sudo systemctl enable --now snapd.socket; then
            warn "snapd.socket failed to enable"
        fi
        
        # Wait for snapd to be ready
        sleep 3
    fi
    
    # Install Maven via apt
    if ! command -v mvn &>/dev/null; then
        if ! execute_with_spinner "Installing Maven" sudo apt-get install -y maven -qq; then
            warn "Maven installation failed, continuing..."
        fi
    fi

    # Install Eclipse via snap
    if ! command -v eclipse &>/dev/null; then
        info "Installing Eclipse via snap (this may take a few minutes)..."
        if ! sudo snap install eclipse --classic; then
            error "Eclipse snap installation failed. Check your internet connection."
        fi
        success "Eclipse installed successfully"
    else
        info "Eclipse already installed"
    fi

    # Verify Eclipse is available
    if ! command -v eclipse &>/dev/null; then
        error "Eclipse installation failed. Try manually: sudo snap install eclipse --classic"
    fi

    # Create directory before writing script
    mkdir -p "$HOME/.local/bin"
    
    # Create custom configuration directory for Eclipse to bypass Snap read-only limits
    # This allows us to suppress the workspace selection dialog
    local eclipse_config="$HOME/.hadoop-eclipse-config"
    mkdir -p "$eclipse_config/.settings"
    
    # Pre-seed preference to suppress workspace dialog
    # org.eclipse.ui.ide.prefs
    cat > "$eclipse_config/.settings/org.eclipse.ui.ide.prefs" <<EOF
MAX_RECENT_WORKSPACES=10
RECENT_WORKSPACES=$HOME/eclipse-workspace
RECENT_WORKSPACES_PROTOCOL=3
SHOW_RECENT_WORKSPACES=false
SHOW_WORKSPACE_SELECTION_DIALOG=false
eclipse.preferences.version=1
EOF

    # Configure User Library
    configure_eclipse_user_library

    # Pre-seed Java Compiler preferences to default to Java 11 (instead of 21)
    # org.eclipse.jdt.core.prefs
    cat > "$eclipse_config/.settings/org.eclipse.jdt.core.prefs" <<EOF
org.eclipse.jdt.core.compiler.codegen.targetPlatform=1.8
org.eclipse.jdt.core.compiler.compliance=1.8
org.eclipse.jdt.core.compiler.source=1.8
eclipse.preferences.version=1
EOF

    cat >"$HOME/.local/bin/eclipse-hadoop.sh" <<'EOF'
#!/bin/bash

export HADOOP_HOME=$HOME/bigdata/hadoop
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH

echo "Preparing Hadoop environment for Eclipse..."

if ! pgrep -f NameNode > /dev/null; then
    echo "Starting Hadoop services..."
    sudo service ssh start > /dev/null 2>&1
    $HADOOP_HOME/sbin/start-dfs.sh > /dev/null 2>&1
    sleep 5
    $HADOOP_HOME/sbin/start-yarn.sh > /dev/null 2>&1
    echo "Hadoop services started"
fi

echo "Waiting for HDFS..."
$HADOOP_HOME/bin/hdfs dfsadmin -safemode wait > /dev/null 2>&1
$HADOOP_HOME/bin/hdfs dfsadmin -safemode leave > /dev/null 2>&1

$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/$USER /tmp > /dev/null 2>&1
$HADOOP_HOME/bin/hdfs dfs -chmod 777 /tmp > /dev/null 2>&1

echo "Environment ready. Launching Eclipse..."
echo ""

# We use a custom configuration directory to ensure our preferences (like suppressing the workspace prompt) apply.
# Snap's internal config is read-only, so this redirection is required.
exec eclipse -configuration "$HOME/.hadoop-eclipse-config" "$@"
EOF

    chmod +x "$HOME/.local/bin/eclipse-hadoop.sh"
    sudo ln -sf "$HOME/.local/bin/eclipse-hadoop.sh" /usr/local/bin/eclipse-hadoop

    success "Eclipse and Maven installed successfully"

    echo -e "\n${YELLOW}IMPORTANT FIRST LAUNCH INSTRUCTION:${NC}"
    echo -e "When launching Eclipse for the first time:"
    echo -e "1. Accept the default workspace directory."
    echo -e "2. ${BOLD}CHECK the box${NC} 'Use this as the default and do not ask again'."
    echo -e "3. Click 'Launch'."
    echo -e "${CYAN}This prevents future workspace issues.${NC}\n"

    info "Launch with: eclipse-hadoop"
    
    mark_done "eclipse_full"
}

setup_environment() {
    skip_if_installed "env_setup" "Environment" && return
    
    echo -e "\n${BOLD}Configuring Environment${NC}"
    
    if ! grep -q "HADOOP_HOME" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" <<'BASHRC'

# Hadoop Ecosystem
export HADOOP_HOME=$HOME/bigdata/hadoop
export SPARK_HOME=$HOME/bigdata/spark
export KAFKA_HOME=$HOME/bigdata/kafka
export PIG_HOME=$HOME/bigdata/pig
export HIVE_HOME=$HOME/bigdata/hive
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$KAFKA_HOME/bin:$PIG_HOME/bin:$HIVE_HOME/bin:$PATH

# Kafka wrapper (Java 17)
kafka-server-start() { JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 kafka-server-start.sh "$@"; }
kafka-topics() { JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 kafka-topics.sh "$@"; }
BASHRC
    fi
    
    mark_done "env_setup"
    success "Environment configured"
}

create_scripts() {
    skip_if_installed "scripts_created" "Helper scripts" && return
    
    echo -e "\n${BOLD}Creating Helper Scripts${NC}"
    
    # Start script
    cat > "$HOME/start-hadoop.sh" <<'START'
#!/bin/bash
INSTALL_DIR="$HOME/bigdata"

sudo service ssh start &>/dev/null
sudo service mysql start &>/dev/null

"$INSTALL_DIR/hadoop/sbin/start-dfs.sh" &>/dev/null
sleep 3
"$INSTALL_DIR/hadoop/sbin/start-yarn.sh" &>/dev/null
sleep 3

export HADOOP_HOME="$INSTALL_DIR/hadoop"
"$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/$USER /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null
"$HADOOP_HOME/bin/hdfs" dfs -chmod 777 /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null

nohup "$INSTALL_DIR/hive/bin/hive" --service metastore &>/dev/null &
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 nohup "$INSTALL_DIR/kafka/bin/kafka-server-start.sh" "$INSTALL_DIR/kafka/config/kraft-server.properties" &>/dev/null &

echo "✓ All services started"
echo "  HDFS: http://localhost:9870"
echo "  YARN: http://localhost:8088"
START
    
    # Stop script
    cat > "$HOME/stop-hadoop.sh" <<'STOP'
#!/bin/bash
INSTALL_DIR="$HOME/bigdata"
"$INSTALL_DIR/hadoop/sbin/stop-yarn.sh" &>/dev/null
"$INSTALL_DIR/hadoop/sbin/stop-dfs.sh" &>/dev/null
pkill -f HiveMetaStore &>/dev/null
pkill -f kafka.Kafka &>/dev/null
echo "✓ All services stopped"
STOP
    
    chmod +x "$HOME/start-hadoop.sh" "$HOME/stop-hadoop.sh"
    
    mark_done "scripts_created"
    success "Helper scripts created"
}

create_eclipse_project() {
    echo -e "\n${BOLD}Create Eclipse Project for Hadoop${NC}"
    
    # Get Project Name (Mandatory)
    while true; do
        read -p "Enter project name: " proj_name
        if [ -n "$proj_name" ]; then
            break
        fi
        echo -e "${RED}Error: Project name cannot be empty.${NC}"
    done

    # Get Class Name (Mandatory)
    while true; do
        read -p "Enter class name (e.g. WordCount): " class_name
        if [ -n "$class_name" ]; then
            break
        fi
        echo -e "${RED}Error: Class name cannot be empty.${NC}"
    done
    
    local workspace_dir="$HOME/eclipse-workspace"
    local proj_dir="$workspace_dir/$proj_name"
    local src_dir="$proj_dir/src"
    
    # Check/Create directory
    if [ -d "$proj_dir" ]; then
        warn "Directory $proj_dir already exists."
        read -p "Overwrite? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && return
    fi
    mkdir -p "$src_dir"
    
    info "Creating project at: $proj_dir"
    
    # Create project settings directory
    mkdir -p "$proj_dir/.settings"

    # FORCE Java 1.8 Compiler Settings at Project Level
    # This prevents Eclipse from using its internal Java 21 default
    cat > "$proj_dir/.settings/org.eclipse.jdt.core.prefs" <<EOF
eclipse.preferences.version=1
org.eclipse.jdt.core.compiler.codegen.inlineJsrBytecode=enabled
org.eclipse.jdt.core.compiler.codegen.targetPlatform=1.8
org.eclipse.jdt.core.compiler.codegen.unusedLocal=preserve
org.eclipse.jdt.core.compiler.compliance=1.8
org.eclipse.jdt.core.compiler.debug.lineNumber=generate
org.eclipse.jdt.core.compiler.debug.localVariable=generate
org.eclipse.jdt.core.compiler.debug.sourceFile=generate
org.eclipse.jdt.core.compiler.problem.assertIdentifier=error
org.eclipse.jdt.core.compiler.problem.enumIdentifier=error
org.eclipse.jdt.core.compiler.source=1.8
EOF

    # Create .project
    cat > "$proj_dir/.project" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<projectDescription>
	<name>$proj_name</name>
	<comment></comment>
	<projects>
	</projects>
	<buildSpec>
		<buildCommand>
			<name>org.eclipse.jdt.core.javabuilder</name>
			<arguments>
			</arguments>
		</buildCommand>
	</buildSpec>
	<natures>
		<nature>org.eclipse.jdt.core.javanature</nature>
	</natures>
</projectDescription>
EOF

    # Create .classpath with JavaSE-11 (User requested JDK 11)
    cat > "$proj_dir/.classpath" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
	<classpathentry kind="src" path="src"/>
	<classpathentry kind="con" path="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-1.8"/>
EOF

    # Add ALL Hadoop JARs (Common, HDFS, YARN, MapReduce) and their libs
    info "Adding Hadoop JARs to classpath..."
    
    # Directories to include
    local hadoop_dirs=(
        "common"
        "common/lib"
        "hdfs"
        "hdfs/lib"
        "mapreduce"
        "mapreduce/lib"
        "yarn"
        "yarn/lib"
    )
    
    for subdir in "${hadoop_dirs[@]}"; do
        for jar in "$INSTALL_DIR/hadoop/share/hadoop/$subdir"/*.jar; do
            # Skip test jars and sources to keep it clean, but ensure we get the main ones
            if [[ -f "$jar" ]] && [[ ! "$jar" == *"tests.jar" ]] && [[ ! "$jar" == *"sources.jar" ]]; then
                echo "	<classpathentry kind=\"lib\" path=\"$jar\"/>" >> "$proj_dir/.classpath"
            fi
        done
    done
    
    echo "</classpath>" >> "$proj_dir/.classpath"

    # Create Java File Template (Default Package)
    local java_file="$src_dir/$class_name.java"
    cat > "$java_file" <<EOF
public class $class_name {

}
EOF
    
    # Create Launch Configuration
    # This ensures "Run" uses the correct JRE (Java 1.8) instead of Eclipse internal (Java 21)
    cat > "$proj_dir/$class_name.launch" <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<launchConfiguration type="org.eclipse.jdt.launching.localJavaApplication">
    <listAttribute key="org.eclipse.debug.core.MAPPED_RESOURCE_PATHS">
        <listEntry value="/$proj_name/src/$class_name.java"/>
    </listAttribute>
    <listAttribute key="org.eclipse.debug.core.MAPPED_RESOURCE_TYPES">
        <listEntry value="1"/>
    </listAttribute>
    <booleanAttribute key="org.eclipse.jdt.launching.ATTR_ATTR_USE_ARGFILE" value="false"/>
    <booleanAttribute key="org.eclipse.jdt.launching.ATTR_EXCLUDE_TEST_CODE" value="true"/>
    <booleanAttribute key="org.eclipse.jdt.launching.ATTR_USE_CLASSPATH_ONLY_JAR" value="false"/>
    <stringAttribute key="org.eclipse.jdt.launching.MAIN_TYPE" value="$class_name"/>
    <stringAttribute key="org.eclipse.jdt.launching.MODULE_NAME" value="$proj_name"/>
    <stringAttribute key="org.eclipse.jdt.launching.PROJECT_ATTR" value="$proj_name"/>
    <stringAttribute key="org.eclipse.jdt.launching.JRE_CONTAINER" value="org.eclipse.jdt.launching.JRE_CONTAINER/org.eclipse.jdt.internal.debug.ui.launcher.StandardVMType/JavaSE-1.8"/>
</launchConfiguration>
EOF

    success "Project '$proj_name' created successfully!"
    info "Created class: $java_file"
    info "Created launch config: $proj_dir/$class_name.launch"
    info "Location: $proj_dir"
    info "Launching Eclipse..."
    
    # Launch Eclipse with the workspace AND the file open using the full path
    # Use the wrapper script to ensure environment variables are set
    local eclipse_cmd="eclipse-hadoop"
    if ! command -v "$eclipse_cmd" &>/dev/null; then
        eclipse_cmd="$HOME/.local/bin/eclipse-hadoop.sh"
    fi
    
    # Launch without logging as requested
    nohup "$eclipse_cmd" -data "$workspace_dir" --launcher.openFile "$java_file" >/dev/null 2>&1 &
    
    # Give it a moment to detach
    sleep 2
    success "Eclipse is launching!"
    
    echo -e "\n${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  IMPORTANT: To see your project/code in Eclipse            ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "1. In Eclipse, go to: ${BOLD}File > Open Projects from File System...${NC}"
    echo -e "2. Click ${BOLD}'Directory'${NC} and navigate to:"
    echo -e "   ${CYAN}$proj_dir${NC}"
    echo -e "3. Click ${BOLD}'Finish'${NC}"
    
    echo -e "${YELLOW}Navigate to:${NC}"
    echo -e "${BOLD} > $proj_name > src > (default package) > $class_name.java${NC}"
    read -p "Press Enter to return to menu..."
}




show_installation_info() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Installation Information                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BOLD}Installed Components:${NC}"
    is_done "hadoop_full" && echo -e "  ${GREEN}✓${NC} Hadoop ${HADOOP_VERSION}" || echo -e "  ${YELLOW}○${NC} Hadoop ${HADOOP_VERSION}"
    is_done "spark_full" && echo -e "  ${GREEN}✓${NC} Spark ${SPARK_VERSION}" || echo -e "  ${YELLOW}○${NC} Spark ${SPARK_VERSION}"
    is_done "kafka_full" && echo -e "  ${GREEN}✓${NC} Kafka ${KAFKA_VERSION}" || echo -e "  ${YELLOW}○${NC} Kafka ${KAFKA_VERSION}"
    is_done "pig_full" && echo -e "  ${GREEN}✓${NC} Pig ${PIG_VERSION}" || echo -e "  ${YELLOW}○${NC} Pig ${PIG_VERSION}"
    is_done "hive_full" && echo -e "  ${GREEN}✓${NC} Hive ${HIVE_VERSION}" || echo -e "  ${YELLOW}○${NC} Hive ${HIVE_VERSION}"
    is_done "eclipse_full" && echo -e "  ${GREEN}✓${NC} Eclipse IDE" || echo -e "  ${YELLOW}○${NC} Eclipse IDE"
    
    echo -e "\n${BOLD}Installation Directory:${NC} $INSTALL_DIR"
    
    echo -e "\n${BOLD}Helper Scripts:${NC}"
    [ -f "$HOME/start-hadoop.sh" ] && echo -e "  ${GREEN}✓${NC} ~/start-hadoop.sh" || echo -e "  ${YELLOW}○${NC} ~/start-hadoop.sh"
    [ -f "$HOME/stop-hadoop.sh" ] && echo -e "  ${GREEN}✓${NC} ~/stop-hadoop.sh" || echo -e "  ${YELLOW}○${NC} ~/stop-hadoop.sh"
    
    echo -e "\n${BOLD}System:${NC} $(free -m 2>/dev/null | awk '/^Mem:/{print int($2/1024)}')GB RAM, $(df -BG "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')GB Free"
    
    if [ -d "$INSTALL_DIR/hadoop" ]; then
        echo -e "\n${BOLD}Web Interfaces:${NC}"
        echo -e "  HDFS: ${CYAN}http://localhost:9870${NC}  YARN: ${CYAN}http://localhost:8088${NC}"
    fi
    
    echo -e "\n${BOLD}Quick Commands:${NC}"
    echo -e "  ${CYAN}~/start-hadoop.sh${NC}  |  ${CYAN}~/stop-hadoop.sh${NC}  |  ${CYAN}hdfs dfs -ls /${NC}"
    
    echo ""
    read -p "Press Enter to continue..."
}

# ==================== MENU SYSTEM ====================

get_install_status() {
    local component=$1
    if is_done "$component"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}○${NC}"
    fi
}

create_shortcut() {
    echo -e "\n${BOLD}Creating Update Shortcut${NC}"
    local shortcut_file="$HOME/dg-script.sh"
    
    # Create the shortcut script
    if cat > "$shortcut_file" <<'EOF'
#!/bin/bash
bash <(curl -fsSL https://raw.githubusercontent.com/darshan-gowdaa/wsl-hadoop-installer/main/installv3.sh)
EOF
    then
        if chmod +x "$shortcut_file"; then
            # Make globally executable
            if sudo ln -sf "$shortcut_file" /usr/local/bin/dg-script.sh; then
                success "Shortcut created and added to PATH"
                info "You can now run it from anywhere using:"
                echo -e "  ${CYAN}dg-script.sh${NC}"
            else
                warn "Could not add to PATH. Run with: ./dg-script.sh"
            fi
        else
            error "Failed to make shortcut executable."
        fi
    else
        error "Failed to create shortcut file."
    fi
    
    read -p "Press Enter to continue..."
}

show_menu() {
    clear
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${MAGENTA}             Hadoop Ecosystem Installer v3              ${NC}"
    echo -e "${BLUE}               github.com/darshan-gowdaa                ${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
    
    # Installation status
    local hadoop_status=$(get_install_status "hadoop_full")
    local spark_status=$(get_install_status "spark_full")
    local kafka_status=$(get_install_status "kafka_full")
    local pig_status=$(get_install_status "pig_full")
    local hive_status=$(get_install_status "hive_full")
    local eclipse_status=$(get_install_status "eclipse_full")
    
    echo -e " ${BOLD}${CYAN}COMPONENTS:${NC}\n"
    printf "  ${BOLD}1)${NC} %-30s %s\n" "Hadoop [HDFS & YARN] ${HADOOP_VERSION}" "$hadoop_status"
    printf "  ${BOLD}2)${NC} %-30s %s\n" "Spark ${SPARK_VERSION}" "$spark_status"
    printf "  ${BOLD}3)${NC} %-30s %s\n" "Kafka ${KAFKA_VERSION}" "$kafka_status"
    printf "  ${BOLD}4)${NC} %-30s %s\n" "Pig ${PIG_VERSION}" "$pig_status"
    printf "  ${BOLD}5)${NC} %-30s %s\n" "Hive ${HIVE_VERSION}" "$hive_status"
    printf "  ${BOLD}6)${NC} %-30s %s\n" "Eclipse IDE" "$eclipse_status"
    
    echo -e "\n ${BOLD}${CYAN}MANAGEMENT:${NC}\n"
    echo -e "  ${BOLD}7)${NC} Start All Services"
    echo -e "  ${BOLD}8)${NC} Stop All Services"
    echo -e "  ${BOLD}9)${NC} Check System Status"
    
    echo -e "\n ${BOLD}${CYAN}SYSTEM:${NC}\n"
    echo -e "  ${BOLD}I)${NC} Installation Info"
    echo -e "  ${BOLD}P)${NC} Create Eclipse Project"
    echo -e "  ${BOLD}S)${NC} Create Update Shortcut"
    echo -e "  ${BOLD}0)${NC} Exit"
    echo ""
}

check_status() {
    echo -e "\n${BOLD}Service Status:${NC}\n"
    
    local services=("NameNode:9870" "DataNode:9864" "ResourceManager:8088" "NodeManager:8042" "Kafka:9092" "HiveMetaStore:9083")
    for svc in "${services[@]}"; do
        IFS=':' read -r name port <<< "$svc"
        check_service_port "$name" "$port"
    done
    
    echo -e "\n${BOLD}Java Processes:${NC}"
    if command -v jps &>/dev/null; then
        jps 2>/dev/null | grep -v "Jps" || echo "  No Java processes"
    else
        echo "  jps command not found"
    fi
    
    echo -e "\n${BOLD}HDFS Status:${NC}"
    if [ -d "$INSTALL_DIR/hadoop" ]; then
        export HADOOP_HOME="$INSTALL_DIR/hadoop"
        if "$HADOOP_HOME/bin/hdfs" dfsadmin -report &>/dev/null; then
            "$HADOOP_HOME/bin/hdfs" dfsadmin -report 2>/dev/null | head -15
        else
            echo "  HDFS not running or not configured"
        fi
    else
        echo "  Hadoop not installed"
    fi
}

start_services() {
    echo -e "\n${BOLD}Starting Services...${NC}\n"
    
    export HADOOP_HOME="${HADOOP_HOME:-$INSTALL_DIR/hadoop}"
    
    # Verify Hadoop is installed
    [ -d "$HADOOP_HOME" ] || error "Hadoop not installed. Install it first from menu."
    
    # Ensure SSH is running
    ensure_service_running "ssh" "sshd" "SSH service not started"
    
    # Test SSH connectivity
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 localhost exit &>/dev/null; then
        error "SSH connection to localhost failed. Check SSH setup."
    fi
    
    # Start HDFS
    if ! execute_with_spinner "Starting HDFS" "$HADOOP_HOME/sbin/start-dfs.sh"; then
        error "HDFS failed to start. Check logs: $HADOOP_HOME/logs/"
    fi
    sleep 5
    
    # Verify NameNode started
    pgrep -f "NameNode" >/dev/null || error "NameNode failed to start. Check: $HADOOP_HOME/logs/hadoop-$USER-namenode-*.log"
    
    # Start YARN
    if ! execute_with_spinner "Starting YARN" "$HADOOP_HOME/sbin/start-yarn.sh"; then
        warn "YARN had startup warnings, continuing..."
    fi
    sleep 5
    
    # Wait for HDFS safe mode
    info "Waiting for HDFS to exit safe mode..."
    local attempts=0
    local max_attempts=120  # Increased to 2 minutes for slow systems
    while [ $attempts -lt $max_attempts ]; do
        if "$HADOOP_HOME/bin/hdfs" dfsadmin -safemode get 2>/dev/null | grep -q "OFF"; then
            success "HDFS ready"
            break
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    
    if [ $attempts -eq $max_attempts ]; then
        warn "HDFS safe mode timeout - forcing exit"
        "$HADOOP_HOME/bin/hdfs" dfsadmin -safemode leave &>/dev/null || true
    fi
    
    # Create HDFS directories using helper function
    setup_hdfs_directories
    
    # Start Hive Metastore if installed
    if [ -d "$INSTALL_DIR/hive" ] && is_done "hive_full"; then
        if ! pgrep -f "HiveMetaStore" >/dev/null; then
            info "Starting Hive Metastore..."
            ensure_service_running "mysql" "mysqld" "MySQL not started"
            nohup "$INSTALL_DIR/hive/bin/hive" --service metastore \
                > "$INSTALL_DIR/hive/metastore.log" 2>&1 &
            sleep 2
        fi
    fi
    
    # Start Kafka if installed
    if [ -d "$INSTALL_DIR/kafka" ] && is_done "kafka_full"; then
        if ! pgrep -f "kafka.Kafka" >/dev/null; then
            info "Starting Kafka..."
            JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
                nohup "$INSTALL_DIR/kafka/bin/kafka-server-start.sh" \
                "$INSTALL_DIR/kafka/config/kraft-server.properties" \
                > "$INSTALL_DIR/kafka/kafka.log" 2>&1 &
            sleep 3
        fi
    fi
    
    success "Services started successfully"
    echo -e "  HDFS: ${CYAN}http://localhost:9870${NC}"
    echo -e "  YARN: ${CYAN}http://localhost:8088${NC}"
}

stop_services() {
    echo -e "\n${BOLD}Stopping Services...${NC}\n"
    
    export HADOOP_HOME="${HADOOP_HOME:-$INSTALL_DIR/hadoop}"
    
    # Check if Hadoop is installed
    if [ ! -d "$HADOOP_HOME" ]; then
        warn "Hadoop not installed, nothing to stop"
        return
    fi
    
    # Stop YARN
    [ -x "$HADOOP_HOME/sbin/stop-yarn.sh" ] && execute_with_spinner "Stopping YARN" "$HADOOP_HOME/sbin/stop-yarn.sh"
    
    # Stop HDFS
    [ -x "$HADOOP_HOME/sbin/stop-dfs.sh" ] && execute_with_spinner "Stopping HDFS" "$HADOOP_HOME/sbin/stop-dfs.sh"
    
    # Stop Hive
    if pgrep -f "HiveMetaStore" >/dev/null; then
        info "Stopping Hive Metastore..."
        pkill -f HiveMetaStore &>/dev/null || true
        sleep 1
    fi
    
    # Stop Kafka
    if pgrep -f "kafka.Kafka" >/dev/null; then
        info "Stopping Kafka..."
        pkill -f kafka.Kafka &>/dev/null || true
        sleep 1
    fi
    
    success "All services stopped"
}

# ==================== MAIN ====================

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${RED}Installation interrupted. Check log: $LOG_FILE${NC}"
    fi
}

trap cleanup_on_error EXIT

main() {
    # Initialize log file
    touch "$LOG_FILE" 2>/dev/null || {
        LOG_FILE="/tmp/hadoop_install.log"
        warn "Using fallback log location: $LOG_FILE"
    }
    
    preflight_checks
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        # Validate input (allow numbers and letters A, I, P, S)
        if [[ ! "$choice" =~ ^[0-9AaIiPpSs]+$ ]]; then
            echo -e "${RED}Invalid option. Please enter a valid option.${NC}"
            sleep 2
            continue
        fi
        
        # Convert to uppercase for case matching
        choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
        
        case $choice in

    1)
        run_install_workflow "Hadoop" install_system_deps install_hadoop setup_environment create_scripts
        ;;
    2)
        run_install_workflow "Spark" install_system_deps install_hadoop install_spark setup_environment
        ;;
    3)
        run_install_workflow "Kafka" install_system_deps install_kafka setup_environment
        ;;
    4)
        run_install_workflow "Pig" install_system_deps install_hadoop install_pig setup_environment
        ;;
    5)
        run_install_workflow "Hive" install_system_deps install_hadoop install_hive setup_environment
        ;;
    6)
        install_system_deps
        install_hadoop
        install_eclipse
        setup_environment
        success "Eclipse IDE installed"
        echo -e "Launch with: ${CYAN}eclipse-hadoop${NC}"
        echo -e "Or run: ${CYAN}$HOME/.local/bin/eclipse-hadoop.sh${NC}"
        read -p "Press Enter to continue..."
        ;;
    7)
        start_services
        read -p "Press Enter to continue..."
        ;;
    8)
        stop_services
        read -p "Press Enter to continue..."
        ;;
    9)
        check_status
        read -p "Press Enter to continue..."
        ;;

    I)
        show_installation_info
        ;;
    P)
        create_eclipse_project
        ;;
    S)
        create_shortcut
        ;;
    0)
        echo -e "\n${GREEN}Goodbye! :) | Star the repo if you like it!${NC}\n"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid option. Please select a valid option.${NC}"
        sleep 2
        ;;
esac
    done
}

main
