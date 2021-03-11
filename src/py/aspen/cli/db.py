import json
from pathlib import Path

import boto3
import click
from IPython.terminal.embed import InteractiveShellEmbed

from aspen import covidhub_import
from aspen.cli.toplevel import cli
from aspen.config.config import RemoteDatabaseConfig
from aspen.config.development import DevelopmentConfig
from aspen.database.connection import enable_profiling, get_db_uri, init_db
from aspen.database.models import *  # noqa: F401, F403
from aspen.database.schema import create_tables_and_schema


@cli.group()
@click.pass_context
def db(ctx):
    # TODO: support multiple runtime environments.
    ctx.obj["ENGINE"] = init_db(get_db_uri(DevelopmentConfig()))


@db.command("set-passwords-from-secret")
@click.pass_context
def set_passwords_from_secret(ctx):
    this_file = Path(__file__)
    root = this_file.parent.parent.parent.parent.parent
    default_db_credentials_file = root / "terraform" / "default-db-credentials.json"
    with default_db_credentials_file.open("r") as fh:
        default_db_credentials = json.load(fh)
    admin_username = default_db_credentials["admin_username"]
    admin_password = default_db_credentials["admin_password"]

    secrets = RemoteDatabaseConfig().AWS_SECRET

    # find the db instance
    rds = boto3.client("rds")
    response = rds.describe_db_instances(DBInstanceIdentifier="aspen-db")
    instance_info = response["DBInstances"][0]
    instance_address = instance_info["Endpoint"]["Address"]
    instance_port = instance_info["Endpoint"]["Port"]
    db_interface = init_db(
        f"postgresql://{admin_username}:{admin_password}@{instance_address}:{instance_port}/aspen_db"
    )

    for username, password in (
        (admin_username, secrets["DB"]["admin_password"]),
        (default_db_credentials["rw_username"], secrets["DB"]["rw_password"]),
        (default_db_credentials["ro_username"], secrets["DB"]["ro_password"]),
    ):
        db_interface.engine.execute(f"""ALTER USER {username} PASSWORD '{password}'""")


@db.command("create")
@click.pass_context
def create_db(ctx):
    create_tables_and_schema(ctx.obj["ENGINE"])


@db.command("interact")
@click.option("--profile/--no-profile", default=False)
@click.pass_context
def interact(ctx, profile):
    # these are injected into the IPython scope, but they appear to be unused.
    engine = ctx.obj["ENGINE"]  # noqa: F841

    if profile:
        enable_profiling()

    shell = InteractiveShellEmbed()
    shell()


@db.command("import-covidhub-project")
@click.option("--covidhub-db-secret", default="cliahub/cliahub_test_db")
@click.option("--rr-project-id", type=str, required=True)
@click.option("--s3-src-prefix", type=str, required=True)
@click.option("--s3-src-profile", type=str, required=True)
@click.option("--s3-dst-prefix", type=str, required=True)
@click.option("--s3-dst-profile", type=str, required=True)
@click.pass_context
def import_covidhub_project(
    ctx,
    covidhub_db_secret,
    rr_project_id,
    s3_src_prefix,
    s3_src_profile,
    s3_dst_prefix,
    s3_dst_profile,
):
    # these are injected into the IPython scope, but they appear to be unused.
    engine = ctx.obj["ENGINE"]

    covidhub_import.import_project(
        engine,
        covidhub_db_secret,
        rr_project_id,
        s3_src_prefix,
        s3_src_profile,
        s3_dst_prefix,
        s3_dst_profile,
    )
