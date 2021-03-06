# variables that can be overriden
variable "hostname" { default = "k8s-master" }
variable "domain" { default = "k8s.lab" }
variable "memory" { default = 4 }
variable "cpu" { default = 1 }
variable "iface" { default = "eth0" }
variable "libvirt_network" { default = "k8s" }
variable "libvirt_pool" { default= "k8s" }

# instance the provider
provider "libvirt" {
  uri = "qemu:///system"
}

# fetch the latest ubuntu release image from their mirrors
resource "libvirt_volume" "os_image" {
  name = "${var.hostname}-os_image"
  pool = var.libvirt_pool
  source = "/tmp/CentOS-7-x86_64-GenericCloud.qcow2"
#  source = "https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2"

  format = "qcow2"
}

# Use CloudInit ISO to add ssh-key to the instance
resource "libvirt_cloudinit_disk" "commoninit" {
  name = "${var.hostname}-commoninit.iso"
  pool = var.libvirt_pool 
  user_data = data.template_file.user_data.rendered
  meta_data = data.template_file.meta_data.rendered
}


data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    hostname = "${var.hostname}.${var.domain}"
    fqdn = "${var.hostname}.${var.domain}"  
    iface = var.iface
  }
}

#Fix for centOS
data "template_file" "meta_data" {
  template = file("${path.module}/network_config.cfg")
  vars = {
    iface = var.iface
  }
}


# Create the machine
resource "libvirt_domain" "k8s-loadbalancer" {
  # domain name in libvirt, not hostname
  name = var.hostname
  memory = var.memory*1024
  vcpu = var.cpu

  disk {
     volume_id = libvirt_volume.os_image.id
  }

  network_interface {
       network_name = var.libvirt_network
  }

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  # IMPORTANT
  # Ubuntu can hang is a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = "true"
  }
}

terraform { 
  required_version = ">= 0.12"
}

output "ips" {
  value = "${flatten(libvirt_domain.k8s-loadbalancer.*.network_interface.0.addresses)}"
}

output "macs" {
  value = "${flatten(libvirt_domain.k8s-loadbalancer.*.network_interface.0.mac)}"
}
