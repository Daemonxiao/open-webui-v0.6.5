import logging
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode, urlparse

import jwt
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, Response, status
from fastapi.responses import RedirectResponse
from sqlalchemy.ext.asyncio import AsyncSession

from open_webui.config import (
    NOVEL_EXPERT_BASE_URL,
    NOVEL_EXPERT_SSO_SECRET,
    NOVEL_EXPERT_SSO_TOKEN_TTL_SECONDS,
    WEBUI_URL,
)
from open_webui.constants import ERROR_MESSAGES
from open_webui.internal.db import get_async_session
from open_webui.utils.access_control import get_permissions, has_permission
from open_webui.utils.auth import get_current_user, get_http_authorization_cred, get_verified_user

log = logging.getLogger(__name__)

router = APIRouter()

_DEFAULT_NEXT = '/generate'
_ISSUER = 'open-webui'
_AUDIENCE = 'novel-expert'


def _safe_next(next_path: str | None) -> str:
    if not next_path:
        return _DEFAULT_NEXT

    parsed = urlparse(next_path)
    if parsed.scheme or parsed.netloc or not next_path.startswith('/') or next_path.startswith('//'):
        return _DEFAULT_NEXT

    return next_path


def _webui_base_url(request: Request) -> str:
    configured_url = str(WEBUI_URL.env_value or WEBUI_URL.value or '').rstrip('/')
    if configured_url:
        return configured_url

    return f'{request.url.scheme}://{request.url.netloc}'


def _login_redirect_response(request: Request, next_path: str | None) -> RedirectResponse:
    launch_path = f'{request.url.path}?{urlencode({"next": _safe_next(next_path)})}'
    query = urlencode({'redirect': launch_path})
    return RedirectResponse(
        url=f'{_webui_base_url(request)}/auth?{query}',
        status_code=status.HTTP_302_FOUND,
    )


async def _get_launch_user(request: Request, response: Response, background_tasks: BackgroundTasks):
    auth_token = get_http_authorization_cred(request.headers.get('Authorization'))
    current_user = await get_current_user(request, response, background_tasks, auth_token)
    return get_verified_user(current_user)


@router.get('/launch')
async def launch_novel_expert(
    request: Request,
    response: Response,
    background_tasks: BackgroundTasks,
    next: str | None = None,
    db: AsyncSession = Depends(get_async_session),
):
    try:
        user = await _get_launch_user(request, response, background_tasks)
    except HTTPException as exc:
        if exc.status_code == status.HTTP_401_UNAUTHORIZED:
            return _login_redirect_response(request, next)
        raise

    has_access = await has_permission(
        user.id,
        'features.novel_expert',
        request.app.state.config.USER_PERMISSIONS,
        db=db,
    )
    has_manage = await has_permission(
        user.id,
        'features.novel_expert_manage',
        request.app.state.config.USER_PERMISSIONS,
        db=db,
    )
    has_super_admin = await has_permission(
        user.id,
        'features.novel_expert_super_admin',
        request.app.state.config.USER_PERMISSIONS,
        db=db,
    )
    if not (has_access or has_manage or has_super_admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=ERROR_MESSAGES.ACCESS_PROHIBITED,
        )

    base_url = str(NOVEL_EXPERT_BASE_URL.env_value or NOVEL_EXPERT_BASE_URL.value or '').rstrip('/')
    if not base_url or not NOVEL_EXPERT_SSO_SECRET:
        log.error('novel_expert_launch_not_configured')
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Novel Expert SSO is not configured',
        )

    permissions = await get_permissions(user.id, request.app.state.config.USER_PERMISSIONS, db=db)
    feature_permissions = (permissions.get('features') or {}) if isinstance(permissions, dict) else {}

    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(seconds=NOVEL_EXPERT_SSO_TOKEN_TTL_SECONDS)
    payload = {
        'iss': _ISSUER,
        'aud': _AUDIENCE,
        'sub': user.id,
        'email': user.email,
        'name': user.name,
        'role': user.role,
        'permissions': {
            'features': {
                'novel_expert': bool(feature_permissions.get('novel_expert')),
                'novel_expert_manage': bool(feature_permissions.get('novel_expert_manage')),
                'novel_expert_super_admin': bool(feature_permissions.get('novel_expert_super_admin')),
            }
        },
        'iat': now,
        'exp': expires_at,
    }
    sso_token = jwt.encode(payload, NOVEL_EXPERT_SSO_SECRET, algorithm='HS256')

    target_next = _safe_next(next)
    query = urlencode({'sso_token': sso_token, 'next': target_next})
    return RedirectResponse(
        url=f'{base_url}/auth/openwebui/callback?{query}',
        status_code=status.HTTP_302_FOUND,
    )
