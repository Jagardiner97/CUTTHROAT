# Project Context: Topology Optimization of Heat Exchangers via PINNs

## Project Summary

This project implements a topology optimization pipeline for heat exchanger design using a
combination of convolutional neural networks (CNNs), reinforcement learning (RL), and
physics-informed neural networks (PINNs). The goal is to discover high-performance heat
exchanger geometries by iteratively generating candidate designs and evaluating them with
CFD simulations — either through a full physics solver (MOOSE) or a surrogate neural
network (PINN).

The optimization uses the **density method**: the design domain is discretized into a 2D
rectangular grid where each cell is classified as either solid (wall/fin material) or
fluid (flow channel). The CNN Generator learns to produce grid assignments that yield
thermally and hydraulically efficient heat exchanger layouts.

---

## Repository Structure

```
topology-optimization.ipynb     # Main notebook: all class definitions and training code
configs/                        # GeometryConfig JSON files (one per generated design)
meshes/                         # GMSH .msh files (one per design)
results/                        # MOOSE Exodus .e result files (one per simulated design)
problems/
  template.i                    # Jinja2 MOOSE input file template
  <NX>x<NY>-generator_weights.pth  # Saved CNN weights, keyed by grid resolution
```

---

## System Architecture

The pipeline has three major components: **Optimizer**, **Generator**, and **Simulator**.

```
                          ┌─────────────────────────────────────────┐
                          │              Optimizer                  │
                          │  - initializes Generator & Simulator    │
                          │  - manages Stage 1 / Stage 2 training   │
                          │  - generates MOOSE .i files from Jinja2 │
                          │  - calls simulator.run() for each mesh  │
                          └───────────────┬─────────────────────────┘
                                          │
                    ┌─────────────────────┼──────────────────────┐
                    ▼                                            ▼
        ┌───────────────────────┐                  ┌────────────────────────┐
        │   HeatExchangerGenerator              │   Simulator             │
        │   (wraps HeatExchangerCNN)            │   type: 'MOOSE'/'PINN'  │
        │                       │              └────────────────────────┘
        │  Stage 1: FilterLoss  │
        │  Stage 2: RL rewards  │
        └───────────────────────┘
```

### Data / File Flow

```
1. HeatExchangerGenerator.generate()
      CNN(z) → soft occupancy grid (B, 1, grid_ny, grid_nx)
      → thresholded binary grid
      → GeometryFilter checks (density, flow path, no pockets)
      → occupancy_to_polygons() → obstacle_polygons
      → GeometryConfig saved as configs/hx_<id>.json
      → HeatExchanger.generate_mesh() via GMSH → meshes/hx_<id>.msh

2. Optimizer.simulate_all_meshes()
      For each meshes/hx_<id>.msh:
        create_input_file(template.i) → results/hx_<id>.i
        Simulator.run(input_file) → results/hx_<id>.e  (Exodus format)
        clean_input_file()

3. (Planned) Optimizer RL loop
      Simulator.analyze_exodus_results() → scalar reward
      Generator CNN weights updated via policy gradient
```

---

## Class Reference

### `GeometryConfig` (dataclass)

Serializable snapshot of a single heat exchanger geometry. Stored as JSON.

| Field | Type | Description |
|---|---|---|
| `grid_nx`, `grid_ny` | `int` | Resolution of the occupancy grid |
| `domain_length`, `domain_height` | `float` | Physical dimensions of the domain |
| `occupancy_grid` | `list[list[float]]` | Soft CNN output before thresholding, shape `(grid_ny, grid_nx)`, values in `[0, 1]` |
| `obstacle_polygons` | `list[list[tuple]]` | CCW bounding-box rectangles for each connected solid region, in physical coordinates |
| `config_id` | `str` | UUID tying the config to its `.msh` and `.e` files |

Key methods: `save(path)`, `load(path)`, `mesh_filename` (property), `grid_cell_size()`, `cell_center(ix, iy)`.

**Note:** The origin is at the bottom-left of the domain. `cell_center()` returns `(x, y)` where `y` is offset by `-domain_height / 2` (i.e., y is centered about zero).

---

### `HeatExchanger`

Container object tying together a `GeometryConfig`, its GMSH mesh, and any simulation results for one design candidate.

