#!/bin/bash
yum update -y
yum install -y httpd
cd & mkdir temp
aws s3 sync  s3://my-simple-webpage temp/
cp -R /temp/* /var/www/html/
rm -rf temp
systemctl start httpd
systemctl enable httpd
#echo "Hello World from $(hostname -f)" > /var/www/html/index.html
echo "Healthy" > /var/www/html/health.html
