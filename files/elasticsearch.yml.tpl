xpack:
  security:
%{ if tls_enabled ~}
    enabled: true
    authc:
      anonymous:
        username: anonymous_user
        roles: superuser
        authz_exception: true
    http:
      ssl:
        enabled: true
        key: "/etc/elasticsearch/tls/server.key"
        certificate: "/etc/elasticsearch/tls/server.pem"
        certificate_authorities: ["/etc/elasticsearch/tls/ca.pem"]
    transport:
      ssl:
        enabled: true
        verification_mode: certificate
        key: "/etc/elasticsearch/tls/server.key"
        certificate: "/etc/elasticsearch/tls/server.pem"
        certificate_authorities: ["/etc/elasticsearch/tls/ca.pem"]
%{ else ~}
    enabled: false
%{ endif ~}
path:
  data: /var/lib/elasticsearch
network:
  host: 0.0.0.0
discovery:
  seed_hosts: "masters.${domain}"
node:
  master: ${is_master ? "true" : "false"}
  data: ${is_master ? "false" : "true"}
  ingest: ${is_master ? "false" : "true"}
cluster:
  name: ${cluster_name}
%{ if length(initial_masters) > 0 ~}
  initial_master_nodes:
%{ for master in initial_masters ~}
    - ${master}
%{ endfor ~}
%{ endif ~}