from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi import HTTPException
from starlette.requests import Request

from open_webui.routers import novel_expert


def _request(token: str | None = None) -> Request:
    headers = []
    if token is not None:
        headers.append((b'authorization', f'Bearer {token}'.encode('utf-8')))
    return Request({'type': 'http', 'headers': headers})


def _token(payload_overrides: dict | None = None, *, secret: str = 'test-secret') -> str:
    now = datetime.now(timezone.utc)
    payload = {
        'iss': 'novel-expert',
        'aud': 'open-webui',
        'scope': 'novel_expert_user_resolve',
        'iat': now,
        'exp': now + timedelta(seconds=60),
    }
    if payload_overrides:
        payload.update(payload_overrides)
    return jwt.encode(payload, secret, algorithm='HS256')


def _token_without_exp() -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode(
        {
            'iss': 'novel-expert',
            'aud': 'open-webui',
            'scope': 'novel_expert_user_resolve',
            'iat': now,
        },
        'test-secret',
        algorithm='HS256',
    )


def test_dedupe_user_ids_strips_empty_values_and_preserves_order():
    assert novel_expert._dedupe_user_ids([' user-1 ', '', 'user-2', 'user-1']) == [
        'user-1',
        'user-2',
    ]


def test_verify_storyos_service_token_accepts_valid_token(monkeypatch):
    monkeypatch.setattr(novel_expert, 'NOVEL_EXPERT_SSO_SECRET', 'test-secret')

    novel_expert._verify_storyos_service_token(_request(_token()))


@pytest.mark.parametrize(
    'token',
    [
        None,
        _token({'aud': 'other'}),
        _token({'iss': 'other'}),
        _token({'scope': 'other'}),
        _token(secret='wrong-secret'),
        _token_without_exp(),
    ],
)
def test_verify_storyos_service_token_rejects_invalid_token(monkeypatch, token):
    monkeypatch.setattr(novel_expert, 'NOVEL_EXPERT_SSO_SECRET', 'test-secret')

    with pytest.raises(HTTPException) as exc_info:
        novel_expert._verify_storyos_service_token(_request(token))

    assert exc_info.value.status_code == 401
