"""
Day 5 "done when" proof — unit-tests scoring + hysteresis against
synthetic samples standing in for a short, honestly-limited real logging
window. Replace SAMPLE_ROUNDS with your actual Day 4 logged data once
you have it.

    python -m gateway.test_adaptive_scoring
"""

from gateway.adaptive_scoring import LinkMetrics, score_dongles, HysteresisSelector

# Each round: one LinkMetrics per dongle. dongle_2 starts weak, improves
# and stays clearly best from round 3 onward — this should trigger a
# switch, but not before round 3 (required_consecutive=3 below).
SAMPLE_ROUNDS = [
    [
        LinkMetrics("dongle_1", signal_strength=-70, latency_ms=80, packet_loss_pct=2),
        LinkMetrics("dongle_2", signal_strength=-95, latency_ms=200, packet_loss_pct=10),
        LinkMetrics("dongle_3", signal_strength=-85, latency_ms=150, packet_loss_pct=5),
    ],
    [
        LinkMetrics("dongle_1", signal_strength=-72, latency_ms=85, packet_loss_pct=3),
        LinkMetrics("dongle_2", signal_strength=-60, latency_ms=60, packet_loss_pct=1),
        LinkMetrics("dongle_3", signal_strength=-84, latency_ms=145, packet_loss_pct=4),
    ],
    [
        LinkMetrics("dongle_1", signal_strength=-71, latency_ms=82, packet_loss_pct=2),
        LinkMetrics("dongle_2", signal_strength=-58, latency_ms=55, packet_loss_pct=1),
        LinkMetrics("dongle_3", signal_strength=-86, latency_ms=155, packet_loss_pct=5),
    ],
    [
        LinkMetrics("dongle_1", signal_strength=-73, latency_ms=88, packet_loss_pct=3),
        LinkMetrics("dongle_2", signal_strength=-59, latency_ms=58, packet_loss_pct=1),
        LinkMetrics("dongle_3", signal_strength=-85, latency_ms=150, packet_loss_pct=5),
    ],
]


def run():
    print("-- scoring each round --")
    selector = HysteresisSelector(required_consecutive=3, margin=0.05)
    active_history = []

    for i, round_samples in enumerate(SAMPLE_ROUNDS):
        scores = score_dongles(round_samples)
        active = selector.update(scores)
        active_history.append(active)
        print(f"round {i+1}: scores={ {k: round(v,3) for k,v in scores.items()} } -> active={active}")

    print(f"\nactive link over time: {active_history}")

    assert active_history[0] == "dongle_1", "round 1 should start on the initial best (dongle_1 vs weak dongle_2)"
    assert active_history[-1] == "dongle_2", "should have switched to dongle_2 once it was sustainably best"
    print("PASS: hysteresis held dongle_1 through early noise, then switched once dongle_2's lead was sustained")

    print("\n-- degenerate case: only 1 dongle reachable --")
    single = [LinkMetrics("dongle_1", signal_strength=-70, latency_ms=80, packet_loss_pct=2)]
    scores = score_dongles(single)
    assert scores == {"dongle_1": 1.0}
    print("PASS: single-candidate case doesn't divide by zero")

    print("\nAll Day 5 scoring/hysteresis checks passed against this (limited) sample set.")
    print("NOTE: only 4 rounds of synthetic data — replace with real Day 4 logs and re-run before trusting this.")


if __name__ == "__main__":
    run()