| Attribute | Type | Description |
|---|---|---|
| `id` | `str` | Derived from `GeometryConfig.config_id` |
| `config_filename` | `str` | `configs/hx_<id>.json` |
| `mesh_filename` | `str` | `meshes/hx_<id>.msh` |
| `result_filename` | `str` | `results/hx_<id>.e` |
| `geometry_config` | `GeometryConfig` | Loaded on construction |
| `obstruction_polygons` | `list` | Extracted from `geometry_config` |
| `mesh_exists` | `bool` | True if `.msh` file is present |
| `solved` | `bool` | True if `.e` result file is present |
| `results` | `dict \| None` | Parsed simulation results (placeholder — not yet implemented) |

Key methods:
- `generate_mesh()` — uses GMSH Python API to build the mesh. Creates a rectangular fluid domain, cuts out obstacle polygons via boolean subtraction, classifies boundaries as `Inlet` (x=0), `Outlet` (x=L), `Top`, `Bottom`, `Wall` (obstacle surfaces). Writes to `meshes/hx_<id>.msh`.
- `read_results()` — placeholder, not yet implemented.

**GMSH boundary classification logic:** boundaries are assigned by center-of-mass coordinates. Inlet is at x≈0, Outlet at x≈domain_length, Top at y≈+domain_height/2, Bottom at y≈-domain_height/2. All other curves (obstacle walls) are tagged as `Wall`.

---

### `HeatExchangerCNN` (nn.Module)

Generative CNN mapping a latent vector `z` to an occupancy grid.

**Input:** `z` — tensor of shape `(B, latent_dim)`, sampled from `N(0,1)`  
**Output:** tensor of shape `(B, 1, grid_ny, grid_nx)`, values in `(0, 1)` via sigmoid

**Architecture:**
1. Fully-connected projection: `latent_dim → base_channels * 4 → base_channels * 4` (with ReLU)
2. Reshape to `(B, base_channels, 2, 2)` — small initial spatial feature map
3. Series of `ConvTranspose2d + BatchNorm2d + ReLU` upsampling blocks, halving channels each block; number of blocks = `max(ceil(log2(grid_nx)), ceil(log2(grid_ny))) - 1`
4. Final `Conv2d(in_ch, 1, kernel_size=1)` head
5. Bilinear interpolation to exactly `(grid_ny, grid_nx)`
6. Sigmoid activation

Weight initialization uses Kaiming normal for conv/linear layers.

Default hyperparameters: `latent_dim=32`, `grid_nx=20`, `grid_ny=10`, `base_channels=64`.

---

### `GeometryFilter`

Hard (non-differentiable) geometry validator. Applied after each `generate()` call.

**Checks:**
1. **Solid density** — fraction of binary solid cells must be in `[min_density, max_density]`
2. **Flow path** — at least one connected fluid component must span from the left column (inlet) to the right column (outlet), using 4-connectivity
3. **No enclosed fluid** — every fluid connected component must touch both the inlet (left) and outlet (right) columns; fluid regions touching only top/bottom boundaries are rejected

All checks use `scipy.ndimage.label` with a 4-connected structuring element.

**Parameters:** `min_density=0.10`, `max_density=0.75`, `threshold=0.5`

Returns `(is_valid: bool, report: dict)` where `report` includes individual check results and the solid density value.

---

### `FilterLoss` (nn.Module)

Differentiable proxy for `GeometryFilter` used during Stage 1 CNN pre-training. All loss terms operate on the soft (un-thresholded) occupancy grid and run entirely on the training device.

| Loss Term | Weight | Purpose |
|---|---|---|
| `density_loss` | 3.0 | Penalizes solid fraction outside `[min_density, max_density]`; asymmetrically penalizes too-high density 3× more (addresses density collapse) |
| `flow_loss` | 2.5 | Penalizes blocked inlet/outlet columns and poor local fluid connectivity |
| `pocket_loss` | 7.5 | Differentiable flood-fill from both left and right; penalizes fluid not reachable from both inlet and outlet |
| `diversity_loss` | 3.0 | Penalizes mode collapse; requires spatial std per sample and inter-sample std across batch above `min_std` |
| `tortuosity_loss` | 0.5 | Penalizes designs with a straight flow path; measures std of fluid y-centroid across x columns |
| `fragmentation_loss` | 5.0 | Penalizes vertically blocking solid columns, horizontally open fluid rows, and unimodal solid/fluid marginal distributions |
| `channel_scale_loss` | 4.0 | FFT-based; penalizes DC-dominated spectra and encourages energy in mid-frequency band corresponding to `target_channel_width` |
| `interface_loss` | 2.0 | Rewards high solid-fluid interface density (Sobel-like gradient); penalizes spatially concentrated interfaces |
| `periodicity_loss` | 2.5 | FFT-based; penalizes when any single AC frequency captures >20% of total AC power along either axis |
| `sharpness_loss` | 4.0 | Penalizes ambiguous cells (values near 0.5) that are surrounded by other ambiguous cells (flat fringe), and ambiguous cells with low gradient magnitude |

