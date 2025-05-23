data "template_file" "config_server_yaml" {
  template = "${file("${path.module}/file_templates/config_server.yaml.tpl")}"
  vars = {
    rke2_token = var.rke2_token
  }
}

data "template_file" "config_other_yaml" {
  template = "${file("${path.module}/file_templates/config_other.yaml.tpl")}"
  vars = {
    rke2_token = var.rke2_token
    server = var.vm_ips[0]
  }
}


data "template_file" "rancher_manifest" {
  template = "${file("${path.module}/file_templates/rancher_manifest.yaml.tpl")}"
  vars = {
    rancher_hostname = var.rancher_hostname
    rancher_version = var.rancher_version
  }
}


data "local_file" "ssh_private_key" {
 filename = var.ssh_private_key 
}

resource "null_resource" "rke2_common" {

  count = var.wk_vm_count + var.cp_vm_count

  triggers = {
    conn_user     = var.ssh_user
    conn_private_key = data.local_file.ssh_private_key.content
    conn_password = var.ssh_password
    conn_host          = var.vm_ips[count.index]
    hostname      = count.index < var.cp_vm_count && var.do_deploy_rancher ? "rancher-${count.index + 1}" : count.index < var.cp_vm_count ? "downstream-cp-${count.index + 1}" : "downstream-wk-${count.index - var.cp_vm_count + 1}"
  }


  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = data.local_file.ssh_private_key.content
      password = var.ssh_password
      host     = var.vm_ips[count.index]
    }
    inline = [
      "mkdir $HOME/.ssh",
      "cat > $HOME/.ssh/authorized_keys <<EOF\n${file(var.public_key_path)}\nEOF",
      "sudo systemctl stop firewalld && systemctl disable firewalld",
      "sudo mkdir -p /etc/rancher/rke2", 
      "sudo mkdir -p /var/lib/rancher/rke2/server/manifests",
      "sudo mkdir -p /var/lib/rancher/rke2/agent/images",
      "sudo mkdir -p /opt/rke2",
      "sudo hostnamectl set-hostname ${self.triggers.hostname}",
      "sudo cp $HOME/rke2/install.sh /opt/rke2/"
    ]
    on_failure = continue
  }


  ## copy install script and RKE2 binary to /opt/rke2
  provisioner "file" {
    source = "${path.module}/rke2"
    destination = "$HOME"

    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = data.local_file.ssh_private_key.content
      password = var.ssh_password
      host     = var.vm_ips[count.index]
    }
  }

  ## Destroy-time provisioner
  provisioner "remote-exec" {
    when = destroy

    connection {
      type     = "ssh"
      user     = self.triggers.conn_user
      private_key = self.triggers.conn_private_key
      password = self.triggers.conn_password
      host     = self.triggers.conn_host
    }
    inline = [
      "rke2-uninstall.sh",

    ] 
  }

}

resource null_resource "rke2_server1_provisioning" {

  depends_on = [
    null_resource.rke2_common
  ]

  provisioner "file" {
    content = data.template_file.config_server_yaml.rendered
    destination = "$HOME/config.yaml"

    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = data.local_file.ssh_private_key.content
      password = var.ssh_password
      host     = var.vm_ips[0]
    }
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = data.local_file.ssh_private_key.content
      password = var.ssh_password
      host     = var.vm_ips[0]
    }
    inline = [
      "sudo chmod +x /opt/rke2/install.sh",
      "sudo cp $HOME/config.yaml /etc/rancher/rke2/config.yaml",
      # TODO : Need to improve the following for both Air Gapped and Non-Airgapped modes
      #"INSTALL_RKE2_METHOD=tar INSTALL_RKE2_ARTIFACT_PATH=/opt/rke2 /opt/rke2/install.sh",
      "sudo INSTALL_RKE2_VERSION=${var.rke2_version} /opt/rke2/install.sh",
      "sudo systemctl enable rke2-server && sudo systemctl start rke2-server",

    ]
    on_failure = continue
  }
}

resource "null_resource" "deploy_rancher" {
  depends_on = [
    null_resource.rke2_common
  ]
  count = var.do_deploy_rancher ? var.cp_vm_count : 0
  provisioner "file" {

    
    content = data.template_file.rancher_manifest.rendered
    destination = "/var/lib/rancher/rke2/server/manifests/rancher-helm-chart.yaml"

    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = var.ssh_private_key
      password = var.ssh_password
      host     = var.vm_ips[count.index]
    }
    on_failure = continue
  }
}

### Waiting between first server and others
resource "time_sleep" "sleep_between_first_server_and_others" {
  
  depends_on = [
    null_resource.rke2_server1_provisioning
  ]

  create_duration = "30s"

}


### Setting up the after-first servers
resource null_resource "rke2_servers_others_provisioning" {

  count = var.cp_vm_count - 1 
  depends_on = [
    time_sleep.sleep_between_first_server_and_others
  ]

  provisioner "file" {
    content = data.template_file.config_other_yaml.rendered
    destination = "/etc/rancher/rke2/config.yaml"

    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = data.local_file.ssh_private_key.content
      password = var.ssh_password
      host     = var.vm_ips[count.index+1]
    }
    on_failure = continue
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = var.ssh_private_key
      password = var.ssh_password
      host     = var.vm_ips[count.index+1]
    }
    inline = [
      "sudo chmod +x /opt/rke2/install.sh",
      # TODO : Need to improve the following for both Air Gapped and Non-Airgapped modes
      #"INSTALL_RKE2_METHOD=tar INSTALL_RKE2_ARTIFACT_PATH=/opt/rke2 /opt/rke2/install.sh",
      "sudo INSTALL_RKE2_VERSION=${var.rke2_version} /opt/rke2/install.sh",
      "sudo systemctl enable rke2-server && sudo systemctl start rke2-server",

    ]
    on_failure = continue
  }
}


### Setting up the Workers
resource null_resource "rke2_workers_provisioning" {

  count = var.wk_vm_count 
  depends_on = [
    time_sleep.sleep_between_first_server_and_others
  ]

  provisioner "file" {
    content = data.template_file.config_other_yaml.rendered
    destination = "/etc/rancher/rke2/config.yaml"

    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = data.local_file.ssh_private_key.content
      password = var.ssh_password
      host     = var.vm_ips[count.index + var.cp_vm_count]
    }

  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.ssh_user
      private_key = data.local_file.ssh_private_key.content
      password = var.ssh_password
      host     = var.vm_ips[count.index + var.cp_vm_count]
    }
    inline = [
      "sudo chmod +x /opt/rke2/install.sh",
      # TODO : Need to improve the following for both Air Gapped and Non-Airgapped modes
      #"INSTALL_RKE2_METHOD=tar INSTALL_RKE2_ARTIFACT_PATH=/opt/rke2 /opt/rke2/install.sh",
      "sudo INSTALL_RKE2_VERSION=${var.rke2_version} /opt/rke2/install.sh",
      #"INSTALL_RKE2_METHOD=tar INSTALL_RKE2_ARTIFACT_PATH=/opt/rke2 /opt/rke2/install.sh",
      "sudo systemctl enable rke2-agent && sudo systemctl start rke2-agent",

    ]
    on_failure = continue
  }

}
