"""The first call (lab Part 4, Step 1): one question, the answer, why it ended,
and what it cost in tokens. Run with `make llm-hello`.

PARSER_API=mantle uses the Anthropic Messages API on Bedrock, as in the lab.
PARSER_API=converse uses Bedrock's Converse API, the fallback while the current
Claude models are not yet available to the account.
"""

from app.ai.pricing import cost_usd
from app.config import settings

QUESTION = "In one sentence: what is an ISO week?"


def ask_mantle(model: str) -> tuple[str, str, dict]:
    from anthropic import AnthropicBedrockMantle

    client = AnthropicBedrockMantle(aws_region=settings.bedrock_region)
    msg = client.messages.create(
        model=model,
        max_tokens=1024,
        output_config={"effort": "low"},
        messages=[{"role": "user", "content": QUESTION}],
    )
    text = next((b.text for b in msg.content if b.type == "text"), "")
    usage = {"input_tokens": msg.usage.input_tokens, "output_tokens": msg.usage.output_tokens}
    return text, msg.stop_reason, usage


def ask_converse(model: str) -> tuple[str, str, dict]:
    import boto3

    client = boto3.client("bedrock-runtime", region_name=settings.bedrock_region)
    resp = client.converse(
        modelId=model,
        messages=[{"role": "user", "content": [{"text": QUESTION}]}],
        inferenceConfig={"maxTokens": 200},
    )
    text = next((b["text"] for b in resp["output"]["message"]["content"] if "text" in b), "")
    usage = {
        "input_tokens": resp["usage"]["inputTokens"],
        "output_tokens": resp["usage"]["outputTokens"],
    }
    return text, resp["stopReason"], usage


if __name__ == "__main__":
    model = settings.parser_model
    ask = ask_mantle if settings.parser_api == "mantle" else ask_converse
    text, stop_reason, usage = ask(model)
    print(f"api:         {settings.parser_api}")
    print(f"model:       {model}")
    print(f"answer:      {text}")
    print(f"stop_reason: {stop_reason}")
    print(f"usage:       {usage['input_tokens']} in / {usage['output_tokens']} out")
    print(f"cost:        ${cost_usd(model, usage)}")
