"""Tests for a meeting's agenda: read, save (replace), validation, cascade."""

import uuid

from sqlalchemy import func, select

from app.models import ActionItem, AgendaItem


async def _meeting(client, meeting_payload) -> str:
    response = await client.post("/api/v1/meetings", json=meeting_payload)
    assert response.status_code == 201, response.text
    return response.json()["id"]


AGENDA = {
    "items": [
        {"topic": "New Pro pricing", "owner": "Олена", "minutes": 15},
        {"topic": "Customer feedback", "owner": "Taras"},
        {"topic": "What to do with the annual discount"},
    ],
    "action_items": [
        {"task": "Compare with competitors", "owner": "Taras", "due": "2026-10-23"},
    ],
}

SUGGESTION = {
    "model": "anthropic.claude-opus-5-5",
    "prompt_version": "agenda-v1",
    "agenda": {"title": "Pricing sync", "items": [{"topic": "New Pro tariffs"}], "language": "uk"},
}


async def test_a_new_meeting_has_an_empty_agenda(client, meeting_payload):
    meeting_id = await _meeting(client, meeting_payload)

    response = await client.get(f"/api/v1/meetings/{meeting_id}/agenda")

    assert response.status_code == 200
    assert response.json() == {
        "meeting_id": meeting_id,
        "items": [],
        "action_items": [],
        "ai_suggestion": None,
    }


async def test_save_then_read_keeps_the_order(client, meeting_payload):
    meeting_id = await _meeting(client, meeting_payload)

    saved = await client.post(f"/api/v1/meetings/{meeting_id}/agenda", json=AGENDA)
    read = await client.get(f"/api/v1/meetings/{meeting_id}/agenda")

    assert saved.status_code == 200, saved.text
    assert saved.json() == read.json()
    body = read.json()
    assert [(i["topic"], i["owner"], i["minutes"], i["position"]) for i in body["items"]] == [
        ("New Pro pricing", "Олена", 15, 0),
        ("Customer feedback", "Taras", None, 1),
        ("What to do with the annual discount", None, None, 2),
    ]
    assert body["action_items"][0] | {"id": None} == {
        "id": None,
        "task": "Compare with competitors",
        "owner": "Taras",
        "due": "2026-10-23",
        "position": 0,
    }


async def test_saving_again_replaces_the_agenda(client, meeting_payload, session):
    meeting_id = await _meeting(client, meeting_payload)
    await client.post(f"/api/v1/meetings/{meeting_id}/agenda", json=AGENDA)

    response = await client.post(
        f"/api/v1/meetings/{meeting_id}/agenda", json={"items": [{"topic": "Only this"}]}
    )

    assert [i["topic"] for i in response.json()["items"]] == ["Only this"]
    assert response.json()["action_items"] == []
    assert await session.scalar(select(func.count()).select_from(AgendaItem)) == 1
    assert await session.scalar(select(func.count()).select_from(ActionItem)) == 0


async def test_the_ai_suggestion_is_stored_next_to_the_saved_agenda(client, meeting_payload):
    meeting_id = await _meeting(client, meeting_payload)

    saved = await client.post(
        f"/api/v1/meetings/{meeting_id}/agenda", json=AGENDA | {"ai_suggestion": SUGGESTION}
    )
    assert saved.json()["ai_suggestion"] == SUGGESTION

    # Typed by hand the next time: no suggestion is kept for that agenda.
    retyped = await client.post(f"/api/v1/meetings/{meeting_id}/agenda", json=AGENDA)
    assert retyped.json()["ai_suggestion"] is None


async def test_the_meeting_list_is_unchanged(client, meeting_payload):
    meeting_id = await _meeting(client, meeting_payload)
    await client.post(
        f"/api/v1/meetings/{meeting_id}/agenda", json=AGENDA | {"ai_suggestion": SUGGESTION}
    )

    meeting = (await client.get(f"/api/v1/meetings/{meeting_id}")).json()

    assert "agenda_ai_suggestion" not in meeting
    assert "items" not in meeting


async def test_invalid_agendas_are_rejected_with_the_field(client, meeting_payload):
    meeting_id = await _meeting(client, meeting_payload)
    url = f"/api/v1/meetings/{meeting_id}/agenda"

    blank = await client.post(url, json={"items": [{"topic": "   "}]})
    zero = await client.post(url, json={"items": [{"topic": "Sync", "minutes": 0}]})
    bad_date = await client.post(url, json={"action_items": [{"task": "X", "due": "Friday"}]})

    assert blank.status_code == 422
    assert blank.json()["error"]["details"][0]["field"] == "items.0.topic"
    assert zero.status_code == 422
    assert zero.json()["error"]["details"][0]["field"] == "items.0.minutes"
    assert bad_date.status_code == 422
    assert bad_date.json()["error"]["details"][0]["field"] == "action_items.0.due"


async def test_unknown_meeting_is_404(client):
    unknown = uuid.uuid4()

    read = await client.get(f"/api/v1/meetings/{unknown}/agenda")
    save = await client.post(f"/api/v1/meetings/{unknown}/agenda", json=AGENDA)

    assert read.status_code == 404
    assert save.status_code == 404
    assert read.json()["error"]["code"] == "not_found"


async def test_deleting_the_meeting_deletes_its_agenda(client, meeting_payload, session):
    meeting_id = await _meeting(client, meeting_payload)
    await client.post(f"/api/v1/meetings/{meeting_id}/agenda", json=AGENDA)

    await client.delete(f"/api/v1/meetings/{meeting_id}")

    assert await session.scalar(select(func.count()).select_from(AgendaItem)) == 0
    assert await session.scalar(select(func.count()).select_from(ActionItem)) == 0
