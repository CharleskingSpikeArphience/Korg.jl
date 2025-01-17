using Statistics: quantile
using Interpolations: LinearInterpolation, Flat

normal_pdf(Δ, σ) = exp(-0.5*Δ^2 / σ^2) / √(2π) / σ

"""
    move_bounds(λs, lb0, ub0, λ₀, window_size)

Using `lb0` and `ub0` as initial guesses, return the indices of `λs`, `(lb, ub)` corresponding to 
`λ₀`` ± `window_size`.  `λs` can either be a 
- Vector, in which case `lb` and `ub` are used as first guesses
- Range, in which case `lb` and `ub` are ignored and the bounds are computed directly
- Vector of Ranges, in which case `lb` and `ub` are also ignored.  In this case, the bounds returned
  are indices into the concatenation of the ranges.
"""
function move_bounds(λs::R, lb, ub, λ₀, window_size) where R <: AbstractRange
    len = length(λs)
    lb = clamp(Int(cld(λ₀ - window_size - λs[1], step(λs)) + 1), 1, len)
    ub = clamp(Int(fld(λ₀ + window_size - λs[1], step(λs)) + 1), 0, len)
    lb,ub
end
function move_bounds(wl_ranges::Vector{R}, lb, ub, λ₀, window_size) where R <: AbstractRange
    cumulative_lengths=cumsum(length.(wl_ranges))
    lb, ub = 1, 0
    # index of the first range for which the last element is greater than λ₀ - window_size
    range_ind = searchsortedfirst(last.(wl_ranges), λ₀ - window_size)
    if range_ind == length(wl_ranges) + 1
        return lb, ub
    end
    lb, ub = move_bounds(wl_ranges[range_ind], lb, ub, λ₀, window_size) 
    if range_ind > 1
        lb += cumulative_lengths[range_ind-1]
        ub += cumulative_lengths[range_ind-1]
    end
    while ub == cumulative_lengths[range_ind] && range_ind < length(wl_ranges)
        range_ind += 1
        ub += move_bounds(wl_ranges[range_ind], lb, ub, λ₀, window_size)[2]
    end
    lb, ub
end
function move_bounds(λs::V, lb, ub, λ₀, window_size) where V <: AbstractVector
    #walk lb and ub to be window_size away from λ₀. assumes λs is sorted
    while lb+1 < length(λs) && λs[lb] < λ₀ - window_size
        lb += 1
    end
    while lb > 1 && λs[lb-1] > λ₀ - window_size
        lb -= 1
    end
    while ub < length(λs) && λs[ub+1] < λ₀ + window_size
        ub += 1
    end
    while ub > 1 && λs[ub] > λ₀ + window_size
        ub -= 1
    end
    lb, ub
end

"""
    constant_R_LSF(flux, wls, R; window_size=3)

Applies a gaussian line spread function the the spectrum with flux vector `flux` and wavelength
vector `wls` with constant spectral resolution, ``R = \\lambda/\\Delta\\lambda``, where 
``\\Delta\\lambda`` is the LSF FWHM.  The `window_size` argument specifies how far out to extend
the convolution kernel in standard deviations.

For the best match to data, your wavelength range should extend a couple ``\\Delta\\lambda`` outside 
the region you are going to compare.

!!! warning
    - This is a naive, slow implementation.  Do not use it when performance matters.

    - `constant_R_LSF` will have weird behavior if your wavelength grid is not locally linearly-spaced.
       It is intended to be run on a fine wavelength grid, then downsampled to the observational (or 
       otherwise desired) grid.
"""
function constant_R_LSF(flux::AbstractVector{F}, wls, R; window_size=3) where F <: Real
    #ideas - require wls to be a range object? 
    convF = zeros(F, length(flux))
    normalization_factor = Vector{F}(undef, length(flux))
    lb, ub = 1,1 #initialize window bounds
    for i in 1:length(wls)
        λ0 = wls[i]
        σ = λ0 / R / (2sqrt(2log(2))) # convert Δλ = λ0/R (FWHM) to sigma
        lb, ub = move_bounds(wls, lb, ub, λ0, window_size*σ)
        ϕ = normal_pdf.(wls[lb:ub] .- λ0, σ)
        normalization_factor[i] = 1 ./ sum(ϕ)
        @. convF[lb:ub] += flux[i]*ϕ
    end
    convF .* normalization_factor
end

"""
    rectify(flux, wls; bandwidth=50, q=0.95, wl_step=1.0)

Rectify the spectrum with flux vector `flux` and wavelengths `wls` by dividing out a moving
`q`-quantile with window size `bandwidth`.  `wl_step` controls the size of the grid that the moving 
quantile is calculated on and interpolated from.  Setting `wl_step` to 0 results in the exact 
calculation with no interpolation, but note that this is very slow when the `wls` is sampled for 
synthesis (~0.01 Å).

Experiments on real spectra show an agreement between the interpolated rectified spectrum and the 
"exact" one (with default values) at the 3 × 10^-4 level.

!!! warning
    This function should not be applied to data with observational error, as taking a quantile will
    bias the rectification relative to the noiseless case.  It is intended as a fast way to compute
    nice-looking rectified theoretical spectra.  
"""
function rectify(flux::AbstractVector{F}, wls; bandwidth=50, q=0.95, wl_step=1.0) where F <: Real
    #construct a range of integer indices into wls corresponding to roughly wl_step-sized steps
    if wl_step == 0
        inds = eachindex(wls)
    else
        inds = 1 : max(1, Int(floor(wl_step/step(wls)))) : length(wls)
    end
    lb = 1
    ub = 1
    moving_quantile = map(wls[inds]) do λ
        lb, ub = move_bounds(wls, lb, ub, λ, bandwidth)
        quantile(flux[lb:ub], q)
    end
    if wl_step == 0
        flux ./ moving_quantile
    else
        itp = LinearInterpolation(wls[inds], moving_quantile, extrapolation_bc=Flat())
        flux ./ itp.(wls)
    end
