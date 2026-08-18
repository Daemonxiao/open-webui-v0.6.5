from open_webui.utils.middleware import (
    _has_clean_chat_completion_finish,
    _should_ignore_late_stream_error,
)


def _emitted_errors(events):
    has_clean_finish = False
    errors = []

    for event in events:
        choices = event.get('choices', [])
        has_clean_finish = has_clean_finish or _has_clean_chat_completion_finish(choices)

        error = event.get('error')
        if error and not _should_ignore_late_stream_error(error, has_clean_finish):
            errors.append(error)

    return errors


def test_error_after_stop_finish_is_ignored():
    events = [
        {'choices': [{'delta': {'content': 'complete answer'}}]},
        {'choices': [{'delta': {}, 'finish_reason': 'stop'}]},
        {'error': {'message': 'late upstream error'}},
    ]

    assert _emitted_errors(events) == []


def test_error_after_partial_content_is_preserved():
    error = {'message': 'stream interrupted'}
    events = [
        {'choices': [{'delta': {'content': 'partial answer'}}]},
        {'error': error},
    ]

    assert _emitted_errors(events) == [error]


def test_error_before_content_is_preserved():
    error = {'message': 'upstream unavailable'}

    assert _emitted_errors([{'error': error}]) == [error]


def test_non_stop_finish_reason_does_not_hide_error():
    error = {'message': 'output truncated'}
    events = [
        {'choices': [{'delta': {}, 'finish_reason': 'length'}]},
        {'error': error},
    ]

    assert _emitted_errors(events) == [error]
