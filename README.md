# Hadoop WSL Installer

Simple one-script setup to run **Hadoop ecosystem on WSL2**.
Made for students so you don’t waste hours fixing Java, SSH, or HDFS issues.

---

## What You Get

- Hadoop 3.3.6 (HDFS + MapReduce)
- YARN 3.3.6
- Spark 3.5.3
- Kafka 3.6.1 (KRaft mode - no ZooKeeper)
- Pig 0.17.0
- Java 11 (auto-installed)

Everything installs inside:

```
~/bigdata/
```

---

## Requirements (Minimum)

* WSL2 with **Ubuntu 22.04 / 24.04**
* Windows **16 GB RAM** (8 GB used by WSL)
* ~15 GB free disk space
* Sudo access

---

## Prerequisites (Do This Once)

### 1) Enable WSL2 on Windows

Run **PowerShell as Administrator**:

```powershell
wsl --install
```

Restart when asked.

Docs: [https://learn.microsoft.com/windows/wsl/install](https://learn.microsoft.com/windows/wsl/install)

---

### 2) Install Ubuntu from Microsoft Store

* Open Microsoft Store
* Search **Ubuntu 22.04 LTS** or **Ubuntu 24.04 LTS**
* Install → Open → set username & password

Store page: [https://apps.microsoft.com/search?query=ubuntu](https://apps.microsoft.com/search?query=ubuntu)

---

### 3) Check WSL Version (Must be WSL2)

```powershell
wsl -l -v
```

If Ubuntu shows **WSL 1**, convert:

```powershell
wsl --set-version Ubuntu 2
```

---

## 4) Update Ubuntu (One Time)

### Before running commands (important)

#### Open PowerShell as Administrator
- Press **Win + X → A**  
  *(or search **PowerShell**, right-click → Run as administrator)*
- From the PowerShell window, launch **Ubuntu**

#### Enable easy paste in PowerShell
1. **Left-click the top bar** of the PowerShell window  
2. Click **Properties**
3. Enable **Use Ctrl+Shift+V as Paste**
4. Click **OK**

**Paste shortcut:** `Ctrl + Shift + V`

---

### Run inside Ubuntu
```bash
sudo apt update && sudo apt upgrade -y
```

## Important: WSL Memory Setup

Create this file in **Windows**:

```
C:\Users\<YOUR_WINDOWS_USERNAME>\.wslconfig
```
Add this if you have 8GB RAM:

```ini
[wsl2]
memory=6GB
processors=2
swap=2GB
```

Add this if you have 16GB RAM:

```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
```

Restart WSL:

```powershell
wsl --shutdown
```

Open Ubuntu again.

---

## Installation

### Recommended (One Command)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/darshan-gowdaa/wsl-hadoop-installer/main/install.sh)
```

During install, **allow Java & SSH in Windows Firewall** when prompted.

---

## After Install

```bash
source ~/.bashrc
~/start-hadoop.sh
```

Check services:

```bash
jps
```

You should see NameNode, DataNode, ResourceManager, NodeManager.

---

## Web Interfaces

* HDFS: [http://localhost:9870](http://localhost:9870)
* YARN: [http://localhost:8088](http://localhost:8088)

---

## Daily Usage (You Only Need These)

```bash
~/start-hadoop.sh    # start all
~/stop-hadoop.sh     # stop all
~/check-hadoop.sh    # status
```
---

## Common Problems & Fixes

### Nothing starts

```bash
cat ~/hadoop_install.log
```

### "Connection refused" on Web UIs

**Windows Firewall blocked Java:**
1. Open Windows Security → Firewall
2. "Allow an app through firewall"
3. Find "Java Platform SE binary"
4. Check "Private networks"

or just Disable AntiVirus

### NameNode error (reset HDFS)

```bash
rm -rf ~/bigdata/hadoop/dfs/namenode/*
rm ~/.hadoop_install_state
./install.sh
```

### SSH error

```bash
sudo service ssh start
ssh localhost exit
```

### After reboot, Hadoop stopped

```bash
~/start-hadoop.sh
```

### Low memory / Java errors

* `.wslconfig` not applied
* Run `wsl --shutdown`
* Reopen Ubuntu

---

## Uninstall

```bash
~/stop-hadoop.sh
rm -rf ~/bigdata
rm ~/.hadoop_install_state
```

Remove Hadoop lines from `~/.bashrc` manually.

---

## Who This Is For

* Students learning Hadoop, Spark, Pig
* Lab work & practice
* Not for production or clusters

---


## Tips

- Run `jps` to see what's running anytime
- Logs are in `~/bigdata/hadoop/logs/` if something breaks
- Kafka logs: `~/bigdata/kafka/kafka.log`
- Script creates a tutorial file - check `/user/$USER/` in HDFS

## Known Issues

- Windows Firewall might block Java on first run → allow it
- Services don't auto-start after WSL reboot → run `~/start-hadoop.sh`
- Installing from `/mnt/c/` is 10x slower → script will warn you

**Tested on:** WSL2 Ubuntu 22.04 / 24.04, Windows 11
