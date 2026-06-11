from unittest.mock import Mock, patch

from langchain_community.document_loaders import Docx2txtLoader, TextLoader

from open_webui.retrieval.loaders.main import REQUESTS_VERIFY, Loader, TikaLoader


def test_tika_loader_reads_json_response(tmp_path):
    file_path = tmp_path / 'legacy.doc'
    file_path.write_bytes(b'legacy word content')
    response = Mock(
        ok=True,
        json=Mock(
            return_value={
                'X-TIKA:content': 'Extracted document text\n',
                'Content-Type': 'application/msword',
            }
        ),
    )

    with patch('open_webui.retrieval.loaders.main.requests.put', return_value=response) as put:
        docs = TikaLoader(
            url='http://tika:9998',
            file_path=str(file_path),
            mime_type='application/msword',
        ).load()

    assert docs[0].page_content == 'Extracted document text'
    put.assert_called_once_with(
        'http://tika:9998/tika/text',
        data=b'legacy word content',
        headers={
            'Accept': 'application/json',
            'Content-Type': 'application/msword',
        },
        verify=REQUESTS_VERIFY,
    )
    assert docs[0].metadata == {'Content-Type': 'application/msword'}


def test_tika_engine_keeps_text_and_docx_on_local_loaders(tmp_path):
    loader = Loader(engine='tika', TIKA_SERVER_URL='http://tika:9998')
    doc_path = tmp_path / 'legacy.doc'
    docx_path = tmp_path / 'current.docx'
    renamed_docx_path = tmp_path / 'current.bin'
    text_path = tmp_path / 'notes.txt'
    doc_path.touch()
    docx_path.touch()
    renamed_docx_path.touch()
    text_path.touch()

    doc_loader = loader._get_loader('legacy.doc', 'application/msword', str(doc_path))
    pdf_loader = loader._get_loader('document.pdf', 'application/pdf', str(tmp_path / 'document.pdf'))
    docx_loader = loader._get_loader(
        'current.docx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        str(docx_path),
    )
    mime_docx_loader = loader._get_loader(
        'current.bin',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        str(renamed_docx_path),
    )
    text_loader = loader._get_loader('notes.txt', 'text/plain', str(text_path))

    assert isinstance(doc_loader, TikaLoader)
    assert isinstance(pdf_loader, TikaLoader)
    assert isinstance(docx_loader, Docx2txtLoader)
    assert isinstance(mime_docx_loader, Docx2txtLoader)
    assert isinstance(text_loader, TextLoader)
