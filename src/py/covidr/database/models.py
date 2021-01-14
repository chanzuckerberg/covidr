# the main models in the database
from sqlalchemy import MetaData
from sqlalchemy.ext.declarative import declarative_base

from . import modelmixins as mx

meta = MetaData(
    schema="covidr",
    naming_convention={
        "ix": "ix_%(column_0_label)s",
        "uq": "uq_%(table_name)s_%(column_0_name)s",
        "ck": "ck_%(table_name)s_%(constraint_name)s",
        "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
        "pk": "pk_%(table_name)s",
    },
)
base = declarative_base(cls=mx.BaseMixin, metadata=meta)
