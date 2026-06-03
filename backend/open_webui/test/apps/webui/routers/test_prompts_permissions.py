import asyncio
from types import SimpleNamespace

from open_webui.models.prompts import Prompts
from open_webui.routers.prompts import can_manage_prompt_app


def _user(user_id: str, role: str = 'user'):
    return SimpleNamespace(id=user_id, role=role)


def _prompt(owner_id: str):
    return SimpleNamespace(user_id=owner_id)


def test_prompt_app_management_scope():
    assert can_manage_prompt_app(_user('admin-id', 'admin'), _prompt('owner-id')) is True
    assert can_manage_prompt_app(_user('owner-id'), _prompt('owner-id')) is True
    assert can_manage_prompt_app(_user('other-id'), _prompt('owner-id')) is False
    assert can_manage_prompt_app(_user('owner-id'), None) is False


def test_prompt_app_usage_scope(monkeypatch):
    async def get_user_by_id(user_id, db=None):
        if user_id == 'admin-owner':
            return _user(user_id, 'admin')
        if user_id == 'normal-owner':
            return _user(user_id, 'user')
        return None

    monkeypatch.setattr('open_webui.models.prompts.Users.get_user_by_id', get_user_by_id)

    assert asyncio.run(Prompts.can_user_use_prompt_app(_prompt('any-owner'), 'admin-user', 'admin')) is True
    assert asyncio.run(Prompts.can_user_use_prompt_app(_prompt('owner-id'), 'owner-id', 'user')) is True
    assert asyncio.run(Prompts.can_user_use_prompt_app(_prompt('admin-owner'), 'normal-user', 'user')) is True
    assert asyncio.run(Prompts.can_user_use_prompt_app(_prompt('normal-owner'), 'normal-user', 'user')) is False
