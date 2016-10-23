# aws-swarm-leader-migrate
Docker image responsible for automatic migration of swarm leader in AWS using Dynamodb. Most of the logic lives in the 
script `entry.sh`.

In order to automate the leader migration, 

1. Run `swarm node ls` command and check if there is a new leader
2. If there is a new leader update Dynamodb and sleep for x seconds and then go to step 1
3. If there is no new leader then sleep for x seconds and then go to step 1

This docker image performs the above steps ensuring the leader information is up to date in Dynamodb. 

This docker image needs following environment variables

  - `NODE_TYPE`: Should be either `manager` or `worker`
  - `DYNAMODB_TABLE`: Name of the dynamodb table to be used for locking and passing cluster information
  - `REGION`: AWS region in which dynamodb table was created (if not provided will default to region of the instance)
  - `CHECK_SLEEP_DURATION`: time in seconds to sleep after each poll to check if leader has changed (defaults 300 or 5 mins)

## docker-compose:

    version: "2"
    services:
        aws-swarm-leader-migrate:
          image: "srikalyan/aws-swarm-leader-migrate:version"
          container_name: "aws-swarm-leader-migrate"
          restart: "always"
          environment:
            NODE_TYPE: "<manager|worker>"
            DYNAMODB_TABLE: "<dynamodb_table>"
          volumes:
            - /var/run/docker.sock:/var/run/docker.sock
            -  /usr/bin/docker:/usr/bin/docker
            - /var/log:/var/log


*Note 1*: This image needs a docker client but does not install one as this would create unnecessary versions which we 
could easily skip by mount the docker binary from host ubuntu machine.

