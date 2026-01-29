# Hadoop WSL Installer
<p align="center">
<img width="500" height="600" alt="image" src="https://github.com/user-attachments/assets/d57eac95-8f87-4970-983b-d4b4043645db" />
</p>

Simple one-command setup to run the **Hadoop ecosystem on WSL2**.
Made for students so you don't waste time fixing Java, SSH, or HDFS issues.

---


Everything installs inside:

```
~/bigdata/
```

---

## Requirements

* Windows 10/11
* Minimum **16 GB RAM recommended** (8 GB also works with limits)
* ~15 GB free disk space
* Internet connection

---

## Pre-Installation (One Time)

### Step 1: Install WSL

Open **PowerShell as Administrator** and run:

```powershell
wsl --update
```

Wait for the update to complete.

Then, install Ubuntu using **one of the following options**:

**Option A: Command Line**
```powershell
wsl --install ubuntu
```

**Option B: Microsoft Store**  
[Download Ubuntu from Microsoft Store](https://apps.microsoft.com/detail/9pdxgncfsczv?hl=en-US&gl=IN)

After installation completes, **close PowerShell**.

---

### Step 2: Enable Required Windows Features

1. Open **Start Menu** → search **Turn Windows features on or off**

2. Enable the following options:

   * **Windows Subsystem for Linux**
   * **Virtual Machine Platform**

<img width="400" height="400" alt="Windows Features" src="https://github.com/user-attachments/assets/9904ae6e-7f4c-4e2a-b162-b2180f13ecec" />

3. Click **OK** and **restart when prompted**

---

### Step 3: WSL Memory Setup (IMPORTANT)

You can configure WSL memory either through **WSL Settings in Windows** (easier) or by **creating a config file** (more control).

---

#### **Option A: Using WSL Settings (Recommended for Beginners)**

1. **Open WSL Settings**
   - Press the **Windows key** (or click Start)
   - Type: **`WSL Settings`**
   - Click on **"WSL Settings"** or **"Windows Subsystem for Linux Settings"**

2. **Navigate to Memory and Processor**
   - In the left sidebar, click **"Memory and processor"**

3. **Configure Based on Your System RAM**

   **If your system has 8 GB RAM:**
   - **Processor Count**: Set to **2**
   - **Memory Size**: Set to **6144 MB** (6 GB)
   - **Swap Size**: Set to **2048 MB** (2 GB)
   
   **If your system has 16 GB RAM or more:**
   - **Processor Count**: Set to **4**
   - **Memory Size**: Set to **8192 MB** (8 GB)
   - **Swap Size**: Set to **2048 MB** (2 GB)

   <img width="600" alt="WSL Memory Settings" src="https://github.com/user-attachments/assets/c69aee87-732f-4b46-a5bb-55a71b3e014d" />

4. **Apply Changes**
   - The settings save automatically
   - Open **PowerShell** and run:
   ```powershell
   wsl --shutdown
   ```
   - Wait 10 seconds, then reopen Ubuntu

---

#### **Option B: Manual Configuration File (If WSL Settings Not Available)**

If you don't see "WSL Settings" in Windows search (older Windows versions), use the manual method:

**Step 1:** Create this file in Windows:
```
C:\Users\<YOUR_WINDOWS_USERNAME>\.wslconfig
```

> **Finding your Windows username:**
> - Open File Explorer → Click "This PC" → "C:" → "Users"
> - Your folder name is your username

**Step 2:** Open with **Notepad** and paste:

**For 8 GB RAM:**
```ini
[wsl2]
memory=6GB
processors=2
swap=2GB
```

**For 16 GB+ RAM:**
```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
```

**Step 3:** Save and apply:
```powershell
wsl --shutdown
```

<img width="400" height="450" alt="wslconfig file" src="https://github.com/user-attachments/assets/94c98c4c-562e-4ab6-85b3-bab8676b4298" />

---

**Why This Matters:**
- Without proper limits, WSL can consume all your RAM and freeze Windows
- Hadoop/Spark need sufficient memory but shouldn't starve your host OS
- These settings ensure stable performance during big data operations

**Troubleshooting:**
- If installation fails with "out of memory", reduce memory allocation by 1-2 GB
- You can adjust these settings anytime and restart WSL with `wsl --shutdown`

---

### Step 4: Open Ubuntu (WSL)

After reboot:

* Open **Ubuntu** from Start Menu **or**
* Open **PowerShell / Command Prompt** and run:

```powershell
wsl
```

Create your Linux username and password when prompted.

---

## Installation

Run the installer **inside Ubuntu (WSL)**:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/darshan-gowdaa/wsl-hadoop-installer/main/installv3.sh)
```

During installation, allow **Java** and **SSH** in Windows Firewall if prompted.

### Installation Menu

The installer provides an interactive menu with the following options:

**Component Installation:**
1. Hadoop (HDFS + YARN + MapReduce)
2. Spark (Analytics Engine)
3. Kafka (Stream Processing)
4. Pig (Data Flow Scripting)
5. Hive (SQL on Hadoop)
6. Eclipse IDE (MapReduce Development)

**Quick Install:**
- **A)** Full Stack (Hadoop + Spark + Kafka + Hive + Pig)

**Service Management:**
7. Start All Services
8. Stop All Services
9. Check Status & Health

**Information:**
- **I)** Show Installation Info
- **0)** Exit

---

## Features

### Smart Installation System
- **Interactive Menu**: Choose individual components or install everything at once
- **Resume Support**: Interrupted installations can resume from where they left off
- **Intelligent DNS Configuration**: Automatically detects and configures best DNS servers (Cloudflare → Google → Network default)
- **Pre-flight Checks**: Validates system requirements before installation
- **Progress Indicators**: Real-time spinners show installation progress

### Automated Configuration
- **SSH Auto-Setup**: Passwordless SSH configured automatically
- **HDFS Formatting**: NameNode formatted and ready to use
- **Directory Structure**: All necessary HDFS directories created with correct permissions
- **Environment Variables**: Automatic PATH configuration in `.bashrc`
- **Service Scripts**: Helper scripts for easy start/stop operations

### Performance Optimized
- **Dynamic Memory Allocation**: YARN memory configured based on your system RAM
- **IPv6 Disabled**: Prevents networking conflicts
- **Swap Management**: Configured for optimal big data workloads
- **Safe Mode Handling**: Automatic HDFS safe mode exit with timeout protection

### Developer Tools
- **Eclipse IDE Integration**: Pre-configured for MapReduce development with:
  - Automatic Hadoop environment setup
  - HDFS directory initialization
  - Maven integration
  - One-command launch: `eclipse-hadoop`
- **Multiple Java Versions**: Java 11 (Hadoop/Spark) and Java 17 (Kafka) with automatic switching
- **Smart Wrappers**: Kafka commands automatically use Java 17

### Comprehensive Stack
- **Hadoop 3.4.2**: Latest stable release with HDFS, YARN, and MapReduce
- **Spark 3.5.8**: Configured for YARN execution with event logging
- **Kafka 4.1.1**: KRaft mode (no ZooKeeper dependency)
- **Hive 3.1.3**: MySQL metastore pre-configured
- **Pig 0.17.0**: Ready for data flow scripting

### Service Management
- **Unified Control**: Start/stop all services with single commands
- **Health Monitoring**: Real-time port checking and service status
- **Process Management**: Automatic cleanup and restart capability
- **MySQL Integration**: Hive metastore service auto-configured

### Web Interfaces
Access these URLs after starting services:
- **HDFS NameNode**: http://localhost:9870
- **YARN ResourceManager**: http://localhost:8088
- **DataNode**: http://localhost:9864
- **NodeManager**: http://localhost:8042

### Status Dashboard
- **Component Status**: Visual indicators (✓ installed, ○ not installed)
- **Service Health**: Real-time port availability checks
- **HDFS Reports**: Cluster health and storage statistics
- **System Info**: RAM usage and disk space monitoring

### Enterprise Features
- **MySQL Database**: Hive metastore with persistent storage
- **User Isolation**: Separate HDFS directories per user
- **Permission Management**: Correct file permissions for multi-user setups
- **Logging**: Comprehensive installation logs at `~/hadoop_install.log`

### Error Handling
- **Mirror Fallback**: Multiple download sources for reliability
- **Graceful Failures**: Clear error messages with recovery suggestions
- **Network Resilience**: Automatic DNS switching and retry logic
- **Systemd Detection**: Smart handling for Eclipse installation

### Convenience Scripts

**Start Services:**
```bash
~/start-hadoop.sh
```
Starts HDFS, YARN, Hive Metastore, and Kafka with proper sequencing

**Stop Services:**
```bash
~/stop-hadoop.sh
```
Gracefully shuts down all running services

**Launch Eclipse:**
```bash
eclipse-hadoop
```
Opens Eclipse with Hadoop environment pre-configured

---

## Quick Start Guide

After installation completes:

```bash
# Reload environment
source ~/.bashrc

