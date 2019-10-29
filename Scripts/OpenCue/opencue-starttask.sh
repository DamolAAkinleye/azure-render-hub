#!/bin/bash

# Disable history expansion to support passwords with '!'
set +H

INSTALLER_PATH=
TENANT_ID=
APP_ID=
KV_NAME=
KV_CERT_THUMB=
CUEBOT_HOST=
CUEBOT_GROUPS=

OPTS=`getopt -n 'parse-options' -o i:t:a:k:c:e:g: --long installerPath:,tenantId:,applicationId:,keyVaultName:,keyVaultCertificateThumbprint:,cuebotHost:,groups: -- "$@"`
if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

echo "Arguments: $@"
eval set -- "$OPTS"

while true; do
  case "$1" in
    -i | --installerPath ) INSTALLER_PATH="$2"; shift 2 ;;
    -t | --tenantId )    TENANT_ID="$2"; shift 2 ;;
    -a | --applicationId ) APP_ID="$2"; shift 2 ;;
    -k | --keyVaultName ) KV_NAME="$2"; shift 2 ;;
    -c | --keyVaultCertificateThumbprint ) KV_CERT_THUMB="$2"; shift 2 ;;
    -h | --cuebotHost ) CUEBOT_HOST="$2"; shift 2 ;;
    -g | --groups ) CUEBOT_GROUPS="$2"; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

SERVICE_NAME="opencue-rqd.service"

# Stop the blade service
systemctl | grep $SERVICE_NAME > /dev/null
if [ $? -eq 0 ]; then
    systemctl stop $SERVICE_NAME
fi

# When Batch recovers a VM, or a VM is pre-empted, a new
# VM replaces the old one.  While the compute node Id doesn't
# change, the hostname does and we want to prevent a new host from
# registering itself in OpenCue.  To do this we'll create a hash
# of the pool and compute node Id which will be predictable.
HOSTNAME_PREFIX="azure-"
hash=$(echo "$AZ_BATCH_POOL_ID-$AZ_BATCH_NODE_ID" | md5sum | cut -c 1-8)
newHostname="${HOSTNAME_PREFIX}${hash}"
echo "Updating hostname `hostname` to $newHostname"
hostnamectl set-hostname $newHostname


# Set any app licenses system wide.
if [ -n "$AZ_BATCH_SOFTWARE_ENTITLEMENT_TOKEN" ]; then
    accountUrl=$AZ_BATCH_ACCOUNT_URL
    if [[ "$accountUrl" == */ ]]; then
        accountUrl=${accountUrl::-1}
    fi
    echo export AZ_BATCH_ACCOUNT_URL=\"$accountUrl\" > /etc/profile.d/ses.sh
    echo export AZ_BATCH_SOFTWARE_ENTITLEMENT_TOKEN=\"$AZ_BATCH_SOFTWARE_ENTITLEMENT_TOKEN\" >> /etc/profile.d/ses.sh
fi

if [ -n "$INSTALLER_PATH" ]; then

    # Find the installer
    installer=$(find ./$INSTALLER_PATH -name 'rqd-*-all.tar.gz' | head -1)

    if [ -e "$installer" ]; then
        # Install Tractor blade

        echo "Installing $installer"

        yum install -y install epel-release gcc python-devel time
        yum install -y python-pip

        tar xvfz "$installer"

        rqd_dir=$(basename -s '.tar.gz' $installer)

        cd $rqd_dir

        pip install -r requirements.txt

        python setup.py install

        if [ -n "$CUEBOT_HOST" ]; then
            echo "Setting Cuebot host to $CUEBOT_HOST"

            # Tractor 2.3 has a bug in the systemd script that points to Tractor 2.2
            echo "CUEBOT_HOST=$CUEBOT_HOST" > /etc/sysconfig/opencue-rqd
        fi

cat > opencue-rqd.service <<EOF
[Unit]
Description=OpenCue RQD Service
Wants=network.target
After=network.target

[Service]
Environment=OPTIONS=
Environment=BIN=/usr/bin
EnvironmentFile=-/etc/sysconfig/opencue-rqd
ExecStart=/bin/bash -c "${BIN}/rqd ${OPTIONS}"
LimitNOFILE=500000
LimitNPROC=500000
StandardOutput=syslog+console
StandardError=syslog+console
SyslogIdentifier=rqd

[Install]
WantedBy=multi-user.target
EOF

        # Copy the systemd service script
        cp opencue-rqd.service /usr/lib/systemd/system

        # Enable the service
        systemctl enable opencue-rqd.service

        systemctl daemon-reload
    else
        echo "No OpenCue installer tarball found in $INSTALLER_PATH"
    fi
fi

if [ -n "$CUEBOT_GROUPS" ]; then
    groups=$(echo $CUEBOT_GROUPS | tr ';' ',')
    # TODO - We need to add this RQD into the specified groups
fi

if [ -n "$APP_INSIGHTS_INSTRUMENTATION_KEY" ]; then
    # Install and setup Application Insights for CPU/GPU and process metrics
    wget -O run-linux.sh https://raw.githubusercontent.com/Azure/batch-insights/v1.3.0/scripts/run-linux.sh
    chmod +x run-linux.sh
    ./run-linux.sh 2>&1
fi