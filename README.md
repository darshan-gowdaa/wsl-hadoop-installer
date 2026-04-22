# Hadoop Ecosystem Installer v4 (WSL & Native Linux)
<p align="center">
  <img width="500" height="600" alt="image" src="https://github.com/user-attachments/assets/c4f1bd30-eaed-4282-bf5f-936049a9d249" />
</p>

Simple one-command setup to run the **Hadoop ecosystem on WSL2 and Native Linux**.
Made for students so you don't waste time fixing Java, SSH, or HDFS issues. Now platform-aware!

---

## Requirements

* **Windows 10/11 (with WSL2)** OR **Native Linux (Ubuntu/Debian)**
* Minimum **16 GB RAM recommended** (8 GB also works with limits)
* ~15 GB free disk space
* Internet connection

---

## Pre-Installation (Windows/WSL Users Only)

*If you are on Native Linux, skip to the Installation section.*

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

#### **Option B: Manual Configuration File (If WSL Settings Not Available)**

**Step 1:** Create this file in Windows:
```
C:\Users\<YOUR_WINDOWS_USERNAME>\.wslconfig
```

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

**Why This Matters:**
- Without proper limits, WSL can consume all your RAM and freeze Windows
- Hadoop/Spark need sufficient memory but shouldn't starve your host OS

---

### Step 4: Open Ubuntu (WSL)

After reboot:
* Open **Ubuntu** from Start Menu **or** run `wsl` in PowerShell.
Create your Linux username and password when prompted.

---

## Installation (WSL & Linux)

