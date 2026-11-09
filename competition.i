# 2D cold-plate design-space model (half-height domain).
# The baseplate temperature and heat-source maps are generated for each case.
# This reduced model solves fluid flow and fluid temperature only; the copper
# fin effect is supplied through q_vol_map using the chosen fin efficiency.

rho = {{ rho }}
mu = {{ mu }}
k = {{ k }}
cp = {{ cp }}

[GlobalParams]
    gravity = '0 0 0'
    pspg = true
[]

[Mesh]
    [gen]
        type = FileMeshGenerator
        file = {{ mesh_name }}
    []
[]

[Variables]
    [vel_x][]
    [vel_y][]
    [p][]
    [T_fluid][]
[]

[AuxVariables]
    # Prescribed spatial copper/base temperature map for diagnostics and for
    # building the heat-source map. It is not an independently solved field.
    [T_b]
        family = LAGRANGE
        order = FIRST
    []
    [Reynolds]
        family = MONOMIAL
        order = CONSTANT
    []
    [Peclet]
        family = MONOMIAL
        order = FIRST
    []
[]

[AuxKernels]
    [T_b_map]
        type = FunctionAux
        variable = T_b
        function = T_base_map
    []
    [Reynolds]
        type = ReynoldsNumberFunctorAux
        speed = speed
        rho = ${rho}
        mu = ${mu}
        variable = Reynolds
    []
    [Peclet]
        type = PecletNumberFunctorAux
        speed = speed
        thermal_diffusivity = thermal_diffusivity
        variable = Peclet
    []
[]

[Kernels]
    [mass]
        type = INSMass
        variable = p
        pressure = p
        u = vel_x
        v = vel_y
    []
    [x_momentum]
        type = INSMomentumLaplaceForm
        variable = vel_x
        u = vel_x
        v = vel_y
        pressure = p
        component = 0
    []
    [y_momentum]
        type = INSMomentumLaplaceForm
        variable = vel_y
        u = vel_x
        v = vel_y
        pressure = p
        component = 1
    []
    [fluid_energy]
        type = INSTemperature
        variable = T_fluid
        u = vel_x
        v = vel_y
    []
    # q_vol_map is the volumetric power map divided by rho*cp, in K/s for the
    # temperature equation. The preprocessor projects chip-cell power through
    # the base footprint, effective 2D depth, and fin-efficiency model.
    [base_and_fin_heat]
        type = BodyForce
        variable = T_fluid
        function = q_vol_map
    []
[]

[BCs]
    # Left-edge inlet: U_in is the domain-average x velocity. A profile can be
    # supplied with inlet_expression if the chosen 2D setup needs one.
    [inlet_u]
        type = FunctionDirichletBC
        boundary = 'Inlet'
        function = inlet_function
        variable = vel_x
    []
    [inlet_v]
        type = DirichletBC
        boundary = 'Inlet'
        value = 0
        variable = vel_y
    []
    [bottom_u]
        type = DirichletBC
        boundary = 'Bottom Wall'
        value = 0
        variable = vel_x
    []
    [bottom_v]
        type = DirichletBC
        boundary = 'Bottom Wall'
        value = 0
        variable = vel_y
    []
    [fin_u]
        type = DirichletBC
        boundary = 'Fin Walls'
        value = 0
        variable = vel_x
    []
    [fin_v]
        type = DirichletBC
        boundary = 'Fin Walls'
        value = 0
        variable = vel_y
    []
    # Horizontal symmetry plane at the top of the half-height domain.
    # Normal velocity is zero; tangential velocity and temperature use natural
    # zero-normal-gradient conditions.
    [symmetry_v]
        type = DirichletBC
        boundary = 'Symmetry'
        value = 0
        variable = vel_y
    []
    [outlet_pressure]
        type = DirichletBC
        boundary = 'Outlet'
        value = {{ P_out }}
        variable = p
    []
    [inlet_temperature]
        type = DirichletBC
        boundary = 'Inlet'
        value = {{ T_in }}
        variable = T_fluid
    []
[]

[Materials]
    [const]
        type = GenericConstantMaterial
        block = 'Fluid'
        prop_names = 'rho mu k cp'
        prop_values = '${rho} ${mu} ${k} ${cp}'
    []
[]

[FunctorMaterials]
    [speed]
        type = ADVectorMagnitudeFunctorMaterial
        vector_magnitude_name = speed
        x_functor = vel_x
        y_functor = vel_y
    []
    [thermal_diffusivity]
        type = ThermalDiffusivityFunctorMaterial
        cp = ${cp}
        k = ${k}
        rho = ${rho}
    []
[]

[Functions]
    [inlet_function]
        type = ParsedFunction
        expression = '{{ inlet_expression }}'
    []
    # Both CSVs use PiecewiseBilinear's grid format: first row x coordinates;
    # each later row starts with a y coordinate and then values across x.
    [T_base_map]
        type = PiecewiseBilinear
        data_file = {{ T_base_map_csv }}
    []
    [q_vol_map]
        type = PiecewiseBilinear
        data_file = {{ q_vol_map_csv }}
    []
[]

[Preconditioning]
    [SMP]
        type = SMP
        full = true
        solve_type = NEWTON
    []
[]

[Executioner]
    type = Steady
    solve_type = NEWTON
    automatic_scaling = true
    compute_scaling_once = false
    off_diagonals_in_auto_scaling = true
    resid_vs_jac_scaling_param = 0
    petsc_options_iname = '-pc_type -pc_factor_mat_solver_type'
    petsc_options_value = 'lu mumps'
    line_search = bt
    nl_rel_tol = 1e-8
    nl_abs_tol = 1e-12
    nl_max_its = 50
[]

[Outputs]
    [exo]
        type = Exodus
        execute_on = FINAL
        file_base = results/{{ case_name }}
    []
    perf_graph = true
[]
