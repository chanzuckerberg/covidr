SHELL := /bin/bash
PYTHON_CODE_DIRECTORIES = src/py


##########
# DATABASE
##########

LOCAL_DB_CONTAINER_NAME = covidr-local
LOCAL_DB_CONTAINER_ID = $(shell docker ps -a | grep $(LOCAL_DB_CONTAINER_NAME) | awk '{print $$1}')
LOCAL_DB_CONTAINER_RUNNING_ID = $(shell docker ps | grep $(LOCAL_DB_CONTAINER_NAME) | awk '{print $$1}')
LOCAL_DB_NAME = covidr_db
LOCAL_DB_ADMIN_USERNAME = postgres  # This has to be "postgres" to ease moving snapshots from RDS.
LOCAL_DB_ADMIN_PASSWORD = admin
LOCAL_DB_RW_USERNAME = user_rw
LOCAL_DB_RW_PASSWORD = password_rw
LOCAL_DB_RO_USERNAME = user_ro
LOCAL_DB_RO_PASSWORD = password_ro
DOCKER_IMAGE = czbiohub/covidhub-postgres:11.5-alpine

start-local-db:
	@if [ "$(LOCAL_DB_CONTAINER_ID)" == "" ]; then \
		docker create --name $(LOCAL_DB_CONTAINER_NAME) -p 5432:5432 \
		-e POSTGRES_USER=$(LOCAL_DB_ADMIN_USERNAME) \
		-e POSTGRES_PASSWORD=$(LOCAL_DB_ADMIN_PASSWORD) \
		-e POSTGRES_DB=$(LOCAL_DB_NAME) \
		$(DOCKER_IMAGE); \
	fi
	@if [ "$(LOCAL_DB_CONTAINER_RUNNING_ID)" == "" ]; then \
		docker start $(LOCAL_DB_CONTAINER_NAME) && sleep 3; \
	fi

setup-local-db:
	@$(MAKE) start-local-db
	@docker exec $(LOCAL_DB_CONTAINER_NAME) psql -h localhost -d $(LOCAL_DB_NAME) -U $(LOCAL_DB_ADMIN_USERNAME) -c "CREATE USER $(LOCAL_DB_RW_USERNAME) WITH PASSWORD '$(LOCAL_DB_RW_PASSWORD)';"
	@docker exec $(LOCAL_DB_CONTAINER_NAME) psql -h localhost -d $(LOCAL_DB_NAME) -U $(LOCAL_DB_ADMIN_USERNAME) -c "CREATE USER $(LOCAL_DB_RO_USERNAME) WITH PASSWORD '$(LOCAL_DB_RO_PASSWORD)';"
	@docker exec $(LOCAL_DB_CONTAINER_NAME) psql -h localhost -d $(LOCAL_DB_NAME) -U $(LOCAL_DB_ADMIN_USERNAME) -c "GRANT CREATE ON DATABASE $(LOCAL_DB_NAME) TO $(LOCAL_DB_RW_USERNAME);"

init-local-db:
	@$(MAKE) setup-local-db
	covidr-cli db create
	ENV=local alembic stamp head

stop-local-db:
	@if [ "$(LOCAL_DB_CONTAINER_RUNNING_ID)" != "" ]; then \
		docker stop $(LOCAL_DB_CONTAINER_NAME); \
	fi

drop-local-db:
	@$(MAKE) stop-local-db
	@( read -p "Delete local database container? [y/N]: " sure && case "$$sure" in [yY]) true;; *) false;; esac )
	docker rm --force $(LOCAL_DB_CONTAINER_NAME) || true



##############
# STYLE CHECKS
##############

style: lint black isort mypy

lint:
	flake8 --ignore "E203, E231, E501, W503" $(PYTHON_CODE_DIRECTORIES)

black:
	black --check $(PYTHON_CODE_DIRECTORIES)

isort:
	isort --check $(PYTHON_CODE_DIRECTORIES)

mypy:
	mypy --ignore-missing-imports $(PYTHON_CODE_DIRECTORIES)

.PHONY: style lint black isort
