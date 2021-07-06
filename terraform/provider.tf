#provider "openstack" {
  # use environment variables
#}

terraform {
  required_version = ">= 0.14"
  backend "http" {
  }
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}
