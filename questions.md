# Questions:
 1. how to load balance multiple services in the docekr compose file: 
    if we use the name of the service directly ... docker-compose automatically load balances services.
 2. giving the service a list of sevices to use.
    - ?????????????????
 3. Having multiple instances and getting their ports:
    - Run docker-compose with `--scale service_name=no_of_instances`
    - in order not to have port issues, make the ports part of the service on exposeing container's ports with assigning host ports so docker can assign random ports
    - run `docker-compose port --index=instance_index service_name container_port` in order to get the host assigned port.
 4. Spawning mutiple deployments using the same compose file: 
    - The only way I could think about was to add a deployment number to the service name. It is possible to do so but the problem is that is not configurable through environment variables (only possible through parsing the docker-compose files everytime we run it.
    - we can maybe use overrides? `https://docs.docker.com/compose/extends/#multiple-compose-files`
    - Since topgun runs on different nodes, maybe we need to run the docker test the same way.
    - PROJECT!!!
    - disregard all that :D
    - -p specifies the project to use (by default parent directory name)
    - the command can look like: `docker-compose -f docker-compose.yml -p depl-2 up -d --build --scale web=2`
 5. Which Dockerfile will we be testing against?
    - The output of the bin-docker job.
    - can also be run internally inside the job itself.
    - per Alex, this doesn't exist anymore! just test against the dev docker-compose now!

# Side Notes: 
  * Will need to run docker cleanup commands for every run
  * It will be really beneficial to use overrides that kinda resembles the operations files in bosh
  * Equivalents:
    * delete-deployment --> docker compose down
    * deploy --> docker-compose up 
    * 
