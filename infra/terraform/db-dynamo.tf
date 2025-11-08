# dynamodb.tf
resource "aws_dynamodb_table" "inventory" {
  name         = "bookstore-inventory"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sku"

  attribute {
    name = "sku"
    type = "S"
  }
}
