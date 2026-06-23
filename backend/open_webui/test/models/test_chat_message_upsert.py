import asyncio
from types import SimpleNamespace

from open_webui.models import chats as chats_module
from open_webui.models.chats import ChatTable


def test_partial_new_message_without_recovery_does_not_corrupt_history(monkeypatch):
    async def run():
        table = ChatTable()
        chat = {'history': {'messages': {}, 'currentId': None}}
        chat_model = SimpleNamespace(user_id='user-1', chat=chat)

        async def fake_get_chat_by_id(chat_id):
            assert chat_id == 'chat-1'
            return chat_model

        async def fake_get_messages_map_by_chat_id(chat_id):
            assert chat_id == 'chat-1'
            return None

        async def fail_upsert_message(**_kwargs):
            raise AssertionError('partial unstructured messages must not be dual-written')

        async def fail_update_chat_by_id(*_args, **_kwargs):
            raise AssertionError('partial unstructured messages must not update embedded history')

        monkeypatch.setattr(table, 'get_chat_by_id', fake_get_chat_by_id)
        monkeypatch.setattr(table, 'update_chat_by_id', fail_update_chat_by_id)
        monkeypatch.setattr(chats_module.ChatMessages, 'get_messages_map_by_chat_id', fake_get_messages_map_by_chat_id)
        monkeypatch.setattr(chats_module.ChatMessages, 'upsert_message', fail_upsert_message)

        result = await table.upsert_message_to_chat_by_id_and_message_id(
            'chat-1',
            'assistant-1',
            {'content': 'partial response'},
        )

        assert result is chat_model
        assert chat['history']['messages'] == {}
        assert chat['history']['currentId'] is None

    asyncio.run(run())


def test_partial_new_message_recovers_structure_from_normalized_store(monkeypatch):
    async def run():
        table = ChatTable()
        chat = {'history': {'messages': {}, 'currentId': None}}
        chat_model = SimpleNamespace(user_id='user-1', chat=chat)
        dual_written = {}
        updated = {}
        recovered_messages = {
            'user-1': {
                'id': 'user-1',
                'role': 'user',
                'parentId': None,
                'childrenIds': ['assistant-1'],
                'content': 'prompt',
                'timestamp': 100,
            },
            'assistant-1': {
                'id': 'assistant-1',
                'role': 'assistant',
                'parentId': 'user-1',
                'childrenIds': [],
                'content': '',
                'done': False,
                'model': 'model-1',
                'timestamp': 101,
            },
        }

        async def fake_get_chat_by_id(_chat_id):
            return chat_model

        async def fake_get_messages_map_by_chat_id(_chat_id):
            return recovered_messages

        async def fake_upsert_message(**kwargs):
            dual_written.update(kwargs)

        async def fake_update_chat_by_id(chat_id, updated_chat):
            updated['chat_id'] = chat_id
            updated['chat'] = updated_chat
            return SimpleNamespace(user_id='user-1', chat=updated_chat)

        monkeypatch.setattr(table, 'get_chat_by_id', fake_get_chat_by_id)
        monkeypatch.setattr(table, 'update_chat_by_id', fake_update_chat_by_id)
        monkeypatch.setattr(chats_module.ChatMessages, 'get_messages_map_by_chat_id', fake_get_messages_map_by_chat_id)
        monkeypatch.setattr(chats_module.ChatMessages, 'upsert_message', fake_upsert_message)

        await table.upsert_message_to_chat_by_id_and_message_id(
            'chat-1',
            'assistant-1',
            {'content': 'completed response'},
        )

        history = updated['chat']['history']
        assert updated['chat_id'] == 'chat-1'
        assert history['currentId'] == 'assistant-1'
        assert history['messages']['user-1']['childrenIds'] == ['assistant-1']
        assert history['messages']['assistant-1'] == {
            **recovered_messages['assistant-1'],
            'content': 'completed response',
        }
        assert dual_written['message_id'] == 'assistant-1'
        assert dual_written['data']['role'] == 'assistant'
        assert dual_written['data']['parentId'] == 'user-1'
        assert dual_written['data']['content'] == 'completed response'

    asyncio.run(run())


