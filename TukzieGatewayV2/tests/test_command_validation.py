"""
Day 2 "done when" proof — run directly, no broker connection needed since
CommandValidator.validate() is broker-agnostic (only .start() touches MQTT).

    python -m gateway.test_command_validation
"""

import hashlib
import hmac
import json
import time

from gateway.command_validation import CommandValidator, MAX_COMMAND_AGE_SECONDS

SHARED_SECRET = "test-secret-change-me"


def make_signed_command(cmd: str, target: str, timestamp: float | None = None) -> bytes:
    timestamp = timestamp if timestamp is not None else time.time()
    payload = {"cmd": cmd, "target": target, "timestamp": timestamp}
    signature_input = f"{cmd}:{target}:{timestamp}"
    token = hmac.new(SHARED_SECRET.encode(), signature_input.encode(), hashlib.sha256).hexdigest()
    payload["auth_token"] = token
    return json.dumps(payload).encode()


def run():
    # No real BrokerConnection needed — validate() doesn't touch it.
    validator = CommandValidator(conn=None, shared_secret=SHARED_SECRET,
                                  max_commands_per_window=3, window_seconds=5.0)

    print("\n-- valid command --")
    r = validator.validate(make_signed_command("lock", "front_door"), source="test_client")
    assert r.accepted, r.reason
    print("PASS: accepted as expected")

    print("\n-- malformed payload --")
    r = validator.validate(b"not json", source="test_client")
    assert not r.accepted
    print(f"PASS: rejected — {r.reason}")

    print("\n-- bad auth token --")
    bad = json.loads(make_signed_command("lock", "front_door"))
    bad["auth_token"] = "wrong"
    r = validator.validate(json.dumps(bad).encode(), source="test_client")
    assert not r.accepted
    print(f"PASS: rejected — {r.reason}")

    print("\n-- stale/replayed command --")
    stale = make_signed_command("lock", "front_door", timestamp=time.time() - MAX_COMMAND_AGE_SECONDS - 5)
    r = validator.validate(stale, source="test_client")
    assert not r.accepted
    print(f"PASS: rejected — {r.reason}")

    print("\n-- flood / rate limiting (limit=3 per 5s) --")
    results = []
    for i in range(6):
        r = validator.validate(make_signed_command("lock", "front_door"), source="flood_client")
        results.append(r.accepted)
        print(f"  command {i+1}: {'accepted' if r.accepted else 'REJECTED — ' + r.reason}")
    assert results[:3] == [True, True, True], "first 3 should pass"
    assert results[3:] == [False, False, False], "commands 4-6 should be rate-limited"
    print("PASS: burst beyond threshold correctly rate-limited")

    print("\nAll Day 2 checks passed.")


if __name__ == "__main__":
    run()
