#Requirements: on master host install Git, Ansible and Terraform
#Clone repository to desired location with git clone https://github.com/mas0lik/terraform-docker.git

#GCP Authentication
#Step 1: Get you GCP authentication json in Console https://console.cloud.google.com/apis/credentials/serviceaccountkey
#Step 2: Place json in /home/pkhramchenkov/ for example
#Step 3: Execute export GOOGLE_APPLICATION_CREDENTIALS=/home/pkhramchenkov/DevOps-gcp.json
#Step 4: Add "export GOOGLE_APPLICATION_CREDENTIALS=/home/pkhramchenkov/DevOps-gcp.json" to /root/.bashrc

#Dockerhub Authentication
#Step 1: Encrypt yor dockerhub password using command ansible-vault
#Execute ansible-vault encrypt_string "your_dockerhub_password" --name "dockerhub_token" --vault-password-file vault_pass
#Default vault password is stored in vault_pass. Change it!
#Step 2: Supply ansible vault output as 'dockerhub_token' var in roles/dockerhub_connect/defaults/main.yml as well
#other credentials

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.59.0"
    }
  }
}

provider "google" {
  # Configuration options
  credentials = file("DevOps-gcp.json")
  project     = "tonal-bloom-302318"
  region      = "us-central1"
  zone        = "us-central1-a"
}

resource "google_compute_instance" "terraform-staging" {
  name          = "terraform-staging"
  #machine_type = "e2-small" // 2vCPU, 2GB RAM
  machine_type  = "e2-medium" // 2vCPU, 4GB RAM
  #machine_type = "custom-6-20480" // 6vCPU, 20GB RAM / 6.5GB RAM per CPU, if needed more refer to next line
  #machine_type = "custom-2-15360-ext" // 2vCPU, 15GB RAM

  #tags = ["terraform", "staging"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      size  = "10" // size in GB for Disk
      type  = "pd-balanced" // Available options: pd-standard, pd-balanced, pd-ssd
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP and external static IP
      #nat_ip = google_compute_address.static.address
    }
  }

  metadata = {
    ssh-keys = "root:${file("/root/.ssh/id_rsa.pub")}" // Point to ssh public key for user root
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
    ]
    connection {
      type     = "ssh"
      user     = "root"
      private_key = file("/root/.ssh/id_rsa")
      host        = self.network_interface[0].access_config[0].nat_ip
    }
  }
}

output "staging_public_ip" {
    value = google_compute_instance.terraform-staging.network_interface[0].access_config[0].nat_ip
}

resource "google_compute_instance" "terraform-production" {
  name          = "terraform-production"
  #machine_type = "e2-small" // 2vCPU, 2GB RAM
  machine_type  = "e2-medium" // 2vCPU, 4GB RAM
  #machine_type = "custom-6-20480" // 6vCPU, 20GB RAM / 6.5GB RAM per CPU, if needed more refer to next line
  #machine_type = "custom-2-15360-ext" // 2vCPU, 15GB RAM

  #tags = ["terraform", "production"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      size  = "10" // size in GB for Disk
      type  = "pd-balanced" // Available options: pd-standard, pd-balanced, pd-ssd
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    network = "default"

    access_config {
      // Ephemeral IP and external static IP
      #nat_ip = google_compute_address.static.address
    }
  }

  metadata = {
    ssh-keys = "root:${file("/root/.ssh/id_rsa.pub")}" // Point to ssh public key for user root
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
    ]
    connection {
      type     = "ssh"
      user     = "root"
      private_key = file("/root/.ssh/id_rsa")
      host        = self.network_interface[0].access_config[0].nat_ip
    }
  }
}

output "production_public_ip" {
    value = google_compute_instance.terraform-production.network_interface[0].access_config[0].nat_ip
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [google_compute_instance.terraform-production]

  create_duration = "30s" // Change to 90s
}

resource "null_resource" "ansible_hosts_provisioner" {
  depends_on = [time_sleep.wait_30_seconds]
  provisioner "local-exec" {
    interpreter = ["/bin/bash" ,"-c"]
    command = <<EOT
      export terraform_staging_public_ip=$(terraform output staging_public_ip);
      echo $terraform_staging_public_ip;
      export terraform_production_public_ip=$(terraform output production_public_ip);
      echo $terraform_production_public_ip;
      sed -i -e "s/staging_instance_ip/$terraform_staging_public_ip/g" ./inventory/hosts;
      sed -i -e "s/production_instance_ip/$terraform_production_public_ip/g" ./inventory/hosts;
      sed -i -e 's/"//g' ./inventory/hosts;
      export ANSIBLE_HOST_KEY_CHECKING=False
    EOT
  }
}

resource "time_sleep" "wait_5_seconds" {
  depends_on = [null_resource.ansible_hosts_provisioner]

  create_duration = "5s"
}

resource "null_resource" "ansible_playbook_provisioner" {
  depends_on = [time_sleep.wait_5_seconds]
  provisioner "local-exec" {
    command = "ansible-playbook -u root --vault-password-file 'vault_pass' --private-key '/root/.ssh/id_rsa' -i inventory/hosts main.yml"
  }
}
