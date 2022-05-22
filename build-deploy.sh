#!/bin/bash
terraform init
terraform destroy --auto-approve #destroy previous deployment resources
terraform validate # validate the code
terraform plan # review the resources to be deployed
terraform apply  --auto-approve # deploy the resources