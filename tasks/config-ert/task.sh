#!/bin/bash -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ -z "$SSL_CERT" ]]; then
DOMAINS=$(cat <<-EOF
  {"domains": ["*.$SYSTEM_DOMAIN", "*.$APPS_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
EOF
)

  CERTIFICATES=`om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "$OPS_MGR_GENERATE_SSL_ENDPOINT" -x POST -d "$DOMAINS"`

  SSL_CERT=`echo $CERTIFICATES | jq --raw-output '.certificate'`
  SSL_PRIVATE_KEY=`echo $CERTIFICATES | jq --raw-output '.key'`

  echo "Using self signed certificates generated using Ops Manager..."
fi

saml_cert_domains=$(cat <<-EOF
  {"domains": ["*.$SYSTEM_DOMAIN", "*.login.$SYSTEM_DOMAIN", "*.uaa.$SYSTEM_DOMAIN"] }
EOF
)

saml_cert_response=`om-linux -t https://$OPS_MGR_HOST -u $OPS_MGR_USR -p $OPS_MGR_PWD -k curl -p "$OPS_MGR_GENERATE_SSL_ENDPOINT" -x POST -d "$saml_cert_domains"`

saml_cert_pem=$(echo $saml_cert_response | jq --raw-output '.certificate')
saml_key_pem=$(echo $saml_cert_response | jq --raw-output '.key')

source $SCRIPT_DIR/load_cf_properties.sh

CF_NETWORK=$(
  echo '{}' |
  jq \
    --arg network_name "$NETWORK_NAME" \
    --arg other_azs "$DEPLOYMENT_NW_AZS" \
    --arg singleton_az "$ERT_SINGLETON_JOB_AZ" \
    '
    . +
    {
      "network": {
        "name": $network_name
      },
      "other_availability_zones": ($other_azs | split(",") | map({name: .})),
      "singleton_availability_zone": {
        "name": $singleton_az
      }
    }
    '
)

CF_RESOURCES=$(
  read -d'' -r input <<EOF
  {
    "backup-prepare": $BACKUP_PREPARE_INSTANCES,
    "ccdb": $CCDB_INSTANCES,
    "clock_global": $CLOCK_GLOBAL_INSTANCES,
    "cloud_controller": $CLOUD_CONTROLLER_INSTANCES,
    "cloud_controller_worker": $CLOUD_CONTROLLER_WORKER_INSTANCES,
    "consul_server": $CONSUL_SERVER_INSTANCES,
    "diego_brain": $DIEGO_BRAIN_INSTANCES,
    "diego_cell": $DIEGO_CELL_INSTANCES,
    "diego_database": $DIEGO_DATABASE_INSTANCES,
    "doppler": $DOPPLER_INSTANCES,
    "etcd_tls_server": $ETCD_TLS_SERVER_INSTANCES,
    "ha_proxy": $HA_PROXY_INSTANCES,
    "loggregator_trafficcontroller": $LOGGREGATOR_TC_INSTANCES,
    "mysql": $MYSQL_INSTANCES,
    "mysql_monitor": $MYSQL_MONITOR_INSTANCES,
    "mysql_proxy": $MYSQL_PROXY_INSTANCES,
    "nats": $NATS_INSTANCES,
    "nfs_server": $NFS_SERVER_INSTANCES,
    "router": $ROUTER_INSTANCES,
    "tcp_router": $TCP_ROUTER_INSTANCES
    "uaa": $UAA_INSTANCES,
    "uaadb": $UAADB_INSTANCES,
  }
EOF

  echo "$input" | jq \
    'map_values(. = {
      "instance_type": {"id":"automatic"},
      "instances": .
    })'
)

om-linux \
  --target https://$OPS_MGR_HOST \
  --username $OPS_MGR_USR \
  --password $OPS_MGR_PWD \
  --skip-ssl-validation \
  configure-product \
  --product-name cf \
  --product-properties "$CF_PROPERTIES" \
  --product-network "$CF_NETWORK" #\
  # --product-resources "$CF_RESOURCES"
