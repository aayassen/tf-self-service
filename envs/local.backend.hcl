bucket                      = "tfstate-local"
key                         = "placeholder" # set per team by tf.sh
region                      = "eu-central-1"
endpoints                   = { s3 = "http://localhost:4566" }
use_path_style              = true
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_metadata_api_check     = true
use_lockfile                = true
