resource "aws_s3_bucket" "tf_state" {
  bucket = "task16-wordpress-tfstate"
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name = "Terraform State Bucket"
  }
}
