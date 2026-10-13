# Spec Delta

## ADDED Requirements

### Requirement: Discovery rows in library tabs
Each library tab SHALL show two of the day's discovery rows that suit it (films: Short tonight, Because
you watched, the shelf, the decade; series: Almost done, the shelf, the decade), drawn from that library
only, preferring rows Home is not showing that day, above the filters and the grid.

#### Scenario: Movies tab
- **WHEN** Home shows Short tonight, Because you watched and Almost done today
- **THEN** the Movies tab shows Been on the shelf a while and the decade row, with films from Movies only