# Start all services
~/start-hadoop.sh

# Verify HDFS is working
hdfs dfs -ls /

# Run a MapReduce example
hadoop jar $HADOOP_HOME/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 2 5

# Start Spark shell
spark-shell

# Create a Kafka topic
kafka-topics --create --topic test --bootstrap-server localhost:9092

# Start Hive
hive

# Launch Eclipse for development
eclipse-hadoop
```

---

## Web Interfaces

After starting services with `~/start-hadoop.sh`:

- **HDFS NameNode**: http://localhost:9870
- **YARN ResourceManager**: http://localhost:8088
- **DataNode**: http://localhost:9864
- **NodeManager**: http://localhost:8042

---

## If Something Fails

Check logs:

```bash
cat ~/hadoop_install.log
```

Restart after reboot:

```bash
~/start-hadoop.sh
```

Check service status:

```bash
# From the installer menu, choose option 9
# Or manually check:
jps  # Lists all Java processes
hdfs dfsadmin -report  # HDFS status
```

Common fixes:

```bash
# If SSH fails
sudo service ssh restart

# If MySQL fails (for Hive)
sudo service mysql restart

# If HDFS is in safe mode
hdfs dfsadmin -safemode leave

# Force cleanup and restart
~/stop-hadoop.sh
~/start-hadoop.sh
```

---

## Uninstall

```bash
~/stop-hadoop.sh
rm -rf ~/bigdata
rm ~/.hadoop_install_state
rm ~/start-hadoop.sh ~/stop-hadoop.sh
```

Remove Hadoop-related lines from `~/.bashrc` manually if needed.

---

## Component Details

### Hadoop
- **HDFS**: Distributed file system on port 9000
- **YARN**: Resource manager on port 8088
- **MapReduce**: Job execution framework

### Spark
- **Master**: YARN mode (no standalone master)
- **Event Logs**: Stored in HDFS at `/spark-logs`
- **History Server**: Not started by default

### Kafka
- **Mode**: KRaft (no ZooKeeper)
- **Port**: 9092
- **Java Version**: Requires Java 17 (auto-switched)

### Hive
- **Metastore**: MySQL database
- **Warehouse**: `/user/hive/warehouse` in HDFS
- **Port**: 9083

### Pig
- **Mode**: Local and MapReduce
- **Execution**: Runs on Hadoop YARN

### Eclipse
- **Launcher**: `eclipse-hadoop` command
- **Auto-config**: Hadoop environment variables pre-set
- **HDFS Init**: Creates user directories on launch

---

## System Requirements Explained

**Why 16 GB RAM?**
- Hadoop components are memory-intensive
- YARN needs 4-6 GB for containers
- WSL2 needs headroom for Windows
- 8 GB works but with limitations

**Why 15 GB disk space?**
- Component archives: ~3 GB
- Extracted files: ~8 GB
- HDFS storage: ~2 GB
- Logs and temp: ~2 GB

---

## Tested On

- **WSL2 Ubuntu 22.04 / 24.04**
- **Windows 11**


---

## Credits

Installer by [github.com/darshan-gowdaa](https://github.com/darshan-gowdaa)

Star the repo if you find it useful!

---

## License

MIT License - Feel free to use and modify

---

## Troubleshooting

### Terminal Configuration (Copy/Paste Shortcuts)

If you're having issues with **Ctrl+V not working** for paste in your terminal:

**Enable Alternate Shortcut:**
1. Open your terminal settings (Windows Terminal, Command Prompt, PowerShell, or Ubuntu)
2. Ensure the option **"Use Ctrl+Shift+C/V as Copy/Paste"** is enabled

**New Shortcuts for WSL/Ubuntu Terminal:**
- **Copy**: `Ctrl + Shift + C`
- **Paste**: `Ctrl + Shift + V`
- **End Process**: `Ctrl + C` (stops a running command)

> **Note**: These shortcuts work in all terminal applications including Command Prompt, PowerShell, WSL, and Ubuntu.

---

### Installation Issues

**"Cannot run from Windows filesystem"**
- Solution: Run from Linux home: `cd ~ && bash <(curl -fsSL ...)`

**"Insufficient disk space"**
- Solution: Free up at least 15 GB in your WSL distribution

**"Download failed"**
- Solution: Check internet connection; installer tries multiple mirrors

**"SSH connection failed"**
- Solution: Verify SSH service: `sudo service ssh status`
- Regenerate keys: `rm -rf ~/.ssh && ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa`

### Runtime Issues

**Services won't start**
- Check if another Hadoop instance is running
- Verify ports are free: `netstat -tuln | grep 9870`
- Review logs in `~/bigdata/hadoop/logs/`

**HDFS stuck in safe mode**
```bash
hdfs dfsadmin -safemode leave
```

**Hive connection errors**
```bash
sudo service mysql status
sudo service mysql restart
```

**Kafka fails to start**
```bash
# Check Java 17 is installed
java -version
# Should show Java 17 for Kafka
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 kafka-server-start.sh ...
```

### Performance Issues

**System is slow**
- Reduce WSL memory in `.wslconfig`
- Stop unused services
- Check Windows Task Manager for overall memory usage

**Jobs fail with Out of Memory**
- Increase YARN memory in `$HADOOP_HOME/etc/hadoop/yarn-site.xml`
- Reduce parallel job execution

---

## FAQ

**Q: Can I run this on Windows 10?**  
A: Yes, but you need WSL2. Run `wsl --update` in PowerShell.

**Q: Do I need Docker?**  
A: No, everything runs natively in WSL2.

**Q: Can I access HDFS from Windows?**  
A: Yes, using `\\wsl$\Ubuntu\home\<username>\bigdata\` in File Explorer for local files, or use HDFS commands from WSL terminal.

**Q: How do I update components?**  
A: Re-run the installer and select components to reinstall.

**Q: Can I run multiple Hadoop versions?**  
A: No, this installer supports one version at a time. Uninstall first.

**Q: Is this production-ready?**  
A: This is for **learning and development only**. For production, use managed clusters or Docker/Kubernetes.


---

**Happy Learning!**