#!/usr/bin/env bash
# Lab 11 - supprime TOUTES les ressources AWS du lab (et uniquement elles : IDs de .aws-state.env + tag Project)
set -uo pipefail
cd "$(dirname "$0")/.."
. ./.aws-state.env; export AWS_PROFILE AWS_REGION AWS_PAGER=""
P=jenkins-lab11

echo "== 1. Instance $INSTANCE_ID"
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --query 'TerminatingInstances[0].CurrentState.Name' --output text
aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" && echo "   terminée"
echo "== 2. Security Group $SG_ID"
aws ec2 delete-security-group --group-id "$SG_ID" && echo "   supprimé"
echo "== 3. Key pair $KEY"
aws ec2 delete-key-pair --key-name "$KEY" && echo "   supprimée"
echo "== 4. IAM $ROLE"
aws iam remove-role-from-instance-profile --instance-profile-name "$ROLE" --role-name "$ROLE"
aws iam delete-instance-profile --instance-profile-name "$ROLE"
aws iam detach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam delete-role --role-name "$ROLE" && echo "   rôle et instance profile supprimés"
echo "== 5. ECR $ECR_REPO (images comprises)"
aws ecr delete-repository --repository-name "$ECR_REPO" --force --query 'repository.repositoryName' --output text
echo "== 6. Local : clé privée et empreinte SSH de l'instance"
rm -f "$PEM" && echo "   $PEM supprimée"
ssh-keygen -R "$EC2_HOST" >/dev/null 2>&1 && echo "   $EC2_HOST retiré de ~/.ssh/known_hosts"

echo
echo "== Vérification : plus aucune ressource du lab"
echo "   instances  : $(aws ec2 describe-instances --filters Name=tag:Project,Values=$P Name=instance-state-name,Values=pending,running,stopping,stopped --query 'length(Reservations[].Instances[])' --output text)"
echo "   SG         : $(aws ec2 describe-security-groups --filters Name=tag:Project,Values=$P --query 'length(SecurityGroups)' --output text)"
echo "   key pairs  : $(aws ec2 describe-key-pairs --filters Name=tag:Project,Values=$P --query 'length(KeyPairs)' --output text)"
echo "   volumes    : $(aws ec2 describe-volumes --filters Name=tag:Project,Values=$P --query 'length(Volumes)' --output text)"
echo "   rôle IAM   : $(aws iam get-role --role-name "$ROLE" >/dev/null 2>&1 && echo PRÉSENT || echo absent)"
echo "   dépôt ECR  : $(aws ecr describe-repositories --repository-names "$ECR_REPO" >/dev/null 2>&1 && echo PRÉSENT || echo absent)"
echo "   autres instances du compte (non touchées) :"
aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,State.Name]' --output text | sed 's/^/     /'
