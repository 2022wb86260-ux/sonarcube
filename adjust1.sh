#!/bin/bash

###############################################################################
# SONARQUBE 9.3 - OPTIMIZED PERMANENT SETUP
# Rocky Linux 9
#
# SonarQube       : 9.3.0.79811
# Elasticsearch    : 7.17.18
# Java             : OpenJDK 17.0.13
# Installation     : /opt/sonarqube
# User             : cloud
# Web Port         : 9000
# ES Port          : 9001
#
# PURPOSE:
#   - Configure Java 17
#   - Fix required permissions
#   - Create/update systemd service
#   - Enable SonarQube at boot
#   - Start SonarQube
#   - Verify service, ports and processes
#   - Create desktop shortcut
#
# NOTE:
#   This script DOES NOT reinstall SonarQube, Java or Elasticsearch.
###############################################################################

set -Eeuo pipefail

###############################################################################
# CONFIGURATION
###############################################################################

SONAR_HOME="/opt/sonarqube"
SONAR_USER="cloud"
SONAR_GROUP="cloud"

JAVA_HOME="/usr/lib/jvm/java-17-openjdk-17.0.13.0.11-4.el9.x86_64"

SONAR_BIN="$SONAR_HOME/bin/linux-x86-64"
SERVICE_FILE="/etc/systemd/system/sonarqube.service"

DESKTOP_DIR="/home/$SONAR_USER/Desktop"
SHORTCUT="$DESKTOP_DIR/sonarqube.desktop"

###############################################################################
# BASIC CHECKS
###############################################################################

echo
echo "============================================================"
echo "       SONARQUBE 9.3 - PERMANENT SETUP"
echo "============================================================"
echo

echo "[1/7] Checking existing SonarQube installation..."

if [ ! -d "$SONAR_HOME" ]; then
    echo "ERROR: SonarQube installation not found:"
    echo "$SONAR_HOME"
    exit 1
fi

if [ ! -x "$SONAR_BIN/sonar.sh" ]; then
    echo "ERROR: sonar.sh not found:"
    echo "$SONAR_BIN/sonar.sh"
    exit 1
fi

echo "OK: SonarQube installation found."

###############################################################################
# JAVA CHECK
###############################################################################

echo
echo "[2/7] Configuring Java 17..."

if [ ! -x "$JAVA_HOME/bin/java" ]; then
    echo "ERROR: Required Java 17 was not found:"
    echo "$JAVA_HOME"
    exit 1
fi

export JAVA_HOME
export ES_JAVA_HOME="$JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

echo "Java version:"
"$JAVA_HOME/bin/java" -version

###############################################################################
# PERMISSIONS
###############################################################################

echo
echo "[3/7] Checking SonarQube ownership..."

CURRENT_OWNER=$(stat -c '%U:%G' "$SONAR_HOME")

if [ "$CURRENT_OWNER" != "$SONAR_USER:$SONAR_GROUP" ]; then

    echo "Correcting SonarQube ownership..."

    sudo chown -R "$SONAR_USER:$SONAR_GROUP" "$SONAR_HOME"

else

    echo "Ownership already correct: $SONAR_USER:$SONAR_GROUP"

fi

# Only ensure the important writable directories are writable.
sudo chmod u+rwX "$SONAR_HOME"
sudo chmod -R u+rwX "$SONAR_HOME/temp" 2>/dev/null || true

###############################################################################
# SYSTEMD SERVICE
###############################################################################

echo
echo "[4/7] Configuring systemd service..."

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=SonarQube Server
After=network.target

[Service]
Type=forking

User=$SONAR_USER
Group=$SONAR_GROUP

Environment="JAVA_HOME=$JAVA_HOME"
Environment="ES_JAVA_HOME=$JAVA_HOME"
Environment="SONAR_JAVA_PATH=$JAVA_HOME/bin/java"
Environment="PATH=$JAVA_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

WorkingDirectory=$SONAR_BIN

ExecStart=$SONAR_BIN/sonar.sh start
ExecStop=$SONAR_BIN/sonar.sh stop

PIDFile=$SONAR_BIN/SonarQube.pid

LimitNOFILE=131072
LimitNPROC=8192

TimeoutStartSec=300
TimeoutStopSec=300

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

sudo systemctl enable sonarqube

echo "Systemd service configured."

###############################################################################
# START SONARQUBE
###############################################################################

echo
echo "[5/7] Starting SonarQube..."

if sudo systemctl is-active --quiet sonarqube; then

    echo "SonarQube is already running."
    echo "No restart required."

