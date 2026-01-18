# Hadoop WSL Installer

Simple one-script setup to run **Hadoop ecosystem on WSL2**.
Made for students so you don’t waste hours fixing Java, SSH, or HDFS issues.

---

## What You Get

* Hadoop (HDFS + MapReduce)
* YARN
* Spark
* Kafka (no Zookeeper)
* Pig
* Ready-made start/stop/check scripts

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

## Important: WSL Memory Setup

Create this file in **Windows**:

```
C:\Users\YourName\.wslconfig
```

Add:

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

## Basic Practice Commands

### HDFS

```bash
echo "hello" > test.txt
hdfs dfs -put test.txt /user/$USER/
hdfs dfs -cat /user/$USER/test.txt
```

### Spark

```bash
spark-shell --master yarn
```

### Kafka

```bash
kafka-topics.sh --create --topic test --bootstrap-server localhost:9092
echo "hi" | kafka-console-producer.sh --topic test --bootstrap-server localhost:9092
```

---

## Common Problems & Fixes

### Nothing starts

```bash
cat ~/hadoop_install.log
```

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

**Tested on:** WSL2 Ubuntu 22.04 / 24.04, Windows 11
