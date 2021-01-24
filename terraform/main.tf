terraform {
  required_version = ">= 0.12"

  backend "s3" {
    region = "ap-southeast-2"
    bucket = "987882637451"
    key    = "iaceit.com/terraform/moodle/ap-southeast-2/terraform.tfstate"
  }
}

