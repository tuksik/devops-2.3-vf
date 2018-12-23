cd k8s-specs

git pull

cd cluster

cat kops

source kops

export BUCKET_NAME=devops23-$(date +%s)

aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --create-bucket-configuration \
    LocationConstraint=$AWS_DEFAULT_REGION

export KOPS_STATE_STORE=s3://$BUCKET_NAME

# Windows Only
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
    --master-size t2.small \
    --node-count 2 \
    --node-size t2.medium \
    --zones $ZONES \
    --master-zones $ZONES \
    --ssh-public-key devops23.pub \
    --networking kubenet \
    --authorization RBAC \
    --yes

kops validate cluster

# Windows only
kops export kubecfg --name ${NAME}

# Windows only
export KUBECONFIG=$PWD/config/kubecfg.yaml

kubectl create \
    -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/ingress-nginx/v1.6.0.yaml

CLUSTER_DNS=$(aws elb \
    describe-load-balancers | jq -r \
    ".LoadBalancerDescriptions[] \
    | select(.DNSName \
    | contains (\"api-devops23\") \
    | not).DNSName")

echo $CLUSTER_DNS

cd ..
# Deploying stateful applications without persisting
# state
cat pv/jenkins-no-pv.yml

kubectl create \
    -f pv/jenkins-no-pv.yml \
    --record --save-config

kubectl --namespace jenkins \
    get events

kubectl --namespace jenkins \
    create secret \
    generic jenkins-creds \
    --from-literal=jenkins-user=jdoe \
    --from-literal=jenkins-pass=incognito

kubectl --namespace jenkins \
    rollout status \
    deployment jenkins

open "http://$CLUSTER_DNS/jenkins"

kubectl --namespace jenkins \
    get pods \
    --selector=app=jenkins \
    -o json

POD_NAME=$(kubectl \
    --namespace jenkins \
    get pods \
    --selector=app=jenkins \
    -o jsonpath="{.items[*].metadata.name}")

echo $POD_NAME

kubectl --namespace jenkins \
    exec -it $POD_NAME pkill java

open "http://$CLUSTER_DNS/jenkins"

# Creating AWS volumes

aws ec2 describe-instances

aws ec2 describe-instances \
    | jq -r \
    ".Reservations[].Instances[] \
    | select(.SecurityGroups[]\
    .GroupName==\"nodes.$NAME\")\
    .Placement.AvailabilityZone"

aws ec2 describe-instances \
    | jq -r \
    ".Reservations[].Instances[] \
    | select(.SecurityGroups[]\
    .GroupName==\"nodes.$NAME\")\
    .Placement.AvailabilityZone" \
    | tee zones

AZ_1=$(cat zones | head -n 1)

AZ_2=$(cat zones | tail -n 1)

VOLUME_ID_1=$(aws ec2 create-volume \
    --availability-zone $AZ_1 \
    --size 10 \
    --volume-type gp2 \
    --tag-specifications "ResourceType=volume,Tags=[{Key=KubernetesCluster,Value=$NAME}]" \
    | jq -r '.VolumeId')

VOLUME_ID_2=$(aws ec2 create-volume \
    --availability-zone $AZ_1 \
    --size 10 \
    --volume-type gp2 \
    --tag-specifications "ResourceType=volume,Tags=[{Key=KubernetesCluster,Value=$NAME}]" \
    | jq -r '.VolumeId')

VOLUME_ID_3=$(aws ec2 create-volume \
    --availability-zone $AZ_2 \
    --size 10 \
    --volume-type gp2 \
    --tag-specifications "ResourceType=volume,Tags=[{Key=KubernetesCluster,Value=$NAME}]" \
    | jq -r '.VolumeId')

echo $VOLUME_ID_1

aws ec2 describe-volumes \
    --volume-ids $VOLUME_ID_1
# Creating Kubernetes persistent volumes
cat pv/pv.yml

cat pv/pv.yml \
    | sed -e \
    "s@REPLACE_ME_1@$VOLUME_ID_1@g" \
    | sed -e \
    "s@REPLACE_ME_2@$VOLUME_ID_2@g" \
    | sed -e \
    "s@REPLACE_ME_3@$VOLUME_ID_3@g" \
    | kubectl create -f - \
    --save-config --record

kubectl get pv
# Creating Kubernetes persistent volumes
cat pv/pvc.yml

kubectl create -f pv/pvc.yml \
    --save-config --record

kubectl --namespace jenkins \
    get pvc

kubectl get pv
# Attaching claimed volumes to Pods
cat pv/jenkins-pv.yml

kubectl apply \
    -f pv/jenkins-pv.yml \
    --record

kubectl --namespace jenkins \
    rollout status \
    deployment jenkins

open "http://$CLUSTER_DNS/jenkins"

POD_NAME=$(kubectl \
    --namespace jenkins \
    get pod \
    --selector=app=jenkins \
    -o jsonpath="{.items[*].metadata.name}")

kubectl --namespace jenkins \
    exec -it $POD_NAME pkill java

open "http://$CLUSTER_DNS/jenkins"

kubectl --namespace jenkins delete \
    deploy jenkins

kubectl --namespace jenkins get pvc

kubectl get pv

kubectl --namespace jenkins \
    delete pvc jenkins

kubectl get pv

kubectl delete -f pv/pv.yml

aws ec2 delete-volume \
    --volume-id $VOLUME_ID_1

aws ec2 delete-volume \
    --volume-id $VOLUME_ID_2

aws ec2 delete-volume \
    --volume-id $VOLUME_ID_3

# Using storage classes to dynamically
# provision persistent volumes

kubectl get sc

cat pv/jenkins-dynamic.yml

kubectl apply \
    -f pv/jenkins-dynamic.yml \
    --record

kubectl --namespace jenkins \
    rollout status \
    deployment jenkins

kubectl --namespace jenkins \
    get events

kubectl --namespace jenkins get pvc

kubectl get pv

aws ec2 describe-volumes \
    --filters 'Name=tag-key,Values="kubernetes.io/created-for/pvc/name"'

kubectl --namespace jenkins \
    delete deploy,pvc jenkins

kubectl get pv

aws ec2 describe-volumes \
    --filters 'Name=tag-key,Values="kubernetes.io/created-for/pvc/name"'

# Using default storage classes

kubectl get sc

kubectl describe sc gp2

cat pv/jenkins-default.yml

diff pv/jenkins-dynamic.yml \
    pv/jenkins-default.yml

kubectl apply \
    -f pv/jenkins-default.yml \
    --record

kubectl get pv

kubectl --namespace jenkins \
    delete deploy,pvc jenkins
# Creating storage classes
cat pv/sc.yml

kubectl create -f pv/sc.yml

kubectl get sc

cat pv/jenkins-sc.yml

kubectl apply \
    -f pv/jenkins-sc.yml \
    --record

aws ec2 describe-volumes \
    --filters 'Name=tag-key,Values="kubernetes.io/created-for/pvc/name"'

kubectl delete ns jenkins

kops delete cluster \
    --name $NAME \
    --yes

aws s3api delete-bucket \
    --bucket $BUCKET_NAME
