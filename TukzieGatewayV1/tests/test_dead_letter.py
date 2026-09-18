"""
Day 6 "done when" proof (Task 15 finish) — no broker needed, dead_letter
just needs any callable to stand in for "publish to the rejected topic."

    python -m gateway.test_dead_letter
"""

from gateway.dead_letter import DeadLetterHandler


def run():
    rejected_log = []
    handler = DeadLetterHandler(publish_rejected_fn=rejected_log.append)

    print("-- valid payload --")
    result = handler.ingest(b'{"schema_version": "0.1.0"}')
    assert result.accepted
    assert len(rejected_log) == 0
    print("PASS: accepted, nothing on the dead-letter sink")

    print("\n-- deliberately malformed payload --")
    result = handler.ingest(b"{not valid json at all")
    assert not result.accepted
    assert len(rejected_log) == 1
    envelope = rejected_log[0]
    assert "reason" in envelope and "raw_payload" in envelope and "rejected_at" in envelope
    print(f"PASS: rejected with reason='{envelope['reason']}', original payload preserved")

    print("\n-- valid JSON but wrong shape --")
    result = handler.ingest(b'{"unexpected_field": 123}')
    assert not result.accepted
    assert len(rejected_log) == 2
    print(f"PASS: rejected with reason='{rejected_log[1]['reason']}'")

    print("\nAll Day 6 dead-letter checks passed — malformed payloads land with a reason, not silently.")


if __name__ == "__main__":
    run()
