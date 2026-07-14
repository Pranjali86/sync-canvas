#!/bin/bash
# One-time AWS infrastructure provisioning (EC2 + S3 + CloudFront)
# PostgreSQL runs as a Docker container on EC2 — no RDS needed
# Run from your local machine: bash deploy/setup-aws.sh
set -e

AWS_REGION="ap-south-1"
APP_NAME="sync-canvas"
KEY_PAIR_NAME="${APP_NAME}-key"

echo "==> Creating EC2 Key Pair..."
if aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" &>/dev/null; then
  echo "    Key pair already exists, skipping."
else
  aws ec2 create-key-pair \
    --region "$AWS_REGION" \
    --key-name "$KEY_PAIR_NAME" \
    --query 'KeyMaterial' \
    --output text > "${KEY_PAIR_NAME}.pem"
  chmod 400 "${KEY_PAIR_NAME}.pem"
  echo "    Key saved to ${KEY_PAIR_NAME}.pem — keep this file safe!"
fi

echo "==> Getting default VPC..."
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)
echo "    VPC: $VPC_ID"

SUBNET_ID=$(aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[0].SubnetId' \
  --output text)
echo "    Subnet: $SUBNET_ID"

echo "==> Creating Security Group for EC2..."
EXISTING_SG=$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=group-name,Values=${APP_NAME}-backend-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || echo "None")

if [ "$EXISTING_SG" != "None" ] && [ "$EXISTING_SG" != "" ]; then
  EC2_SG="$EXISTING_SG"
  echo "    Security group already exists: $EC2_SG"
else
  EC2_SG=$(aws ec2 create-security-group \
    --region "$AWS_REGION" \
    --group-name "${APP_NAME}-backend-sg" \
    --description "SyncCanvas EC2 backend" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$EC2_SG" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$EC2_SG" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$EC2_SG" \
    --protocol tcp --port 443 --cidr 0.0.0.0/0
  echo "    EC2 SG: $EC2_SG"
fi

echo "==> Launching EC2 instance (t3.small, Docker + PostgreSQL + Node.js)..."
AMI_ID=$(aws ec2 describe-images \
  --region "$AWS_REGION" \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' \
  --output text)
echo "    Using AMI: $AMI_ID"

EC2_INSTANCE=$(aws ec2 run-instances \
  --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type t3.small \
  --key-name "$KEY_PAIR_NAME" \
  --security-group-ids "$EC2_SG" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
  --user-data file://deploy/ec2-userdata.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${APP_NAME}-backend}]" \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "    EC2 instance: $EC2_INSTANCE"

echo "==> Creating S3 bucket for frontend..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET="${APP_NAME}-frontend-${ACCOUNT_ID}"

if aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
  echo "    Bucket already exists: $S3_BUCKET"
else
  aws s3api create-bucket \
    --region "$AWS_REGION" \
    --bucket "$S3_BUCKET" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
  aws s3api put-public-access-block \
    --region "$AWS_REGION" \
    --bucket "$S3_BUCKET" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  echo "    S3 bucket: $S3_BUCKET"
fi

echo "==> Creating CloudFront Origin Access Control..."
OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config \
    "Name=${APP_NAME}-oac,Description=SyncCanvas,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
  --query 'OriginAccessControl.Id' \
  --output text)
echo "    OAC: $OAC_ID"

echo "==> Attaching S3 bucket policy for CloudFront OAC..."
aws s3api put-bucket-policy \
  --bucket "$S3_BUCKET" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"AllowCloudFrontOAC\",
      \"Effect\": \"Allow\",
      \"Principal\": {\"Service\": \"cloudfront.amazonaws.com\"},
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${S3_BUCKET}/*\"
    }]
  }"

echo "==> Creating CloudFront distribution (SPA with 404→index.html)..."
CF_RESULT=$(aws cloudfront create-distribution \
  --distribution-config "{
    \"CallerReference\": \"${APP_NAME}-$(date +%s)\",
    \"Comment\": \"SyncCanvas frontend\",
    \"DefaultRootObject\": \"index.html\",
    \"Origins\": {
      \"Quantity\": 1,
      \"Items\": [{
        \"Id\": \"s3-${S3_BUCKET}\",
        \"DomainName\": \"${S3_BUCKET}.s3.${AWS_REGION}.amazonaws.com\",
        \"S3OriginConfig\": {\"OriginAccessIdentity\": \"\"},
        \"OriginAccessControlId\": \"${OAC_ID}\"
      }]
    },
    \"DefaultCacheBehavior\": {
      \"TargetOriginId\": \"s3-${S3_BUCKET}\",
      \"ViewerProtocolPolicy\": \"redirect-to-https\",
      \"CachePolicyId\": \"658327ea-f89d-4fab-a63d-7e88639e58f6\",
      \"Compress\": true
    },
    \"CustomErrorResponses\": {
      \"Quantity\": 1,
      \"Items\": [{
        \"ErrorCode\": 404,
        \"ResponsePagePath\": \"/index.html\",
        \"ResponseCode\": \"200\",
        \"ErrorCachingMinTTL\": 0
      }]
    },
    \"HttpVersion\": \"http2and3\",
    \"Enabled\": true
  }" \
  --query 'Distribution.[Id,DomainName]' \
  --output text)

CF_DIST_ID=$(echo "$CF_RESULT" | awk '{print $1}')
CF_DOMAIN=$(echo "$CF_RESULT"  | awk '{print $2}')
echo "    CloudFront ID:  $CF_DIST_ID"
echo "    CloudFront URL: https://$CF_DOMAIN"

echo "==> Waiting for EC2 public IP..."
sleep 15
EC2_IP=$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$EC2_INSTANCE" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo ""
echo "========================================="
echo "  Infrastructure ready!"
echo "========================================="
echo ""
echo "  EC2 IP:           $EC2_IP"
echo "  S3 Bucket:        $S3_BUCKET"
echo "  CloudFront ID:    $CF_DIST_ID"
echo "  CloudFront URL:   https://$CF_DOMAIN"
echo ""
echo "  NEXT STEPS:"
echo "  1. SSH in and update .env:"
echo "     ssh -i ${KEY_PAIR_NAME}.pem ec2-user@$EC2_IP"
echo "     nano /app/sync-canvas/.env"
echo "     Set: DB_PASSWORD, JWT_SECRET, CORS_ORIGINS=https://$CF_DOMAIN"
echo ""
echo "  2. Add these GitHub Secrets to your repo:"
echo "     AWS_ACCESS_KEY_ID           = (your key)"
echo "     AWS_SECRET_ACCESS_KEY       = (your secret)"
echo "     AWS_REGION                  = $AWS_REGION"
echo "     S3_BUCKET_NAME              = $S3_BUCKET"
echo "     CLOUDFRONT_DISTRIBUTION_ID  = $CF_DIST_ID"
echo "     EC2_HOST                    = $EC2_IP"
echo "     EC2_SSH_KEY                 = (paste contents of ${KEY_PAIR_NAME}.pem)"
echo "     VITE_WS_BASE_URL            = ws://$EC2_IP"
echo ""
echo "  3. Push to main — GitHub Actions will deploy everything."
echo "========================================="
