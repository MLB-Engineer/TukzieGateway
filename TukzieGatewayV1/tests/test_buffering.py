"""
Day 3 "done when" proof — simulates a flaky publish function (fails on
demand) to prove no data loss and correct ordering across a disconnect.

    python -m gateway.test_buffering
"""

import os

from gateway.buffering import StoreAndForwardBuffer
from gateway.schema import TelemetryPacket

DB_PATH = "test_buffer.sqlite3"


class FlakyPublisher:
    """Publish function that can be switched offline/online on demand,
    and records everything that actually made it through, in order."""

    def __init__(self):
        self.online = True
        self.delivered: list[dict] = []

    def __call__(self, payload: dict) -> None:
        if not self.online:
            raise ConnectionError("simulated broker disconnect")
        self.delivered.append(payload)


def run():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    publisher = FlakyPublisher()
    buf = StoreAndForwardBuffer(publish_fn=publisher, db_path=DB_PATH)

    print("-- publishing 3 packets while online --")
    for i in range(3):
        packet = TelemetryPacket()
        went_live = buf.send({"seq": i, "schema_version": packet.schema_version})
        assert went_live, f"packet {i} should have gone out live"
    print(f"PASS: {len(publisher.delivered)} delivered live, {buf.pending_count()} pending")

    print("\n-- killing connectivity, publishing 3 more --")
    publisher.online = False
    for i in range(3, 6):
        packet = TelemetryPacket()
        went_live = buf.send({"seq": i, "schema_version": packet.schema_version})
        assert not went_live, f"packet {i} should have been queued, not sent live"
    assert buf.pending_count() == 3
    print(f"PASS: {buf.pending_count()} correctly queued while offline")

    print("\n-- reconnecting and flushing --")
    publisher.online = True
    flushed = buf.flush()
    assert flushed == 3
    assert buf.pending_count() == 0
    print(f"PASS: {flushed} flushed, 0 pending remain")

    print("\n-- verifying order and completeness --")
    all_seqs = [p["seq"] for p in publisher.delivered]
    assert all_seqs == [0, 1, 2, 3, 4, 5], f"got {all_seqs}"
    assert all(p["schema_version"] for p in publisher.delivered), "schema_version missing on some packet"
    print(f"PASS: delivered in order {all_seqs}, all carrying schema_version")

    os.remove(DB_PATH)
    print("\nAll Day 3 checks passed — no data loss, order preserved, schema versioned.")


if __name__ == "__main__":
    run()
