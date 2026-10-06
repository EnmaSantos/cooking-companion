import asyncio
import os
import unittest
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException

from main import _cache, _request, details, search


class ProxyTests(unittest.TestCase):
    def setUp(self):
        _cache.clear()

    def test_missing_key_does_not_call_upstream(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(HTTPException) as error:
                asyncio.run(_request("/food/1", {}))
            self.assertEqual(error.exception.status_code, 503)

    def test_search_validation(self):
        # FastAPI validates bounds; the route also rejects whitespace-only terms.
        with self.assertRaises(HTTPException) as error:
            asyncio.run(search("  "))
        self.assertEqual(error.exception.status_code, 422)
        with self.assertRaises(HTTPException):
            asyncio.run(details(-1))

    def test_caches_success_without_exposing_key(self):
        class Response:
            status_code = 200
            def json(self):
                return {"fdcId": 7, "description": "Flour"}

        mock_client = AsyncMock()
        mock_client.get.return_value = Response()
        mock_client.__aenter__.return_value = mock_client
        with patch.dict(os.environ, {"FOODDATA_API_KEY": "secret"}):
            with patch("main.httpx.AsyncClient", return_value=mock_client):
                first = asyncio.run(_request("/food/7", {}))
                second = asyncio.run(_request("/food/7", {}))
        self.assertEqual(first, second)
        self.assertNotIn("secret", str(first))
        self.assertEqual(mock_client.get.await_count, 1)


if __name__ == "__main__":
    unittest.main()
