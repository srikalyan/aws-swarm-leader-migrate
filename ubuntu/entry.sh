#!/bin/bash
echo "#================================================================================================================"
echo "Starting Swarm leader migration monitoring process"
echo "NODE_TYPE=$NODE_TYPE"
echo "DYNAMODB_TABLE=$DYNAMODB_TABLE"
echo "AWS_REGION=$REGION"
echo "CHECK_SLEEP_DURATION=${CHECK_SLEEP_DURATION:-300}"

function get_region {
    export AZ=$(curl http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null)
    export REGION=${AZ::-1}
    echo "Availability Zone=$AZ and AWS_REGION=$REGION"
}

get_leader_ip_from_dynamodb()
{
    # query dynamodb and get the Ip for the leader.
    MANAGER=$(aws dynamodb get-item --region $REGION --table-name $DYNAMODB_TABLE --key '{"node_type":{"S": "primary_manager"}}')
    export MANAGER_IP=$(echo $MANAGER | jq -r '.Item.ip.S')
    export MANAGER_TOKEN=$(echo $MANAGER | jq -r '.Item.manager_token.S')
    export WORKER_TOKEN=$(echo $MANAGER | jq -r '.Item.worker_token.S')

    echo "PRIMARY_MANAGER_IP=$MANAGER_IP"
    echo "MANAGER_TOKEN=$MANAGER_TOKEN"
    echo "WORKER_TOKEN=$WORKER_TOKEN"
}

confirm_leader_ready()
{
    n=0
    until [ $n -ge 5 ]
    do
        get_leader_ip_from_dynamodb
        # if Manager IP or manager_token is empty or manager_token is null, not ready yet.
        # token would be null for a short time between swarm init, and the time the
        # token is added to dynamodb
        if [ -z "$MANAGER_IP" ] || [ -z "$MANAGER_TOKEN" ] || [ "$MANAGER_TOKEN" == "null" ]; then
            echo "Leader Not ready yet, sleep for 60 seconds."
            sleep 60
            n=$[$n+1]
        else
            echo "Leader is ready."
            break
        fi
    done
}

get_leader_info_from_cluster()
{
    echo "Getting leader IP from cluster"
    export MANAGER_NODE=$(docker node ls | grep  'Leader' | awk '{print $1}')
    if [ -z "$MANAGER_NODE" ]; then
        export MANAGER_IP_FROM_CLUSTER=""
    else
        export MANAGER_IP_FROM_CLUSTER=$(docker node inspect $MANAGER_NODE -f "{{ .ManagerStatus.Addr }}" | cut -d":" -f1)
    fi
    echo "GOT $MANAGER_IP_FROM_CLUSTER as leader"
}

update_leader_info() {
    echo "Updating leader IP as $MANAGER_IP_FROM_CLUSTER"
    aws dynamodb put-item \
        --table-name $DYNAMODB_TABLE \
        --region $REGION \
        --item '{"node_type":{"S": "primary_manager"},"ip": {"S":"'"$MANAGER_IP_FROM_CLUSTER"'"},"manager_token": {"S":"'"$MANAGER_TOKEN"'"},"worker_token": {"S":"'"$WORKER_TOKEN"'"}}' \
        --return-consumed-capacity TOTAL

}

watch_and_update_leader()
{
    # check if manager is ready
    if [ -z "$MANAGER_IP" ] || [ "$MANAGER_TOKEN" == "null" ]; then
        echo "Check if manager is ready"
        confirm_leader_ready
        echo "MANAGER_IP=$MANAGER_IP"

    fi

    if [ -z "$MANAGER_IP" ] || [ "$MANAGER_TOKEN" == "null" ]; then
        echo "Manager seems not ready so not doing much here"
        return
    fi

    get_leader_info_from_cluster
    if [ -z "$MANAGER_IP_FROM_CLUSTER" ]; then
        echo "Unable to get manager ip from cluster"
        return
    elif [ "$MANAGER_IP_FROM_CLUSTER" != "$MANAGER_IP" ]; then
        echo "Leader has changed from $MANAGER_IP to $MANAGER_IP_FROM_CLUSTER checking once again from dynamodb"

        get_leader_ip_from_dynamodb

        if [ "$MANAGER_IP_FROM_CLUSTER" != "$MANAGER_IP" ]; then
            update_leader_info
            get_leader_ip_from_dynamodb
        fi
    else
        echo "Leader has not changed from $MANAGER_IP"
    fi

}

if [ -z "$REGION" ]; then
    get_region
fi

while true; do

    echo "#============================================================================================================"
    watch_and_update_leader
    echo "#============================================================================================================"
    sleep ${CHECK_SLEEP_DURATION:-300}

done


echo "Shuttting down swarm leader migration process"
echo "#================================================================================================================"
