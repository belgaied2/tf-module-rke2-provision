variable "public_key_path" {
  description = "path of public key for nodes"
  default     = "~/.ssh/id_rsa.pub"
}


variable "cp_vm_count" {
  description = "Number of VMs to spin up for RKE"
}

variable "wk_vm_count" {
  description = "Number of VMs to spin up for RKE"
}

variable "vm_ips" {
  type = list(string)
  description = "List of IP Addresses for all VMs to use deploy Rancher on."
}


variable "ssh_user" {
  type = string
  description = "SSH Username to connect to VM with"
}

variable "ssh_password" {
  type = string
  description = "SSH Password to connect to VM with"
}

variable "ssh_private_key" {
  type = string
  description = "SSH Private Key path to connect to VM with"
}

variable "vm_name_prefix" {
  description = "Prefix for the VM name in vSphere"
  default     = "rancher-ha"
}

variable "rke2_token" {
  description = "Desired RKE2 token"
}

variable "rancher_hostname" {
  description = "Desired Hostname for Rancher App"
  default = ""
}

variable "do_deploy_rancher" {
  type = bool
  description = "Variable to decide if Rancher will be deployed."
  default = false
}


variable "rke2_version" {
  description = "RKE2 Version to deploy"
  default = "v1.30.4+rke2r1"
  
}

variable "rancher_version" {
  type = string
  description = "Rancher version to be deployed"
  default = "v2.9.2"
}