def test_existing_message_still_accepts_partial_updates(monkeypatch):
    async def run():
        table = ChatTable()
        chat = {
            'history': {
                'currentId': 'assistant-1',
                'messages': {
                    'assistant-1': {
                        'id': 'assistant-1',
                        'role': 'assistant',
                        'parentId': None,
                        'childrenIds': [],
                        'content': 'old',
                        'timestamp': 100,
                    }
                },
            }
        }
        chat_model = SimpleNamespace(user_id='user-1', chat=chat)
        dual_written = {}
        updated = {}

        async def fake_get_chat_by_id(_chat_id):
            return chat_model

        async def fail_get_messages_map_by_chat_id(_chat_id):
            raise AssertionError('existing messages should not require normalized recovery')

        async def fake_upsert_message(**kwargs):
            dual_written.update(kwargs)

        async def fake_update_chat_by_id(_chat_id, updated_chat):
            updated['chat'] = updated_chat
            return SimpleNamespace(user_id='user-1', chat=updated_chat)

        monkeypatch.setattr(table, 'get_chat_by_id', fake_get_chat_by_id)
        monkeypatch.setattr(table, 'update_chat_by_id', fake_update_chat_by_id)
        monkeypatch.setattr(chats_module.ChatMessages, 'get_messages_map_by_chat_id', fail_get_messages_map_by_chat_id)
        monkeypatch.setattr(chats_module.ChatMessages, 'upsert_message', fake_upsert_message)

        await table.upsert_message_to_chat_by_id_and_message_id(
            'chat-1',
            'assistant-1',
            {'content': 'new'},
        )

        message = updated['chat']['history']['messages']['assistant-1']
        assert message['id'] == 'assistant-1'
        assert message['role'] == 'assistant'
        assert message['content'] == 'new'
        assert dual_written['data'] == message

    asyncio.run(run())


def test_existing_malformed_message_recovers_before_partial_update(monkeypatch):
    async def run():
        table = ChatTable()
        chat = {
            'history': {
                'currentId': 'assistant-1',
                'messages': {
                    'assistant-1': {
                        'content': 'old partial',
                    }
                },
            }
        }
        chat_model = SimpleNamespace(user_id='user-1', chat=chat)
        updated = {}
        recovered_messages = {
            'user-1': {
                'id': 'user-1',
                'role': 'user',
                'parentId': None,
                'childrenIds': ['assistant-1'],
                'content': 'prompt',
                'timestamp': 100,
            },
            'assistant-1': {
                'id': 'assistant-1',
                'role': 'assistant',
                'parentId': 'user-1',
                'childrenIds': [],
                'content': '',
                'done': False,
                'timestamp': 101,
            },
        }

        async def fake_get_chat_by_id(_chat_id):
            return chat_model

        async def fake_get_messages_map_by_chat_id(_chat_id):
            return recovered_messages

        async def fake_upsert_message(**_kwargs):
            return None

        async def fake_update_chat_by_id(_chat_id, updated_chat):
            updated['chat'] = updated_chat
            return SimpleNamespace(user_id='user-1', chat=updated_chat)

        monkeypatch.setattr(table, 'get_chat_by_id', fake_get_chat_by_id)
        monkeypatch.setattr(table, 'update_chat_by_id', fake_update_chat_by_id)
        monkeypatch.setattr(chats_module.ChatMessages, 'get_messages_map_by_chat_id', fake_get_messages_map_by_chat_id)
        monkeypatch.setattr(chats_module.ChatMessages, 'upsert_message', fake_upsert_message)

        await table.upsert_message_to_chat_by_id_and_message_id(
            'chat-1',
            'assistant-1',
            {'content': 'new partial'},
        )

        history = updated['chat']['history']
        assert history['messages']['user-1']['role'] == 'user'
        assert history['messages']['assistant-1'] == {
            **recovered_messages['assistant-1'],
            'content': 'new partial',
        }

    asyncio.run(run())