**`pocket_loss` implementation detail:** Uses a smooth flood-fill approximation via `avg_pool2d` with alpha scaling (instead of `max_pool2d`) to keep gradients alive. Two separate fills are seeded from the left and right columns; a cell is considered valid only if reachable from both. Downsamples to reduce memory for grids larger than 50,000 cells.

**`density_loss` implementation detail:** Combines a hinge loss, a pull-toward-center loss, a straight-through estimator (STE) hard density loss, and an edge-aware sharpening term that more heavily penalizes ambiguous cells adjacent to decided (near-0 or near-1) cells.

---

### `HeatExchangerGenerator`

Wraps `HeatExchangerCNN`, `GeometryFilter`, and post-processing. Primary interface for the `Optimizer`.

**Constructor parameters:**

| Parameter | Default | Description |
|---|---|---|
| `grid_nx`, `grid_ny` | 20, 10 | Occupancy grid resolution |
| `domain_length`, `domain_height` | 1.0, 0.5 | Physical domain dimensions |
| `latent_dim` | 32 | CNN latent vector size |
| `threshold` | 0.5 | Binarization threshold |
| `device` | `"cpu"` | PyTorch device |
| `min_density`, `max_density` | 0.25, 0.70 | Solid fraction bounds |
| `config_directory` | `"configs"` | Where to save `GeometryConfig` JSON files |
| `mesh_directory` | `"meshes"` | Where to save `.msh` files |
| `mesh_params` | see below | GMSH meshing options |

Default `mesh_params`: `mesh_algorithm=8` (Frontal-Delaunay), `mesh_recombine=1` (quad elements), `mesh_element_order=2` (second-order). `mesh_min` and `mesh_max` are set automatically from `dx = domain_length / grid_nx` and `dy = domain_height / grid_ny`.

**Key methods:**

- `pretrain_on_filter(n_steps, batch_size, lr, log_every, num_workers)` — Stage 1 training. Uses `FilterLoss`, Adam optimizer, `ReduceLROnPlateau` scheduler, gradient clipping (`max_norm=1.0`), optional CUDA AMP. Hard `GeometryFilter` checks run in a `ThreadPoolExecutor` in parallel with GPU training. Returns `history` list of per-log-step loss breakdowns.

- `generate(z, config_id, print_polygons)` — Generate a single geometry. Runs the CNN, applies `GeometryFilter`, converts occupancy to polygons, creates `GeometryConfig` and `HeatExchanger`. Returns `(GeometryConfig, soft_grid_tensor)` on success or `(None, None)` on filter failure.

- `generate_batch(n, max_attempts, generation_mode)` — Generate `n` valid geometries, resampling on filter failures. Raises `RuntimeError` after `max_attempts` consecutive failures.

- `occupancy_to_polygons(occupancy, ...)` — Converts binary occupancy grid to a list of CCW bounding-box rectangles using `scipy.ndimage.label`. One rectangle per connected solid component.

- `create_id(nx, ny, length, gen_mode, id_num)` — Creates human-readable IDs in the format `NxM-<cell_size>m-<mode><NNNN>` (e.g., `20x10-0.050m-t0001`).

- `save_weights(path)` / `load_weights(path)` — Serialize/deserialize CNN weights.

- `run_diagnostic()` — Prints CNN output statistics and filter report; displays soft and binary occupancy grid side-by-side.

- `plot_training_curves()` — Plots loss component curves and filter pass rate over Stage 1 training steps.

---

### `Simulator`

Thin wrapper around the simulation backend. Currently implements MOOSE only; PINN backend is planned.

| Parameter | Description |
|---|---|
| `type` | `'MOOSE'` or `'PINN'` (PINN not yet implemented) |
| `params` | For MOOSE: path to the compiled MOOSE application binary (default `"./cutthroat-opt"`) |

