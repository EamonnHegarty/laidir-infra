# Chicken-and-egg: this root creates the state bucket, so its first apply uses
# local state. After the first apply, uncomment the block below and run
#   terraform init -migrate-state
# to move bootstrap's own state into the bucket it created. See README.md.

# terraform {
#   backend "s3" {
#     bucket       = "laidir-tfstate-670518205160"
#     key          = "bootstrap/terraform.tfstate"
#     region       = "eu-west-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
