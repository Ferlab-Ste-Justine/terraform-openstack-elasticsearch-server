# About

This terraform module provisions an elasticsearch 7 server that is part of a cluster on openstack.

# Status

This is a refactor of the following project, currently in POC: https://github.com/Ferlab-Ste-Justine/openstack-elasticsearch-cluster

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
- **domain**: Domain of the cluster, also used for master discovery. Should have a **masters** subdomain that resolves to the ip of the masters and a **workers** subdomain that resolves to the ip of the workers.
- **initial_masters**: List of host names for the initial masters to bootstrap the cluster when it is created with its initial nodes. Should be empty for additional servers that will be added to the cluster later on.
- **keypair_name**: Name of the keypair that will be used to ssh to the node
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