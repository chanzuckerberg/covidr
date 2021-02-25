import pytest

from aspen.config.testing import TestingConfig
from aspen.main import application


@pytest.fixture(scope="function")
def app(postgres_database):
    application.config.from_object(TestingConfig())
    application.config["DATABASE_CONFIG"].URI = postgres_database.as_uri()
    yield application


@pytest.fixture(scope="function")
def client(app):
    request_ctx = app.test_request_context()
    request_ctx.push()
    yield app.test_client()
    request_ctx.pop()