**`run_moose(input_file, n_processors)`** — Executes the MOOSE app via `subprocess` using `conda run -n moose mpiexec -np <N> <app> -i <input_file>`. Captures stdout/stderr. Prints error if `returncode != 0`.

**`analyze_exodus_results(exodus_file)`** — Currently a placeholder using PyVista (`pv.read()`). Prints mesh info and array names but does not extract scalar performance metrics yet.

**`run(input_file, n_processors)`** — Dispatches to `run_moose()` or PINN (not yet implemented).

---

### `Optimizer`

Orchestrates the full optimization pipeline. Currently handles initialization and batch MOOSE simulation; RL training loop is not yet implemented.

**Constructor parameters:**

| Parameter | Default | Description |
|---|---|---|
| `domain_dimensions` | `[2.0, 1.0, 100, 50]` | `[length, height, grid_nx, grid_ny]` |
| `generator_type` | `'pretrained_CNN'` | `'pretrained_CNN'` loads weights; `'untrained_CNN'` runs Stage 1 pre-training |
| `simulator_type` | `'MOOSE'` | Passed to `Simulator` |
| `mesh_files_dir` | `"meshes"` | Directory to scan for `.msh` files |
| `results_dir` | `"results"` | Directory to scan for `.e` files and write `.i` files |
| `device` | `"cpu"` | PyTorch device for the Generator |

**Weight file convention:** `problems/<grid_nx>x<grid_ny>-generator_weights.pth`

**Key methods:**

- `initialize_generator(generator_type, domain_dimensions)` — Constructs `HeatExchangerGenerator`. If `'untrained_CNN'`, calls `pretrain_on_filter(n_steps=3000)`. If `'pretrained_CNN'`, loads weights from the convention path.

- `initialize_simulator(simulator_type)` — Constructs `Simulator`.

- `create_input_file(template_path, output_dir, mesh_name)` — Renders the Jinja2 MOOSE `.i` template with mesh name, case ID, and placeholder fluid properties (`rho`, `mu`, `k`, `cp` all set to 1.0). Writes to `results/<case_id>.i`. The case ID is extracted from the mesh filename (e.g., `hx_20x10-0.050m-t0001` from `hx_20x10-0.050m-t0001.msh`).

- `clean_input_file(input_file)` — Deletes the `.i` file after simulation to avoid clutter.

- `run_simulation(input_file, n_processors)` — Calls `self.simulator.run()`.

- `simulate_all_meshes()` — Iterates over all `.msh` files in `mesh_files_dir`; skips any for which a matching `.e` file already exists in `results_dir`. For each unsimulated mesh: creates the input file, runs simulation with 4 processors, cleans up.

---

## Training Workflow

### Stage 1 — Filter Pre-training (`pretrain_on_filter`)

The CNN is trained end-to-end using `FilterLoss` as a differentiable supervisor. No simulation is involved. The goal is for the Generator to reliably pass all `GeometryFilter` hard checks.

- **Optimizer:** Adam, `lr=1e-3`
- **Scheduler:** `ReduceLROnPlateau(factor=0.5, patience=5)` — reduces LR when total loss plateaus
- **Mixed precision:** Enabled for CUDA (`torch.amp.autocast` + `GradScaler`); disabled for MPS
- **Gradient clipping:** `max_norm=1.0` — important at high grid resolutions
- **Hard filter evaluation:** Runs in `ThreadPoolExecutor` in parallel with GPU training steps; results are collected at the next log interval
- **Termination:** Fixed number of steps (`n_steps`); final pass rate evaluated on 50 samples

### Stage 2 — RL Fine-tuning (planned)

Will use scalar performance metrics from the `Simulator` as reward signals to update the Generator CNN via policy gradient or similar RL algorithm. Not yet implemented.

---

## Geometry Representation Details

### Coordinate System

- Origin at bottom-left of the domain.
- x increases left to right (flow direction).
- y increases bottom to top, but is offset so the domain is centered about y=0 (y ranges from `-domain_height/2` to `+domain_height/2`).
- Inlet: left face (x=0); Outlet: right face (x=domain_length).

### Occupancy Grid

- Shape: `(grid_ny, grid_nx)` — row-major, y-axis first.
- Values: soft float in `[0, 1]` from CNN sigmoid. 1 = solid, 0 = fluid.
- Binarized at `threshold=0.5` for filter checks and polygon extraction.

### Obstacle Polygon Extraction

