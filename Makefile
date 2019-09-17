SHELL := /bin/bash

PSWD=foobar

TDMQ_FILES=$(wildcard tdmq/*.py tdmq/client/*.py)

DOCKER_STACKS_REV := 6c3390a9292e8475d18026eb60f8d712b5b901db
TDMQJ_DEPS=tdmproject/tdmqj-deps

all: images

# FIXME copying tests/data twice...
docker/tdmq-dist: apidocs setup.py ${TDMQ_FILES} tests
	rm -rf docker/tdmq-dist ; mkdir docker/tdmq-dist
	cp -rf apidocs setup.py tdmq tests docker/tdmq-dist

tdmq-client: docker/Dockerfile.tdmqc
	docker build -f docker/Dockerfile.tdmqc --target=tdmq-client -t tdmproject/tdmq-client docker

tdmqc: docker/tdmq-dist tdmq-client docker/Dockerfile.tdmqc
	docker build -f docker/Dockerfile.tdmqc -t tdmproject/tdmqc docker

jupyter: docker/tdmq-dist tdmq-client docker/Dockerfile.jupyter
	docker build -f docker/Dockerfile.jupyter --target jupyter-deps -t ${TDMQJ_DEPS} docker
	docker build -f docker/Dockerfile.jupyter -t tdmproject/tdmqj docker

jupyterhub: jupyter
	if [[ ! -d docker-stacks ]]; then git clone https://github.com/jupyter/docker-stacks.git; fi
	cd docker-stacks;	git checkout ${DOCKER_STACKS_REV}
	cd docker-stacks/base-notebook/; docker build -t tdmproject/base-notebook --build-arg BASE_CONTAINER=${TDMQJ_DEPS} .
	cd docker-stacks/minimal-notebook/; docker build -t tdmproject/minimal-notebook --build-arg BASE_CONTAINER=tdmproject/base-notebook .
	docker build -f docker/Dockerfile.jupyterhub  -t tdmproject/tdmqj-hub --build-arg HADOOP_CLASSPATH=$$(docker run --rm --entrypoint "" ${TDMQJ_DEPS} /opt/hadoop/bin/hadoop classpath --glob) .



web: docker/tdmq-dist docker/Dockerfile.web
	docker build -f docker/Dockerfile.web -t tdmproject/tdmq docker

tdmq-db: docker/tdmq-db docker/tdmq-dist
	docker build -f docker/Dockerfile.tdmq-db -t tdmproject/tdmq-db docker

images: tdmqc jupyter web tdmq-db jupyterhub

docker/docker-compose-dev.yml: docker/docker-compose.yml-tmpl
	sed -e "s^LOCAL_PATH^$${PWD}^" \
	    -e "s^USER_UID^$$(id -u)^" \
	    -e "s^USER_GID^$$(id -g)^" \
	    -e "s^DEV=false^DEV=true^" \
	    -e "s^#DEV ^^" \
	       < docker/docker-compose.yml-tmpl > docker/docker-compose-dev.yml


docker/docker-compose.yml: docker/docker-compose.yml-tmpl
	sed -e "s^LOCAL_PATH^$${PWD}^" \
	    -e "s^USER_UID^$$(id -u)^" \
	    -e "s^USER_GID^$$(id -g)^" \
	     < docker/docker-compose.yml-tmpl > docker/docker-compose.yml

run: images docker/docker-compose.yml
	docker-compose -f ./docker/docker-compose.yml up

startdev: images docker/docker-compose-dev.yml
	docker-compose -f ./docker/docker-compose-dev.yml up -d

stopdev:
	docker-compose -f ./docker/docker-compose-dev.yml down

start: images docker/docker-compose.yml
	docker-compose -f ./docker/docker-compose.yml up -d
	# Try to wait for timescaleDB and HDFS
	docker-compose -f ./docker/docker-compose.yml exec timescaledb bash -c 'for i in {{1..8}}; do sleep 5; pg_isready && break; done || { echo ">> Timed out waiting for timescaleDB" >&2; exit 2; }'
	docker-compose -f ./docker/docker-compose.yml exec namenode hdfs dfsadmin -safemode wait
	docker-compose -f ./docker/docker-compose.yml exec datanode bash -c 'for i in {{1..8}}; do sleep 5; datanode_cid && break; done || { echo ">> Timed out waiting for datanode to join HDFS" >&2; exit 3; }'

stop:
	docker-compose -f ./docker/docker-compose.yml down

run-tests: start
	docker-compose -f ./docker/docker-compose.yml exec --user $$(id -u) tdmqc fake_user.sh /bin/bash -c 'cd $${TDMQ_DIST} && pytest -v tests'
	docker exec datanode bash -c 'until datanode_cid; do sleep 0.1; done'
	docker exec namenode bash -c "hdfs dfs -mkdir /tiledb"
	docker exec namenode bash -c "hdfs dfs -chmod a+wr /tiledb"
	docker logs tdmq-notebook
	docker exec tdmq-notebook bash -c "sed -i s/localhost/namenode/ /opt/hadoop/etc/hadoop/core-site.xml"
	docker exec tdmq-notebook bash -c "python /quickstart_dense.py -f hdfs://namenode:8020/tiledb"
	docker exec tdmq-notebook bash -c "python -c 'import tdmq, matplotlib'"


clean: stop
	rm -rf docker-stacks

.PHONY: all tdmqc-deps tdmqc jupyter jupyterhub web images run start stop startdev stopdev clean
