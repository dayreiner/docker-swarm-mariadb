Zero to HA Docker Swarm and MariaDB Galera cluster in 15 minutes on IBM Softlayer (or anywhere, really)
==================

Some scripts for an upcoming [blog](http://18pct.com/blog) article. Will document more when I've got it written.

## No Context Short Version

- Multi-master docker swarm cluster
- HA Consul running on the swarm itself.
- btrfs storage driver.
- Multi-master MariaDB Galera cluster running out of containers on the swarm, natch.
- Overlay network between MariaDB swarm containers for cluster communication etc.
- Percona Xtrabackup instead of rsync for state transfer.

Tested from CentOS 7. Requires the Softlayer "[slcli](https://github.com/softlayer/softlayer-python)" command-line api client tool (`pip install softlayer`) and expect (`yum -y install expect`) if not already present on the system you're running these from. 
Otherwise, look through the scripts to get an idea of the process. 

- `cd config ; cp swarm.conf swarm.local`
- `vi swarm.local` and change values for your nodes and environment
- `cd ../scripts`
- `./provision_softlayer.sh` (orders nodes, run post-provisioning scripts)
- `./build_swarm.sh` (Deploys multi-master swarm using HA consul on the swarm nodes themselves)
- Wait for the swarm nodes to find the consul cluster and finish bootstrapping the swarm 
 - `eval $(docker-machine env --swarm sw1)`
 - `docker info` and wait for all three nodes to be listed
- `./deploy_mariadb.sh` Bootstrap the MariaDB cluster on the swarm nodes.
- `docker exec -ti sw1-db1 bash`, run `mysql` and `show status like 'wsrep%';` to confirm the cluster is operational.
- Also includes scripts for tearing down the swarm, rebuilding it and cancelling the swarm instances in Softlayer

Zero to functional Galera Cluster across three Softlayer instances:
```
    real    13m17.885s
    user    0m15.442s
    sys     0m3.577s
```
