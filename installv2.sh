#!/bin/bash

# WSL Hadoop Ecosystem - Interactive Menu Installer
# by github.com/darshan-gowdaa

set -Eeo pipefail

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
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ==================== UTILITY FUNCTIONS ====================

log() { echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

mark_done() { echo "$1" >> "$STATE_FILE"; }
is_done() { [ -f "$STATE_FILE" ] && grep -Fxq "$1" "$STATE_FILE" 2>/dev/null; }

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
    ("$@" &>/dev/null) & spinner $! "$msg"
}

download_file() {
    local url=$1
    local output=$2
    local mirrors=(
        "$url"
        "https://dlcdn.apache.org/$(echo $url | sed 's|https://[^/]*/||')"
        "https://archive.apache.org/dist/$(echo $url | sed 's|https://[^/]*/||')"
    )
    
    for mirror in "${mirrors[@]}"; do
        if wget --progress=bar:force --timeout=60 --tries=2 -O "$output" "$mirror" 2>&1; then
            [ -f "$output" ] && [ $(stat -c%s "$output") -gt 1000000 ] && return 0
            rm -f "$output"
        fi
    done
    return 1
}

# ==================== PRE-FLIGHT CHECKS ====================

preflight_checks() {
    clear
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Hadoop WSL Installer - github.com/darshan-gowdaa  ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}\n"
    
    # Check WSL
    if ! grep -qi microsoft /proc/version 2>/dev/null; then
        error "Not running on WSL. This installer is WSL-optimized."
    fi
    
    # Check WSL2
    if ! grep -q "WSL2" /proc/version 2>/dev/null; then
        echo -e "${YELLOW}WARNING: WSL1 detected. Performance will be poor.${NC}"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    fi
    
    # Check location
    [[ $(readlink -f "$PWD") == /mnt/* ]] && error "Run from Linux filesystem, not /mnt/"
    
    # Check memory
    local mem_gb=$(free -m | awk '/^Mem:/{print int($2/1024)}')
    [ $mem_gb -lt 6 ] && echo -e "${YELLOW}WARNING: Only ${mem_gb}GB RAM. Recommend 8GB+${NC}"
    
    # Check disk space
    local avail_gb=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    [ $avail_gb -lt 12 ] && error "Need 12GB+ free space. Available: ${avail_gb}GB"
    
    # Check sudo
    sudo -v || error "Sudo access required"
    
    success "Pre-flight checks passed"
    sleep 1
}

# ==================== INSTALLATION FUNCTIONS ====================

install_system_deps() {
    if is_done "system_setup"; then
        info "System dependencies already installed"
        return
    fi
    
    echo -e "\n${BOLD}[1/8] Installing System Dependencies${NC}"
    
    execute_with_spinner "Updating package lists" sudo apt-get update -qq
    
    local pkgs=(openjdk-11-jdk openjdk-17-jdk wget ssh netcat-openbsd vim mysql-server)
    execute_with_spinner "Installing packages" sudo apt-get install -y "${pkgs[@]}" -qq
    
    execute_with_spinner "Configuring Java 11 as default" \
        sudo update-alternatives --set java /usr/lib/jvm/java-11-openjdk-amd64/bin/java
    
    # SSH setup
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        execute_with_spinner "Generating SSH keys" \
            ssh-keygen -t rsa -P '' -f "$HOME/.ssh/id_rsa" -q
        cat "$HOME/.ssh/id_rsa.pub" >> "$HOME/.ssh/authorized_keys"
    fi
    
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/id_rsa ~/.ssh/authorized_keys
    chmod 644 ~/.ssh/id_rsa.pub
    
    # SSH config
    cat > ~/.ssh/config <<'EOF'
Host localhost 127.0.0.1 0.0.0.0
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
    chmod 600 ~/.ssh/config
    
    # Start services
    sudo service ssh start &>/dev/null || true
    sudo service mysql start &>/dev/null || true
    
    # IPv6 fix
    if ! grep -q "disable_ipv6" /etc/sysctl.conf 2>/dev/null; then
        echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf >/dev/null
        sudo sysctl -p >/dev/null 2>&1 || true
    fi
    
    mark_done "system_setup"
    success "System dependencies installed"
}

install_hadoop() {
    if is_done "hadoop_full"; then
        info "Hadoop already installed"
        return
    fi
    
    echo -e "\n${BOLD}[2/8] Installing Hadoop ${HADOOP_VERSION}${NC}"
    
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
    if is_done "spark_full"; then
        info "Spark already installed"
        return
    fi
    
    echo -e "\n${BOLD}[3/8] Installing Spark ${SPARK_VERSION}${NC}"
    
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
    if is_done "kafka_full"; then
        info "Kafka already installed"
        return
    fi
    
    echo -e "\n${BOLD}[4/8] Installing Kafka ${KAFKA_VERSION}${NC}"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "kafka_2.13-${KAFKA_VERSION}" ]; then
        download_file \
            "https://dlcdn.apache.org/kafka/${KAFKA_VERSION}/kafka_2.13-${KAFKA_VERSION}.tgz" \
            "kafka.tgz" || error "Kafka download failed"
        
        execute_with_spinner "Extracting Kafka" tar -xzf kafka.tgz
        rm kafka.tgz
    fi
    
    rm -f kafka && ln -s "kafka_2.13-${KAFKA_VERSION}" kafka
    mkdir -p "$INSTALL_DIR/kafka/kraft-logs"
    
    # Generate cluster ID
    local cid
    if [ -f "$INSTALL_DIR/kafka/.cluster-id" ]; then
        cid=$(cat "$INSTALL_DIR/kafka/.cluster-id")
    else
        cid=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 "$INSTALL_DIR/kafka/bin/kafka-storage.sh" random-uuid)
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
EOF
    
    # Format storage
    if [ ! -f "$INSTALL_DIR/kafka/kraft-logs/meta.properties" ]; then
        JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
            "$INSTALL_DIR/kafka/bin/kafka-storage.sh" format -t "$cid" \
            -c "$INSTALL_DIR/kafka/config/kraft-server.properties" &>/dev/null
    fi
    
    mark_done "kafka_full"
    success "Kafka installed and configured"
}

install_pig() {
    if is_done "pig_full"; then
        info "Pig already installed"
        return
    fi
    
    echo -e "\n${BOLD}[5/8] Installing Pig ${PIG_VERSION}${NC}"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "pig-${PIG_VERSION}" ]; then
        download_file \
            "https://archive.apache.org/dist/pig/pig-${PIG_VERSION}/pig-${PIG_VERSION}.tar.gz" \
            "pig.tgz" || error "Pig download failed"
        
        execute_with_spinner "Extracting Pig" tar -xzf pig.tgz
        rm pig.tgz
    fi
    
    rm -f pig && ln -s "pig-${PIG_VERSION}" pig
    
    mark_done "pig_full"
    success "Pig installed"
}

install_hive() {
    if is_done "hive_full"; then
        info "Hive already installed"
        return
    fi
    
    echo -e "\n${BOLD}[6/8] Installing Hive ${HIVE_VERSION}${NC}"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "apache-hive-${HIVE_VERSION}-bin" ]; then
        download_file \
            "https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" \
            "hive.tgz" || error "Hive download failed"
        
        execute_with_spinner "Extracting Hive" tar -xzf hive.tgz
        rm hive.tgz
    fi
    
    rm -f hive && ln -s "apache-hive-${HIVE_VERSION}-bin" hive
    
    # MySQL setup
    sudo service mysql start &>/dev/null || true
    sleep 2
    
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

setup_environment() {
    if is_done "env_setup"; then
        info "Environment already configured"
        return
    fi
    
    echo -e "\n${BOLD}[7/8] Configuring Environment${NC}"
    
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
    if is_done "scripts_created"; then
        info "Helper scripts already created"
        return
    fi
    
    echo -e "\n${BOLD}[8/8] Creating Helper Scripts${NC}"
    
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

"$INSTALL_DIR/hadoop/bin/hdfs" dfs -mkdir -p /user/$USER /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null
"$INSTALL_DIR/hadoop/bin/hdfs" dfs -chmod 777 /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null

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

# ==================== MENU SYSTEM ====================

show_menu() {
    clear
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Hadoop Ecosystem Installer - Interactive Menu    ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${CYAN}Installation Options:${NC}"
    echo -e "  ${BOLD}1)${NC} Full Installation (All Components)"
    echo -e "  ${BOLD}2)${NC} Hadoop Only"
    echo -e "  ${BOLD}3)${NC} Spark Only"
    echo -e "  ${BOLD}4)${NC} Kafka Only"
    echo -e "  ${BOLD}5)${NC} Pig Only"
    echo -e "  ${BOLD}6)${NC} Hive Only"
    echo ""
    echo -e "${CYAN}Management:${NC}"
    echo -e "  ${BOLD}7)${NC} Start All Services"
    echo -e "  ${BOLD}8)${NC} Stop All Services"
    echo -e "  ${BOLD}9)${NC} Check Status"
    echo -e "  ${BOLD}0)${NC} Exit"
    echo ""
}

check_status() {
    echo -e "\n${BOLD}Service Status:${NC}"
    
    local services=("NameNode:9870" "DataNode:9864" "ResourceManager:8088" "NodeManager:8042" "Kafka:9092" "HiveMetaStore:9083")
    for svc in "${services[@]}"; do
        IFS=':' read -r name port <<< "$svc"
        if nc -z localhost "$port" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $name"
        else
            echo -e "  ${RED}✗${NC} $name"
        fi
    done
    echo ""
    
    jps 2>/dev/null | grep -v "Jps" || echo "No Java processes running"
}

start_services() {
    echo -e "\n${BOLD}Starting Services...${NC}\n"
    
    export HADOOP_HOME="$INSTALL_DIR/hadoop"
    
    execute_with_spinner "Starting HDFS" "$HADOOP_HOME/sbin/start-dfs.sh"
    sleep 3
    execute_with_spinner "Starting YARN" "$HADOOP_HOME/sbin/start-yarn.sh"
    sleep 3
    
    "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/$USER /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null
    "$HADOOP_HOME/bin/hdfs" dfs -chmod 777 /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null
    
    nohup "$INSTALL_DIR/hive/bin/hive" --service metastore &>/dev/null &
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
        nohup "$INSTALL_DIR/kafka/bin/kafka-server-start.sh" \
        "$INSTALL_DIR/kafka/config/kraft-server.properties" &>/dev/null &
    
    success "All services started"
    echo -e "  HDFS: ${CYAN}http://localhost:9870${NC}"
    echo -e "  YARN: ${CYAN}http://localhost:8088${NC}"
}

stop_services() {
    echo -e "\n${BOLD}Stopping Services...${NC}\n"
    
    export HADOOP_HOME="$INSTALL_DIR/hadoop"
    
    execute_with_spinner "Stopping YARN" "$HADOOP_HOME/sbin/stop-yarn.sh"
    execute_with_spinner "Stopping HDFS" "$HADOOP_HOME/sbin/stop-dfs.sh"
    
    pkill -f HiveMetaStore &>/dev/null || true
    pkill -f kafka.Kafka &>/dev/null || true
    
    success "All services stopped"
}

# ==================== MAIN ====================

main() {
    preflight_checks
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1)
                install_system_deps
                install_hadoop
                install_spark
                install_kafka
                install_pig
                install_hive
                setup_environment
                create_scripts
                echo -e "\n${GREEN}✓ Full installation complete!${NC}"
                echo -e "Run: ${CYAN}source ~/.bashrc${NC} and ${CYAN}~/start-hadoop.sh${NC}"
                read -p "Press Enter to continue..."
                ;;
            2)
                install_system_deps
                install_hadoop
                setup_environment
                create_scripts
                success "Hadoop installed"
                read -p "Press Enter to continue..."
                ;;
            3)
                install_system_deps
                install_hadoop
                install_spark
                setup_environment
                success "Spark installed"
                read -p "Press Enter to continue..."
                ;;
            4)
                install_system_deps
                install_kafka
                setup_environment
                success "Kafka installed"
                read -p "Press Enter to continue..."
                ;;
            5)
                install_system_deps
                install_hadoop
                install_pig
                setup_environment
                success "Pig installed"
                read -p "Press Enter to continue..."
                ;;
            6)
                install_system_deps
                install_hadoop
                install_hive
                setup_environment
                success "Hive installed"
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
            0)
                echo -e "\n${GREEN}Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

main