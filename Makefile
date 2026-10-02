BUILD ?= up --build --remove-orphans -d
DC ?= $(shell docker compose version 2>&1 >/dev/null && echo "docker compose" || echo "docker-compose")
SUBNET ?= 10.11
SUBNET6 ?= 2001:db8:1:1::
SLURM_RELEASE ?= slurm-26-05-3-1

ifdef SCALEOUT_DEFAULT_HOST
	HOST ?= $(SCALEOUT_DEFAULT_HOST)
else
	HOST ?= login
endif

.EXPORT_ALL_VARIABLES:
DISABLE_XDMOD ?=
.PHONY: git-submodules git-slurm clean clean-nodelist uninstall run bash save load nocache cloud benchmark-% test-build

default: ./docker-compose.yml run

./docker-compose.yml: buildout.sh
	bash buildout.sh > ./docker-compose.yml

#based on https://stackoverflow.com/questions/52337010/automatic-initialization-and-update-of-submodules-in-makefile
git-submodules: ./docker-compose.yml
	@if git submodule status | egrep -q '^[-+]' ; then \
	        git submodule update --init --recursive --checkout --depth 1 --recommend-shallow --single-branch 1>&2; \
	fi

# checkout the correct Slurm branch as submodules will cache the wrong hash
git-slurm: git-submodules
	# always update git to check the hash of the SLURM_RELEASE
	$(eval SLURM_RELEASE_HASH := $(shell \
		cd scaleout/src/slurm && ( \
			(git fetch --depth 1 origin $(SLURM_RELEASE) && \
				git log -1 --format=format:"%H" $(SLURM_RELEASE) \
			) || (git fetch origin --depth 1 -a --tags && \
				git log -1 --format=format:"%H" origin/$(SLURM_RELEASE) \
			) || (git fetch origin -a --tags && (\
				git log -1 --format=format:"%H" $(SLURM_RELEASE) || \
				git log -1 --format=format:"%H" origin/$(SLURM_RELEASE)) \
			) \
		) 2>/dev/null ))
	$(eval SLURM_HASH := $(shell \
		cd scaleout/src/slurm && \
		git log -1 --format=format:"%H" HEAD 2>/dev/null \
	))
	test ! -z $(SLURM_RELEASE_HASH) || exit 1
	test ! -z $(SLURM_RELEASE) || exit 1
	test ! -z $(SLURM_HASH) || exit 1
	cd scaleout/src/slurm && git checkout $(SLURM_RELEASE_HASH) -fq || ( \
		git fetch --depth 1 --tags origin $(SLURM_RELEASE) && \
		git checkout $(SLURM_RELEASE_HASH) -fq \
	)

git-patches: git-slurm $(wildcard patch.d/*.patch)
	[ -z "$(wildcard ./patch.d/*.patch)" ] || ( \
		cd scaleout/src/slurm && \
		readlink -e -- $(wildcard ./patch.d/*.patch) | xargs \
			git am -3 --empty=keep --ignore-space-change \
			--exclude=NEWS -- \
	)

build: ./docker-compose.yml git-submodules git-patches git-slurm
	env COMPOSE_HTTP_TIMEOUT=3000 $(DC) --ansi=never --progress=plain $(BUILD)

stop:
	$(DC) --progress=quiet down

set_nocache:
	$(eval BUILD := build --no-cache)

nocache: set_nocache build

clean-nodelist:
	truncate -s0 scaleout/nodelist

clean:
	@[ -f ./docker-compose.yml ] && ( \
		$(DC) --progress=quiet down --remove-orphans --rmi local -v -t 1; \
		$(DC) --progress=quiet kill --remove-orphans -s SIGKILL; \
		$(DC) --progress=quiet rm -f -v -s; \
		unlink ./docker-compose.yml &>/dev/null; \
	) || true
	git submodule foreach --recursive git clean -xfd
	git submodule foreach --recursive 'git rebase --abort || :' &>/dev/null
	git submodule foreach --recursive 'git am --abort || :' &>/dev/null
	git submodule foreach --recursive 'git cherry-pick --abort || :' &>/dev/null
	git submodule foreach --recursive git reset --hard >/dev/null
	#git submodule deinit -f --all >/dev/null
	git submodule update --init --recursive >/dev/null

uninstall:
	$(DC) --progress=quiet down --rmi all --remove-orphans -t1 -v
	$(DC) rm -v

run: ./docker-compose.yml
	$(DC) up --remove-orphans -d

cloud:
	test -f cloud_socket && unlink cloud_socket || true
	touch cloud_socket
	test -f ./docker-compose.yml && unlink ./docker-compose.yml || true
	env CLOUD=1 bash buildout.sh > ./docker-compose.yml
	python3 ./cloud_monitor.py3 "$(DC)"
	test -f ./docker-compose.yml && unlink ./docker-compose.yml || true
	test -f cloud_socket && unlink cloud_socket || true

bash:
	$(DC) exec $(HOST) /bin/bash

save: build
	$(eval IMAGES := $(shell $(DC) config | awk '{if ($$1 == "image:") print $$2;}' | sort | uniq))
	docker save -o scaleout.tar $(IMAGES)

load:
	docker load -i scaleout.tar

benchmark-%: clean-nodelist clean
	$(eval SLURM_BENCHMARK := $(subst benchmark-,,$@))
	env SLURM_BENCHMARK=$(SLURM_BENCHMARK) bash buildout.sh > ./docker-compose.yml
	env COMPOSE_HTTP_TIMEOUT=3000 $(DC) --ansi=never --progress=plain $(BUILD)
	$(DC) up --remove-orphans -d
	$(DC) exec $(HOST) bash -c '(find /root/benchmark/run.d/ -type f -name $(SLURM_BENCHMARK)\*.sh | xargs -i echo bash "{} &"; echo wait) | bash -x'
	$(DC) --progress=quiet down
	truncate -s0 scaleout/nodelist

test-build: clean-nodelist clean build
	$(DC) exec $(HOST) bash /usr/local/bin/test-build.sh
	test -f ./docker-compose.yml && ($(DC) --progress=quiet kill -s SIGKILL; $(DC) --progress=quiet down --remove-orphans -t1; unlink ./docker-compose.yml) || true
	[ -f cloud_socket ] && unlink cloud_socket || true
