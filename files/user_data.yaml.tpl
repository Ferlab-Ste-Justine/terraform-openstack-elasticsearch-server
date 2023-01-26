#cloud-config
preserve_hostname: false
hostname: ${node_name}
users:
  - default
  - name: node-exporter
    system: true
    lock_passwd: true
  - name: elasticsearch
    system: true
    lock_passwd: true
write_files:
  #Chrony config
%{ if chrony.enabled ~}
  - path: /opt/chrony.conf
    owner: root:root
    permissions: "0444"
    content: |
%{ for server in chrony.servers ~}
      server ${join(" ", concat([server.url], server.options))}
%{ endfor ~}
%{ for pool in chrony.pools ~}
      pool ${join(" ", concat([pool.url], pool.options))}
%{ endfor ~}
      driftfile /var/lib/chrony/drift
      makestep ${chrony.makestep.threshold} ${chrony.makestep.limit}
      rtcsync
%{ endif ~}
  #Elasticsearch tls files
%{ if ca_certificate != "" ~}
  - path: /etc/elasticsearch/tls/server.key
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, server_key)}
  - path: /etc/elasticsearch/tls/server.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, join("", [server_certificate, ca_certificate]))}
  - path: /etc/elasticsearch/tls/ca.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, ca_certificate)}
%{ endif ~}
  #Elasticsearch configuration files
  - path: /etc/elasticsearch/jvm.options
    owner: root:root
    permissions: "0444"
    content: |
      #Taking the settings as are in the elasticsearch distribution,
      #minus the heap size and settings for previous jdk versions not in use

      #Heap
      -Xms__HEAP_SIZE__m
      -Xmx__HEAP_SIZE__m

      #G1GC Configuration
      14-:-XX:+UseG1GC
      14-:-XX:G1ReservePercent=25
      14-:-XX:InitiatingHeapOccupancyPercent=30

      #JVM temporary directory
      -Djava.io.tmpdir=/opt/java-temp

      #Heap dump
      -XX:+HeapDumpOnOutOfMemoryError
      -XX:HeapDumpPath=data

      #Fatal errors
      -XX:ErrorFile=logs/hs_err_pid%p.log

      # JDK 9+ GC logging
      9-:-Xlog:gc*,gc+age=trace,safepoint:file=logs/gc.log:utctime,pid,tags:filecount=32,filesize=64m
  - path: /etc/elasticsearch/elasticsearch.yml
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, elasticsearch_boot_configuration)}
%{ if length(initial_masters) > 0 ~}
  - path: /etc/elasticsearch/elasticsearch-runtime.yml
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, elasticsearch_runtime_configuration)}
%{ endif ~}
  #Elasticsearch systemd configuration
  - path: /usr/local/bin/set_es_heap
    owner: root:root
    permissions: "0555"
    content: |
      #!/bin/bash
%{ if is_master ~}
      HEAP_SIZE=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') * 3 / 4 / 1024 ))
%{ else ~}
      HEAP_SIZE=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 2 / 1024 ))
%{ endif ~}
      sed "s/__HEAP_SIZE__/$HEAP_SIZE/g" -i /etc/elasticsearch/jvm.options
  #See: https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#initial_master_nodes
