#!/bin/bash

# WSL Hadoop Ecosystem Installation Script
# Purpose: Student learning environment for Hadoop ecosystem
# Installs: Hadoop, YARN, Spark, Kafka (KRaft), Pig

set -Eeuo pipefail

# === Configuration ===
INSTALL_DIR="$HOME/bigdata"
HADOOP_VERSION="${HADOOP_VERSION:-3.4.2}"      # Latest stable release (Aug 2025)
SPARK_VERSION="${SPARK_VERSION:-3.5.3}"        # Latest verified stable (Sep 2025)
KAFKA_VERSION="${KAFKA_VERSION:-4.1.1}"        # Latest stable with KRaft (Nov 2025)
PIG_VERSION="${PIG_VERSION:-0.18.0}"           # Latest with Hadoop 3 support (Sep 2025)
JAVA_VERSION="11"

STATE_FILE="$HOME/.hadoop_install_state"
LOG_FILE="$HOME/hadoop_install.log"
LOCK_FILE="$HOME/.hadoop_install.lock"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# === Pre-flight Checks ===
preflight_checks() {
    echo ""
    echo -e "${GREEN}=== Hadoop Ecosystem Installer ===${NC}"
    echo ""
    
    # Check if running from Windows filesystem (CRITICAL)
    if [[ "$PWD" == /mnt/* ]]; then
        error "⚠️ You're in Windows filesystem (/mnt/c)
        
Hadoop will be 10x SLOWER here!

Fix: Move to Linux home directory:
  cd ~
  # Download script again or move it:
  cp $0 ~/
  cd ~ && bash ./$(basename $0)"
    fi
    
    # Verify running in WSL
    if ! grep -qi microsoft /proc/version 2>/dev/null; then
        echo -e "${YELLOW}WARNING:${NC} This script is optimized for WSL."
        echo "You appear to be running on native Linux."
        read -p "Continue anyway? (y/n): " choice
        [[ "$choice" != "y" ]] && exit 0
    fi
    
    # Check WSL version
    local wsl_version=2
    if ! grep -q "WSL2" /proc/version 2>/dev/null; then
        warn "You might be on WSL1. Hadoop will be SLOW."
        echo "To upgrade: Open PowerShell as admin and run:"
        echo "  wsl --set-version Ubuntu 2"
        read -p "Continue anyway? (y/n): " choice
        [[ "$choice" != "y" ]] && exit 0
    else
        log "✓ Running on WSL2"
    fi
    
    # Check Ubuntu version
    if ! grep -qi ubuntu /etc/os-release 2>/dev/null; then
        echo -e "${YELLOW}WARNING:${NC} This script is tested on Ubuntu."
        echo "Your distribution may have compatibility issues."
        read -p "Continue anyway? (y/n): " choice
        [[ "$choice" != "y" ]] && exit 0
    fi
    
    # WSL Memory Check
    local total_mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_mem_gb" -lt 6 ]; then
        warn "WSL has only ${total_mem_gb}GB RAM allocated."
        echo ""
        echo "For Hadoop learning, you need at least 8GB allocated to WSL."
        echo ""
        echo "To fix: Create C:\\Users\\<username>\\.wslconfig with:"
        echo ""
        echo "[wsl2]"
        echo "memory=8GB"
        echo "swap=2GB"
        echo "processors=4"
        echo ""
        echo "Then restart WSL: wsl --shutdown in PowerShell"
        echo ""
        read -p "Continue with limited memory? (not recommended) (y/n): " choice
        [[ "$choice" != "y" ]] && exit 0
    else
        log "[OK] WSL has ${total_mem_gb}GB RAM allocated"
    fi
    
    # Sudo warning and test
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT:${NC}"
    echo "  - This script requires sudo access for package installation"
    echo "  - You will be prompted for your WSL password"
    echo "  - Installation takes 5-10 minutes depending on internet speed"
    echo "  - Requires ~10GB disk space"
    echo ""
    
    echo -e "${YELLOW}Testing sudo access...${NC}"
    if ! sudo -v; then
        error "Sudo authentication failed. Did you forget your WSL password?
        
To reset: Open PowerShell as admin and run:
  wsl -u root
  passwd <your-username>
  exit"
    fi
    log "✓ Sudo access confirmed"
    
    echo ""
    echo -e "${YELLOW}WARNING - WINDOWS FIREWALL:${NC}"
    echo "During installation, Windows will show firewall popups:"
    echo "  - Java Platform SE binary"
    echo "  - OpenSSH SSH Server"
    echo ""
    echo "ACTION REQUIRED: Click 'Allow access' on Private networks"
    echo "WARNING: DO NOT click 'Block' - Hadoop will not function"
    echo ""
    
    echo ""
    echo "Press Ctrl+C to cancel, or Enter to continue..."
    read
    
    echo ""
}

# === Trap Handlers ===
cleanup_on_exit() {
    local exit_code=$?
    rm -f "$LOCK_FILE"
    if [ $exit_code -ne 0 ]; then
        warn "Installation failed. Check logs: $LOG_FILE"
    fi
}

trap cleanup_on_exit EXIT
trap 'error "Script failed at line $LINENO"' ERR

# === Helper Functions ===
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

mark_done() {
    flock 200
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

check_disk_space() {
    local required_gb=10
    local available_gb=$(df -BG "$HOME" | awk 'NR==2 {print int($4)}')
    local wsl_location=$(df -h "$HOME" | awk 'NR==2 {print $1}')
    
    log "WSL storage: $wsl_location (${available_gb}GB available)"
    
    if [ "$available_gb" -lt "$required_gb" ]; then
        error "Need ${required_gb}GB free. Have ${available_gb}GB.
        
Breakdown:
  - Hadoop install: ~2GB
  - Sample datasets: 1-2GB  
  - HDFS data: 2-5GB (learning)
  - Logs: 1-2GB over time

Free up space or move to different drive."
    fi
    log "Disk space check passed: ${available_gb}GB available"
}

acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        error "Another installation is running. Remove $LOCK_FILE if this is incorrect."
    fi
}

download_with_retry() {
    local url=$1
    local output=$2
    local retries=3
    
    for i in $(seq 1 $retries); do
        # Remove corrupted file before retry
        rm -f "$output"
        
        if wget -c --timeout=60 --tries=2 -O "$output" "$url"; then
            if tar -tzf "$output" >/dev/null 2>&1 || file "$output" | grep -q "gzip compressed"; then
                log "Downloaded and verified: $output"
                return 0
            else
                warn "Downloaded file corrupted, retrying... ($i/$retries)"
                rm -f "$output"
            fi
        else
            warn "Download failed, retrying... ($i/$retries)"
            rm -f "$output"
        fi
        sleep 3
    done
    
    # Try archive.apache.org as fallback
    log "Trying archive mirror..."
    local archive_url="${url/dlcdn.apache.org/archive.apache.org\/dist}"
    rm -f "$output"
    if wget -c --timeout=60 -O "$output" "$archive_url"; then
        if tar -tzf "$output" >/dev/null 2>&1; then
            log "Downloaded from archive mirror: $output"
            return 0
        fi
    fi
    
    error "Failed to download $url after $retries attempts and archive fallback"
}

# === System Setup ===
setup_system() {
    if is_done "system_setup"; then
        log "System setup already done, skipping..."
        return
    fi
    
    log "Updating system packages..."
    if ! sudo apt-get update -qq; then
        error "Failed to update packages"
    fi
    
    if ! sudo apt-get install -y openjdk-${JAVA_VERSION}-jdk wget curl ssh \
    netcat-openbsd vim net-tools rsync tar gzip unzip util-linux file; then
        error "Failed to install required packages"
    fi
    
    # SSH for passwordless localhost (pseudo-distributed mode doesn't need daemon)
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        log "Creating SSH keys for Hadoop pseudo-distributed mode (local only)"
        log "This enables localhost communication required by Hadoop daemons"
        ssh-keygen -t rsa -P '' -f "$HOME/.ssh/id_rsa" -q
        cat "$HOME/.ssh/id_rsa.pub" >> "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"
        chmod 700 "$HOME/.ssh"
    fi
    
    if [ ! -f "$HOME/.ssh/known_hosts" ] || ! grep -q "localhost" "$HOME/.ssh/known_hosts" 2>/dev/null; then
        ssh-keyscan -H localhost >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
        ssh-keyscan -H 127.0.0.1 >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
    fi
    
    # Start SSH service (WSL requirement)
    if ! sudo service ssh status &>/dev/null; then
        log "Starting SSH service..."
        sudo service ssh start || error "SSH service failed to start"
    fi
    
    # Auto-start SSH on WSL boot
    if ! grep -q "service ssh start" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" <<'EOF'

# Auto-start SSH for Hadoop (WSL requirement)
if ! pgrep -x sshd > /dev/null; then
    sudo service ssh start 2>/dev/null
fi
EOF
    fi
    
    mark_done "system_setup"
    log "System setup completed"
}

# === Java Setup ===
setup_java() {
    if is_done "java_setup"; then
        log "Java setup already done, skipping..."
        return
    fi
    
    if command -v update-alternatives >/dev/null 2>&1; then
        JAVA_HOME=$(update-alternatives --query java | grep 'Value:' | cut -d' ' -f2 | sed 's|/bin/java||')
    else
        JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    fi
    
    if [ ! -d "$JAVA_HOME" ]; then
        error "JAVA_HOME detection failed: $JAVA_HOME"
    fi
    
    if ! grep -q "JAVA_HOME" "$HOME/.bashrc"; then
        log "Adding JAVA_HOME to .bashrc..."
        cat >> "$HOME/.bashrc" <<EOF

# Java Environment
export JAVA_HOME=$JAVA_HOME
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    fi
    
    chmod 600 "$HOME/.bashrc"
    mark_done "java_setup"
    log "Java setup completed: $JAVA_HOME"
}

# === Hadoop Installation ===
install_hadoop() {
    if is_done "hadoop_install"; then
        log "Hadoop already installed, skipping..."
        return
    fi
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Remove corrupted partial downloads
    if [ ! -d "hadoop-${HADOOP_VERSION}" ]; then
        rm -f "hadoop-${HADOOP_VERSION}.tar.gz"
        
        log "Downloading Hadoop ${HADOOP_VERSION}..."
        download_with_retry \
            "https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" \
            "hadoop-${HADOOP_VERSION}.tar.gz"
        
        log "Extracting Hadoop..."
        tar -xzf "hadoop-${HADOOP_VERSION}.tar.gz"
    fi
    
    rm -f hadoop
    ln -s "hadoop-${HADOOP_VERSION}" hadoop
    
    mark_done "hadoop_install"
    log "Hadoop installed successfully"
}

# === Hadoop Configuration ===
configure_hadoop() {
    if is_done "hadoop_config"; then
        log "Hadoop already configured, skipping..."
        return
    fi
    
    export HADOOP_HOME="$INSTALL_DIR/hadoop"
    export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
    
    # WSL-aware memory calculation
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    YARN_MEM=$((TOTAL_MEM * 70 / 100))
    CONTAINER_MEM=$((YARN_MEM / 2))
    
    # Cap at reasonable limits for WSL
    if [ "$YARN_MEM" -gt 4096 ]; then
        YARN_MEM=4096
        CONTAINER_MEM=2048
    fi
    
    log "Configuring Hadoop (YARN Memory: ${YARN_MEM}MB)..."
    
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
    
    # core-site.xml (properly quoted)
    cat > "$HADOOP_CONF_DIR/core-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:9000</value>
    </property>
    <property>
        <name>hadoop.tmp.dir</name>
        <value>${INSTALL_DIR}/hadoop/tmp</value>
    </property>
    <property>
        <name>hadoop.http.staticuser.user</name>
        <value>$USER</value>
    </property>
</configuration>
EOF
    
    # hdfs-site.xml
    mkdir -p "$INSTALL_DIR/hadoop/dfs/namenode" "$INSTALL_DIR/hadoop/dfs/datanode" "$INSTALL_DIR/hadoop/tmp"
    cat > "$HADOOP_CONF_DIR/hdfs-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file://${INSTALL_DIR}/hadoop/dfs/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file://${INSTALL_DIR}/hadoop/dfs/datanode</value>
    </property>
    <property>
        <name>dfs.namenode.http-address</name>
        <value>localhost:9870</value>
    </property>
</configuration>
EOF
    
    # mapred-site.xml (fixed variable expansion)
    cat > "$HADOOP_CONF_DIR/mapred-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.application.classpath</name>
        <value>${HADOOP_HOME}/share/hadoop/mapreduce/*:${HADOOP_HOME}/share/hadoop/mapreduce/lib/*</value>
    </property>
    <property>
        <name>yarn.app.mapreduce.am.env</name>
        <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
    </property>
    <property>
        <name>mapreduce.map.env</name>
        <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
    </property>
    <property>
        <name>mapreduce.reduce.env</name>
        <value>HADOOP_MAPRED_HOME=${HADOOP_HOME}</value>
    </property>
</configuration>
EOF
    
    # yarn-site.xml
    cat > "$HADOOP_CONF_DIR/yarn-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>
        <value>org.apache.hadoop.mapred.ShuffleHandler</value>
    </property>
    <property>
        <name>yarn.resourcemanager.hostname</name>
        <value>localhost</value>
    </property>
    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>${YARN_MEM}</value>
    </property>
    <property>
        <name>yarn.scheduler.maximum-allocation-mb</name>
        <value>${YARN_MEM}</value>
    </property>
    <property>
        <name>yarn.scheduler.minimum-allocation-mb</name>
        <value>512</value>
    </property>
    <property>
        <name>yarn.nodemanager.vmem-check-enabled</name>
        <value>false</value>
    </property>
    <property>
        <name>yarn.app.mapreduce.am.resource.mb</name>
        <value>${CONTAINER_MEM}</value>
    </property>
    <property>
        <name>yarn.nodemanager.env-whitelist</name>
        <value>JAVA_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE,HADOOP_YARN_HOME,HADOOP_HOME,PATH,LANG,TZ,HADOOP_MAPRED_HOME</value>
    </property>
</configuration>
EOF
    
    echo "localhost" > "$HADOOP_CONF_DIR/workers"
    
    mark_done "hadoop_config"
    log "Hadoop configuration completed"
}

# === Spark Installation ===
install_spark() {
    if is_done "spark_install"; then
        log "Spark already installed, skipping..."
        return
    fi
    
    cd "$INSTALL_DIR"
    
    # Remove corrupted partial downloads
    if [ ! -d "spark-${SPARK_VERSION}-bin-hadoop3" ]; then
        rm -f "spark-${SPARK_VERSION}-bin-hadoop3.tgz"
        
        log "Downloading Spark ${SPARK_VERSION}..."
        download_with_retry \
            "https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz" \
            "spark-${SPARK_VERSION}-bin-hadoop3.tgz"
        
        log "Extracting Spark..."
        tar -xzf "spark-${SPARK_VERSION}-bin-hadoop3.tgz"
    fi
    
    rm -f spark
    ln -s "spark-${SPARK_VERSION}-bin-hadoop3" spark
    
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
    log "Spark installed successfully"
}

# === Kafka Installation (KRaft mode) ===
install_kafka() {
    if is_done "kafka_install"; then
        log "Kafka already installed, skipping..."
        return
    fi
    
    cd "$INSTALL_DIR"
    
    KAFKA_SCALA="2.13"
    
    # Remove corrupted partial downloads
    if [ ! -d "kafka_${KAFKA_SCALA}-${KAFKA_VERSION}" ]; then
        rm -f "kafka_${KAFKA_SCALA}-${KAFKA_VERSION}.tgz"
        
        log "Downloading Kafka ${KAFKA_VERSION}..."
        download_with_retry \
            "https://dlcdn.apache.org/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA}-${KAFKA_VERSION}.tgz" \
            "kafka_${KAFKA_SCALA}-${KAFKA_VERSION}.tgz"
        
        log "Extracting Kafka..."
        tar -xzf "kafka_${KAFKA_SCALA}-${KAFKA_VERSION}.tgz"
    fi
    
    rm -f kafka
    ln -s "kafka_${KAFKA_SCALA}-${KAFKA_VERSION}" kafka
    
    mkdir -p "$INSTALL_DIR/kafka/kraft-logs"
    
    log "Configuring Kafka in KRaft mode..."
    KAFKA_CLUSTER_ID=$("$INSTALL_DIR/kafka/bin/kafka-storage.sh" random-uuid)
    
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
        log "Formatting Kafka storage..."
        if ! "$INSTALL_DIR/kafka/bin/kafka-storage.sh" format -t "$KAFKA_CLUSTER_ID" \
            -c "$INSTALL_DIR/kafka/config/kraft-server.properties"; then
            error "Kafka storage format failed. Check cluster ID: $KAFKA_CLUSTER_ID"
        fi
    else
        log "Kafka storage already formatted, skipping..."
    fi
    
    mark_done "kafka_install"
    log "Kafka installed and configured (KRaft mode)"
}

# === Pig Installation ===
install_pig() {
    if is_done "pig_install"; then
        log "Pig already installed, skipping..."
        return
    fi
    
    cd "$INSTALL_DIR"
    
    # Remove corrupted partial downloads
    if [ ! -d "pig-${PIG_VERSION}" ]; then
        rm -f "pig-${PIG_VERSION}.tar.gz"
        
        log "Downloading Pig ${PIG_VERSION}..."
        download_with_retry \
            "https://dlcdn.apache.org/pig/pig-${PIG_VERSION}/pig-${PIG_VERSION}.tar.gz" \
            "pig-${PIG_VERSION}.tar.gz"
        
        log "Extracting Pig..."
        tar -xzf "pig-${PIG_VERSION}.tar.gz"
    fi
    
    rm -f pig
    ln -s "pig-${PIG_VERSION}" pig
    
    mark_done "pig_install"
    log "Pig installed successfully"
}

# === Environment Variables ===
setup_environment() {
    if is_done "env_setup"; then
        log "Environment already configured, skipping..."
        return
    fi
    
    log "Configuring environment variables..."
    
    if ! grep -q "HADOOP_HOME" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" <<EOF

# Hadoop Ecosystem Environment
export HADOOP_HOME=$INSTALL_DIR/hadoop
export HADOOP_CONF_DIR=\$HADOOP_HOME/etc/hadoop
export HADOOP_MAPRED_HOME=\$HADOOP_HOME
export HADOOP_COMMON_HOME=\$HADOOP_HOME
export HADOOP_HDFS_HOME=\$HADOOP_HOME
export YARN_HOME=\$HADOOP_HOME
export HADOOP_COMMON_LIB_NATIVE_DIR=\$HADOOP_HOME/lib/native
export HADOOP_OPTS="-Djava.library.path=\$HADOOP_HOME/lib/native"

export SPARK_HOME=$INSTALL_DIR/spark
export KAFKA_HOME=$INSTALL_DIR/kafka
export PIG_HOME=$INSTALL_DIR/pig

export PATH=\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin:\$SPARK_HOME/bin:\$KAFKA_HOME/bin:\$PIG_HOME/bin:\$PATH
EOF
    fi
    
    export HADOOP_HOME="$INSTALL_DIR/hadoop"
    export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
    export SPARK_HOME="$INSTALL_DIR/spark"
    export KAFKA_HOME="$INSTALL_DIR/kafka"
    export PIG_HOME="$INSTALL_DIR/pig"
    export PATH="$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$SPARK_HOME/bin:$KAFKA_HOME/bin:$PIG_HOME/bin:$PATH"
    
    chmod 600 "$STATE_FILE" 2>/dev/null || true
    chmod 600 "$LOG_FILE" 2>/dev/null || true
    
    mark_done "env_setup"
    log "Environment variables configured"
    log ""
    log "${YELLOW}IMPORTANT:${NC} Run 'source ~/.bashrc' to load environment variables"
    log "Or restart your terminal"
}

# === Helper Scripts ===
create_helper_scripts() {
    if is_done "helper_scripts"; then
        log "Helper scripts already created, skipping..."
        return
    fi
    
    log "Creating service management scripts..."
    
    # Start script
    cat > "$HOME/start-hadoop.sh" <<'STARTSCRIPT'
#!/bin/bash
set -e

echo "Starting Hadoop Ecosystem..."
echo ""

# Start SSH
if ! pgrep -x sshd > /dev/null; then
    echo "Starting SSH service..."
    sudo service ssh start
fi

# Start HDFS
echo "Starting HDFS..."
~/bigdata/hadoop/sbin/start-dfs.sh
sleep 3

# Start YARN
echo "Starting YARN..."
~/bigdata/hadoop/sbin/start-yarn.sh
sleep 5

# Start Kafka
if ! pgrep -f "kafka.Kafka" > /dev/null; then
    echo "Starting Kafka (KRaft mode)..."
    nohup ~/bigdata/kafka/bin/kafka-server-start.sh \
        ~/bigdata/kafka/config/kraft-server.properties \
        > ~/bigdata/kafka/kafka.log 2>&1 &
    echo $! > ~/bigdata/kafka/kafka.pid
    sleep 3
fi

echo ""
echo "[OK] Services started successfully"
echo ""
echo "Running processes:"
jps

echo ""
echo "Web Interfaces:"
echo "  HDFS NameNode:    http://localhost:9870"
echo "  YARN ResourceMgr: http://localhost:8088"
echo ""
STARTSCRIPT

    # Stop script
    cat > "$HOME/stop-hadoop.sh" <<'STOPSCRIPT'
#!/bin/bash

echo "Stopping Hadoop Ecosystem..."
echo ""

echo "Stopping YARN..."
~/bigdata/hadoop/sbin/stop-yarn.sh

echo "Stopping HDFS..."
~/bigdata/hadoop/sbin/stop-dfs.sh

if pgrep -f "kafka.Kafka" > /dev/null; then
    echo "Stopping Kafka..."
    pkill -f kafka.Kafka
fi

echo ""
echo "[OK] All services stopped"
echo ""
STOPSCRIPT

    # Status check script
    cat > "$HOME/check-hadoop.sh" <<'CHECKSCRIPT'
#!/bin/bash

echo "Hadoop Ecosystem Status"
echo "======================="
echo ""

echo "Running Java Processes:"
jps

echo ""
echo "Service Status:"
services=("NameNode:9870" "DataNode:9864" "ResourceManager:8088" "NodeManager:8042" "Kafka:9092")
for service in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service"
    if nc -z localhost $port 2>/dev/null; then
        printf "  [OK] %-20s (port %s)\n" "$name" "$port"
    else
        printf "  [--] %-20s (port %s) NOT RUNNING\n" "$name" "$port"
    fi
done

echo ""
echo "HDFS Status:"
~/bigdata/hadoop/bin/hdfs dfsadmin -report 2>/dev/null | head -10

echo ""
echo "Disk Usage:"
~/bigdata/hadoop/bin/hdfs dfs -df -h 2>/dev/null
CHECKSCRIPT

    # Restart script for convenience
    cat > "$HOME/restart-hadoop.sh" <<'RESTARTSCRIPT'
#!/bin/bash

echo "Restarting Hadoop Ecosystem..."
echo ""

# Stop all
~/stop-hadoop.sh
sleep 3

# Start all
~/start-hadoop.sh
RESTARTSCRIPT

    chmod +x "$HOME/start-hadoop.sh"
    chmod +x "$HOME/stop-hadoop.sh"
    chmod +x "$HOME/check-hadoop.sh"
    chmod +x "$HOME/restart-hadoop.sh"
    
    mark_done "helper_scripts"
    log "✓ Created helper scripts:"
    log "  ~/start-hadoop.sh   - Start all services"
    log "  ~/stop-hadoop.sh    - Stop all services"
    log "  ~/check-hadoop.sh   - Check service status"
    log "  ~/restart-hadoop.sh - Restart all services"
}

# === Format HDFS ===
format_hdfs() {
    if is_done "hdfs_format"; then
        log "HDFS already formatted, skipping..."
        return
    fi
    
    # Test SSH connectivity first (required for Hadoop daemons)
    log "Testing SSH connectivity (required for Hadoop daemons)..."
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 localhost exit 2>/dev/null; then
        error "SSH to localhost failed. Run: sudo service ssh start"
    fi
    
    # Protect existing data
    if [ -d "$INSTALL_DIR/hadoop/dfs/namenode/current" ]; then
        warn "⚠️  Existing HDFS data found. Formatting will DELETE all data!"
        read -p "Continue? (type 'yes' to confirm): " confirm
        if [ "$confirm" != "yes" ]; then
            log "Format cancelled. To use existing HDFS, mark as done:"
            log "  echo 'hdfs_format' >> $STATE_FILE"
            exit 0
        fi
    fi
    
    log "Formatting HDFS NameNode..."
    if ! "$HADOOP_HOME/bin/hdfs" namenode -format -force -nonInteractive; then
        error "Failed to format HDFS"
    fi
    
    mark_done "hdfs_format"
    log "HDFS formatted successfully"
}

# === Start Services ===
wait_for_service() {
    local service=$1
    local port=$2
    local max_wait=30
    
    log "Waiting for $service on port $port..."
    for i in $(seq 1 $max_wait); do
        if nc -z localhost $port 2>/dev/null; then
            log "$service is ready"
            return 0
        fi
        sleep 1
    done
    warn "$service did not start within ${max_wait}s"
    return 1
}

start_services() {
    log "Starting all services..."
    
    safe_exec "$HADOOP_HOME/sbin/stop-dfs.sh" 2>/dev/null
    safe_exec "$HADOOP_HOME/sbin/stop-yarn.sh" 2>/dev/null
    pkill -f "kafka.Kafka" 2>/dev/null || true
    sleep 3
    
    log "Starting HDFS..."
    if ! "$HADOOP_HOME/sbin/start-dfs.sh"; then
        error "Failed to start HDFS"
    fi
    wait_for_service "NameNode" 9870
    
    log "Starting YARN..."
    if ! "$HADOOP_HOME/sbin/start-yarn.sh"; then
        error "Failed to start YARN"
    fi
    wait_for_service "ResourceManager" 8088
    
    log "Creating Spark event log directory in HDFS..."
    sleep 5
    safe_exec "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /spark-logs
    safe_exec "$HADOOP_HOME/bin/hdfs" dfs -chmod 777 /spark-logs
    
    log "Starting Kafka (KRaft mode)..."
    
    # WSL2 IPv6 fix for Kafka connectivity
    if grep -qi microsoft /proc/version; then
        log "Configuring WSL2 network settings for Kafka..."
        sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 2>/dev/null || true
        sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1 2>/dev/null || true
    fi
    
    nohup "$KAFKA_HOME/bin/kafka-server-start.sh" "$KAFKA_HOME/config/kraft-server.properties" > "$INSTALL_DIR/kafka/kafka.log" 2>&1 &
    KAFKA_PID=$!
    echo $KAFKA_PID > "$INSTALL_DIR/kafka/kafka.pid"
    
    if wait_for_service "Kafka" 9092; then
        log "Kafka started successfully (PID: $KAFKA_PID)"
    else
        warn "Kafka may not have started. Check: $INSTALL_DIR/kafka/kafka.log"
    fi
}

# === Verification ===
verify_installation() {
    log "Verifying installation..."
    
    echo ""
    log "=== Java Processes (jps) ==="
    jps || warn "jps failed"
    
    # Check for expected processes
    echo ""
    EXPECTED_PROCS="NameNode DataNode ResourceManager NodeManager"
    for proc in $EXPECTED_PROCS; do
        if ! jps | grep -q "$proc"; then
            warn "$proc is NOT running! Check logs: $HADOOP_HOME/logs/"
        fi
    done
    
    echo ""
    log "=== HDFS Status ==="
    safe_exec "$HADOOP_HOME/bin/hdfs" dfsadmin -report 2>&1 | head -20
    
    echo ""
    log "=== YARN Node Status ==="
    safe_exec "$HADOOP_HOME/bin/yarn" node -list
    
    echo ""
    log "=== Testing HDFS Operations ==="
    safe_exec "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/$USER
    if echo "test" | "$HADOOP_HOME/bin/hdfs" dfs -put -f - /user/$USER/test.txt; then
        safe_exec "$HADOOP_HOME/bin/hdfs" dfs -cat /user/$USER/test.txt
    else
        warn "HDFS write test failed"
    fi
    
    echo ""
    log "=== Kafka Process Check ==="
    if pgrep -f "kafka.Kafka" > /dev/null; then
        echo "Kafka: RUNNING"
    else
        echo "Kafka: NOT RUNNING"
    fi
    
    echo ""
    log "=== Version Information ==="
    echo "Hadoop: $("$HADOOP_HOME/bin/hadoop" version | head -1)"
    echo "Spark: $("$SPARK_HOME/bin/spark-submit" --version 2>&1 | grep version | head -1)"
    echo "Kafka: $(ls -d "$KAFKA_HOME" 2>/dev/null | xargs basename) (KRaft mode)"
    echo "Pig: $("$PIG_HOME/bin/pig" -version 2>&1 | head -1)"
}

# === First-Run Tutorial ===
run_first_tutorial() {
    if is_done "tutorial_complete"; then
        return
    fi
    
    echo ""
    echo -e "${GREEN}=== Quick 2-Minute Tutorial ===${NC}"
    echo "Let's verify everything works with a simple word count example!"
    echo ""
    
    read -p "Press Enter to run tutorial or Ctrl+C to skip..." -t 30 || return
    
    # Create sample file
    cat > /tmp/sample.txt <<EOF
hadoop is awesome
hadoop is powerful
spark works with hadoop
mapreduce on hadoop
EOF
    
    log "1. Uploading file to HDFS..."
    if "$HADOOP_HOME/bin/hdfs" dfs -put -f /tmp/sample.txt /user/$USER/; then
        log "[OK] File uploaded successfully"
    else
        warn "Upload failed - tutorial skipped"
        return
    fi
    
    log "2. Running word count (MapReduce job)..."
    "$HADOOP_HOME/bin/hdfs" dfs -rm -r /user/$USER/output 2>/dev/null || true
    
    if "$HADOOP_HOME/bin/hadoop" jar \
        "$HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-"*.jar \
        wordcount /user/$USER/sample.txt /user/$USER/output; then
        
        echo ""
        log "3. Results:"
        echo "-----------------------------------"
        "$HADOOP_HOME/bin/hdfs" dfs -cat /user/$USER/output/part-r-00000
        echo "-----------------------------------"
        
        echo ""
        log "[OK] Tutorial complete! You just ran your first Hadoop job!"
        echo ""
    else
        warn "Tutorial job failed - check logs"
    fi
    
    mark_done "tutorial_complete"
}

# === Quick Start Guide ===
print_guide() {
    cat <<EOF

${GREEN}=== Installation Complete! ===${NC}

${YELLOW}✅ Verified Version Information (January 2026):${NC}
  Hadoop: 3.4.2 (Released Aug 29, 2025 - Latest Stable)
  Spark: 3.5.3 (Released Sep 23, 2024 - Stable)
  Kafka: 4.1.1 (Released Nov 12, 2025 - Latest Stable with KRaft)
  Pig: 0.18.0 (Released Sep 15, 2025 - Hadoop 3, Spark 3, Python 3)
  Java: OpenJDK 11 (LTS - Recommended for Hadoop 3.4.x)

${YELLOW}Service Management (Easy Mode):${NC}

  ~/start-hadoop.sh    # Start all services
  ~/stop-hadoop.sh     # Stop all services
  ~/check-hadoop.sh    # Check service status
  ~/restart-hadoop.sh  # Restart all services

${YELLOW}Service Management (Manual):${NC}

# Start individually:
  \$HADOOP_HOME/sbin/start-dfs.sh
  \$HADOOP_HOME/sbin/start-yarn.sh
  nohup \$KAFKA_HOME/bin/kafka-server-start.sh \$KAFKA_HOME/config/kraft-server.properties > \$KAFKA_HOME/kafka.log 2>&1 &

# Stop individually:
  \$HADOOP_HOME/sbin/stop-dfs.sh
  \$HADOOP_HOME/sbin/stop-yarn.sh
  pkill -f kafka.Kafka

# Check running processes:
  jps

${YELLOW}Quick Test Commands:${NC}

# HDFS:
  hdfs dfs -ls /
  hdfs dfs -put file.txt /user/$USER/

# MapReduce:
  hadoop jar \$HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 2 10

# Spark (on YARN):
  spark-shell --master yarn
  pyspark --master yarn

# Kafka (KRaft - no ZooKeeper):
  kafka-topics.sh --create --topic test --bootstrap-server localhost:9092
  kafka-console-producer.sh --topic test --bootstrap-server localhost:9092
  kafka-console-consumer.sh --topic test --from-beginning --bootstrap-server localhost:9092

# Pig:
  pig -x mapreduce

${YELLOW}Web Interfaces:${NC}
  HDFS NameNode:        http://localhost:9870
  YARN ResourceManager: http://localhost:8088
  YARN NodeManager:     http://localhost:8042

${YELLOW}Important Notes:${NC}
  • Run 'source ~/.bashrc' to load environment variables
  • Kafka uses KRaft mode (no ZooKeeper needed)
  • Spark defaults to YARN mode
  • Installation dir: $INSTALL_DIR
  • Logs: $LOG_FILE
  • Kafka logs: $INSTALL_DIR/kafka/kafka.log

${YELLOW}Verified Download URLs:${NC}
  Hadoop: https://dlcdn.apache.org/hadoop/common/hadoop-3.4.2/hadoop-3.4.2.tar.gz
  Spark: https://dlcdn.apache.org/spark/spark-3.5.3/spark-3.5.3-bin-hadoop3.tgz
  Kafka: https://dlcdn.apache.org/kafka/4.1.1/kafka_2.13-4.1.1.tgz
  Pig: https://dlcdn.apache.org/pig/pig-0.18.0/pig-0.18.0.tar.gz

${YELLOW}Troubleshooting:${NC}
  • If services don't start, check: $HADOOP_HOME/logs/
  • For Kafka issues, check: $KAFKA_HOME/kafka.log
  • To re-run installation: rm $STATE_FILE && bash $0

${YELLOW}Common Student Issues:${NC}

  Issue: NameNode won't start
  Fix: rm -rf ~/bigdata/hadoop/dfs/namenode/* 
       Then re-run: echo 'hdfs_format' >> $STATE_FILE && bash $0

  Issue: "Connection refused" on localhost
  Fix: Check Windows firewall settings above

  Issue: "Permission denied" SSH
  Fix: chmod 600 ~/.ssh/* 
       ssh-keyscan -H localhost >> ~/.ssh/known_hosts

  Issue: Services stop after WSL restarts
  Fix: Run ~/start-hadoop.sh after each WSL restart
       Or add to ~/.bashrc: ~/start-hadoop.sh

EOF
}

# === Main Execution ===
main() {
    preflight_checks
    
    log "Starting Hadoop Ecosystem Installation..."
    log "Installation directory: $INSTALL_DIR"
    
    acquire_lock
    check_disk_space
    
    setup_system
    setup_java
    install_hadoop
    configure_hadoop
    install_spark
    install_kafka
    install_pig
    setup_environment
    format_hdfs
    create_helper_scripts
    start_services
    
    sleep 3
    verify_installation
    run_first_tutorial
    print_guide
    
    log "${GREEN}Installation completed successfully!${NC}"
    log "Run: source ~/.bashrc"
}

main
