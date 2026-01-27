#!/bin/bash

# WSL Hadoop Ecosystem - Interactive Menu Installer
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
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ==================== UTILITY FUNCTIONS ====================

log() { echo "[$(date +'%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

mark_done() { echo "$1" >> "$STATE_FILE"; }
is_done() { [ -f "$STATE_FILE" ] && grep -Fxq "$1" "$STATE_FILE" 2>/dev/null; }

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
            rm -f "$output"
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
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Hadoop WSL Installer - github.com/darshan-gowdaa  ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}\n"
    
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
    
    # Check sudo
    if ! sudo -n true 2>/dev/null; then
        info "Sudo access required. Please enter password:"
        sudo -v || error "Sudo authentication failed"
    fi
    
    success "Pre-flight checks passed"
    sleep 1
}

# ==================== INSTALLATION FUNCTIONS ====================

install_system_deps() {
    if is_done "system_setup"; then
        info "System dependencies already installed"
        return
    fi
    
    echo -e "\n${BOLD}Installing System Dependencies${NC}"
    
    if ! execute_with_spinner "Updating package lists" sudo apt-get update -qq; then
        warn "Package update had warnings, continuing..."
    fi
    
    local pkgs=(openjdk-11-jdk openjdk-17-jdk wget ssh netcat-openbsd vim mysql-server rsync)
    if ! execute_with_spinner "Installing packages" sudo apt-get install -y "${pkgs[@]}" -qq; then
        error "Package installation failed. Check your internet connection and try again."
    fi
    
    # Verify Java installation
    if [ ! -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
        error "Java 11 installation failed. Run: sudo apt-get install -y openjdk-11-jdk"
    fi
    
    if [ ! -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
        error "Java 17 installation failed. Run: sudo apt-get install -y openjdk-17-jdk"
    fi
    
    safe_execute sudo update-alternatives --set java /usr/lib/jvm/java-11-openjdk-amd64/bin/java
    
    # SSH setup with error checking
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        mkdir -p "$HOME/.ssh"
        if ! ssh-keygen -t rsa -P '' -f "$HOME/.ssh/id_rsa" -q &>/dev/null; then
            error "SSH key generation failed"
        fi
        cat "$HOME/.ssh/id_rsa.pub" >> "$HOME/.ssh/authorized_keys"
    fi
    
    chmod 700 ~/.ssh 2>/dev/null || true
    chmod 600 ~/.ssh/id_rsa 2>/dev/null || true
    chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true
    chmod 644 ~/.ssh/id_rsa.pub 2>/dev/null || true
    
    # SSH config
    mkdir -p ~/.ssh
    cat > ~/.ssh/config <<'EOF'
Host localhost 127.0.0.1 0.0.0.0
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF
    chmod 600 ~/.ssh/config
    
    # Start services with checks
    if ! pgrep -x sshd >/dev/null; then
        sudo service ssh start &>/dev/null || warn "SSH service failed to start"
    fi
    
    if ! pgrep -x mysqld > /dev/null; then
        # Ensure MySQL directories exist
        sudo mkdir -p /var/run/mysqld 2>/dev/null || true
        sudo chown mysql:mysql /var/run/mysqld 2>/dev/null || true
        
        if ! sudo service mysql start &>/dev/null; then
            warn "MySQL service failed to start"
            warn "Hive installation will fail without MySQL"
            warn "To fix manually run: sudo service mysql start"
        else
            success "MySQL service started"
        fi
    fi
    
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
    
    echo -e "\n${BOLD}Installing Hadoop ${HADOOP_VERSION}${NC}"
    
    # Verify Java 11 exists
    if [ ! -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
        error "Java 11 not found. Install with: sudo apt-get install -y openjdk-11-jdk"
    fi
    
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
    if is_done "spark_full"; then
        info "Spark already installed"
        return
    fi
    
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
    if is_done "kafka_full"; then
        info "Kafka already installed"
        return
    fi
    
    echo -e "\n${BOLD}Installing Kafka ${KAFKA_VERSION}${NC}"
    
    # Verify Java 17 exists
    if [ ! -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
        error "Java 17 not found. Install with: sudo apt-get install -y openjdk-17-jdk"
    fi
    
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
    if is_done "pig_full"; then
        info "Pig already installed"
        return
    fi
    
    echo -e "\n${BOLD}Installing Pig ${PIG_VERSION}${NC}"
    
    cd "$INSTALL_DIR"
    
    if [ ! -d "pig-${PIG_VERSION}" ]; then
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
    if is_done "hive_full"; then
        info "Hive already installed"
        return
    fi
    
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
    if ! sudo service mysql start &>/dev/null; then
        if ! pgrep -x mysqld > /dev/null; then
            error "MySQL is required for Hive but failed to start. Run: sudo service mysql start"
        fi
    fi
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

install_eclipse() {
    if is_done "eclipse_full"; then
        info "Eclipse already installed"
        return
    fi

    echo -e "\n${BOLD}Installing Eclipse IDE for MapReduce Development${NC}"
    
    # Install Maven via apt
    if ! command -v mvn &>/dev/null; then
        if ! execute_with_spinner "Installing Maven" sudo apt-get install -y maven -qq; then
            warn "Maven installation failed, continuing..."
        fi
    fi

    # Install Eclipse via snap
    if ! command -v eclipse &>/dev/null; then
        if ! execute_with_spinner "Installing Eclipse via snap" sudo snap install eclipse --classic; then
            error "Eclipse snap installation failed. Check your internet connection."
        fi
    else
        info "Eclipse already installed"
    fi

    # Verify Eclipse is available
    if ! command -v eclipse &>/dev/null; then
        error "Eclipse installation failed. Try manually: sudo snap install eclipse --classic"
    fi

    # Create directory before writing script
    mkdir -p "$HOME/.local/bin"

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

exec eclipse
EOF

    chmod +x "$HOME/.local/bin/eclipse-hadoop.sh"
    sudo ln -sf "$HOME/.local/bin/eclipse-hadoop.sh" /usr/local/bin/eclipse-hadoop

    cat >"$HOME/ECLIPSE_MAPREDUCE_GUIDE.txt" <<'GUIDE'
=================================================================
  Eclipse MapReduce Development Guide (No Plugins Required)
=================================================================

QUICK START:
------------
1. Launch Eclipse with Hadoop environment:
   $ eclipse-hadoop
   
   (Or just: eclipse &)

2. Create New Java Project:
   File → New → Java Project
   - Project name: WordCount
   - JRE: Select "JavaSE-11"
   - Click "Finish"

3. Add Hadoop Dependencies (Choose ONE method):

   METHOD A: Using Maven (Easier!, but not recommended by the teacher)
   ---------------------------------------------
   Right-click project → Configure → Convert to Maven Project
   
   Open pom.xml and add inside <project>:
   
   <dependencies>
       <dependency>
           <groupId>org.apache.hadoop</groupId>
           <artifactId>hadoop-client</artifactId>
           <version>3.4.2</version>
       </dependency>
   </dependencies>
   
   Save → Right-click project → Maven → Update Project
   
   METHOD B: Manual JARs (Followed by the TEACHER)
   ------------------------------------
   Right-click project → Build Path → Configure Build Path
   → Libraries → Add External JARs
   
   Add ALL JARs from:
   ~/bigdata/hadoop-3.4.2/share/hadoop/common/*.jar
   ~/bigdata/hadoop-3.4.2/share/hadoop/mapreduce/*.jar
   ~/bigdata/hadoop-3.4.2/share/hadoop/hdfs/*.jar
   ~/bigdata/hadoop-3.4.2/share/hadoop/yarn/*.jar
   
   Click "Apply and Close"

4. Write Your MapReduce Code:
   Create: src/wordcount/WordCount.java
   (Use standard MapReduce template)

5. Export JAR:
   Right-click project → Export → Java → Runnable JAR File
   - Launch configuration: Choose "WordCount"
   - Export destination: /home/$USER/wordcount.jar
   - Library handling: "Extract required libraries into generated JAR"
   - Click "Finish"

6. Run on Hadoop:
   $ hdfs dfs -mkdir -p /input
   $ hdfs dfs -put input.txt /input/
   $ hadoop jar ~/wordcount.jar wordcount.WordCount /input /output
   $ hdfs dfs -cat /output/part-r-00000

IMPORTANT NOTES:
----------------
✓ Maven method is cleaner and manages dependencies automatically
✓ NO Hadoop Eclipse plugins needed - plugins are outdated/buggy
✓ This is the exam-safe, production-standard method
✓ Export as "Runnable JAR" includes all dependencies
✓ Use "hadoop jar" command to run (not java -jar)
✓ Package name in command must match Java code

TROUBLESHOOTING:
----------------
• ClassNotFoundException: Check package name in command
• JAR runs locally but not on Hadoop: Re-export with dependencies
• GUI doesn't open: Ensure WSLg is working (Windows 11 required)
• Maven not found: Restart Eclipse after installation

=================================================================
GUIDE

    success "Eclipse and Maven installed successfully"
    info "Launch: eclipse-hadoop | Guide: cat ~/ECLIPSE_MAPREDUCE_GUIDE.txt"
    
    mark_done "eclipse_full"
}

setup_environment() {
    if is_done "env_setup"; then
        info "Environment already configured"
        return
    fi
    
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
    if is_done "scripts_created"; then
        info "Helper scripts already created"
        return
    fi
    
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
    echo -e "${GREEN}║ Hadoop Installation for WSL github.com/darshangowdaa  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${CYAN}Installation Options:${NC}"
    echo -e "  ${BOLD}1)${NC} Hadoop Only"
    echo -e "  ${BOLD}2)${NC} Spark Only"
    echo -e "  ${BOLD}3)${NC} Kafka Only"
    echo -e "  ${BOLD}4)${NC} Pig Only [Beta Version]"
    echo -e "  ${BOLD}5)${NC} Hive Only [Beta Version]"
    echo -e "  ${BOLD}6)${NC} Eclipse IDE with Hadoop Plugin"
    echo ""
    echo -e "${CYAN}Management:${NC}"
    echo -e "  ${BOLD}7)${NC} Start All Services"
    echo -e "  ${BOLD}8)${NC} Stop All Services"
    echo -e "  ${BOLD}9)${NC} Check Status"
    echo -e "  ${BOLD}0)${NC} Exit"
    echo ""
}

check_status() {
    echo -e "\n${BOLD}Service Status:${NC}\n"
    
    local services=("NameNode:9870" "DataNode:9864" "ResourceManager:8088" "NodeManager:8042" "Kafka:9092" "HiveMetaStore:9083")
    for svc in "${services[@]}"; do
        IFS=':' read -r name port <<< "$svc"
        if nc -z localhost "$port" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $name (port $port)"
        else
            echo -e "  ${RED}✗${NC} $name (port $port)"
        fi
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
    if [ ! -d "$HADOOP_HOME" ]; then
        error "Hadoop not installed. Install it first from menu."
    fi
    
    # Ensure SSH is running
    if ! pgrep -x sshd >/dev/null; then
        sudo service ssh start &>/dev/null || warn "SSH service not started"
    fi
    
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
    if ! pgrep -f "NameNode" >/dev/null; then
        error "NameNode failed to start. Check: $HADOOP_HOME/logs/hadoop-$USER-namenode-*.log"
    fi
    
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
    
    # Create HDFS directories
    info "Creating HDFS directories..."
    "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/$USER 2>/dev/null || true
    "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /spark-logs 2>/dev/null || true
    "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/hive/warehouse 2>/dev/null || true
    "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /tmp/hive 2>/dev/null || true
    "$HADOOP_HOME/bin/hdfs" dfs -chmod 777 /spark-logs /user/hive/warehouse /tmp/hive 2>/dev/null || true
    
    # Start Hive Metastore if installed
    if [ -d "$INSTALL_DIR/hive" ] && is_done "hive_full"; then
        if ! pgrep -f "HiveMetaStore" >/dev/null; then
            info "Starting Hive Metastore..."
            
            # Ensure MySQL is running
            if ! pgrep -x mysqld >/dev/null; then
                sudo service mysql start &>/dev/null || warn "MySQL not started"
            fi
            
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
    if [ -x "$HADOOP_HOME/sbin/stop-yarn.sh" ]; then
        execute_with_spinner "Stopping YARN" "$HADOOP_HOME/sbin/stop-yarn.sh"
    fi
    
    # Stop HDFS
    if [ -x "$HADOOP_HOME/sbin/stop-dfs.sh" ]; then
        execute_with_spinner "Stopping HDFS" "$HADOOP_HOME/sbin/stop-dfs.sh"
    fi
    
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
        
        # Validate input is numeric
        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid option. Please enter a number (0-9).${NC}"
            sleep 2
            continue
        fi
        
        case $choice in

    1)
        install_system_deps
        install_hadoop
        setup_environment
        create_scripts
        success "Hadoop installed"
        echo -e "Run: ${CYAN}source ~/.bashrc${NC}"
        read -p "Press Enter to continue..."
        ;;
    2)
        install_system_deps
        install_hadoop
        install_spark
        setup_environment
        success "Spark installed"
        echo -e "Run: ${CYAN}source ~/.bashrc${NC}"
        read -p "Press Enter to continue..."
        ;;
    3)
        install_system_deps
        install_kafka
        setup_environment
        success "Kafka installed"
        echo -e "Run: ${CYAN}source ~/.bashrc${NC}"
        read -p "Press Enter to continue..."
        ;;
    4)
        install_system_deps
        install_hadoop
        install_pig
        setup_environment
        success "Pig installed"
        echo -e "Run: ${CYAN}source ~/.bashrc${NC}"
        read -p "Press Enter to continue..."
        ;;
    5)
        install_system_deps
        install_hadoop
        install_hive
        setup_environment
        success "Hive installed"
        echo -e "Run: ${CYAN}source ~/.bashrc${NC}"
        read -p "Press Enter to continue..."
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
    0)
        echo -e "\n${GREEN}Goodbye!${NC}\n"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid option. Please select 0-9.${NC}"
        sleep 2
        ;;
esac
    done
}

main
