"""Bounded public recipe and food catalog API; provider credentials stay server-side."""

from __future__ import annotations

import os
import re
import time
from collections import OrderedDict
from pathlib import Path
from typing import Any, Optional

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query, Request

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

API_ROOT = "https://api.nal.usda.gov/fdc/v1"
MEAL_ROOT = "https://www.themealdb.com/api/json/v2"
CACHE_SIZE = 128
CACHE_SECONDS = 3600
_cache: OrderedDict[str, tuple[float, dict[str, Any]]] = OrderedDict()

app = FastAPI(title="Cooking Companion Catalog API", docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware("http")
async def cache_catalog_responses(request: Request, call_next):
    response = await call_next(request)
    if (request.method == "GET" and response.status_code == 200
            and request.url.path.startswith(("/foods/", "/recipes/"))):
        response.headers["Cache-Control"] = "public, max-age=0, s-maxage=3600, stale-while-revalidate=86400"
    return response


@app.get("/health")
async def health() -> dict[str, str]:
    _key()
    _meal_key()
    return {"status": "ok"}


def _key() -> str:
    key = os.environ.get("FOODDATA_API_KEY", "").strip()
    if not key or key.startswith("replace_with_"):
        raise HTTPException(status_code=503, detail="USDA key is not configured")
    return key


async def _request(path: str, params: dict[str, Any]) -> dict[str, Any]:
    cache_key = f"usda:{path}:{sorted(params.items())}"
    hit = _cache.get(cache_key)
    if hit and time.monotonic() - hit[0] < CACHE_SECONDS:
        _cache.move_to_end(cache_key)
        return hit[1]
    # The key is supplied only here and is never returned to the phone.
    params = {**params, "api_key": _key()}
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(10.0)) as client:
            response = await client.get(f"{API_ROOT}{path}", params=params)
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail="USDA is unreachable") from exc
    if response.status_code == 429:
        raise HTTPException(status_code=429, detail="USDA rate limit reached")
    if response.status_code == 404:
        raise HTTPException(status_code=404, detail="Food not found")
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="USDA request failed")
    try:
        payload = response.json()
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="Invalid USDA response") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=502, detail="Invalid USDA response")
    _cache[cache_key] = (time.monotonic(), payload)
    _cache.move_to_end(cache_key)
    while len(_cache) > CACHE_SIZE:
        _cache.popitem(last=False)
    return payload


def _meal_key() -> str:
    key = os.environ.get("THEMEALDB_API_KEY", "").strip()
    if key.startswith("replace_with_") or not re.fullmatch(r"[A-Za-z0-9_-]+", key):
        raise HTTPException(status_code=503, detail="TheMealDB key is not configured")
    return key


async def _meal_request(endpoint: str, params: dict[str, str]) -> dict[str, Any]:
    key = _meal_key()
    cache_key = f"meal:{endpoint}:{sorted(params.items())}"
    hit = _cache.get(cache_key)
    if hit and time.monotonic() - hit[0] < CACHE_SECONDS:
        _cache.move_to_end(cache_key)
        return hit[1]
    # The key is only sent to the provider, never included in a client response.
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(10.0)) as client:
            response = await client.get(f"{MEAL_ROOT}/{key}/{endpoint}.php", params=params)
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail="TheMealDB is unreachable") from exc
    if response.status_code == 429:
        raise HTTPException(status_code=429, detail="TheMealDB rate limit reached")
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="TheMealDB request failed")
    try:
        payload = response.json()
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="Invalid TheMealDB response") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=502, detail="Invalid TheMealDB response")
    _cache[cache_key] = (time.monotonic(), payload)
    _cache.move_to_end(cache_key)
    while len(_cache) > CACHE_SIZE:
        _cache.popitem(last=False)
    return payload


@app.get("/foods/search")
async def search(q: str = Query(min_length=2, max_length=80), page: int = Query(default=1, ge=1, le=100)) -> dict[str, Any]:
    query = q.strip()
    if len(query) < 2:
        raise HTTPException(status_code=422, detail="Search needs at least two characters")
    return await _request("/foods/search", {"query": query, "pageNumber": page, "pageSize": 25})


@app.get("/foods/{fdc_id}")
async def details(fdc_id: int) -> dict[str, Any]:
    if fdc_id <= 0:
        raise HTTPException(status_code=422, detail="Invalid food ID")
    return await _request(f"/food/{fdc_id}", {})


@app.get("/recipes/search")
async def recipe_search(q: str = Query(min_length=1, max_length=80)) -> dict[str, Any]:
    query = q.strip()
    if not query:
        raise HTTPException(status_code=422, detail="Enter a recipe name")
    return await _meal_request("search", {"s": query})


@app.get("/recipes/categories")
async def recipe_categories() -> dict[str, Any]:
    return await _meal_request("categories", {})


@app.get("/recipes/filter")
async def recipe_filter(category: Optional[str] = Query(default=None, max_length=60),
                        ingredient: Optional[str] = Query(default=None, max_length=80)) -> dict[str, Any]:
    category = category.strip() if category is not None else None
    ingredient = ingredient.strip() if ingredient is not None else None
    if bool(category) == bool(ingredient):
        raise HTTPException(status_code=422, detail="Choose one category or ingredient")
    return await _meal_request("filter", {"c": category} if category else {"i": ingredient or ""})


@app.get("/recipes/{meal_id}")
async def recipe_details(meal_id: str) -> dict[str, Any]:
    if not re.fullmatch(r"[0-9]{1,12}", meal_id):
        raise HTTPException(status_code=422, detail="Invalid recipe ID")
    return await _meal_request("lookup", {"i": meal_id})
