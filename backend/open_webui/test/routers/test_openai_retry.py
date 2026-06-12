import asyncio
import json

from fastapi import HTTPException
from open_webui.routers.openai import (
    _CHAT_COMPLETION_MAX_RETRIES,
    _inspect_sse_probe,
    _is_retryable_upstream_status,
    _retry_backoff,
    _retrying_chat_stream,
)


class FakeContent:
    def __init__(self, chunks=None, error=None):
        self.chunks = chunks or []
        self.error = error

    def __aiter__(self):
        return self._iterate()

    async def _iterate(self):
        for chunk in self.chunks:
            yield chunk
        if self.error:
            raise self.error


class FakeResponse:
    def __init__(self, chunks=None, error=None, status=200, content_type='text/event-stream'):
        self.content = FakeContent(chunks, error)
        self.status = status
        self.headers = {'Content-Type': content_type}
        self.closed = False

    def close(self):
        self.closed = True

    async def text(self):
        return json.dumps({'error': {'message': 'upstream failed'}})


def test_stream_retries_before_first_usable_data_and_closes_failed_response(monkeypatch):
    async def run():
        first = FakeResponse(error=ConnectionError('disconnected'))
        second = FakeResponse(chunks=[b'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'])
        responses = iter([second])
        sleeps = []

        async def request_factory():
            return next(responses)

        async def fake_sleep(retry_count):
            sleeps.append(retry_count)

        monkeypatch.setattr('open_webui.routers.openai._retry_backoff', fake_sleep)
        chunks = [chunk async for chunk in _retrying_chat_stream(first, request_factory)]

        assert first.closed
        assert second.closed
        assert sleeps == [1]
        assert '"description": "Retrying upstream model (retry 1/3)"' in chunks[0]
        assert chunks[1] == b'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'

    asyncio.run(run())


def test_stream_does_not_retry_after_first_usable_data():
    async def run():
        response = FakeResponse(
            chunks=[b'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n'],
            error=ConnectionError('late failure'),
        )
        request_calls = 0

        async def request_factory():
            nonlocal request_calls
            request_calls += 1
            return FakeResponse()

        try:
            async for _ in _retrying_chat_stream(response, request_factory):
                pass
        except HTTPException as exc:
            assert exc.status_code == 502
            assert exc.detail['message'] == 'late failure'
            assert exc.detail['retry_count'] == 0
        else:
            raise AssertionError('late stream failure was not propagated')

        assert request_calls == 0
        assert response.closed

    asyncio.run(run())


def test_all_upstream_http_errors_are_retryable():
    for status_code in (400, 401, 403, 404, 408, 429, 500, 503):
        assert _is_retryable_upstream_status(status_code)

    assert not _is_retryable_upstream_status(399)


def test_stream_cancellation_is_not_retried():
    async def run():
        response = FakeResponse(error=asyncio.CancelledError())
        request_calls = 0

        async def request_factory():
            nonlocal request_calls
            request_calls += 1
            return FakeResponse()

        try:
            async for _ in _retrying_chat_stream(response, request_factory):
                pass
        except asyncio.CancelledError:
            pass
        else:
            raise AssertionError('cancellation was not propagated')

        assert request_calls == 0
        assert response.closed

    asyncio.run(run())


def test_stream_final_error_preserves_detail_and_retry_count(monkeypatch):
    async def run():
        responses = [FakeResponse(error=ConnectionError(f'failure {index}')) for index in range(4)]
        response_iter = iter(responses[1:])

        async def request_factory():
            return next(response_iter)

        async def fake_sleep(_retry_count):
            return None

        monkeypatch.setattr('open_webui.routers.openai._retry_backoff', fake_sleep)
        chunks = [chunk async for chunk in _retrying_chat_stream(responses[0], request_factory)]
        final_event = json.loads(chunks[-1].removeprefix('data: ').strip())

        assert final_event['error']['retry_count'] == _CHAT_COMPLETION_MAX_RETRIES
        assert final_event['error']['detail'] == {
            'type': 'ConnectionError',
            'message': 'failure 3',
        }
        assert final_event['error']['status_code'] == 502
        assert all(response.closed for response in responses)

    asyncio.run(run())


def test_sse_probe_treats_provider_error_as_retryable_preflight_failure():
    state, detail = _inspect_sse_probe(b'data: {"error":{"message":"overloaded"}}\n\n')

    assert state == 'error'
    assert detail == {'message': 'overloaded'}


def test_sse_probe_waits_for_complete_event_and_visible_content():
    partial = b'data: {"choices":[{"delta":{"content":"hel'
    assert _inspect_sse_probe(partial) == ('pending', None)

    role_only = b'data: {"choices":[{"delta":{"role":"assistant","content":""}}]}\n\n'
    assert _inspect_sse_probe(role_only) == ('pending', None)

    visible = role_only + b'data: {"choices":[{"delta":{"content":"hello"}}]}\n\n'
    assert _inspect_sse_probe(visible) == ('usable', None)


def test_retry_backoff_uses_one_two_four_seconds_plus_jitter(monkeypatch):
    delays = []

    async def fake_sleep(delay):
        delays.append(delay)

    monkeypatch.setattr('open_webui.routers.openai.random.uniform', lambda _start, _end: 0.2)
    monkeypatch.setattr('open_webui.routers.openai.asyncio.sleep', fake_sleep)

    async def run():
        for retry_count in range(1, 4):
            await _retry_backoff(retry_count)

    asyncio.run(run())
    assert delays == [1.2, 2.2, 4.2]


def test_stream_closes_retryable_http_error_before_next_attempt(monkeypatch):
    async def run():
        first = FakeResponse(error=ConnectionError('disconnected'))
        overloaded = FakeResponse(status=503)
        success = FakeResponse(chunks=[b'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'])
        response_iter = iter([overloaded, success])

        async def request_factory():
            return next(response_iter)

        async def fake_sleep(_retry_count):
            return None

        monkeypatch.setattr('open_webui.routers.openai._retry_backoff', fake_sleep)
        chunks = [chunk async for chunk in _retrying_chat_stream(first, request_factory)]

        assert overloaded.closed
        assert sum('"type": "status"' in chunk for chunk in chunks if isinstance(chunk, str)) == 2
        assert chunks[-1] == b'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n'

    asyncio.run(run())
