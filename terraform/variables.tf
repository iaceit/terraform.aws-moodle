variable "region" {
  default = "ap-southeast-2"
}

variable "key_pair" {
  default = "aws-shared-key"
}

variable "tags" {
  type = map(string)

  default = {
    "service"    = "iaceit.com"
    "created-by" = "terraform"
    "owner"      = "iaceit.com"
    "repo"       = "terraform.moodle"
  }
}

