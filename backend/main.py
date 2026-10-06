"""Small local proxy for FoodData Central. Only food search and details are exposed."""

from __future__ import annotations

import os
import time
from collections import OrderedDict
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Query

API_ROOT = "https://api.nal.usda.gov/fdc/v1"
CACHE_SIZE = 128
CACHE_SECONDS = 3600
_cache: OrderedDict[str, tuple[float, dict[str, Any]]] = OrderedDict()

app = FastAPI(title="Cooking Companion USDA Proxy", docs_url=None, redoc_url=None, openapi_url=None)


def _key() -> str:
    key = os.environ.get("FOODDATA_API_KEY", "").strip()
    if not key:
        raise HTTPException(status_code=503, detail="USDA key is not configured")
    return key


async def _request(path: str, params: dict[str, Any]) -> dict[str, Any]:
    cache_key = f"{path}:{sorted(params.items())}"
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
