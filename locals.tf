#locals{
#    tags = {
#        created_by = "terraform"
#    }
#
#    aws_ecr_url = "account??.dkr.ecr.<region??>.amazonaws.com"
#}

locals{
    tags = {
        created_by = "terraform"
    }

    aws_ecr_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}