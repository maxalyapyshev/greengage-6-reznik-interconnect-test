.PHONY: build up init start stop check network test shell down verify
build:
	bash scripts/build.sh
up:
	bash scripts/lab.sh up
init:
	bash scripts/lab.sh init
start:
	bash scripts/lab.sh start
stop:
	bash scripts/lab.sh stop
check:
	bash scripts/lab.sh check
network:
	bash scripts/network.sh
test:
	bash scripts/lab.sh test
shell:
	bash scripts/lab.sh shell
down:
	bash scripts/lab.sh down
verify:
	python3 scripts/verify.py