Connected solid components (4-connectivity) are found via `scipy.ndimage.label`. Each component is represented as the **bounding-box rectangle** of that component (not the exact pixel outline). Polygons are CCW, in physical (meter) coordinates. This bounding-box approximation keeps polygons valid for GMSH boolean operations and avoids staircase geometry artifacts.

### Mesh Generation (GMSH)

1. Create a rectangle for the full fluid domain.
2. Create planar surfaces for each obstacle polygon.
3. Boolean cut: subtract obstacle surfaces from the fluid rectangle.
4. Classify boundary curves by center-of-mass into physical groups: `Fluid` (2D), `Inlet`, `Outlet`, `Top`, `Bottom`, `Wall` (1D).
5. Apply mesh size parameters from `mesh_params`.
6. Generate 2D mesh and write `.msh` file.

---

## MOOSE Integration

MOOSE input files are generated from a **Jinja2 template** at `problems/template.i`. The template is rendered with:

| Variable | Value |
|---|---|
| `mesh_name` | e.g. `hx_20x10-0.050m-t0001.msh` |
| `case_name` | e.g. `hx_20x10-0.050m-t0001` |
| `rho`, `mu`, `k`, `cp` | Placeholder value of `1.0` (to be replaced with real fluid properties) |

MOOSE is invoked via the `moose` conda environment using `mpiexec`. The compiled app is expected at the path passed to `Simulator(params=...)` (default: `./cutthroat-opt`).

Results are written in **Exodus format** (`.e` files), readable with PyVista. Result parsing and extraction of performance metrics is a planned next step.

---

## Current Development Status

| Component | Status |
|---|---|
| `GeometryConfig` | Complete |
| `HeatExchanger` (mesh generation) | Complete |
| `HeatExchangerCNN` | Complete |
| `GeometryFilter` | Complete |
| `FilterLoss` (Stage 1) | Complete |
| `HeatExchangerGenerator` (Stage 1 training) | Complete |
| `HeatExchangerGenerator` (Stage 2 RL training) | Not yet implemented |
| `Simulator` (MOOSE backend) | Partially implemented — `run_moose()` works; `analyze_exodus_results()` is a placeholder |
| `Simulator` (PINN backend) | Not yet implemented |
| `Optimizer` (batch MOOSE simulation) | Partially implemented |
| `Optimizer` (RL training loop) | Not yet implemented |

### Immediate Next Steps

1. **`Simulator.analyze_exodus_results()`** — Extract scalar performance metrics (e.g., pressure drop, outlet temperature, effectiveness) from MOOSE Exodus output. These will become the RL reward signal.
2. **MOOSE template** (`problems/template.i`) — Finalize the MOOSE input file with real physics blocks (Navier-Stokes, energy equation, boundary conditions) and proper fluid properties.
3. **`Optimizer` RL loop** — Implement Stage 2: call Generator, simulate, extract reward, update CNN weights via policy gradient.
4. **PINN Simulator** — Train a PINN surrogate on MOOSE-generated data and plug it into the `Simulator` interface to accelerate the RL loop.

---

## Key Dependencies

| Library | Role |
|---|---|
| `torch` / `torch.nn` | CNN definition, training, AMP |
| `numpy` | Array manipulation |
| `scipy.ndimage` | Connected component labeling for filter checks |
| `gmsh` | Mesh generation from polygon geometry |
| `pyvista` | Reading Exodus result files |
| `jinja2` | MOOSE input file templating |
| `uuid` | Unique IDs for geometry configs |
| `subprocess` | Launching MOOSE simulation processes |
| `concurrent.futures.ThreadPoolExecutor` | Parallel hard filter evaluation during training |
| `matplotlib` | Diagnostic plots and training curves |

---

## Relevant Physics

The heat exchanger involves conjugate heat transfer. The governing PDEs embedded in the planned PINN loss are:

- **Continuity (incompressible):** ∇·**u** = 0
- **Navier-Stokes:** ρ(**u**·∇)**u** = −∇p + μ∇²**u**
- **Energy equation:** ρcₚ(**u**·∇T) = k∇²T + Q

Performance metrics of interest:
- **Effectiveness (ε):** ratio of actual to maximum possible heat transfer
- **Pressure drop (ΔP):** hydraulic resistance through the exchanger
- **Nusselt number (Nu):** dimensionless convective heat transfer coefficient

---

*Last updated based on code in `topology-optimization.ipynb`. Update this document as the Simulator and Optimizer are developed.*
