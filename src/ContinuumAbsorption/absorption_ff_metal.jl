"""
    positive_ion_ff_absorption(ν::Real, T::Real, number_densities::Dict, ne::Real,
                               departure_coefficients=Peach1970.departure_coefficients)

Computes the free-free linear absorption coefficient (in cm⁻¹) for all species except H⁻ and He⁻.
Uses provided departure coefficients when they available, and the uncorrected hydrogenic 
approximation when they are not.

# Arguments
- `ν`: frequency in Hz
- `T`: temperature in K
- `number_densities` is a `Dict` mapping each `Species` to its number density.
- `ne`: the number density of free electrons.
- `departure_coefficients` (optional, defaults to [Peach1970](@ref)): 
   a dictionary mapping species to the departure coefficients for the ff process it participates in 
   (e.g. C II maps to the C III ff departure coefficients--see note below).  Departure coefficients 
   should be callables taking temperature and (photon energy / RydbergH / Zeff^2).  See 
   [Peach1970](@ref) for details.

!!! note
    A free-free interaction is named as though the species interacting with the free electron had 
    one more bound electron (in other words it's named as though the free-electron and ion were 
    bound together). The `Z` argument and `ni` values should be specified for the species that 
    actually participates in the reaction. For example:
    - Si I ff absorption: `ni` holds the number density of Si II, and `Z=1` (net charge of Si II)
    - Si II ff absorption: `ni` holds the number density of Si III, and `Z=2` (net charge of Si III)
"""
function _all_ff_absorption(ν::Real, T::Real, number_densities::Dict, ne::Real;
                              departure_coefficients=Peach1970.departure_coefficients)
    #TODO bounds checking
    error("I think we may need the user to pass in the partition functions for every species")

    ndens_Z1 = 0.0
    ndens_Z2 = 0.0
    ndens_Z3 = 0.0

    α_out = 0.0 * ν

    for (k,ndens) in number_densities
        if k.charge <= 0
            # skip neutral species. They don't participate in ff interations.
            # While Korg doesn't track negatively charged ions as a separate species at the moment,
            # skip them too, in case that changes.
            continue 
        elseif k in departure_coefficients
            # photon energy in Rydberg*Zeff^2, see equation (5) in Peach 1967 
            # https://articles.adsabs.harvard.edu/pdf/1967MmRAS..71....1P
            σ = ν/ Z^2 * (hplanck_eV / Rydberg_eV) 

            # add directly to α_out if there is a departure coefficient
            coeffs = departure_coefficients[k]
            α_out = hydrogenic_ff_absorption(ν, T, Z, ni, ne) * (1 + departure_coefficients(T, σ))
        else
            #sum up contributions of hydrogenic ff coeffs, add them to α_out at the end
            if (k.charge == 1)     # e.g. O II
                ndens_Z1 += ndens
            elseif (k.charge == 2) # e.g. O III
                ndens_Z2 += ndens
            else
                error("triply+ ionized species not supported")
            end
        end
    end

    #add contributions from species for which we use the uncorrected hydrogenic approximation
    α_out += hydrogenic_ff_absorption(T, ν, 1, ndens_Z1, ne)
    α_out += hydrogenic_ff_absorption(T, ν, 2, ndens_Z2, ne)

    α_out
end

