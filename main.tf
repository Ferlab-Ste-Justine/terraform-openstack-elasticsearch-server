locals {
  es_bootstrap_config = templatefile(
    "${path.module}/files/elasticsearch.yml.tpl",
    {
      domain = var.domain
      cluster_name = var.cluster_name
      is_master = var.is_master
      initial_masters = var.initial_masters
      tls_enabled = var.tls_enabled
    }
  )
  es_runtime_config = templatefile(
    "${path.module}/files/elasticsearch.yml.tpl",
    {
      domain = var.domain
      cluster_name = var.cluster_name
      is_master = var.is_master
      initial_masters = []
      tls_enabled = var.tls_enabled
    }
  )
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/files/user_data.yaml.tpl", 
      {
        nameserver_ips = var.nameserver_ips
        is_master = var.is_master
        initial_masters = var.initial_masters
        node_name = var.name
        server_key = var.tls_enabled ? tls_private_key.key.0.private_key_pem : ""
        server_certificate = var.tls_enabled ? tls_locally_signed_cert.certificate.0.cert_pem : ""
        ca_certificate = var.tls_enabled ? var.ca.certificate : ""
        request_protocol = var.tls_enabled ? "https" : "http"
        elasticsearch_boot_configuration = local.es_bootstrap_config
        elasticsearch_runtime_configuration = local.es_runtime_config
        chrony = var.chrony
      }
    )
  }
}

resource "openstack_compute_instance_v2" "elasticsearch" {
  name            = var.name
  image_id        = var.image_id
  flavor_id       = var.flavor_id
  key_pair        = var.keypair_name
  user_data = data.template_cloudinit_config.user_data.rendered

  network {
    port = var.network_port.id
  }

  scheduler_hints {
    group = var.server_group.id
  }

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}