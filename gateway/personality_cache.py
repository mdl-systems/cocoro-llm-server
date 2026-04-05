#!/usr/bin/env python3
"""
gateway/personality_cache.py
cocoro-core 人格状態キャッシュ

cocoro-core (192.168.50.92:8001) から人格状態を取得してキャッシュする。
vLLMへのリクエスト時にsystem promptとして注入することで、
人格の一貫性を保ちながら低レイテンシを実現する。

キャッシュ戦略:
  - TTL: 60秒（人格は頻繁に変化しない）
  - 取得失敗時はフォールバックキャッシュを使用
  - スレッドセーフ（asyncio対応）
"""

import asyncio
import logging
import time
from typing import Optional
from dataclasses import dataclass, field

import httpx

logger = logging.getLogger(__name__)

# ── 定数 ──────────────────────────────────────────────────────────────────────
COCORO_CORE_URL = "http://192.168.50.92:8001"
CACHE_TTL_SECONDS = 60
REQUEST_TIMEOUT = 5.0   # 秒（LLM推論を遅らせないよう短めに設定）


@dataclass
class PersonalityState:
    """cocoro-coreから取得した人格状態"""
    character_name: str = "cocoro"
    system_prompt: str = ""
    emotion: str = "neutral"
    language: str = "ja"
    fetched_at: float = field(default_factory=time.time)

    def is_expired(self, ttl: float = CACHE_TTL_SECONDS) -> bool:
        return (time.time() - self.fetched_at) > ttl

    def to_system_message(self) -> dict:
        """OpenAI形式のsystem messageに変換"""
        if not self.system_prompt:
            return {}
        return {
            "role": "system",
            "content": self.system_prompt,
        }


class PersonalityCache:
    """cocoro-core人格状態のスレッドセーフキャッシュ"""

    def __init__(
        self,
        cocoro_core_url: str = COCORO_CORE_URL,
        api_key: str = "cocoro-2026",
        ttl: float = CACHE_TTL_SECONDS,
    ):
        self.cocoro_core_url = cocoro_core_url
        self.api_key = api_key
        self.ttl = ttl
        self._cache: Optional[PersonalityState] = None
        self._lock = asyncio.Lock()
        self._client: Optional[httpx.AsyncClient] = None

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(
                timeout=REQUEST_TIMEOUT,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json",
                },
            )
        return self._client

    async def _fetch_from_cocoro(self) -> Optional[PersonalityState]:
        """cocoro-core APIから人格状態を取得する"""
        try:
            client = await self._get_client()
            response = await client.get(
                f"{self.cocoro_core_url}/api/v1/personality/current"
            )
            response.raise_for_status()
            data = response.json()

            return PersonalityState(
                character_name=data.get("character_name", "cocoro"),
                system_prompt=data.get("system_prompt", ""),
                emotion=data.get("emotion", "neutral"),
                language=data.get("language", "ja"),
                fetched_at=time.time(),
            )

        except httpx.ConnectError:
            logger.warning(
                f"cocoro-core ({self.cocoro_core_url}) に接続できません"
            )
            return None
        except httpx.TimeoutException:
            logger.warning(
                "cocoro-core へのリクエストがタイムアウトしました"
            )
            return None
        except Exception as e:
            logger.error(f"cocoro-core からの取得に失敗: {e}")
            return None

    async def get(self) -> PersonalityState:
        """
        キャッシュから人格状態を取得する。
        キャッシュが期限切れまたは未取得の場合はcocoro-coreから取得する。
        取得失敗時はフォールバックキャッシュ（最後の有効値）を返す。
        """
        async with self._lock:
            if self._cache is not None and not self._cache.is_expired(self.ttl):
                return self._cache

            fresh = await self._fetch_from_cocoro()
            if fresh is not None:
                self._cache = fresh
                logger.debug(
                    f"人格キャッシュ更新: {fresh.character_name} "
                    f"[{fresh.emotion}]"
                )
                return self._cache
            elif self._cache is not None:
                # フォールバック: 古いキャッシュを返す
                logger.warning("cocoro-core取得失敗 → 古いキャッシュを使用")
                return self._cache
            else:
                # 初回取得失敗: デフォルト状態を返す
                logger.warning("cocoro-core取得失敗 → デフォルト人格を使用")
                return PersonalityState()

    async def inject_personality(
        self,
        messages: list[dict],
    ) -> list[dict]:
        """
        メッセージリストの先頭にsystem promptを注入する。
        すでにsystem messageがある場合は追記する。
        """
        state = await self.get()
        if not state.system_prompt:
            return messages

        result = list(messages)
        system_msg = state.to_system_message()

        if result and result[0].get("role") == "system":
            # 既存のsystem messageに追記
            existing = result[0]["content"]
            result[0] = {
                "role": "system",
                "content": f"{system_msg['content']}\n\n{existing}",
            }
        else:
            result.insert(0, system_msg)

        return result

    async def close(self) -> None:
        if self._client and not self._client.is_closed:
            await self._client.aclose()


# ── シングルトンインスタンス ──────────────────────────────────────────────────
import os
_personality_cache = PersonalityCache(
    cocoro_core_url=os.getenv("COCORO_CORE_URL", COCORO_CORE_URL),
    api_key=os.getenv("COCORO_API_KEY", "cocoro-2026"),
)


def get_personality_cache() -> PersonalityCache:
    return _personality_cache
