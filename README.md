Zero to HA MariaDB and Docker Swarm in under 15 minutes on IBM Softlayer (or anywhere, really)
==================

Provisioning helper scripts for my post [Zero to HA MariaDB and Docker Swarm in under 15 minutes on IBM Softlayer (or anywhere, really)](http://18pct.com/zero-to-mariadb-cluster-in-docker-swarm-in-15-minutes-part-1/) over at my [blog](http://18pct.com/blog/).

## Build Goals

- Multi-master, highly-available docker swarm cluster on CentOS 7.
- HA Consul key-value store running on the swarm itself.
- Use the btrfs storage driver (or alternately, device-mapper with LVM).
- Containerized MariaDB Galera cluster running on the swarm, natch.
- Overlay network between MariaDB nodes for cluster communication etc.
- Percona Xtrabackup instead of rsync to reduce locking during state transfers.

# Putting it all Together

In addition to the deployment helper scripts in the `scripts` directory, you'll find compose files for consul and MariaDB using my [CentOS7 MariaDB Galera](https://hub.docker.com/r/dayreiner/centos7-mariadb-10.1-galera/) docker image off of [docker hub](hub.docker.com) in the `compose` dir.

Running through the scripts in order, you'll end up with an n-node MariaDB Galera cluster running on top of a multi-master Docker Swarm, using an HA Consul cluster for swarm discovery and btrfs container storage -- all self-contained within the *n* swarm masters. In a real production environment, you would want to consider moving the database and any services on to Swarm agent hosts, and leave the three swarm masters to the task of managing the swarm itself.

To quickly deploy your own MariaDB cluster, follow the steps outlined below. If you prefer to just read through scripts and see for yourself how things are done (or on a different platform), you can browse through the scripts directly [here](https://github.com/dayreiner/docker-swarm-mariadb/tree/master/scripts). The provisioning process was tested from a CentOS 7 host, so YMMV with other OSes -- if you run in to any issues, feel free to [report them here](https://github.com/dayreiner/docker-swarm-mariadb/issues).

### Prerequsites
In order to run the scripts, you'll need to have the the Softlayer "[slcli](https://github.com/softlayer/softlayer-python)" command-line api client tool (`pip install softlayer`) installed and configured on the system you'll be running docker-machine from (or an alternate way to get the IP addresses of your instances if provisioned elsewhere). The expect command (`yum -y install expect`) is also required to run the softlayer order script -- otherwise you can provision instances yourself manually.

## Running the scripts
To get started, first clone this repository:

```bash
git clone git@github.com:dayreiner/docker-swarm-mariadb.git
```

Change to the `docker-swarm-mariadb` directory and run `source source.me` to set your docker-machine storage path to the `machine` subdirectory of the repository. This will help keep everything self-contained. Next go in the `config` directory and copy the premade example `swarm.conf` file to a new file called `swarm.local`. Make any changes you need to `swarm.local`; this will override the values in the example config. The config file is used to define some variables your environment, the number of swarm nodes etc. Once that's done, you can either provision the swarm instances automatically via the softlayer provisioning script or just skip ahead to building the swarm or the MariaDB cluster and overlay network:

### Steps
1. `cd config ; cp swarm.conf swarm.local`
2. `vi swarm.local` -- and change values for your nodes and environment
3. `cd ../scripts`
4. `./provision_softlayer.sh` -- generate ssh keys, orders nodes, runs post-provisioning scripts
5. `./build_swarm.sh` -- deploys the swarm and the consul cluster
6. Wait for the swarm nodes to find the consul cluster and finish bootstrapping the swarm. Check with:
 - `eval $(docker-machine env --swarm sw1)`
 - `docker info` -- and wait for all three nodes to be listed
7. `./deploy_mariadb.sh` Bootstrap the MariaDB cluster on the swarm nodes.
 - Check container logs to confirm all nodes have started
 - Run `docker exec -ti sw1-db1 mysql -psecret "show status like 'wsrep%';"` to confirm the cluster is happy.
9. *Optionally* run `./deploy_mariadb.sh` a second time to redeploy db1 as a standard galera cluster member.

The repo also includes scripts for tearing down the swarm, rebuilding it and cancelling the swarm instances in Softlayer when you're done.

#### Zero to a functional Galera Cluster across three Softlayer instances:

```bash
    real    13m17.885s
    user    0m15.442s
    sys     0m3.577s
```

Nice!
