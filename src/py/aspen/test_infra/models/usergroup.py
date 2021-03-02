from aspen.database.models import Group, User


def group_factory(name="groupname", email="groupemail", address="123 Main St") -> Group:
    return Group(name=name, email=email, address=address)


def user_factory(
    group: Group,
    name="test",
    auth0_user_id="test_auth0_id",
    email="test_user@dph.org",
    group_admin=True,
    system_admin=True,
) -> User:
    return User(
        name=name,
        auth0_user_id=auth0_user_id,
        email=email,
        group_admin=group_admin,
        system_admin=system_admin,
        group=group,
    )