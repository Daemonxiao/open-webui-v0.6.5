import re
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status

from open_webui.models.prompts import (
    PromptForm,
    PromptUserResponse,
    PromptAccessResponse,
    PromptAccessListResponse,
    PromptAppSummaryListResponse,
    PromptModel,
    Prompts,
)
from open_webui.models.access_grants import AccessGrants
from open_webui.models.prompt_history import (
    PromptHistories,
    PromptHistoryModel,
    PromptHistoryResponse,
)
from open_webui.constants import ERROR_MESSAGES
from open_webui.utils.auth import get_admin_user, get_verified_user
from open_webui.internal.db import get_async_session
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel


class PromptVersionUpdateForm(BaseModel):
    version_id: str


class PromptMetadataForm(BaseModel):
    name: str
    command: str
    tags: Optional[list[str]] = None


router = APIRouter()

PAGE_ITEM_COUNT = 30


def can_manage_prompt_app(user, prompt: PromptModel | None = None) -> bool:
    return user.role == 'admin'


def ensure_can_manage_prompt_app(user, prompt: PromptModel | None = None):
    if not can_manage_prompt_app(user, prompt):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=ERROR_MESSAGES.ACCESS_PROHIBITED,
        )


async def generate_unique_prompt_command(command: str, db: AsyncSession) -> str:
    base_command = re.sub(r'[^a-zA-Z0-9-_]+', '-', (command or '').strip().strip('/')).strip('-')
    if not base_command:
        base_command = 'prompt-app'

    candidate = base_command
    suffix = 2
    while await Prompts.get_prompt_by_command(candidate, db=db):
        candidate = f'{base_command}-{suffix}'
        suffix += 1

    return candidate


############################
# GetPrompts
# The hardest part is knowing what to ask. Let the right
# question already be here when it is needed.
############################


@router.get('/', response_model=list[PromptModel])
async def get_prompts(user=Depends(get_admin_user), db: AsyncSession = Depends(get_async_session)):
    return await Prompts.get_prompts(db=db)


@router.get('/tags', response_model=list[str])
async def get_prompt_tags(user=Depends(get_admin_user), db: AsyncSession = Depends(get_async_session)):
    return await Prompts.get_tags(db=db)


@router.get('/apps', response_model=PromptAppSummaryListResponse)
async def get_prompt_apps(user=Depends(get_verified_user), db: AsyncSession = Depends(get_async_session)):
    return await Prompts.get_prompt_app_summaries(db=db)


@router.get('/admin/list', response_model=PromptAccessListResponse)
@router.get('/list', response_model=PromptAccessListResponse)
async def get_prompt_list(
    query: Optional[str] = None,
    view_option: Optional[str] = None,
    tag: Optional[str] = None,
    order_by: Optional[str] = None,
    direction: Optional[str] = None,
    page: Optional[int] = 1,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    limit = PAGE_ITEM_COUNT

    page = max(1, page)
    skip = (page - 1) * limit

    filter = {}
    if query:
        filter['query'] = query
    if view_option:
        filter['view_option'] = view_option
    if tag:
        filter['tag'] = tag
    if order_by:
        filter['order_by'] = order_by
    if direction:
        filter['direction'] = direction

    ensure_can_manage_prompt_app(user)

    result = await Prompts.search_prompts(
        user.id,
        filter=filter,
        skip=skip,
        limit=limit,
        enforce_access_control=False,
        db=db,
    )

    return PromptAccessListResponse(
        items=[
            PromptAccessResponse(
                **prompt.model_dump(),
                write_access=True,
            )
            for prompt in result.items
        ],
        total=result.total,
    )


############################
# CreateNewPrompt
############################


@router.post('/create', response_model=Optional[PromptModel])
async def create_new_prompt(
    form_data: PromptForm,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    if not form_data.name.strip() or not (form_data.description or '').strip() or not form_data.content.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ERROR_MESSAGES.DEFAULT('Name, description, and prompt are required'),
        )

    form_data.command = await generate_unique_prompt_command(form_data.command or form_data.name, db=db)
    prompt = await Prompts.insert_new_prompt(user.id, form_data, db=db)

    if prompt:
        return prompt
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=ERROR_MESSAGES.DEFAULT(),
    )


############################
# GetPromptByCommand
############################


@router.get('/command/{command}', response_model=Optional[PromptAccessResponse])
async def get_prompt_by_command(
    command: str, user=Depends(get_admin_user), db: AsyncSession = Depends(get_async_session)
):
    prompt = await Prompts.get_prompt_by_command(command, db=db)

    if prompt:
        return PromptAccessResponse(**prompt.model_dump(), write_access=True)

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail=ERROR_MESSAGES.NOT_FOUND,
    )


############################
# GetPromptById
############################


@router.get('/id/{prompt_id}', response_model=Optional[PromptAccessResponse])
async def get_prompt_by_id(
    prompt_id: str, user=Depends(get_admin_user), db: AsyncSession = Depends(get_async_session)
):
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if prompt:
        return PromptAccessResponse(**prompt.model_dump(), write_access=True)

    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail=ERROR_MESSAGES.NOT_FOUND,
    )


############################
# UpdatePromptById
############################


