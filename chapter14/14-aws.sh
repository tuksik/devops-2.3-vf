cd k8s-specs

git pull

export AWS_ACCESS_KEY_ID=[...]

export AWS_SECRET_ACCESS_KEY=[...]

aws --version

export AWS_DEFAULT_REGION=us-east-2

aws iam create-group \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
    --group-name kops

aws iam attach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
    --group-name kops

aws iam create-user \
    --user-name kops

aws iam add-user-to-group \
    --user-name kops \
    --group-name kops

aws iam create-access-key \
    --user-name kops >kops-creds

cat kops-creds

export AWS_ACCESS_KEY_ID=$(\
    cat kops-creds | jq -r \
    '.AccessKey.AccessKeyId')

export AWS_SECRET_ACCESS_KEY=$(
    cat kops-creds | jq -r \
    '.AccessKey.SecretAccessKey')

aws ec2 describe-availability-zones \
    --region $AWS_DEFAULT_REGION

export ZONES=$(aws ec2 \
    describe-availability-zones \
    --region $AWS_DEFAULT_REGION \
    | jq -r \
    '.AvailabilityZones[].ZoneName' \
    | tr '\n' ',' | tr -d ' ')

ZONES=${ZONES%?}

echo $ZONES

mkdir -p cluster

cd cluster

aws ec2 create-key-pair \
    --key-name devops23 > log 

cat log    | jq -r '.KeyMaterial' \
    >devops23.pem

chmod 400 devops23.pem

ssh-keygen -y -f devops23.pem \
    >devops23.pub

# Creating a kubernetes cluster in AWS

export NAME=devops23.k8s.local

export BUCKET_NAME=devops23-$(date +%s)

aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --create-bucket-configuration \
    LocationConstraint=$AWS_DEFAULT_REGION

export KOPS_STATE_STORE=s3://$BUCKET_NAME

# If MacOS
brew update && brew install kops

# If MacOS
curl -Lo kops https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-darwin-amd64

# If MacOS
chmod +x ./kops

# If MacOS
sudo mv ./kops /usr/local/bin/

# If Linux
wget -O kops https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64

# If Linux
chmod +x ./kops

# If Linux
sudo mv ./kops /usr/local/bin/

# If Windows
mkdir config

# If Windows
alias kops="docker run -it --rm \
    -v $PWD/devops23.pub:/devops23.pub \
    -v $PWD/config:/config \
    -e KUBECONFIG=/config/kubecfg.yaml \
    -e NAME=$NAME -e ZONES=$ZONES \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -e KOPS_STATE_STORE=$KOPS_STATE_STORE \
    vfarcic/kops"

kops create cluster \
    --name $NAME \
    --master-count 3 \
    --node-count 1 \
    --node-size t2.small \
    --master-size t2.small \
    --zones $ZONES \
    --master-zones $ZONES \
    --ssh-public-key devops23.pub \
    --networking kubenet \
    --kubernetes-version v1.9.1 \
    --yes

kops get cluster

kubectl cluster-info

kops validate cluster

kubectl --namespace kube-system get pods
# Updating the cluster
kops edit --help

kops edit ig --name $NAME nodes

kops update cluster --name $NAME --yes

kops validate cluster

kubectl get nodes
# Upgrading the cluster manually
kops edit cluster $NAME

kops update cluster $NAME

kops update cluster $NAME --yes

kops rolling-update cluster $NAME

kops rolling-update cluster $NAME --yes

kubectl get nodes

# Upgrading the cluster automatically
kops upgrade cluster $NAME --yes

kops update cluster $NAME --yes

kops rolling-update cluster $NAME --yes
# Accessing the cluster
aws elb describe-load-balancers

kubectl config view

kubectl create \
    -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/ingress-nginx/v1.6.0.yaml

kubectl --namespace kube-ingress \
    get all

aws elb describe-load-balancers

CLUSTER_DNS=$(aws elb describe-load-balancers | jq -r \
    ".LoadBalancerDescriptions[] \
    | select(.DNSName \
    | contains (\"api-devops23\") \
    | not).DNSName")
# Deploying applications
cd ..

kubectl create \
    -f aws/go-demo-2.yml \
    --record --save-config

kubectl rollout status \
    deployment go-demo-2-api

curl -i "http://$CLUSTER_DNS/demo/hello"

# Exploring high-availability and fault-
# tolerance
aws ec2 \
    describe-instances | jq -r \
    ".Reservations[].Instances[] \
    | select(.SecurityGroups[]\
    .GroupName==\"nodes.$NAME\")\
    .InstanceId"

INSTANCE_ID=$(aws ec2 \
    describe-instances | jq -r \
    ".Reservations[].Instances[] \
    | select(.SecurityGroups[]\
    .GroupName==\"nodes.$NAME\")\
    .InstanceId" | tail -n 1)

aws ec2 terminate-instances \
    --instance-ids $INSTANCE_ID

aws ec2 \
    describe-instances | jq -r \
    ".Reservations[].Instances[] \
    | select(\
    .SecurityGroups[].GroupName \
    ==\"nodes.$NAME\").InstanceId"

aws ec2 \
    describe-instances | jq -r \
    ".Reservations[].Instances[] \
    | select(.SecurityGroups[]\
    .GroupName==\"nodes.$NAME\")\
    .InstanceId"

kubectl get nodes

kubectl get nodes
# Giving others access to the cluster
cd cluster

mkdir -p config

export KUBECONFIG=$PWD/config/kubecfg.yaml

kops export kubecfg --name ${NAME}

cat $KUBECONFIG

# Destroying the cluster

echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
ZONES=$ZONES
NAME=$NAME
KOPS_STATE_STORE=$KOPS_STATE_STORE" \
    >kops

kops delete cluster \
    --name $NAME \
    --yes

aws s3api delete-bucket \
    --bucket devops23-store
# Do NOT run this
# Replace `[...]` with the administrative access key ID.
export AWS_ACCESS_KEY_ID=[...]

# Do NOT run this
# Replace `[...]` with the administrative secret access key.
export AWS_SECRET_ACCESS_KEY=[...]

# Do NOT run this
aws iam remove-user-from-group \
    --user-name kops \
    --group-name kops

# Do NOT run this
aws iam delete-access-key \
    --user-name kops \
    --access-key-id $(\
    cat kops-creds | jq -r \
    '.AccessKey.AccessKeyId')

# Do NOT run this
aws iam delete-user \
    --user-name kops

# Do NOT run this
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
    --group-name kops

# Do NOT run this
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --group-name kops

# Do NOT run this
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess \
    --group-name kops

# Do NOT run this
aws iam detach-group-policy \
    --policy-arn arn:aws:iam::aws:policy/IAMFullAccess \
    --group-name kops

# Do NOT run this
aws iam delete-group \
    --group-name kops
