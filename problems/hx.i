# couette.i - generated mesh for 2x1 rectangular channel
# Material properties
rho = 1
mu = 1
k = 1
cp = 1

[GlobalParams]
    gravity = '0 0 0' # No gravity for this problem
    pspg = true # Enable PSPG stabilization for pressure
[]

[Mesh]
    [gen]
        type = FileMeshGenerator
        file = heat_exchanger.msh
    []
    [corner_node]
        type = ExtraNodesetGenerator
        input = gen
        new_boundary = 'pinned_node'
        nodes = '0'
    []  
[]

[AuxVariables]
    [Pe]
        family = MONOMIAL
        order = FIRST
    []
[]

[AuxKernels]
    [Pe]
        type = PecletNumberFunctorAux
        speed = speed
        thermal_diffusivity = 'thermal_diffusivity'
        variable = Pe
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
[]      

# Dirichlet BCs: top (u,v)=(3,0), bottom (u,v)=(0,0)
[BCs]
    [x_no_slip]
        type = DirichletBC
        boundary = 'Bottom Top Wall'
        value = 0.0
        variable = vel_x
    []
    [y_no_slip]
        type = DirichletBC
        boundary = 'Bottom Top Wall'
        value = 0.0
        variable = vel_y
    []
    [inlet]
        type = FunctionDirichletBC
        boundary = 'Inlet'
        function = 'inlet_function'
        variable = vel_x
    []
    [pressure_pin]
        type = DirichletBC
        boundary = 'pinned_node'
        value = 0.0
        variable = p
    []
    [T_hot]
        type = DirichletBC
        boundary = 'Wall'
        value = 1.0
        variable = T
    []
    [T_cold]
        type = DirichletBC
        boundary = 'Inlet'
        value = 0.0
        variable = T
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
        expression = '15.0' # Constant inlet velocity
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
    type = Steady
    petsc_options_iname = '-pc_type -pc_asm_overlap -sub_pc_type'
    petsc_options_value = 'asm      2               lu'
    line_search = 'none'
    nl_rel_tol = 1e-12
[]

[Outputs]
    exodus = true
    file_base = problems/hx/hx
    perf_graph = true
[]
