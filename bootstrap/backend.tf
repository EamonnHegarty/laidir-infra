# Chicken-and-egg: this root creates the state bucket, so its very first apply
# used local state. After that apply, this backend block was enabled and
#   terraform init -migrate-state
# moved bootstrap's own state into the bucket it created. See README.md.

terraform {
  backend "s3" {
    bucket       = "laidir-tfstate-670518205160"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
