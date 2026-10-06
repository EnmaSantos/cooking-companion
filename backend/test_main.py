import asyncio
import os
import unittest
from unittest.mock import AsyncMock, patch

from fastapi import HTTPException
from fastapi.testclient import TestClient

from main import _cache, _meal_request, _request, app, details, recipe_filter, recipe_details, search


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

    def test_meal_key_is_required_and_invalid_ids_are_rejected(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(HTTPException) as error:
                asyncio.run(_meal_request("search", {"s": "pasta"}))
            self.assertEqual(error.exception.status_code, 503)
        with self.assertRaises(HTTPException) as error:
            asyncio.run(recipe_details("../key"))
        self.assertEqual(error.exception.status_code, 422)
        with self.assertRaises(HTTPException) as error:
            asyncio.run(recipe_filter(category="Dessert", ingredient="Chicken"))
        self.assertEqual(error.exception.status_code, 422)

    def test_meal_proxy_uses_v2_and_caches_without_exposing_key(self):
        class Response:
            status_code = 200
            def json(self):
                return {"meals": [{"idMeal": "123", "strMeal": "Pasta"}]}

        mock_client = AsyncMock()
        mock_client.get.return_value = Response()
        mock_client.__aenter__.return_value = mock_client
        with patch.dict(os.environ, {"THEMEALDB_API_KEY": "private-test-key"}):
            with patch("main.httpx.AsyncClient", return_value=mock_client):
                first = asyncio.run(_meal_request("search", {"s": "pasta"}))
                second = asyncio.run(_meal_request("search", {"s": "pasta"}))
        self.assertEqual(first, second)
        self.assertEqual(mock_client.get.await_count, 1)
        self.assertIn("/api/json/v2/private-test-key/search.php", mock_client.get.call_args.args[0])
        self.assertNotIn("private-test-key", str(first))

    def test_public_routes_are_bounded_and_cache_success(self):
        client = TestClient(app)
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(client.get("/health").status_code, 503)
        with patch.dict(os.environ, {"FOODDATA_API_KEY": "test-usda", "THEMEALDB_API_KEY": "test-meal"}):
            self.assertEqual(client.get("/health").json(), {"status": "ok"})
        self.assertEqual(client.get("/recipes/filter").status_code, 422)
        self.assertEqual(client.get("/recipes/not-an-id").status_code, 422)
        self.assertEqual(client.get("/foods/search?q=x").status_code, 422)
        with patch("main._meal_request", new_callable=AsyncMock) as fetch:
            fetch.return_value = {"meals": []}
            response = client.get("/recipes/search?q=pasta")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"meals": []})
        self.assertIn("s-maxage=3600", response.headers["cache-control"])


if __name__ == "__main__":
    unittest.main()
