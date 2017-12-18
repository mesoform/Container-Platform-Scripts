#!/usr/bin/env bash

# short script to :
# - generate zabbix agent config hostname, hostmetadata, server and serveractive parameters
# - check resolf.conf domain is set
# - check the hostname is fully qualified and correct if not:
#   In an ideal world dns_domain Docker parameter will set the FQDN and this script won't be needed.
#   Simply have zabbix_sender commands in containerpilot.json use $HOSTNAME environment variable "-s", "{{ .HOSTNAME }}".
#   However, this doesn't happen on Joyent Triton so we need to work around that issue
#   https://github.com/joyent/sdc-vmtools-lx-brand/issues/16
#   https://github.com/joyent/smartos-live/issues/514

ZABBIX_AGENT_CONF=/etc/coprocesses/zabbix/zabbix_agentd.conf
ZABBIX_AGENT_PARAMS_PATH=/etc/coprocesses/zabbix/zabbix_agentd.d
HOSTNAME_FILE=/etc/hostname
RESOLV_FILE=/etc/resolv.conf

# Variable assignment
action=$1
interval=$2

check_resolv_file(){
    _log "Checking dns_domain"
    CURRENT_DOMAIN=$(grep domain ${RESOLV_FILE})
    if [ $? -eq 1 ]; then
        _log "dns_domain not set"
        echo "domain ${DNS_DOMAIN}" >> ${RESOLV_FILE}
        _log "dns_domain updated"
    else
        _log "dns_domain already set correctly on host"
    fi
}

check_hostname(){
    _log "Checking hostname"
    hostname_string=$(hostname)
    container_hostname=$(echo $hostname_string | awk -F. '{print $1}')
    if [ ${container_hostname}.${DNS_DOMAIN} != $(hostname) ]; then
        _log "Updating container hostname"
        export HOSTNAME=$(hostname).${DNS_DOMAIN}
        echo ${HOSTNAME} > ${HOSTNAME_FILE}
        hostname -F ${HOSTNAME_FILE}
        _log "Container hostname updated"
    else
        export HOSTNAME=$(hostname)
        _log "Container hostname already fully qualified"
    fi
}

generate_agent_cfg(){
    _log "Generating Zabbix Agent config"
    echo "Hostname=${HOSTNAME}" > ${ZABBIX_AGENT_PARAMS_PATH}/Hostname.conf
    echo "HostMetadata=${HOSTMETADATA}" > ${ZABBIX_AGENT_PARAMS_PATH}/HostMetadata.conf
    echo "Server=${EM_SERVER}" > ${ZABBIX_AGENT_PARAMS_PATH}/Server.conf
    echo "ServerActive=${EM_SERVER}" > ${ZABBIX_AGENT_PARAMS_PATH}/ServerActive.conf
    _log "Zabbix Agent config generated"
}

heartbeat(){
    while true
    do
        zabbix_sender -c /etc/coprocesses/zabbix/zabbix_agentd.conf --key container.state --value 1
        sleep $interval
    done
}

setup(){
    _log "Platform integration setup"
    check_resolv_file
    check_hostname
    generate_agent_cfg
}

_log(){
    echo "    $(date -u '+%Y-%m-%d %H:%M:%S') containerpilot: $@"
}

# run specified action
${action}

exit 0