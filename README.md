# Hadoop WSL Installer

Simple one-command setup to run the **Hadoop ecosystem on WSL2**.
Made for students so you don’t waste time fixing Java, SSH, or HDFS issues.

---

## What You Get / Installed Versions

* Hadoop 3.4.2 (HDFS + MapReduce)
* YARN 3.4.2
* Spark 3.5.8
* Kafka 4.1.1 (KRaft mode, no ZooKeeper)
* Pig 0.17.0
* Hive 3.1.3
* Java 11 and Java 17

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
wsl --install ubuntu
```

Wait until it completes and **close PowerShell**.

---

### Step 2: Enable Required Windows Features

1. Open **Start Menu** → search **Turn Windows features on or off**

2. Enable the following options:

   * **Windows Subsystem for Linux**
   * **Virtual Machine Platform**
<img width="400" height="400" alt="image" src="https://github.com/user-attachments/assets/9904ae6e-7f4c-4e2a-b162-b2180f13ecec" />

3. Click **OK** and **restart when prompted**

---

### Step 3: WSL Memory Setup (IMPORTANT)

Create this file in **Windows**:

```
C:\Users\<YOUR_WINDOWS_USERNAME>\.wslconfig
```

> Replace `<YOUR_WINDOWS_USERNAME>` with your actual Windows user name.

#### If your system has **8 GB RAM**

```ini
[wsl2]
memory=6GB
processors=2
swap=2GB
```

#### If your system has **16 GB RAM or more**

```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
```
<img width="400" height="450" alt="image" src="https://github.com/user-attachments/assets/94c98c4c-562e-4ab6-85b3-bab8676b4298" />


Apply the changes:

```powershell
wsl --shutdown
```

Open **Ubuntu** again after this.

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
bash <(curl -fsSL https://raw.githubusercontent.com/darshan-gowdaa/wsl-hadoop-installer/main/installv2.sh)
```

During installation, allow **Java** and **SSH** in Windows Firewall if prompted.

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

---

## Uninstall

```bash
~/stop-hadoop.sh
rm -rf ~/bigdata
rm ~/.hadoop_install_state
```

Remove Hadoop-related lines from `~/.bashrc` manually if needed.

---

Tested on **WSL2 Ubuntu 22.04 / 24.04** with **Windows 11**
