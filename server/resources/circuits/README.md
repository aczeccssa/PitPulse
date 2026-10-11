# Circuit geometry and calibration

`f1-circuits.geojson` is the unmodified `f1-circuits.geojson` from
[bacinger/f1-circuits](https://github.com/bacinger/f1-circuits/tree/394d8fbe70ef2c0b0c8d23ff7bee61fa09606055),
commit `394d8fbe70ef2c0b0c8d23ff7bee61fa09606055`. Its MIT license is retained in
`LICENSE.md`; `source.json` records the pinned source. Feature IDs describe the
dataset and are not evidence that every year's layout has been checked.

`calibrations.json` contains three non-collinear XY/geographic fitting anchors
and three held-out validation controls for each supported circuit/season.
Only the fitting anchors determine the affine transform. The server rejects a
calibration if any independent control exceeds 20 metres, or if fitting anchors
are collinear. Z is neither fitted nor interpreted as geographic altitude.

| Circuit / season | Geometry | Fitting vertex indices | Held-out vertex indices | Held-out errors (metres) |
| --- | --- | --- | --- | --- |
| Singapore / 2026 | `sg-2008` | 8, 60, 100 | 36, 76, 108 | 0.90, 5.36, 1.55 |
| Austin / 2025 | `us-2012` | 0, 90, 130 | 60, 120, 140 | 3.72, 7.68, 5.95 |

Controls pair observed F1 archive XY samples with surveyed GeoJSON vertices.
An initial geometric alignment helps identify matching track locations; its
parameters are not used by the final three-anchor transform. The validation
samples are distinct from the fitting samples. These checks establish an
archive-to-outline alignment, not independently measured GPS accuracy for every
car, pit-lane coordinate or future Session.

The Singapore controls use the [2026 qualifying archive](https://livetiming.formula1.com/static/2026/2026-10-11_Singapore_Grand_Prix/2026-10-10_Qualifying/Position.z.jsonStream)
and the current 19-turn layout. Austin controls use the
[2025 qualifying archive](https://livetiming.formula1.com/static/2025/2025-10-19_United_States_Grand_Prix/2025-10-18_Qualifying/Position.z.jsonStream)
and the [full F1 circuit map](https://circuitoftheamericas.com/event/f1/map/).
Raw captured feeds are not bundled. `source` in each calibration records the
archive and the exact geometry controls.

**Austin 2026 remains disabled.** A new year's coordinate origin and layout must
be confirmed with independent controls before adding a matching season entry.
Other tracks also retain their location basemap without invented car positions.
Unverified outlines carry a current-year verification warning.

Run the reproducible numeric gate with:

```sh
cargo test --manifest-path server/Cargo.toml services::circuits
```

Real feed overlays and Mapbox interaction require separate acceptance; see
[live-map acceptance](../../../docs/acceptance/live-map.md).
