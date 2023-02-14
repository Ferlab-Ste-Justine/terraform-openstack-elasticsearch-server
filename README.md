# About

This terraform module provisions an elasticsearch 7 server that is part of a cluster on openstack.

# Limitations

## Security

While tls is enabled, access-control is currently disabled.

For this reason, the cluster should be running on a private network.

We tried integrating pki authentication, but Elastic is restricting that feature to those who have a Gold or better license, which, to put it diplomatically, is an interesting choice to say the least.

Potential solutions we are contemplating are:
- Using password authentication instead
- Using an additional networking security layer (ex: Haproxy or even a service mesh)
- Switching to Opensearch

## Prerequisites

The module has been developped with an recent Ubuntu image. Your mileage may vary with other distributions.

Furthermore, the module assumes that you have a dynamically configurable dns service that will be modified as part of the terraform execution for master discovery.

## Node Roles Topology Assumption

The module assumes that you will be working with dedicated masters nodes and dedicated worker nodes and supports that use-case.

# Usage

## Input Variables

- **name**: Name to give to the vm. Will be the hostname as well.
- **cluster_name**: Name of the elasticsearch cluster the server will join.
- **network_port**: Resource of type **openstack_networking_port_v2** to assign to the vm for network connectivity.
- **server_group**: Server group to assign to the node. Should be of type **openstack_compute_servergroup_v2**.
- **image_id**: Id of the vm image used to provision the node
- **flavor_id**: Id of the VM flavor
- **keypair_name**: Name of the keypair that will be used to ssh to the node
- **domain**: Domain of the cluster, also used for master discovery. Should have a **masters** subdomain that resolves to the ip of the masters and a **workers** subdomain that resolves to the ip of the workers.

- **initial_masters**: List of host names for the initial masters to bootstrap the cluster when it is created with its initial nodes. Should be empty for additional servers that will be added to the cluster later on.
- **nameserver_ips**: Ips of nameservers that are to be used for master discovery. This list can be left blank if the network's dns servers already fulfill that role.
- **is_master**: Whether the server is a master. Otherwise, it will be a worker.
- **tls_enabled**: Whether the elasticsearch server should communicate over https or regular http.
- **chrony**: Optional chrony configuration for when you need a more fine-grained ntp setup on your vm. It is an object with the following fields:
  - **enabled**: If set the false (the default), chrony will not be installed and the vm ntp settings will be left to default.
  - **servers**: List of ntp servers to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server)
  - **pools**: A list of ntp server pools to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool)
  - **makestep**: An object containing remedial instructions if the clock of the vm is significantly out of sync at startup. It is an object containing two properties, **threshold** and **limit** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep)
The following variables are used to serve traffic over tls, if enabled:
- **ca**: Certificate authority used to sign the certificate of the server. It is an object with the following fields:
  - **key**: Private key that was used to sign the ca certificate
  - **key_algorithm**: Algorithm of the private key that was used to sign the ca certificate
  - **certificate**: The ca's certificate 
- **server_certificate**: Parameters for the server's certificate. It is an object with the following fields:
  - **organization**: The es server certificate's organization. Defaults to **Ferlab**
  - **certificate_validity_period**: The validity period of the certificate for the es server. Defaults to 100 years.
  - **certificate_early_renewal_period**: Period before the certificate's expiry when Terraform will try to auto-renew the certificate for the es server. Defaults to 1 year.
  - **additional_domains**: Additional domains to add to the server certificate

## Example

