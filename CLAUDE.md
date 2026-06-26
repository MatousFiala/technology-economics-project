# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an empirical economics project studying the causal effect of a **bonus incentive** offered by a Prague bikesharing provider to users who return bikes to specific locations (e.g., hilly parts of the city where bikes would otherwise accumulate). The goal is to identify whether the bonus changes the spatial distribution of available bikes.

**Research design — difference-in-differences:**
- **Treatment group**: Stations from the provider that offers the bonus
- **Control group**: Matched stations from a provider that does not offer a bonus (matched primarily on proximity)
- **Outcome variable**: Number of available bikes at a station, measured in the morning (after overnight redistribution by vans) and in the evening (reflecting organic user behavior)
- The DiD compares morning vs. evening availability across treated and control stations before and after the bonus was introduced

## Repository Structure

```
code/         # Analysis scripts and notebooks
figures-plots/ # Output figures and plots
latex/         # Academic write-up
```

## Development Notes

- The `code/` directory is the main workspace. Scripts should be self-contained and reproducible.
- Data is not committed to the repository. Document data sources and acquisition steps in code comments or a dedicated script.
- Figures output from analysis go in `figures-plots/`.
- The final write-up lives in `latex/`.