%{ if length(initial_masters) > 0 ~}
  - path: /usr/local/bin/boostrap_es_config
    owner: root:root
    permissions: "0555"
    content: |
      #!/bin/sh
      echo "Waiting for server to join cluster with green status before removing initial master nodes from configuration"
      STATUS=$(curl --silent --cacert /etc/elasticsearch/tls/ca.pem ${request_protocol}://127.0.0.1:9200/_cluster/health | jq ".status")
      while [ "$STATUS" != "\"green\"" ]; do
          sleep 1
          STATUS=$(curl --silent --cacert /etc/elasticsearch/tls/ca.pem ${request_protocol}://127.0.0.1:9200/_cluster/health | jq ".status")
      done
      mv /etc/elasticsearch/elasticsearch-runtime.yml /etc/elasticsearch/elasticsearch.yml
      echo "Server has joined cluster with green status, initial master nodes removed from configuration"
%{ endif ~}
  - path: /etc/systemd/system/elasticsearch.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Elasticsearch"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      Environment=ES_PATH_CONF=/etc/elasticsearch
      Environment=LOG4J_FORMAT_MSG_NO_LOOKUPS=true
      Environment=ES_TMPDIR=/opt/es-temp
      #https://www.elastic.co/guide/en/elasticsearch/reference/current/system-config.html
      LimitNOFILE=65535
      LimitNPROC=4096
      User=elasticsearch
      Group=elasticsearch
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/opt/es/bin/elasticsearch

      [Install]
      WantedBy=multi-user.target
  #Prometheus node exporter systemd configuration
  - path: /etc/systemd/system/node-exporter.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Prometheus Node Exporter"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=node-exporter
      Group=node-exporter
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/usr/local/bin/node_exporter

      [Install]
      WantedBy=multi-user.target
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg-agent
  - software-properties-common
  - libdigest-sha-perl
  - jq
%{ if chrony.enabled ~}
  - chrony
%{ endif ~}
runcmd:
  #Finalize Chrony Setup
%{ if chrony.enabled ~}
  - cp /opt/chrony.conf /etc/chrony/chrony.conf
  - systemctl restart chrony.service 
%{ endif ~}
  #Add dns servers
%{ if length(nameserver_ips) > 0 ~}
  - echo "DNS=${join(" ", nameserver_ips)}" >> /etc/systemd/resolved.conf
  - systemctl stop systemd-resolved
  - systemctl start systemd-resolved
%{ endif ~}
  #Install elasticsearch
  ##Get elasticsearch executables
  - wget -O /opt/elasticsearch-7.17.0-linux-x86_64.tar.gz https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.0-linux-x86_64.tar.gz
  - wget -O /opt/elasticsearch-7.17.0-linux-x86_64.tar.gz.sha512 https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.17.0-linux-x86_64.tar.gz.sha512
  - cd /opt && shasum -a 512 -c elasticsearch-7.17.0-linux-x86_64.tar.gz.sha512
  - tar zxvf /opt/elasticsearch-7.17.0-linux-x86_64.tar.gz -C /opt
  - mv /opt/elasticsearch-7.17.0 /opt/es
  - chown -R elasticsearch:elasticsearch /opt/es
  - rm /opt/elasticsearch-7.17.0-linux-x86_64.tar.gz /opt/elasticsearch-7.17.0-linux-x86_64.tar.gz.sha512
  ##Setup requisite directories, non-templated files and permissions
  - mkdir -p /var/lib/elasticsearch && chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
  ##When the doc says one thing: https://www.elastic.co/guide/en/elasticsearch/reference/current/important-settings.html#es-tmpdir
  ##And the code says another: https://github.com/elastic/elasticsearch/blob/7.17/server/src/main/java/org/elasticsearch/bootstrap/Security.java#L213
  ##You do both if you can and then you are covered no matter what
  - mkdir -p /opt/es-temp && chown -R elasticsearch:elasticsearch /opt/es-temp
  - mkdir -p /opt/java-temp && chown -R elasticsearch:elasticsearch /opt/java-temp
  - cp /opt/es/config/log4j2.properties /etc/elasticsearch/log4j2.properties
  - chown -R elasticsearch:elasticsearch /etc/elasticsearch
  ##Runtime configuration adjustments
  - /usr/local/bin/set_es_heap
  - echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
  - echo 'vm.swappiness = 1' >> /etc/sysctl.conf
  - sysctl -p
  ##Launch service
  - systemctl enable elasticsearch
  - systemctl start elasticsearch
  #Install prometheus node exporter as a binary managed as a systemd service
  - wget -O /opt/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.3.0/node_exporter-1.3.0.linux-amd64.tar.gz
  - mkdir -p /opt/node_exporter
  - tar zxvf /opt/node_exporter.tar.gz -C /opt/node_exporter
  - cp /opt/node_exporter/node_exporter-1.3.0.linux-amd64/node_exporter /usr/local/bin/node_exporter
  - chown node-exporter:node-exporter /usr/local/bin/node_exporter
  - rm -r /opt/node_exporter && rm /opt/node_exporter.tar.gz
  - systemctl enable node-exporter
  - systemctl start node-exporter
%{ if length(initial_masters) > 0 ~}
  - /usr/local/bin/boostrap_es_config
%{ endif ~}