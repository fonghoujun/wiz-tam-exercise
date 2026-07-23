#!/bin/bash
set -e

# --- Install MongoDB 4.4 (outdated version, intentional) ---
wget -qO - https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.4.list

apt-get update -y
apt-get install -y mongodb-org=4.4.29 mongodb-org-server=4.4.29 mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 mongodb-org-tools=4.4.29

systemctl start mongod
systemctl enable mongod

# --- Bind to all interfaces so the app (on EKS) can reach it ---
sed -i "s/bindIp: 127.0.0.1/bindIp: 0.0.0.0/" /etc/mongod.conf

# --- Create admin + app users before enabling auth ---
sleep 5
mongo <<EOF
use admin
db.createUser({
  user: "mongoAdmin",
  pwd: "${mongo_admin_password}",
  roles: [ { role: "root", db: "admin" } ]
})
use appdb
db.createUser({
  user: "appUser",
  pwd: "${mongo_app_password}",
  roles: [ { role: "readWrite", db: "appdb" } ]
})
EOF

# --- Enable authentication ---
cat >> /etc/mongod.conf <<EOF
security:
  authorization: enabled
EOF

systemctl restart mongod

# --- Install AWS CLI for backup uploads ---
apt-get install -y unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# --- Backup script ---
cat > /usr/local/bin/mongo-backup.sh <<'SCRIPT'
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/tmp/mongo-backup-$TIMESTAMP"
mongodump --username mongoAdmin --password '${mongo_admin_password}' --authenticationDatabase admin --out $BACKUP_DIR
tar -czf "$BACKUP_DIR.tar.gz" -C /tmp "mongo-backup-$TIMESTAMP"
aws s3 cp "$BACKUP_DIR.tar.gz" "s3://${backup_bucket_name}/"
rm -rf "$BACKUP_DIR" "$BACKUP_DIR.tar.gz"
SCRIPT

chmod +x /usr/local/bin/mongo-backup.sh

# --- Daily cron job (2am) ---
cat > /etc/cron.d/mongo-backup <<'CRON'
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 2 * * * root /usr/local/bin/mongo-backup.sh >> /var/log/mongo-backup.log 2>&1
CRON