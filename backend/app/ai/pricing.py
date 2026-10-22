"""What a model call costs, from the token counts in its usage.

List prices in dollars per million tokens (Anthropic's, as in the lab's Part 1;
Bedrock's own price page is the one that counts for the bill). A model that is
not listed costs None rather than a made-up number.
"""

from decimal import Decimal

PRICES_PER_MILLION: dict[str, tuple[Decimal, Decimal]] = {
    # model id (without any "us." / "global." inference-profile prefix): (input, output)
    "anthropic.claude-opus-5-5": (Decimal("4.00"), Decimal("20.00")),
    "anthropic.claude-sonnet-5-5": (Decimal("2.00"), Decimal("10.00")),
    "anthropic.claude-haiku-5-5": (Decimal("0.10"), Decimal("0.50")),
    "anthropic.claude-sonnet-4-5-20250929-v1:0": (Decimal("3.00"), Decimal("15.00")),
}


def base_model_id(model: str) -> str:
    """us.anthropic.claude-… → anthropic.claude-…"""
    for prefix in ("us.", "eu.", "apac.", "global."):
        if model.startswith(prefix):
            return model[len(prefix) :]
    return model


def cost_usd(model: str, usage: dict) -> float | None:
    prices = PRICES_PER_MILLION.get(base_model_id(model))
    if prices is None:
        return None
    price_in, price_out = prices
    cost = (
        Decimal(usage.get("input_tokens", 0)) * price_in
        + Decimal(usage.get("output_tokens", 0)) * price_out
    ) / Decimal(1_000_000)
    return float(round(cost, 6))
