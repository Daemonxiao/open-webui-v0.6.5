import logging
from typing import Optional

import aiohttp
from fastapi import APIRouter, Depends, HTTPException, Request, status

from open_webui.env import (
    AIOHTTP_CLIENT_SESSION_SSL,
    AIOHTTP_CLIENT_TIMEOUT,
    TOKENFUN_USAGE_ADMIN_KEY,
    TOKENFUN_USAGE_API_BASE_URL,
    TOKENFUN_USAGE_ENABLED,
    TOKENFUN_USAGE_SOURCE,
)
from open_webui.utils.auth import get_admin_user, get_verified_user

log = logging.getLogger(__name__)

router = APIRouter()
admin_router = APIRouter()


def _ensure_enabled():
    if not TOKENFUN_USAGE_ENABLED:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Tokenfun usage is disabled')
    if not TOKENFUN_USAGE_API_BASE_URL or not TOKENFUN_USAGE_ADMIN_KEY:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Tokenfun usage is not configured')


async def _proxy_get(path: str, params: dict) -> dict:
    _ensure_enabled()
    url = f'{TOKENFUN_USAGE_API_BASE_URL}{path}'
    headers = {'Authorization': f'Bearer {TOKENFUN_USAGE_ADMIN_KEY}'}
    clean_params = {k: v for k, v in params.items() if v not in (None, '')}

    try:
        timeout = aiohttp.ClientTimeout(total=AIOHTTP_CLIENT_TIMEOUT)
        async with aiohttp.ClientSession(timeout=timeout, trust_env=True) as session:
            async with session.get(
                url,
                params=clean_params,
                headers=headers,
                ssl=AIOHTTP_CLIENT_SESSION_SSL,
            ) as response:
                try:
                    data = await response.json()
                except Exception:
                    data = {'detail': await response.text()}

                if response.status >= 400:
                    raise HTTPException(status_code=response.status, detail=data)
                return data
    except HTTPException:
        raise
    except Exception as e:
        log.exception('Tokenfun usage proxy failed')
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(e))


def _common_params(
    request: Request,
    start_timestamp: Optional[int],
    end_timestamp: Optional[int],
    p: Optional[int],
    page_size: Optional[int],
) -> dict:
    return {
        'source': TOKENFUN_USAGE_SOURCE,
        'start_timestamp': start_timestamp,
        'end_timestamp': end_timestamp,
        'p': p or request.query_params.get('p'),
        'page_size': page_size or request.query_params.get('page_size'),
    }


@router.get('/summary')
async def get_self_tokenfun_usage_summary(
    request: Request,
    start_timestamp: Optional[int] = None,
    end_timestamp: Optional[int] = None,
    user=Depends(get_verified_user),
):
    return await _proxy_get(
        '/api/log/stat',
        {
            'external_source': TOKENFUN_USAGE_SOURCE,
            'external_user_id': user.id,
            'start_timestamp': start_timestamp,
            'end_timestamp': end_timestamp,
        },
    )


@router.get('/chats')
async def get_self_tokenfun_usage_chats(
    request: Request,
    start_timestamp: Optional[int] = None,
    end_timestamp: Optional[int] = None,
    p: Optional[int] = None,
    page_size: Optional[int] = None,
    user=Depends(get_verified_user),
):
    params = _common_params(request, start_timestamp, end_timestamp, p, page_size)
    params['external_user_id'] = user.id
    return await _proxy_get('/api/external-usage/chats', params)


@router.get('/chats/{chat_id:path}/logs')
async def get_self_tokenfun_usage_chat_logs(
    chat_id: str,
    p: Optional[int] = None,
    page_size: Optional[int] = None,
    user=Depends(get_verified_user),
):
    return await _proxy_get(
        f'/api/external-usage/chats/{chat_id}/logs',
        {
            'source': TOKENFUN_USAGE_SOURCE,
            'external_user_id': user.id,
            'p': p,
            'page_size': page_size,
        },
    )


@admin_router.get('/users')
async def get_admin_tokenfun_usage_users(
    request: Request,
    start_timestamp: Optional[int] = None,
    end_timestamp: Optional[int] = None,
    external_user_id: Optional[str] = None,
    external_username: Optional[str] = None,
    p: Optional[int] = None,
    page_size: Optional[int] = None,
    user=Depends(get_admin_user),
):
    params = _common_params(request, start_timestamp, end_timestamp, p, page_size)
    params.update(
        {
            'external_user_id': external_user_id,
            'external_username': external_username,
        }
    )
    return await _proxy_get('/api/external-usage/users', params)


@admin_router.get('/users/{user_id}/chats')
async def get_admin_tokenfun_usage_user_chats(
    request: Request,
    user_id: str,
    start_timestamp: Optional[int] = None,
    end_timestamp: Optional[int] = None,
    p: Optional[int] = None,
    page_size: Optional[int] = None,
    user=Depends(get_admin_user),
):
    params = _common_params(request, start_timestamp, end_timestamp, p, page_size)
    params['external_user_id'] = user_id
    return await _proxy_get('/api/external-usage/chats', params)


@admin_router.get('/chats/{chat_id:path}/logs')
async def get_admin_tokenfun_usage_chat_logs(
    chat_id: str,
    external_user_id: Optional[str] = None,
    p: Optional[int] = None,
    page_size: Optional[int] = None,
    user=Depends(get_admin_user),
):
    return await _proxy_get(
        f'/api/external-usage/chats/{chat_id}/logs',
        {
            'source': TOKENFUN_USAGE_SOURCE,
            'external_user_id': external_user_id,
            'p': p,
            'page_size': page_size,
        },
    )