end

"""
    air_to_vacuum(λ; cgs=λ<1)

Convert λ from an air to vacuum.  λ is assumed to be in Å if it is ⩾ 1, in cm otherwise.  Formula 
from Birch and Downs (1994) via the VALD website.

See also: [`vacuum_to_air`](@ref).
"""
function air_to_vacuum(λ; cgs=λ<1)
    if cgs
        λ *= 1e8
    end
    s = 1e4/λ
    n = 1 + 0.00008336624212083 + 0.02408926869968 / (130.1065924522 - s^2) + 0.0001599740894897 / (38.92568793293 - s^2)
    if cgs
        λ *= 1e-8
    end
    λ * n
end

"""
    vacuum_to_air(λ; cgs=λ<1)

convert λ from a vacuum to air.  λ is assumed to be in Å if it is ⩾ 1, in cm otherwise.  Formula 
from Birch and Downs (1994) via the VALD website.

See also: [`air_to_vacuum`](@ref).
"""
function vacuum_to_air(λ; cgs=λ<1)
    if cgs
        λ *= 1e8
    end
    s = 1e4/λ
    n = 1 + 0.0000834254 + 0.02406147 / (130 - s^2) + 0.00015998 / (38.9 - s^2)
    if cgs
        λ *= 1e-8
    end
    λ / n
end

# take some care to avoid subnormal values (they can slow things down a lot!)
_nextfloat_skipsubnorm(v::F) where {F<:AbstractFloat} =
    ifelse(-floatmin(F) ≤ v < 0, F(0), ifelse(0 ≤ v < floatmin(F), floatmin(F), nextfloat(v)))
_prevfloat_skipsubnorm(v::F) where {F<:AbstractFloat} =
    ifelse(-floatmin(F) < v ≤ 0, -floatmin(F), ifelse(0 < v ≤ floatmin(F), F(0), prevfloat(v)))

struct Interval # represents an exclusive interval
    lower::Float64
    upper::Float64

    function Interval(lower::Real, upper::Real; exclusive_lower = true, exclusive_upper = true)
        @assert lower < upper "the upper bound must exceed the lower bound"
        lower, upper = Float64(lower), Float64(upper)
        new((exclusive_lower || isinf(lower)) ? lower : _prevfloat_skipsubnorm(lower),
            (exclusive_upper || isinf(upper)) ? upper : _nextfloat_skipsubnorm(upper))
    end
end

# convenience function for defining interval where both bounds are inclusive
closed_interval(lo, up) = Interval(lo, up; exclusive_lower = false, exclusive_upper = false)

"""
    contained(value, interval)

Returns whether `value` is contained by `interval`.

# Examples
```julia-repl
julia> contained(0.5, Interval(1.0,10.0))
false
julia> contained(5.0, Interval(1.0,10.0))
true
```
"""
contained(value::Real, interval::Interval) = interval.lower < value < interval.upper


"""
    contained_slice(vals, interval)

Returns a range of indices denoting the elements of `vals` (which are assumed to be sorted in
 increasing order) that are contained by `interval`. When no entries are contained by interval,
this returns `(1,0)` (which is a valid empty slice).
"""
contained_slice(vals::AbstractVector, interval::Interval) =
    searchsortedfirst(vals, interval.lower):searchsortedlast(vals, interval.upper)

function _convert_λ_endpoint(λ_endpoint::AbstractFloat, λ_lower_bound::Bool)
    # determine the functions that:
    # - retrieve the neighboring ν val in the in-bounds and out-of-bounds directions
    # - specify the desired relationship between an in-bounds λ and λ_lower_bound
    inbound_ν_neighbor, oobound_ν_neighbor, inbound_λ_to_endpoint_relation =
        λ_lower_bound ? (prevfloat, nextfloat, >) : (nextfloat, prevfloat, <)

    ν_endpoint = (λ_endpoint == 0) ? Inf : c_cgs/λ_endpoint
    if isfinite(ν_endpoint) && (ν_endpoint != 0)
        # Adjust ν_endpoint in 2 cases:
        # Case 1: The neighboring ν to ν_endpoint that should be in-bounds, corresponds to a λ
        # value that is out-of-bounds. Nudge ν_endpoint in the "in-bounds" direction until resolved
        while !inbound_λ_to_endpoint_relation(c_cgs/inbound_ν_neighbor(ν_endpoint), λ_endpoint)
            ν_endpoint = inbound_ν_neighbor(ν_endpoint)
        end
        # Case 2: The current value of ν_endpoint corresponds to a λ that is in-bounds. Nudge
        # ν_endpoint in the "out-of-bounds" direction until resolved.
        while inbound_λ_to_endpoint_relation(c_cgs/ν_endpoint, λ_endpoint)
            ν_endpoint = oobound_ν_neighbor(ν_endpoint)
        end
    end
    ν_endpoint
end

"""
    λ_to_ν_bound(λ_bound)

Converts a λ `Inverval` (in cm) to an equivalent ν `Interval` (in Hz), correctly accounting for 
tricky floating point details at the bounds.
"""
λ_to_ν_bound(λ_bound::Interval) =
    Interval(_convert_λ_endpoint(λ_bound.upper, false), _convert_λ_endpoint(λ_bound.lower, true))