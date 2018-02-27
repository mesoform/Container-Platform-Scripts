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
_HOSTNAME=$(hostname | awk -F. '{print $1}')
CURRENT_DOMAIN=$(grep domain ${RESOLV_FILE} | awk '{print $2}')
DEFAULT_DNS_DOMAIN="unset.domain.local"
_DNS_DOMAIN=${DNS_DOMAIN:-${DEFAULT_DNS_DOMAIN}}

# Variable assignment
action=$1
interval=$2


check_resolv_file(){
    _log "Checking dns_domain"
    if [ -n "${CURRENT_DOMAIN}" ]; then
        _log "${RESOLV_FILE} domain already set correctly on host"
    else
        set_resolver
    fi
}

check_hostname(){
    _log "Checking hostname"
    if [ "${HOSTNAME}" == "${_HOSTNAME}.${CURRENT_DOMAIN}" ]; then
        _log "Container hostname already fully qualified"
    else
        set_hostname
    fi
}

set_hostname(){
    _log "Updating container hostname"
    # make sure we just have the host part
    export HOSTNAME=${_HOSTNAME}.${CURRENT_DOMAIN}
    # If we have permissions
    if [ -n "$(capsh --print | grep cap_sys_admin)" ]; then
        _log "set the hostname for consistency with agents"
        echo ${HOSTNAME} > ${HOSTNAME_FILE}
        hostname -F ${HOSTNAME_FILE}
    fi
    # if it is running
    if [ -n "$(pgrep containerpilot)" ]; then
        _log "update containerpilot's environment"
        containerpilot -putenv 'HOSTNAME=${HOSTNAME}'
    fi
    _log "Container hostname updated"

}

set_resolver(){
    _log "domain not set in ${RESOLV_FILE}. Updating..."
    echo "domain ${_DNS_DOMAIN}" >> ${RESOLV_FILE}
    _log "dns_domain updated"
    if [ "${_DNS_DOMAIN}" == "${DEFAULT_DNS_DOMAIN}" ]; then
        _log "WARNING: domain set to ${DEFAULT_DNS_DOMAIN}. If running on Triton, try setting '$DNS_DOMAIN' environment variable"
    fi
    CURRENT_DOMAIN=${_DNS_DOMAIN}
}

generate_agent_cfg(){
    _log "Generating Zabbix Agent config"
    echo "Hostname=${HOSTNAME}" > ${ZABBIX_AGENT_PARAMS_PATH}/Hostname.conf
    echo "HostMetadata=${HOSTMETADATA}" > ${ZABBIX_AGENT_PARAMS_PATH}/HostMetadata.conf
    echo "Server=${EM_SERVER}" > ${ZABBIX_AGENT_PARAMS_PATH}/Server.conf
    echo "ServerActive=${EM_SERVER}" > ${ZABBIX_AGENT_PARAMS_PATH}/ServerActive.conf
    _log "Zabbix Agent config generated"
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

