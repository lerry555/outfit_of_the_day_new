#!/usr/bin/env python3
"""Build assets/data/airports.json from OurAirports airports.csv (large + medium, IATA)."""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

try:
    from timezonefinder import TimezoneFinder
except ImportError:
    print("Install: pip install timezonefinder", file=sys.stderr)
    sys.exit(1)

try:
    import pycountry
except ImportError:
    pycountry = None  # type: ignore


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "tool" / "airports_raw.csv"
OUT_PATH = ROOT / "assets" / "data" / "airports.json"


def country_name(iso2: str) -> str:
    iso2 = (iso2 or "").strip().upper()
    if not iso2 or pycountry is None:
        return iso2
    try:
        return pycountry.countries.get(alpha_2=iso2).name
    except Exception:
        return iso2


def main() -> None:
    if not CSV_PATH.is_file():
        print(f"Missing {CSV_PATH}", file=sys.stderr)
        sys.exit(1)

    tf = TimezoneFinder()
    allowed = {"large_airport", "medium_airport"}
    out: list[dict] = []

    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = (row.get("type") or "").strip()
            if t not in allowed:
                continue
            iata = (row.get("iata_code") or "").strip().upper()
            if len(iata) != 3 or not iata.isalpha():
                continue
            icao = (row.get("gps_code") or row.get("ident") or "").strip().upper()
            name = (row.get("name") or "").strip()
            city = (row.get("municipality") or "").strip()
            iso = (row.get("iso_country") or "").strip().upper()
            try:
                lat = float(row.get("latitude_deg") or 0)
                lon = float(row.get("longitude_deg") or 0)
            except ValueError:
                continue
            if abs(lat) < 0.01 and abs(lon) < 0.01:
                continue

            tz = tf.timezone_at(lat=lat, lng=lon)

            out.append(
                {
                    "iata": iata,
                    "icao": icao[:4] if icao else "",
                    "name": name,
                    "city": city,
                    "country": country_name(iso),
                    "iso_country": iso,
                    "lat": round(lat, 5),
                    "lon": round(lon, 5),
                    "timezone": tz,
                    "airport_type": t,
                }
            )

    out.sort(key=lambda r: (r["iata"], r["name"]))

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "source": "OurAirports",
        "filter": "type in large_airport,medium_airport; valid IATA",
        "count": len(out),
        "airports": out,
    }
    with OUT_PATH.open("w", encoding="utf-8") as w:
        json.dump(payload, w, ensure_ascii=False, separators=(",", ":"))

    print(f"Wrote {len(out)} airports to {OUT_PATH}")


if __name__ == "__main__":
    main()
