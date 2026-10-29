# template.i - template input file for MOOSE simulations of heat exchanger problems
# Material properties
rho = {{ rho }}
mu = {{ mu }}
k = {{ k }}
cp = {{ cp }}

[GlobalParams]
    gravity = '0 0 0' # No gravity for this problem
    pspg = true # Enable PSPG stabilization for pressure
[]

[Mesh]
    [gen]
        type = FileMeshGenerator
        file = {{ mesh_name }}
    []
    [corner_node]
        type = ExtraNodesetGenerator
        input = gen
        new_boundary = 'pinned_node'
        nodes = '0'
    []  
[]

[AuxVariables]
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
        thermal_diffusivity = 'thermal_diffusivity'
        variable = Peclet
    []
[]

[Variables]
    [vel_x][]
    [vel_y][]
    [p][]
    [T][]
[]

[Kernels]
    [mass]
        type = INSMass
        variable = p
        pressure = p
        u = vel_x
        v = vel_y
    []
    [x_momentum_space]
        type = INSMomentumLaplaceForm
        variable = vel_x
        u = vel_x
        v = vel_y
        pressure = p
        component = 0
    []
    [y_momentum_space]
        type = INSMomentumLaplaceForm
        variable = vel_y
        u = vel_x
        v = vel_y
        pressure = p
        component = 1
    []
    [temperature_space]
        type = INSTemperature
        variable = T
        u = vel_x
        v = vel_y
    []
        [x_momentum_time]
        type = INSMomentumTimeDerivative
        variable = vel_x
    []
    [y_momentum_time]
        type = INSMomentumTimeDerivative
        variable = vel_y
    []
    [temperature_time]
        type = INSTemperatureTimeDerivative
        variable = T
    []
[]      

[BCs]
    [x_no_slip]
        type = DirichletBC
        boundary = 'TopBottom'
        value = 0.0
        variable = vel_x
    []
    [y_no_slip]
        type = DirichletBC
        boundary = 'TopBottom'
        value = 0.0
        variable = vel_y
    []
    [inlet_u]
        type = FunctionDirichletBC
        boundary = 'Inlet'
        value = inlet_function
        variable = vel_x
    []
    [inlet_v]
        type = DirichletBC
        boundary = 'Inlet'
        value = 0.0
        variable = vel_y
    []
    [pressure_pin]
        type = DirichletBC
        boundary = 'Outlet'
        value = {{ P_pin }}
        variable = p
    []
    [T_hot]
        type = DirichletBC
        boundary = 'TopBottom'
        value = {{ T_wall }}
        variable = T
    []
    [T_cold]
        type = DirichletBC
        boundary = 'Inlet'
        value = {{ T_in }}
        variable = T
    []  
[]

[ICs]
    [vel_x_ic]
        type = ConstantIC
        variable = vel_x
        value = {{ U_in }}
    []
    [T_ic]
        type = ConstantIC
        variable = T
        value = {{ T_in }}
    []
[]

[Materials]
    [const]
        type = GenericConstantMaterial
        block = 1
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
        expression = {{ U_profile_expression }}
    []
[]

[Preconditioning]
    [SMP]
        type = SMP
        full = true
        solve_type = 'NEWTON'
    []
[]

[Executioner]
    type = Transient
    solve_type = 'NEWTON'
    automatic_scaling = true
    compute_scaling_once = false
    off_diagonals_in_auto_scaling = true
    resid_vs_jac_scaling_param = 0

    petsc_options_iname = '-pc_type -pc_factor_mat_solver_type'
    petsc_options_value = 'lu       mumps'
    line_search = 'bt'
    nl_rel_tol = 1e-8
    nl_abs_tol = 1e-12
    nl_max_its = 20

    steady_state_detection = true
    steady_state_tolerance = 1e-8
    start_time = 0
    end_time = 1e6          # just a ceiling; detection should stop it earlier

    [TimeStepper]
        type = IterationAdaptiveDT
        dt = 1.0
        growth_factor = 1.5
        cutback_factor = 0.5
        optimal_iterations = 6
        dtmax = 500
    []
[]

[Outputs]
    [exo]
        type = Exodus
        execute_on = 'FINAL'
        file_base = validation/{{ case_name }}
    []
    perf_graph = true
[]
