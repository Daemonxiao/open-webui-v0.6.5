import logging
from typing import Optional
from urllib.parse import urlparse, urlunparse

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


def _normalize_tokenfun_base_url(url: str) -> str:
    url = (url or '').strip().rstrip('/')
    if not url:
        return ''

    parsed = urlparse(url)
    path = parsed.path.rstrip('/')
    if path.endswith('/v1'):
        path = path[:-3].rstrip('/')

    return urlunparse(
        (
            parsed.scheme,
            parsed.netloc,
            path,
            '',
            '',
            '',
        )
    ).rstrip('/')


def _is_likely_tokenfun_url(url: str) -> bool:
    normalized = _normalize_tokenfun_base_url(url).lower()
    return any(
        marker in normalized
        for marker in (
            'host.containers.internal',
            'tokenfun',
            'new-api',
            ':3001',
        )
    )


def _get_openai_connection_key(request: Request, usage_base_url: str) -> str:
    api_base_urls = list(getattr(request.app.state.config, 'OPENAI_API_BASE_URLS', []) or [])
    api_keys = list(getattr(request.app.state.config, 'OPENAI_API_KEYS', []) or [])
    normalized_usage_base_url = _normalize_tokenfun_base_url(usage_base_url)

    for index, api_base_url in enumerate(api_base_urls):
        if index >= len(api_keys):
            continue
        if _normalize_tokenfun_base_url(api_base_url) == normalized_usage_base_url:
            return (api_keys[index] or '').strip()

    if normalized_usage_base_url:
        return ''

    for index, api_base_url in enumerate(api_base_urls):
        if index >= len(api_keys):
            continue
        if _is_likely_tokenfun_url(api_base_url):
            return (api_keys[index] or '').strip()

    return ''


def _get_usage_base_url(request: Request) -> str:
    configured_base_url = _normalize_tokenfun_base_url(TOKENFUN_USAGE_API_BASE_URL)
    if configured_base_url:
        return configured_base_url

    for api_base_url in getattr(request.app.state.config, 'OPENAI_API_BASE_URLS', []) or []:
        if _is_likely_tokenfun_url(api_base_url):
            return _normalize_tokenfun_base_url(api_base_url)

    return ''


def _get_usage_admin_key(request: Request, usage_base_url: str) -> str:
    if TOKENFUN_USAGE_ADMIN_KEY:
        return TOKENFUN_USAGE_ADMIN_KEY.strip()
    return _get_openai_connection_key(request, usage_base_url)


def _ensure_enabled(request: Request) -> tuple[str, str]:
    if not TOKENFUN_USAGE_ENABLED:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Tokenfun usage is disabled')

    usage_base_url = _get_usage_base_url(request)
    usage_admin_key = _get_usage_admin_key(request, usage_base_url)
    if not usage_base_url or not usage_admin_key:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Tokenfun usage is not configured')

    return usage_base_url, usage_admin_key


async def _proxy_get(request: Request, path: str, params: dict) -> dict:
    usage_base_url, usage_admin_key = _ensure_enabled(request)
    url = f'{usage_base_url}{path}'
    headers = {'Authorization': f'Bearer {usage_admin_key}'}
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
        request,
        '/api/external-usage/summary',
        {
            'source': TOKENFUN_USAGE_SOURCE,
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
    return await _proxy_get(request, '/api/external-usage/chats', params)


@router.get('/chats/{chat_id:path}/logs')
async def get_self_tokenfun_usage_chat_logs(
    request: Request,
    chat_id: str,
    p: Optional[int] = None,
    page_size: Optional[int] = None,
    user=Depends(get_verified_user),
):
    return await _proxy_get(
        request,
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
    return await _proxy_get(request, '/api/external-usage/users', params)


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
    return await _proxy_get(request, '/api/external-usage/chats', params)


@admin_router.get('/chats/{chat_id:path}/logs')
async def get_admin_tokenfun_usage_chat_logs(
    request: Request,
    chat_id: str,
    external_user_id: Optional[str] = None,
    p: Optional[int] = None,
    page_size: Optional[int] = None,
    user=Depends(get_admin_user),
):
    return await _proxy_get(
        request,
        f'/api/external-usage/chats/{chat_id}/logs',
        {
            'source': TOKENFUN_USAGE_SOURCE,
            'external_user_id': external_user_id,
            'p': p,
            'page_size': page_size,
        },
    )
