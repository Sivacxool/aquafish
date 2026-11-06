"""Create a Workers room allowlist from the owner's private pairing cards."""

import argparse
import hashlib
import html
import json
from pathlib import Path
import re

from pairing_card import validate


def digest(label, value):
    return hashlib.sha256((label + value).encode("utf-8")).hexdigest()


def room_for(card):
    source = card.read_text(encoding="utf-8")
    match = re.search(r'<textarea id="payload"[^>]*>(.*?)</textarea>', source, re.S)
    if not match:
        raise ValueError("Expected an AquaHatch pairing card")
    data = validate(json.loads(html.unescape(match[1])))
    writer = digest("aquahatch relay write v1:", data["token"])
    reader = digest("aquahatch relay read v1:", writer)
    room = digest("aquahatch relay room v1:", reader)
    kind = "cameras" if data["kind"] == "camera" else "readings"
    return kind + ":" + room


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cards", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        rooms = sorted({room_for(card) for card in args.cards})
        args.output.write_text(json.dumps({"RELAY_ROOMS": ",".join(rooms)}) + "\n", encoding="utf-8")
    except (OSError, ValueError, TypeError, KeyError):
        parser.exit(1, "Could not prepare the allowlist. Check the private cards and output path.\n")
    print(f"Allowlist prepared for {len(rooms)} device(s).")


if __name__ == "__main__":
    main()