@router.post('/id/{prompt_id}/update', response_model=Optional[PromptModel])
async def update_prompt_by_id(
    prompt_id: str,
    form_data: PromptForm,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    if not form_data.name.strip() or not (form_data.description or '').strip() or not form_data.content.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ERROR_MESSAGES.DEFAULT('Name, description, and prompt are required'),
        )

    # Check for command collision if command is being changed
    if form_data.command != prompt.command:
        existing_prompt = await Prompts.get_prompt_by_command(form_data.command, db=db)
        if existing_prompt and existing_prompt.id != prompt.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=ERROR_MESSAGES.COMMAND_TAKEN,
            )

    # Use the ID from the found prompt
    updated_prompt = await Prompts.update_prompt_by_id(prompt.id, form_data, user.id, db=db)
    if updated_prompt:
        return updated_prompt
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ERROR_MESSAGES.DEFAULT(),
        )


############################
# UpdatePromptMetadata
############################


@router.post('/id/{prompt_id}/update/meta', response_model=Optional[PromptModel])
async def update_prompt_metadata(
    prompt_id: str,
    form_data: PromptMetadataForm,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    """Update prompt name and command only (no history created)."""
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    # Check for command collision if command is being changed
    if form_data.command != prompt.command:
        existing_prompt = await Prompts.get_prompt_by_command(form_data.command, db=db)
        if existing_prompt and existing_prompt.id != prompt.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=ERROR_MESSAGES.COMMAND_TAKEN,
            )

    updated_prompt = await Prompts.update_prompt_metadata(
        prompt.id, form_data.name, form_data.command, form_data.tags, db=db
    )
    if updated_prompt:
        return updated_prompt
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ERROR_MESSAGES.DEFAULT(),
        )


@router.post('/id/{prompt_id}/update/version', response_model=Optional[PromptModel])
async def set_prompt_version(
    prompt_id: str,
    form_data: PromptVersionUpdateForm,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)
    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    updated_prompt = await Prompts.update_prompt_version(prompt.id, form_data.version_id, db=db)
    if updated_prompt:
        return updated_prompt
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=ERROR_MESSAGES.DEFAULT(),
        )


############################
# UpdatePromptAccessById
############################


class PromptAccessGrantsForm(BaseModel):
    access_grants: list[dict]


@router.post('/id/{prompt_id}/access/update', response_model=Optional[PromptModel])
async def update_prompt_access_by_id(
    prompt_id: str,
    form_data: PromptAccessGrantsForm,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)
    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    await AccessGrants.set_access_grants('prompt', prompt_id, form_data.access_grants, db=db)

    return await Prompts.get_prompt_by_id(prompt_id, db=db)


############################
# TogglePromptActiveById
############################


@router.post('/id/{prompt_id}/toggle', response_model=Optional[PromptModel])
async def toggle_prompt_active(
    prompt_id: str, user=Depends(get_admin_user), db: AsyncSession = Depends(get_async_session)
):
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    result = await Prompts.toggle_prompt_active(prompt.id, db=db)
    if result:
        return result
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=ERROR_MESSAGES.DEFAULT(),
    )


############################
# DeletePromptById
############################


@router.delete('/id/{prompt_id}/delete', response_model=bool)
async def delete_prompt_by_id(
    prompt_id: str, user=Depends(get_admin_user), db: AsyncSession = Depends(get_async_session)
):
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    result = await Prompts.delete_prompt_by_id(prompt.id, db=db)
    return result


############################
# Prompt History Endpoints
############################


@router.get('/id/{prompt_id}/history', response_model=list[PromptHistoryResponse])
async def get_prompt_history(
    prompt_id: str,
    page: int = 0,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    """Get version history for a prompt."""
    PAGE_SIZE = 20

    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    history = await PromptHistories.get_history_by_prompt_id(prompt.id, limit=PAGE_SIZE, offset=page * PAGE_SIZE, db=db)
    return history


@router.get('/id/{prompt_id}/history/{history_id}', response_model=PromptHistoryModel)
async def get_prompt_history_entry(
    prompt_id: str,
    history_id: str,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    """Get a specific version from history."""
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    history_entry = await PromptHistories.get_history_entry_by_id(history_id, db=db)
    if not history_entry or history_entry.prompt_id != prompt.id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    return history_entry


@router.delete('/id/{prompt_id}/history/{history_id}', response_model=bool)
async def delete_prompt_history_entry(
    prompt_id: str,
    history_id: str,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    """Delete a history entry. Cannot delete the active production version."""
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    # Cannot delete active production version
    if prompt.version_id == history_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Cannot delete the active production version',
        )

    success = await PromptHistories.delete_history_entry(history_id, db=db)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    return success


@router.get('/id/{prompt_id}/history/diff')
async def get_prompt_diff(
    prompt_id: str,
    from_id: str,
    to_id: str,
    user=Depends(get_admin_user),
    db: AsyncSession = Depends(get_async_session),
):
    """Get diff between two versions."""
    prompt = await Prompts.get_prompt_by_id(prompt_id, db=db)

    if not prompt:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    ensure_can_manage_prompt_app(user, prompt)

    diff = await PromptHistories.compute_diff(from_id, to_id, db=db)
    if not diff:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=ERROR_MESSAGES.NOT_FOUND,
        )

    return diff