```
locals {
  cluster = {
    masters = [
      {
        name            = "master-1"
        enabled         = true
        flavor          = module.reference_infra.flavors.micro.id
        image           = data.openstack_images_image_v2.ubuntu_focal.id
        initial_cluster = true
      },
      {
        name            = "master-2"
        enabled         = true
        flavor          = module.reference_infra.flavors.micro.id
        image           = data.openstack_images_image_v2.ubuntu_focal.id
        initial_cluster = true
      },
      {
        name            = "master-3"
        enabled         = true
        flavor          = module.reference_infra.flavors.micro.id
        image           = data.openstack_images_image_v2.ubuntu_focal.id
        initial_cluster = true
      }
    ]
    workers = [
      {
        name            = "worker-1"
        enabled         = true
        flavor          = module.reference_infra.flavors.small.id
        image           = data.openstack_images_image_v2.ubuntu_focal.id
        initial_cluster = true
      },
      {
        name            = "worker-2"
        enabled         = true
        flavor          = module.reference_infra.flavors.small.id
        image           = data.openstack_images_image_v2.ubuntu_focal.id
        initial_cluster = true
      },
      {
        name            = "worker-3"
        enabled         = true
        flavor          = module.reference_infra.flavors.small.id
        image           = data.openstack_images_image_v2.ubuntu_focal.id
        initial_cluster = true
      }
    ]
  }
}

module "ca" {
  source = "./ca"
}

resource "openstack_compute_keypair_v2" "es" {
  name = "elasticsearch"
}

module "es_security_groups" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-elasticsearch-security-groups.git"
  namespace = "myproject"
}

resource "openstack_compute_servergroup_v2" "es_masters" {
  name     = "myproject-es-masters"
  policies = ["soft-anti-affinity"]
}

resource "openstack_compute_servergroup_v2" "es_workers" {
  name     = "myproject-es-workers"
  policies = ["soft-anti-affinity"]
}

resource "openstack_networking_port_v2" "es_masters" {
  for_each = {
    for master in local.cluster.masters : master.name => master
  }

  name               = "myproject-es-${each.value.name}"
  network_id         = module.reference_infra.networks.internal.id
  security_group_ids = [module.es_security_groups.groups.master.id]
  admin_state_up     = true
}

resource "openstack_networking_port_v2" "es_workers" {
  for_each = {
    for worker in local.cluster.workers : worker.name => worker
  }

  name               = "myproject-es-${each.value.name}"
  network_id         = module.reference_infra.networks.internal.id
  security_group_ids = [module.es_security_groups.groups.worker.id]
  admin_state_up     = true
}

module "es_domain" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-zonefile.git"
  domain = "elasticsearch.myproject.com"
  container = local.dns.bucket_name
  dns_server_name = "ns.myproject.com."
  a_records = concat([
    for master in openstack_networking_port_v2.es_masters: {
      prefix = "masters"
      ip = master.all_fixed_ips.0
    }
  ],
  [
    for worker in openstack_networking_port_v2.es_workers: {
      prefix = "workers"
      ip = worker.all_fixed_ips.0
    } 
  ])
}

module "es_masters" {
  for_each = {
    for master in local.cluster.masters : master.name => master if master.enabled
  }
  
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-elasticsearch-server.git"
  name = "myproject-es-${each.value.name}"
  network_port = openstack_networking_port_v2.es_masters[each.value.name]
  server_group = openstack_compute_servergroup_v2.es_masters
  cluster_name = "myproject-es"
  image_id = each.value.image
  flavor_id = each.value.flavor
  domain = "elasticsearch.myproject.com"
  nameserver_ips = local.dns.nameserver_ips
  is_master = true
  initial_masters = each.value.initial_cluster ? [for master in openstack_networking_port_v2.es_masters: master.all_fixed_ips.0] : []
  tls_enabled = true
  ca = module.ca
  keypair_name = openstack_compute_keypair_v2.es.name

  server_certificate = {
    organization = "myorg"
    validity_period = 100*365*24
    early_renewal_period = 365*24
    additional_domains = ["elasticsearch", "elasticsearch-masters", "masters.elasticsearch.myproject.com"]
  }
}

module "es_workers" {
  for_each = {
    for worker in local.cluster.workers : worker.name => worker if worker.enabled
  }

  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-openstack-elasticsearch-server.git"
  name = "myproject-es-${each.value.name}"
  network_port = openstack_networking_port_v2.es_workers[each.value.name]
  server_group = openstack_compute_servergroup_v2.es_workers
  cluster_name = "myproject-es"
  image_id = each.value.image
  flavor_id = each.value.flavor
  domain = "elasticsearch.myproject.com"
  nameserver_ips = local.dns_ops.nameserver_ips
  is_master = false
  initial_masters = each.value.initial_cluster ? [for master in openstack_networking_port_v2.es_masters: master.all_fixed_ips.0] : []
  tls_enabled = true
  ca = module.ca
  keypair_name = openstack_compute_keypair_v2.es.name

  server_certificate = {
    organization = "myorg"
    validity_period = 100*365*24
    early_renewal_period = 365*24
    additional_domains = ["elasticsearch", "elasticsearch-workers", "workers.elasticsearch.myproject.com"]
  }
}
```