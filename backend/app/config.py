"""Application settings, loaded from the environment."""

from functools import lru_cache
from zoneinfo import ZoneInfo

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://app:app@db:5432/meetings"
    app_timezone: str = "Europe/Kyiv"
    cors_origins: str = "http://localhost:3000"
    log_level: str = "INFO"
    run_migrations_on_start: bool = True
    seed_demo_data: bool = False
    version: str = Field(default="1.0.0")

    # The agenda parser. The model is configuration, not code: switching it is a
    # redeploy, and every log line and stored suggestion records which one ran.
    # PARSER_API picks the Bedrock API: "mantle" is the Anthropic Messages API
    # (the current Claude models), "converse" is Bedrock's provider-neutral API.
    parser_model: str = "anthropic.claude-opus-5-5"
    parser_api: str = "mantle"
    bedrock_region: str = "us-east-1"
    # The parser only answers callers signed in to this pool and app client.
    cognito_user_pool_id: str = ""
    cognito_client_id: str = ""

    @field_validator("parser_api")
    @classmethod
    def _validate_parser_api(cls, value: str) -> str:
        if value not in ("mantle", "converse"):
            raise ValueError("PARSER_API must be 'mantle' or 'converse'")
        return value

    @field_validator("app_timezone")
    @classmethod
    def _validate_timezone(cls, value: str) -> str:
        ZoneInfo(value)  # raises for an unknown timezone
        return value

    @property
    def tz(self) -> ZoneInfo:
        return ZoneInfo(self.app_timezone)

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
