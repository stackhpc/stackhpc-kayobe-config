#provider "openstack" {
# use environment variables
#}

terraform {
  required_version = ">= 0.14"
  backend "local" {
  }
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}
