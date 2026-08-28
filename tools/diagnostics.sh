#!/bin/bash

# NOTE(mgoddard): This has been adapted from
# roles/kayobe-diagnostics/files/get_logs.sh in Kayobe.

# Environment variables:
# $LOG_DIR is the directory to copy logs to.

# TODO: Make this script more robust and use set -e.
set +o errexit
set -u

copy_logs() {
    mkdir -p ${LOG_DIR}/{docker_logs,kolla_node_configs,system_logs}

    cp -rnL /etc/kolla/* ${LOG_DIR}/kolla_node_configs
    # Don't save the IPA images.
    rm ${LOG_DIR}/kolla_node_configs/ironic-http/ironic-agent.{kernel,initramfs}
    rm ${LOG_DIR}/kolla_node_configs/ironic-tftp/ironic-agent.{kernel,initramfs}

    if [[ -d /opt/kayobe/etc/kolla ]]; then
	mkdir -p ${LOG_DIR}/kolla_build_configs
        cp -rnL /opt/kayobe/etc/kolla/* ${LOG_DIR}/kolla_build_configs/
    fi

    cp -rvnL /var/log/* ${LOG_DIR}/system_logs/

    journalctl --no-pager > ${LOG_DIR}/system_logs/syslog.log
    journalctl --no-pager -u docker.service > ${LOG_DIR}/system_logs/docker.log
    journalctl --no-pager -u vbmcd.service > ${LOG_DIR}/system_logs/vbmcd.log
    journalctl --no-pager -u NetworkManager.service > ${LOG_DIR}/system_logs/NetworkManager.log

    if [[ -d /etc/sysconfig/network-scripts/ ]]; then
        cp -r /etc/sysconfig/network-scripts/ ${LOG_DIR}/system_logs/
    fi

    if [[ -d /etc/NetworkManager/system-connections/ ]]; then
        cp -r /etc/NetworkManager/system-connections/ ${LOG_DIR}/system_logs/
    fi

    if [[ -d /etc/yum.repos.d/ ]]; then
        cp -r /etc/yum.repos.d/ ${LOG_DIR}/system_logs/
    fi

    if [[ -d /etc/apt/sources.list.d/ ]]; then
        cp -r /etc/apt/sources.list.d/ ${LOG_DIR}/system_logs/
    fi

    if [[ -d /etc/systemd/ ]]; then
        cp -rL /etc/systemd/ ${LOG_DIR}/system_logs/
    fi

    df -h > ${LOG_DIR}/system_logs/df.txt
    # Gather disk usage statistics for files and directories larger than 1MB
    du -d 5 -hx / | sort -hr | grep '^[0-9\.]*[MGT]' > ${LOG_DIR}/system_logs/du.txt
    free  > ${LOG_DIR}/system_logs/free.txt
    cat /etc/hosts  > ${LOG_DIR}/system_logs/hosts.txt
    parted -l > ${LOG_DIR}/system_logs/parted-l.txt
    mount > ${LOG_DIR}/system_logs/mount.txt
    env > ${LOG_DIR}/system_logs/env.txt
    ip address > ${LOG_DIR}/system_logs/ip-address.txt
    ip route > ${LOG_DIR}/system_logs/ip-route.txt
    ip route show table all > ${LOG_DIR}/system_logs/ip-route-all-tables.txt
    ip rule list > ${LOG_DIR}/system_logs/ip-rule-list.txt
    pvs > ${LOG_DIR}/system_logs/pvs.txt
    vgs > ${LOG_DIR}/system_logs/vgs.txt
    lvs > ${LOG_DIR}/system_logs/lvs.txt

    iptables-save > ${LOG_DIR}/system_logs/iptables.txt

    if [ `command -v dpkg` ]; then
        dpkg -l > ${LOG_DIR}/system_logs/dpkg-l.txt
    fi
    if [ `command -v rpm` ]; then
        rpm -qa > ${LOG_DIR}/system_logs/rpm-qa.txt
    fi

    # final memory usage and process list
    ps -eo user,pid,ppid,lwp,%cpu,%mem,size,rss,cmd > ${LOG_DIR}/system_logs/ps.txt

    # available entropy
    cat /proc/sys/kernel/random/entropy_avail > ${LOG_DIR}/system_logs/entropy_avail.txt

    # docker related information
    (docker info && docker images && docker ps -a) > ${LOG_DIR}/system_logs/docker-info.txt

    for container in $(docker ps -a --format "{{.Names}}"); do
        docker logs --tail all ${container} &> ${LOG_DIR}/docker_logs/${container}.txt
    done

    # Bifrost: grab config files and logs from the container.
    if [[ $(docker ps -q -f name=bifrost_deploy) ]]; then
	mkdir -p ${LOG_DIR}/bifrost
        for service in dnsmasq ironic-api ironic-conductor ironic-inspector mariadb nginx rabbitmq-server; do
            mkdir -p ${LOG_DIR}/bifrost/$service
            docker exec bifrost_deploy \
                systemctl status $service -l -n 10000 > ${LOG_DIR}/bifrost/$service/${service}-systemd-status.txt
            docker exec bifrost_deploy \
                journalctl -u $service --no-pager > ${LOG_DIR}/bifrost/$service/${service}-journal.txt
        done
        docker exec -it bifrost_deploy \
            journalctl --no-pager > ${LOG_DIR}/bifrost/bifrost-journal.log
        for d in dnsmasq.conf ironic ironic-inspector nginx/nginx.conf; do
            docker cp bifrost_deploy:/etc/$d ${LOG_DIR}/kolla_node_configs/bifrost/
        done
        docker cp bifrost_deploy:/var/log/mariadb/mariadb.log ${LOG_DIR}/bifrost/mariadb/
    fi

    # IPA build logs
    if [[ -f /opt/kayobe/images/ipa/ipa.stderr ]] || [[ -f /opt/kayobe/images/ipa/ipa.stdout ]]; then
        mkdir -p ${LOG_DIR}/ipa
        cp /opt/kayobe/images/ipa/ipa.stderr /opt/kayobe/images/ipa/ipa.stdout ${LOG_DIR}/ipa/
    fi

    # Overcloud host image build logs
    if [[ -f /opt/kayobe/images/deployment_image/deployment_image.stderr ]] || [[ -f /opt/kayobe/images/deployment_image/deployment_image.stdout ]]; then
        mkdir -p ${LOG_DIR}/deployment_image
        cp /opt/kayobe/images/deployment_image/deployment_image.stderr /opt/kayobe/images/deployment_image/deployment_image.stdout ${LOG_DIR}/deployment_image/
    fi

    chown -R stack: ${LOG_DIR}
}

copy_logs
