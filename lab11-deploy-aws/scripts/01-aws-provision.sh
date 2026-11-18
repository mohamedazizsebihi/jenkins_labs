#!/usr/bin/env bash
# Lab 11 - « zéro console AWS » : crée (ou retrouve) les ressources du lab, toutes taguées Project=jenkins-lab11.
#   ECR (lab11/jenkins-demo-app), rôle IAM + instance profile (lecture ECR), Security Group (22/80 depuis
#   l'IP du poste), paire de clés ed25519, instance t3.micro Ubuntu 24.04. Les IDs vont dans .aws-state.env.
set -euo pipefail
cd "$(dirname "$0")/.."
export AWS_PROFILE=${AWS_PROFILE:-isoset} AWS_REGION=${AWS_REGION:-us-east-1} AWS_PAGER=""
P=jenkins-lab11; NAME=lab11-jenkins-ec2; KEY=lab11-jenkins; SG=lab11-jenkins-sg
ROLE=lab11-ec2-ecr-read; REPO=lab11/jenkins-demo-app
PEM=$HOME/.ssh/lab11-ec2.pem; STATE=.aws-state.env
MYIP="$(curl -fsS https://checkip.amazonaws.com)/32"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY=$ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com

# 1. Dépôt ECR privé (scan des vulnérabilités au push)
aws ecr describe-repositories --repository-names "$REPO" >/dev/null 2>&1 ||
  aws ecr create-repository --repository-name "$REPO" --image-scanning-configuration scanOnPush=true \
      --tags Key=Project,Value=$P >/dev/null
echo "OK  ECR            $ECR_REGISTRY/$REPO"

# 2. Rôle IAM de l'instance : lecture seule ECR (aucun secret sur le serveur)
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --tags Key=Project,Value=$P \
      --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
fi
if ! aws iam get-instance-profile --instance-profile-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$ROLE" --tags Key=Project,Value=$P >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$ROLE" --role-name "$ROLE"
fi
echo "OK  IAM            rôle + instance profile $ROLE (AmazonEC2ContainerRegistryReadOnly)"

# 3. Security Group : SSH et HTTP uniquement depuis l'IP publique du poste
VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$SG Name=vpc-id,Values=$VPC \
        --query 'SecurityGroups[0].GroupId' --output text)
if [ "$SG_ID" = None ]; then
  SG_ID=$(aws ec2 create-security-group --group-name $SG --vpc-id "$VPC" \
          --description "Lab 11 Jenkins - SSH et HTTP depuis le poste du lab" \
          --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$P},{Key=Name,Value=$SG}]" \
          --query GroupId --output text)
fi
for port in 22 80; do
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port $port --cidr "$MYIP" >/dev/null 2>&1 || true
done
echo "OK  Security Group $SG_ID ($SG) : 22 et 80 depuis $MYIP uniquement"

# 4. Paire de clés ed25519 : la clé privée n'existe qu'en local (jamais dans Git)
if ! aws ec2 describe-key-pairs --key-names $KEY >/dev/null 2>&1; then
  ( umask 077; aws ec2 create-key-pair --key-name $KEY --key-type ed25519 \
      --tag-specifications "ResourceType=key-pair,Tags=[{Key=Project,Value=$P}]" \
      --query KeyMaterial --output text > "$PEM" )
fi
[ -s "$PEM" ] || { echo "ERREUR : la paire $KEY existe mais $PEM est absent" >&2; exit 1; }
chmod 600 "$PEM"
echo "OK  Key pair       $KEY -> $PEM ($(stat -c '%A' "$PEM"))"

# 5. Instance EC2 (retrouvée par son tag si elle existe déjà)
IID=$(aws ec2 describe-instances --filters Name=tag:Project,Values=$P Name=instance-state-name,Values=pending,running,stopping,stopped \
      --query 'Reservations[0].Instances[0].InstanceId' --output text)
if [ "$IID" = None ]; then
  AMI=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
        --query Parameter.Value --output text)
  for try in 1 2 3 4 5 6; do   # l'instance profile met quelques secondes à se propager
    IID=$(aws ec2 run-instances --image-id "$AMI" --instance-type t3.micro --key-name $KEY \
          --security-group-ids "$SG_ID" --iam-instance-profile Name=$ROLE \
          --metadata-options HttpTokens=required,HttpEndpoint=enabled \
          --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=$P},{Key=Name,Value=$NAME}]" \
                               "ResourceType=volume,Tags=[{Key=Project,Value=$P}]" \
          --query 'Instances[0].InstanceId' --output text 2>/dev/null) && break
    sleep 10
  done
  [ -n "$IID" ] && [ "$IID" != None ] || { echo "ERREUR : run-instances" >&2; exit 1; }
fi
aws ec2 wait instance-running --instance-ids "$IID"
IP=$(aws ec2 describe-instances --instance-ids "$IID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "OK  Instance       $IID ($NAME, t3.micro, Ubuntu 24.04, IMDSv2) -> $IP"

echo -n "    attente de SSH "
for _ in $(seq 1 60); do
  ssh -i "$PEM" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 ubuntu@"$IP" true 2>/dev/null && break
  echo -n "."; sleep 5
done; echo
ssh -i "$PEM" -o BatchMode=yes ubuntu@"$IP" 'echo "    connecté : $(hostname) - $(lsb_release -ds)"'

cat > "$STATE" <<EOS
# État des ressources AWS du Lab 11 (généré, hors Git)
AWS_PROFILE=$AWS_PROFILE
AWS_REGION=$AWS_REGION
ACCOUNT=$ACCOUNT
ECR_REGISTRY=$ECR_REGISTRY
ECR_REPO=$REPO
ROLE=$ROLE
SG_ID=$SG_ID
KEY=$KEY
PEM=$PEM
INSTANCE_ID=$IID
EC2_HOST=$IP
EOS
echo "OK  état écrit dans $STATE"