else

    sudo systemctl start sonarqube

    echo "Waiting for SonarQube to initialize..."

    for i in {1..30}; do

        if sudo systemctl is-active --quiet sonarqube; then
            echo "SonarQube service is active."
            break
        fi

        sleep 2

    done

fi

###############################################################################
# VERIFY SERVICE
###############################################################################

echo
echo "[6/7] Verifying SonarQube..."

if ! sudo systemctl is-active --quiet sonarqube; then

    echo
    echo "ERROR: SonarQube failed to start."
    echo
    echo "Recent logs:"
    sudo journalctl -u sonarqube -n 80 --no-pager

    exit 1

fi

echo "SUCCESS: SonarQube service is ACTIVE."

echo
echo "Checking port 9000..."

if sudo ss -lntp | grep -q ':9000'; then
    echo "SUCCESS: Port 9000 is LISTENING."
else
    echo "WARNING: Port 9000 is not listening yet."
fi

echo
echo "Checking port 9001..."

if sudo ss -lntp | grep -q ':9001'; then
    echo "SUCCESS: Port 9001 is LISTENING."
else
    echo "WARNING: Port 9001 is not listening yet."
fi

echo
echo "SonarQube processes:"
sudo ps -ef | grep '[s]onar' || true

echo
echo "Elasticsearch processes:"
sudo ps -ef | grep '[e]lasticsearch' || true

###############################################################################
# DESKTOP SHORTCUT
###############################################################################

echo
echo "[7/7] Creating desktop shortcut..."

sudo -u "$SONAR_USER" mkdir -p "$DESKTOP_DIR"

sudo -u "$SONAR_USER" tee "$SHORTCUT" > /dev/null <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=SonarQube
Comment=Start and Open SonarQube
Exec=bash -c 'sudo systemctl start sonarqube && sleep 10 && xdg-open http://localhost:9000'
Icon=applications-development
Terminal=false
Categories=Development;WebDevelopment;
EOF

sudo chmod +x "$SHORTCUT"

sudo -u "$SONAR_USER" gio set "$SHORTCUT" metadata::trusted true 2>/dev/null || true

echo "Desktop shortcut created:"
echo "$SHORTCUT"

###############################################################################
# FINAL RESULT
###############################################################################

echo
echo "============================================================"
echo "             SONARQUBE SETUP COMPLETE"
echo "============================================================"
echo

echo "SonarQube Service:"
sudo systemctl is-active sonarqube

echo
echo "SonarQube URL:"
echo "http://localhost:9000"

echo
echo "Java:"
"$JAVA_HOME/bin/java" -version 2>&1 | head -n 1

echo
echo "Listening Ports:"
sudo ss -lntp | grep -E ':9000|:9001' || true

echo
echo "Desktop Shortcut:"
echo "$SHORTCUT"

echo
echo "============================================================"
echo "              SUCCESSFULLY CONFIGURED"
echo "============================================================"
echo

#Complete Command List
# Check current versions
java -version
javac -version
rpm -qi jenkins
# Remove old Java (optional)
sudo dnf remove -y java-17-openjdk java-17-openjdk-devel
# Install Java 21
sudo dnf install -y java-21-openjdk java-21-openjdk-devel
# Verify Java installation
java -version
javac -version
# Set Java 21 as default (if multiple versions exist)
sudo alternatives --config java
sudo alternatives --config javac
# Remove existing Jenkins repository
sudo rm -f /etc/yum.repos.d/jenkins.repo
# Add latest Jenkins LTS repository
sudo wget -O /etc/yum.repos.d/jenkins.repo
https://pkg.jenkins.io/redhat-stable/jenkins.repo
# Disable GPG verification
sudo sed -i 's/^gpgcheck=.*/gpgcheck=0/' /etc/yum.repos.d/jenkins.repo
grep -q "^gpgcheck=" /etc/yum.repos.d/jenkins.repo || echo "gpgcheck=0" |
sudo tee -a /etc/yum.repos.d/jenkins.repo
# Refresh repository metadata
sudo dnf clean all
sudo dnf makecache
# Upgrade Jenkins
sudo dnf upgrade -y jenkins
# (If Jenkins is not installed)
# sudo dnf install -y jenkins
# Configure Jenkins to use Java 21
sudo mkdir -p /etc/systemd/system/jenkins.service.d
sudo tee /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="JAVA_HOME=/usr/lib/jvm/java-21-openjdk"
EOF
# Reload and restart Jenkins
sudo systemctl daemon-reload
sudo systemctl enable jenkins
sudo systemctl restart jenkins
# Check Jenkins status
sudo systemctl status jenkins
# Verify versions
java -version
javac -version
rpm -qi jenkins
# Verify Jenkins is using Java 21
sudo journalctl -u jenkins -n 50 --no-page