Run the installer **inside your terminal (WSL or Native Linux)**:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/darshan-gowdaa/wsl-hadoop-installer/main/installv4.sh)
```

During installation, allow **Java** and **SSH** in Windows Firewall if prompted (WSL only).

### What You Can Install
The installer supports installing the following Big Data programs:
1. **Hadoop (3.4.2)**: Core HDFS, YARN, and MapReduce framework.
2. **Spark (3.5.8)**: In-memory fast analytics engine (configured for YARN).
3. **Kafka (4.1.1)**: Stream processing with KRaft mode (no ZooKeeper needed).
4. **Pig (0.17.0)**: Data flow scripting language for Hadoop.
5. **Hive (3.1.3)**: Data warehouse software facilitating reading, writing, and managing large datasets residing in distributed storage using SQL.
6. **Eclipse IDE**: Configured out-of-the-box for writing Hadoop MapReduce programs.

### Installation Menu

The installer detects your platform and provides an interactive menu:

**Components**
- 1-6) Select individual components to install.
- **A)** Install ALL Components (Hadoop + Spark + Kafka + Hive + Pig)

**Management & Tools**
- **7)** Start All Services
- **8)** Stop All Services
- **9)** Check System Status
- **P)** Create Eclipse Project (Automates MapReduce boilerplate setup)

**System Options**
- **U)** Update System (Update APT/Snap packages)
- **D)** Uninstall Components (Interactive removal menu)
- **S)** Create Script Shortcut (`dg-script.sh`)
- **0)** Exit

---

## Core & Hidden Features

The v4 installer includes several advanced automations running in the background to prevent common bugs:

### 1. Dynamic Java Routing (No Version Conflicts)
Modern Hadoop requires Java 11, Kafka requires Java 17, and Hive works best on Java 8. The script automatically installs all three and injects **smart wrappers** into your `.bashrc`. 
When you type a Kafka command, it transparently uses Java 17, while Hadoop defaults to Java 11, avoiding `ClassVersion` errors automatically.

### 2. Auto-Tuning YARN Memory
Hadoop is infamous for hanging if it runs out of memory. The installer inspects your machine's total RAM and dynamically configures `yarn-site.xml` and `mapred-site.xml` limits so that containers have enough memory to run MapReduce jobs without crashing your system.

### 3. Global Service Shortcuts (`start-hadoop.sh` & `stop-hadoop.sh`)
Instead of starting HDFS, YARN, Hive, and Kafka manually, the script creates two global shortcuts in your home directory (`~/start-hadoop.sh` and `~/stop-hadoop.sh`). 
- It starts MySQL automatically for Hive.
- It sequentially waits for NameNodes to exit "Safe Mode" before starting Hive's Metastore.
- It triggers Kafka in KRaft mode asynchronously.

### 4. Resilient Downloads & Connectivity
- **IPv6 Auto-Disable**: Prevents strange "connection refused" errors in Hadoop.
- **Intelligent DNS**: If WSL fails to resolve network addresses (common issue), the script automatically injects Cloudflare/Google DNS servers.
- **Mirror Fallbacks**: If an Apache download mirror is down, the script instantly falls back to an archive mirror so installations don't fail midway.

### 5. Automated HDFS User & Hive Directories
A fresh Hadoop cluster cannot be used until proper user folders are created. The installer automatically drops into HDFS, runs `mkdir -p /user/$USER`, `/spark-logs`, and `/user/hive/warehouse`, and `chmod 777`s them so Spark and Hive don't throw permission errors on launch.

---

## Interactive Tools Guide

### Global Script Shortcut
You don't need to curl the script every time! Press **S** in the installer menu to create a global shortcut. 
You can then launch the installer from anywhere by just typing:
```bash
dg-script.sh
```

### Create Eclipse Projects (MapReduce Setup)
Pressing **P** from the menu opens the Eclipse Project generation wizard.
It automatically:
- Creates a new Eclipse workspace project with your given name.
- Pre-configures the Java 1.8 compiler (required by Hadoop).
- Adds all the required Hadoop JARs (Common, HDFS, YARN, MapReduce) into the `.classpath`.
- Scaffolds your Main Class and Launch Configuration.
- Opens Eclipse directly into your newly generated file.

### Interactive Uninstall Menu
Pressing **D** from the menu opens the Uninstall options. 
You can choose to safely and cleanly remove individual components (like just Spark, or just Hive) or use option **A** to wipe all installed components and configurations instantly.

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

## Troubleshooting

### Terminal Configuration (Copy/Paste Shortcuts)
- **Copy**: `Ctrl + Shift + C`
- **Paste**: `Ctrl + Shift + V`

### Installation Issues
**"Cannot run from Windows filesystem"**
- Solution: Run from Linux home: `cd ~ && bash <(curl -fsSL ...)`

**"Insufficient disk space"**
- Solution: Free up at least 15 GB in your WSL/Linux distribution

**"SSH connection failed"**
- Solution: Verify SSH service: `sudo service ssh status`

### Runtime Issues
**Services won't start**
- Check if another Hadoop instance is running
- Verify ports are free: `netstat -tuln | grep 9870`

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
```

### If Something Fails
Check logs:
```bash
cat ~/hadoop_install.log
```

---

## FAQ

**Q: Can I run this on Windows 10?**  
A: Yes, but you need WSL2. Run `wsl --update` in PowerShell.

**Q: Can I run this on Native Linux?**  
A: Yes, v4 supports native Linux (Ubuntu/Debian) natively.

**Q: Do I need Docker?**  
A: No, everything runs natively in WSL2 or Linux.

**Q: Can I access HDFS from Windows?**  
A: Yes, using `\\wsl$\Ubuntu\home\<username>\bigdata\` in File Explorer for local files, or use HDFS commands from WSL terminal.

**Q: Is this production-ready?**  
A: This is for **learning and development only**.

---

## Tested On

- **WSL2 Ubuntu 22.04 / 24.04**
- **Native Ubuntu 22.04 / 24.04**
- **Windows 11**

---

## Credits

Installer by [github.com/darshan-gowdaa](https://github.com/darshan-gowdaa)

Star the repo if you find it useful!

---

## License

MIT License - Feel free to use and modify

---

**Happy Learning!**