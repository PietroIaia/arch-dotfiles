# Shared timing for the bar's width animations (now-playing island, tween-text labels).
ANIM_MS = 500
FRAME_MS = 25


def ease(start: int, target: int, t: float) -> int:
    # Ease-out cubic over t in [0, 1].
    return round(start + (target - start) * (1 - (1 - min(t, 1.0)) ** 3))
