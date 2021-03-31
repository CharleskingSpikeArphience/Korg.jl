module SSSynth
    export synthesize

    _data_dir = joinpath(@__DIR__, "../data") 

    include("constants.jl")      #physical constants
    include("atomic_data.jl")    #symbols and atomic weights
    include("line_opacity.jl")   #opacity, line profile, voigt function
    include("partition_func.jl") #approximate partition functions
    include("saha_boltzmann.jl") #saha equation
    include("linelist.jl")       #parse line lists
    include("atmosphere.jl")     #parse model atmospheres

    #load data when the package is imported. We might as well do this until we ship with alternative 
    #datasets
    ionization_energies = setup_ionization_energies()
    partition_funcs = setup_atomic_partition_funcs()

    include("continuum_opacity/continuum_opacity.jl") #Define continuum opacity functions.
    include("synthesize.jl")                          #solve radiative transfer equation
    include("LSF.jl")

end # module
